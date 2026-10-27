#!/usr/bin/env python3
"""Report what a Claude Code session and its subagents cost, against the ticket-flow budgets.

Per API call (a "turn"), context = input + cache-read + cache-write tokens: everything the
model read. What you pay is the sum over turns of input, cache writes (5-minute and 1-hour),
cache reads and output, each at the model's price — so it is driven by turns x context, plus
cache *rewrites*: turns that write again a prefix the previous turn had cached (cache expired
during a pause, model switched, compaction).

Prices live in prices.json next to this script (or --prices FILE), never in the code, and
the log stores raw token counts per model: when prices change, edit the file and
`--summary` re-prices every logged session. A model missing from the file is reported with
its tokens and no cost, never guessed.

Guard rails: peak context of the main session and of each subagent, and no auto-compaction.
A manual /compact at a clean point is fine; an automatic one means the task outgrew a session.

Usage:
  ctx-report.py                     latest session for the current directory
  ctx-report.py SESSION.jsonl       a specific transcript
  ctx-report.py --hook              read {"transcript_path": ...} from stdin (Claude Code hook);
                                    never fails the hook, prints one line
  ctx-report.py --summary LOG       re-price a cost log with the current prices, per branch
  --log FILE                        append rows to a cost log; skipped if FILE's directory does
                                    not exist (so `--log .dev/cost.tsv` logs only in repos that
                                    use ticket-flow)
  --prices FILE                     price table (default: prices.json beside this script)
  --main-budget N / --agent-budget N   peak-context budgets, defaults 200000 / 150000

Exit status: 0 within budget, 1 peak over budget or auto-compacted, 2 no transcript found
(--hook always exits 0).
"""
import argparse
import collections
import csv
import datetime
import json
import os
import re
import sys
from pathlib import Path

KINDS = ("input", "write_5m", "write_1h", "read", "output", "rewrite_5m", "rewrite_1h")
STALE_DAYS = 90


# ---------- prices ----------

