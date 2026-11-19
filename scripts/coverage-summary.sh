#!/bin/sh
# Prints line coverage per BrievieKit target from the JSON `swift test --enable-code-coverage` writes, and
# copies the report and the table to $2 (default build/coverage).
# Usage: scripts/coverage-summary.sh <codecov.json> [output-dir]
#
# Only files under Packages/BrievieKit/Sources/<Target>/ count: tests and plugin-generated code do not.
set -eu

report="${1:?usage: coverage-summary.sh <codecov.json> [output-dir]}"
out="${2:-build/coverage}"
mkdir -p "$out"
cp "$report" "$out/codecov.json"

# THRESHOLD: no minimum is enforced yet. To start enforcing one, set a number here (percent of lines, total
# over all targets), for example MINIMUM_TOTAL=60, and record the decision in docs/DECISIONS.md.
MINIMUM_TOTAL=""

/usr/bin/env python3 -I - "$report" "$out/summary.txt" "$MINIMUM_TOTAL" <<'PY' || exit 1
import json, re, sys

report, summary_path, minimum = sys.argv[1], sys.argv[2], sys.argv[3]
files = json.load(open(report))["data"][0]["files"]

targets = {}
for entry in files:
    match = re.search(r"/Sources/([^/]+)/", entry["filename"])
    if not match or "/.build/" in entry["filename"]:
        continue
    lines = entry["summary"]["lines"]
    covered, count = targets.get(match.group(1), (0, 0))
    targets[match.group(1)] = (covered + lines["covered"], count + lines["count"])

def percent(covered, count):
    return 100.0 * covered / count if count else 0.0

rows = [f"{'Target':<20} {'Lines':>8} {'Covered':>8} {'Percent':>8}"]
total_covered = total_count = 0
for name in sorted(targets):
    covered, count = targets[name]
    total_covered, total_count = total_covered + covered, total_count + count
    rows.append(f"{name:<20} {count:>8} {covered:>8} {percent(covered, count):>7.1f}%")
total = percent(total_covered, total_count)
rows.append(f"{'Total':<20} {total_count:>8} {total_covered:>8} {total:>7.1f}%")

text = "\n".join(rows) + "\n"
print(text, end="")
open(summary_path, "w").write(text)

if minimum and total < float(minimum):
    sys.exit(f"Line coverage {total:.1f}% is below the minimum {minimum}%.")
PY
