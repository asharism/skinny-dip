#!/bin/bash
# Run a drive script (SKINNYDIP_DRIVE) in the agent build of Skinny and print the result.
#
#   scripts/drive.sh <steps.json> [--no-build] [--keep-open]
#
# Builds Debug into .build/agent under bundle ID com.hitesh.SkinnyDipAgent (never the real
# one: it shares the user's Scratch Documents), copies the steps into that container's tmp,
# launches the app, waits for <steps>.result.json, prints it, quits the app, and exits
# non-zero if any step failed. Step format: .claude/skills/drive-app/SKILL.md
set -euo pipefail

[[ $# -ge 1 && -f $1 ]] || { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
steps=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
build=1; keep=0
for arg in "$@"; do
  case $arg in
    --no-build) build=0 ;;
    --keep-open) keep=1 ;;
    *) echo "Unknown option $arg" >&2; exit 2 ;;
  esac
done

bundle_id=com.hitesh.SkinnyDipAgent
derived=.build/agent
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app="$derived/Build/Products/Debug/Skinny.app"
binary="$root/$app/Contents/MacOS/Skinny"
container="$HOME/Library/Containers/$bundle_id/Data"
tmp="$container/tmp"

if [[ $build == 1 || ! -d $app ]]; then
  command -v xcodegen >/dev/null && xcodegen generate >/dev/null
  xcodebuild build -scheme SkinnyDip -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived" PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" -quiet
fi

if pgrep -f "$binary" >/dev/null; then
  echo "The agent build is already running; quit it first." >&2
  exit 1
fi

mkdir -p "$tmp"
name=drive-$(date +%Y%m%d-%H%M%S)-$$.json
cp "$steps" "$tmp/$name"
result="$tmp/$name.result.json"
rm -f "$result"

# Start from no Scratch Documents and no saved windows, in this bundle's container only.
rm -rf "$container/Library/Application Support/Skinny Dip/Scratch" \
       "$container/Library/Saved Application State/$bundle_id.savedState"

open -n -F --env "SKINNYDIP_DRIVE=$tmp/$name" "$app"
pid=""
for _ in $(seq 60); do
  pid=$(pgrep -f "$binary" | head -1 || true)
  [[ -n $pid ]] && break
  sleep 0.5
done
[[ -n $pid ]] || { echo "App did not start" >&2; exit 1; }
[[ $keep == 1 ]] || trap 'kill "$pid" 2>/dev/null || true' EXIT

state() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("state",""))
except Exception: print("")' "$result"; }

for _ in $(seq 600); do
  [[ $(state) == done ]] && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.5
done
[[ -f $result ]] || { echo "No result written" >&2; exit 1; }
cp "$result" "${steps%.json}.result.json"
cat "$result"
python3 -c 'import json,sys
r = json.load(open(sys.argv[1]))
sys.exit(0 if r.get("state") == "done" and r.get("ok") else 1)' "$result"
