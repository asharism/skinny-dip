#!/usr/bin/env python3
"""Summarizes a soak run (#62): scripts/soak-summary.py <run.csv> [<run.json>]

Per process: footprint when typing starts, at the end of typing, at the end of
the idle phase, the peak, the growth rate while typing (least-squares slope,
MB per hour) and the change over the idle phase. Then typing latency.
"""
import csv
import json
import sys


def slope(points):
    if len(points) < 2:
        return 0.0
    n = len(points)
    mx = sum(x for x, _ in points) / n
    my = sum(y for _, y in points) / n
    den = sum((x - mx) ** 2 for x, _ in points)
    return sum((x - mx) * (y - my) for x, y in points) / den if den else 0.0


def main():
    rows = list(csv.DictReader(open(sys.argv[1])))
    if not rows:
        print("no samples")
        return
    columns = [c for c in rows[0] if c not in ("seconds", "state")]

    def value(row, column):
        try:
            return float(row[column])
        except (TypeError, ValueError):
            return None

    for row in rows:
        values = [value(row, c) for c in columns]
        row["total"] = sum(v for v in values if v is not None)
    columns.append("total")

    typing = [r for r in rows if r["state"] == "typing"]
    idle = [r for r in rows if r["state"] in ("idle", "done")]
    print(f"{sys.argv[1]}: {len(rows)} samples, {len(typing)} while typing, {len(idle)} idle")
    print()
    header = f"{'process':<22}{'start':>8}{'end typing':>12}{'end idle':>10}{'peak':>8}{'MB/h typing':>13}{'idle Δ':>9}"
    print(header)
    print("-" * len(header))
    for column in columns:
        series = [(float(r["seconds"]), value(r, column)) for r in typing]
        series = [(x, y) for x, y in series if y is not None]
        all_values = [value(r, column) for r in rows if value(r, column) is not None]
        if not series:
            continue
        start = series[0][1]
        end_typing = series[-1][1]
        idle_values = [value(r, column) for r in idle if value(r, column) is not None]
        end_idle = idle_values[-1] if idle_values else float("nan")
        rate = slope(series) * 3600
        print(f"{column:<22}{start:>8.1f}{end_typing:>12.1f}{end_idle:>10.1f}{max(all_values):>8.1f}{rate:>13.1f}{end_idle - end_typing:>9.1f}")

    if len(sys.argv) > 2:
        try:
            log = json.load(open(sys.argv[2]))
        except (OSError, ValueError):
            return
        print()
        overall = log.get("overall", {})
        print(f"driver state: {log.get('state')}  typed characters: {log.get('typedCharacters')}  config: {json.dumps(log.get('config'))}")
        if log.get("error"):
            print(f"driver error: {log['error']}")
        print(f"typing latency (ms) over {overall.get('count', 0)} characters: "
              f"p50 {overall.get('p50', 0):.1f}  p95 {overall.get('p95', 0):.1f}  max {overall.get('max', 0):.1f}")
        minutes = [m for m in log.get("minutes", []) if m["phase"] == "typing" and m["latencyMs"]["count"]]
        if minutes:
            print(f"{'minute':>7}{'tab':>5}{'chars':>7}{'p50':>8}{'p95':>8}{'max':>8}{'timeouts':>10}")
            for m in minutes:
                l = m["latencyMs"]
                print(f"{m['minute']:>7}{m['tab']:>5}{m['characters']:>7}{l['p50']:>8.1f}{l['p95']:>8.1f}{l['max']:>8.1f}{m['timeouts']:>10}")


if __name__ == "__main__":
    main()
