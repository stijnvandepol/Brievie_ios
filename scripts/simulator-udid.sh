#!/bin/sh
# Prints the UDID of an available iPhone simulator on the newest installed iOS runtime.
# Prefers a device named $1 (e.g. "iPhone 17") on that runtime, else the first iPhone there.
# Exits 1 with a message on stderr when no iPhone simulator is available.
set -eu

xcrun simctl list -j devices available | /usr/bin/env python3 -I -c '
import json, re, sys

preferred = sys.argv[1] if len(sys.argv) > 1 else ""
devices = json.load(sys.stdin)["devices"]

def ios_version(runtime):
    match = re.search(r"SimRuntime\.iOS-([0-9-]+)$", runtime)
    return tuple(int(part) for part in match.group(1).split("-")) if match else None

runtimes = sorted(
    (version, runtime)
    for runtime, entries in devices.items()
    if (version := ios_version(runtime)) is not None
    and any(d["name"].startswith("iPhone") for d in entries)
)
if not runtimes:
    sys.exit("No available iPhone simulator found. Install an iOS simulator runtime in Xcode.")

iphones = [d for d in devices[runtimes[-1][1]] if d["name"].startswith("iPhone")]
chosen = next((d for d in iphones if d["name"] == preferred), iphones[0])
print(chosen["udid"])
' "${1:-}"