def load_prices(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def bucket_of(model, prompt, prices):
    """Model id as logged, plus a tier suffix when the price table tiers by prompt length."""
    entry = price_entry(prices, model)
    if entry and entry.get("over_tokens") and prompt > entry["over_tokens"]:
        return f"{model}>{entry['over_tokens']}"
    return model


def price_entry(prices, bucket):
    """Exact model match after dropping a date suffix, a [1m]-style tag and a tier suffix."""
    if not prices:
        return None
    model = re.sub(r">\d+$", "", bucket or "")
    model = re.sub(r"\[.*\]$", "", model)
    model = re.sub(r"-\d{8}$", "", model)
    entry = prices.get("models", {}).get(model)
    if entry and bucket != model and re.search(r">\d+$", bucket) and "over" in entry:
        return {**entry, **entry["over"]}
    return entry


def price(tokens_by_bucket, prices):
    """(dollars, rewrite dollars, buckets with no price)."""
    total = rewrite = 0.0
    unknown = []
    for bucket, t in tokens_by_bucket.items():
        p = price_entry(prices, bucket)
        if not p:
            if any(t[kd] for kd in KINDS):
                unknown.append(base_model(bucket))
            continue
        total += sum(t[kd] * p[kd] for kd in ("input", "write_5m", "write_1h", "read", "output")) / 1e6
        rewrite += (t["rewrite_5m"] * (p["write_5m"] - p["read"])
                    + t["rewrite_1h"] * (p["write_1h"] - p["read"])) / 1e6
    return total, rewrite, sorted(set(unknown))


def staleness(prices):
    try:
        age = (datetime.date.today() - datetime.date.fromisoformat(prices["checked"])).days
    except (KeyError, TypeError, ValueError):
        return "prices.json has no valid 'checked' date"
    if age > STALE_DAYS:
        return f"prices last checked {prices['checked']} ({age} days ago) — verify at {prices.get('source', 'the pricing page')}"
    return None


# ---------- transcripts ----------

def scan(path, prices, sidechain=False):
    r = {"peak": 0, "first": None, "turns": 0, "rewrites": 0, "auto": 0, "manual": 0,
         "summaries": 0, "branch": None, "start": None, "end": None, "prompt": None,
         "tokens": collections.defaultdict(lambda: dict.fromkeys(KINDS, 0))}
    seen = set()
    prev = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp")
            if ts:
                r["start"] = r["start"] or ts
                r["end"] = ts
            r["branch"] = d.get("gitBranch") or r["branch"]
            t = d.get("type")
            if t == "system" and d.get("subtype") == "compact_boundary":
                trig = (d.get("compactMetadata") or {}).get("trigger")
                r["manual" if trig == "manual" else "auto"] += 1   # unknown counts as auto
            if d.get("isCompactSummary"):
                r["summaries"] += 1
            if t == "user" and r["prompt"] is None and not d.get("isMeta"):
                c = (d.get("message") or {}).get("content")
                if isinstance(c, list):
                    c = " ".join(b.get("text", "") for b in c if isinstance(b, dict))
                if isinstance(c, str) and c.strip():
                    r["prompt"] = c.strip()
            if t != "assistant" or bool(d.get("isSidechain")) != sidechain:
                continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            key = msg.get("id") or d.get("requestId") or d.get("uuid")
            if not u or key in seen:          # one API call is logged once per content block
                continue
            seen.add(key)
            inp = u.get("input_tokens") or 0
            read = u.get("cache_read_input_tokens") or 0
            write = u.get("cache_creation_input_tokens") or 0
            w1h = min((u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens") or 0, write)
            ctx = inp + read + write
            tok = r["tokens"][bucket_of(msg.get("model") or "unknown", ctx, prices)]
            tok["input"] += inp
            tok["read"] += read
            tok["write_1h"] += w1h
            tok["write_5m"] += write - w1h
            tok["output"] += u.get("output_tokens") or 0
            # cache miss: re-wrote part of a prefix the previous call had cached
            missed = min(prev - read, write)
            if r["turns"] and missed > 5_000:
                r["rewrites"] += 1
                tok["rewrite_1h" if w1h * 2 > write else "rewrite_5m"] += missed
            prev = ctx
            r["turns"] += 1
            r["first"] = ctx if r["first"] is None else r["first"]
            r["peak"] = max(r["peak"], ctx)
    if not (r["auto"] or r["manual"]):            # older transcripts: summary marker only
        r["auto"] = r["summaries"]
    return r


def agents_of(session_path, prices):
    """Subagent transcripts: <session>/subagents/agent-*.jsonl (with .meta.json for the label)."""
    d = session_path.with_suffix("") / "subagents"
    out = []
    for f in sorted(d.glob("agent-*.jsonl")) if d.is_dir() else []:
        r = scan(f, prices, sidechain=True)
        label = None
        try:
            label = json.loads(f.with_name(f.name[:-len(".jsonl")] + ".meta.json").read_text()).get("description")
        except (OSError, ValueError):
            pass
        r["label"] = label or (r["prompt"] or f.stem).splitlines()[0][:60]
        out.append(r)
    return out


def latest_for_cwd():
    root = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "projects"
    cwd = os.getcwd()
    slug = root / re.sub(r"[^A-Za-z0-9]", "-", cwd)
    files = list(slug.glob("*.jsonl")) if slug.is_dir() else []
    if not files:  # slug rule differs between versions: fall back to matching the recorded cwd
        for f in root.glob("*/*.jsonl"):
            try:
                with open(f, encoding="utf-8") as fh:
                    for _, line in zip(range(30), fh):
                        if json.loads(line).get("cwd") == cwd:
                            files.append(f)
                            break
            except (OSError, ValueError):
                continue
    return max(files, key=lambda f: f.stat().st_mtime) if files else None


# ---------- output ----------

def k(n):
    if n >= 1e6:
        return f"{n / 1e6:.2f}M"
    return f"{round(n / 1000)}k" if n >= 1000 else str(round(n))


def usd(total, unknown):
    if unknown and not total:
        return "?"
    return ("≥" if unknown else "") + f"${total:.2f}"


def merge(parts):
    out = collections.defaultdict(lambda: dict.fromkeys(KINDS, 0))
    for p in parts:
        for b, t in p.items():
            for kd in KINDS:
                out[b][kd] += t[kd]
    return out


def base_model(bucket):
    """Model id without date suffix, [1m]-style tag or price-tier suffix."""
    return re.sub(r"(-\d{8})?(\[.*\])?(>\d+)?$", "", bucket)


def token_totals(tokens_by_bucket):
    """Per model: input, cache write, cache read, output, total. Rewrites are part of write, not added."""
    out = collections.defaultdict(lambda: dict.fromkeys(("input", "write", "read", "output", "total"), 0))
    for bucket, t in tokens_by_bucket.items():
        row = out[base_model(bucket)]
        row["input"] += t["input"]
        row["write"] += t["write_5m"] + t["write_1h"]
        row["read"] += t["read"]
        row["output"] += t["output"]
        row["total"] += t["input"] + t["write_5m"] + t["write_1h"] + t["read"] + t["output"]
    return out


def tokens_of(tokens_by_bucket):
    return sum(r["total"] for r in token_totals(tokens_by_bucket).values())


def print_tokens(tokens_by_bucket):
    rows = token_totals(tokens_by_bucket)
    if not rows:
        return
    width = max(len(m) for m in rows) + 2
    print(f"  tokens {'model':<{width}}{'input':>8}{'write':>9}{'read':>9}{'output':>9}{'total':>9}")
    sums = dict.fromkeys(("input", "write", "read", "output", "total"), 0)
    for model in sorted(rows):
        r = rows[model]
        for f in sums:
            sums[f] += r[f]
        print(f"         {model:<{width}}{k(r['input']):>8}{k(r['write']):>9}{k(r['read']):>9}"
              f"{k(r['output']):>9}{k(r['total']):>9}")
    if len(rows) > 1:
        print(f"         {'all':<{width}}{k(sums['input']):>8}{k(sums['write']):>9}{k(sums['read']):>9}"
              f"{k(sums['output']):>9}{k(sums['total']):>9}")


LOG_FIELDS = ["when", "session", "branch", "part", "model", "turns", "peak", "auto_compactions",
              "manual_compactions", "agents", "verdict", *KINDS]


def write_log(path, session, m, agents, verdict):
    when = datetime.datetime.now().isoformat(timespec="seconds")
    rows = []
    for part, parts, turns, peak, auto, manual in (
            ("main", [m["tokens"]], m["turns"], m["peak"], m["auto"], m["manual"]),
            ("agents", [x["tokens"] for x in agents], sum(x["turns"] for x in agents),
             max((x["peak"] for x in agents), default=0), sum(x["auto"] for x in agents),
             sum(x["manual"] for x in agents))):
        for bucket, t in merge(parts).items():
            rows.append({"when": when, "session": session, "branch": m["branch"] or "", "part": part,
                         "model": bucket, "turns": turns, "peak": peak, "auto_compactions": auto,
                         "manual_compactions": manual, "agents": len(agents) if part == "agents" else 0,
                         "verdict": verdict, **t})
    new = not Path(path).exists()
    with open(path, "a", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, LOG_FIELDS, delimiter="\t")
        if new:
            w.writeheader()
        w.writerows(rows)


def summary(log, prices):
    by_branch = collections.OrderedDict()
    with open(log, encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            b = by_branch.setdefault(row["branch"] or "-", {
                "sessions": set(), "tokens": collections.defaultdict(lambda: dict.fromkeys(KINDS, 0)),
                "main_peak": 0, "agent_peak": 0, "auto": {}, "over": set()})
            b["sessions"].add(row["session"])
            for kd in KINDS:
                b["tokens"][row["model"]][kd] += int(row.get(kd) or 0)
            peak = int(row["peak"] or 0)
            if row["part"] == "main":
                b["main_peak"] = max(b["main_peak"], peak)
                b["auto"][row["session"]] = int(row["auto_compactions"] or 0)
            else:
                b["agent_peak"] = max(b["agent_peak"], peak)
            if row["verdict"] == "OVER":
                b["over"].add(row["session"])
    print(f"{'branch':<16}{'sessions':>9}{'tokens':>9}{'cost':>11}{'rewrites':>10}{'main peak':>11}"
          f"{'agent peak':>12}{'auto-compact':>14}{'over':>6}")
    unknown_all = set()
    for name, b in by_branch.items():
        total, rewrite, unknown = price(b["tokens"], prices)
        unknown_all.update(unknown)
        print(f"{name:<16}{len(b['sessions']):>9}{k(tokens_of(b['tokens'])):>9}{usd(total, unknown):>11}"
              f"{usd(rewrite, unknown):>10}{k(b['main_peak']):>11}{k(b['agent_peak']):>12}"
              f"{sum(b['auto'].values()):>14}{len(b['over']):>6}")
    everything = merge([b["tokens"] for b in by_branch.values()])
    total, _, unknown = price(everything, prices)
    print(f"{'all':<16}{sum(len(b['sessions']) for b in by_branch.values()):>9}"
          f"{k(tokens_of(everything)):>9}{usd(total, unknown):>11}")
    print()
    print_tokens(everything)
    notes(prices, unknown_all)


def notes(prices, unknown):
    if prices is None:
        print("  note: no prices.json — tokens only; costs need the price table")
        return
    if unknown:
        print(f"  note: no price for {', '.join(sorted(unknown))} — add to prices.json "
              f"(source: {prices.get('source', 'the pricing page')}); costs marked ≥ exclude them")
    stale = staleness(prices)
    if stale:
        print(f"  note: {stale}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("transcript", nargs="?")
    ap.add_argument("--hook", action="store_true")
    ap.add_argument("--log")
    ap.add_argument("--summary")
    ap.add_argument("--prices", default=str(Path(__file__).resolve().with_name("prices.json")))
    ap.add_argument("--main-budget", type=int, default=200_000)
    ap.add_argument("--agent-budget", type=int, default=150_000)
    a = ap.parse_args()
    prices = load_prices(a.prices)

    if a.summary:
        summary(a.summary, prices)
        return 0

    path = None
    if a.hook:
        try:
            path = json.load(sys.stdin).get("transcript_path")
        except ValueError:
            pass
    path = Path(path or a.transcript or latest_for_cwd() or "")
    if not path.is_file():
        print("ctx-report: no transcript found", file=sys.stderr)
        return 0 if a.hook else 2

    m = scan(path, prices)
    agents = agents_of(path, prices)
    over_main = m["peak"] > a.main_budget or m["auto"] > 0
    over_agents = [x for x in agents if x["peak"] > a.agent_budget]
    verdict = "OVER" if over_main or over_agents else "ok"
    m_cost, m_rew, m_unk = price(m["tokens"], prices)
    everything = merge([m["tokens"], *(x["tokens"] for x in agents)])
    all_cost, _, all_unk = price(everything, prices)

    if a.hook:
        print(f"ctx-report: {verdict} {k(tokens_of(everything))} tokens, {usd(all_cost, all_unk)}, "
              f"main peak {k(m['peak'])}, auto-compactions {m['auto']}, {len(agents)} agents, "
              f"max agent peak {k(max((x['peak'] for x in agents), default=0))}")
    else:
        print(f"session {path.stem}  branch {m['branch'] or '-'}  {m['start'] or ''} → {m['end'] or ''}")
        print(f"  main   peak {k(m['peak']):>5}  first turn {k(m['first'] or 0):>4}  turns {m['turns']:>3}"
              f"  tokens {k(tokens_of(m['tokens'])):>6}  cost {usd(m_cost, m_unk):>8}"
              f"  rewrites {m['rewrites']} ({usd(m_rew, m_unk)})"
              f"  compactions auto {m['auto']} manual {m['manual']}  {'OVER' if over_main else 'ok'}")
        for x in agents:
            c, _, u = price(x["tokens"], prices)
            flag = "OVER" if x["peak"] > a.agent_budget else "ok"
            print(f"  agent  peak {k(x['peak']):>5}  turns {x['turns']:>3}  tokens {k(tokens_of(x['tokens'])):>6}"
                  f"  cost {usd(c, u):>8}  {flag:4}  {x['label']}")
        print(f"  total  {k(tokens_of(everything))} tokens, {usd(all_cost, all_unk)}"
              f"   (guard rails: peak {k(a.main_budget)} main / {k(a.agent_budget)} per agent, no auto-compaction)")
        print_tokens(everything)
        if m["first"] and m["first"] > 0.25 * a.main_budget:
            print(f"  note: the first turn already reads {k(m['first'])} (system prompt, tools, MCP servers, "
                  f"CLAUDE.md, the skill) — trim those before blaming the plan")
        if m_cost and m_rew > 0.2 * m_cost:
            print(f"  note: {usd(m_rew, m_unk)} went to re-writing the cache — long pauses past the cache "
                  f"lifetime, a model switch, or compaction")
        notes(prices, set(all_unk))

    if a.log and Path(a.log).parent.is_dir():
        write_log(a.log, path.stem, m, agents, verdict)

    return 0 if a.hook or verdict == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
