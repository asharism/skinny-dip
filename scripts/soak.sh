#!/bin/bash
# Memory and typing soak (#62). Builds Skinny (Release, with the Debug-only soak
# driver compiled in), launches it with a separate bundle ID so the user's real
# Scratch Documents are never touched, lets the in-app driver type into 3 Tabs,
# and samples `footprint` of the app and its WebKit helpers every 30 s.
#
#   scripts/soak.sh <typing minutes> [KEY=VALUE ...] [options]
#
#   KEY=VALUE            passed to the app, e.g. SKINNYDIP_SOAK_NO_PREVIEW=1,
#                        SKINNYDIP_SOAK_NO_HISTORY_EXPORT=1, SKINNYDIP_SOAK_TABS=3
#   --idle <minutes>     idle phase after typing (default 10)
#   --interval <secs>    sampling interval (default 30)
#   --bundle-id <id>     default com.hitesh.SkinnyDipAgent; never com.hitesh.SkinnyDip
#   --derived-data <dir> default .build/agent
#   --label <name>       added to the output file names
#   --no-build           reuse the last build
#
# Output: .build/soak/<timestamp>[-label].csv (MB per process), the driver's
# .json log (typing latency per minute) and a .summary.txt from soak-summary.py.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[[ $# -ge 1 && $1 =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
minutes=$1; shift
idle=10
interval=30
bundle_id=com.hitesh.SkinnyDipAgent
derived=.build/agent
label=""
build=1
app_env=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --idle) idle=$2; shift 2 ;;
    --interval) interval=$2; shift 2 ;;
    --bundle-id) bundle_id=$2; shift 2 ;;
    --derived-data) derived=$2; shift 2 ;;
    --label) label=$2; shift 2 ;;
    --no-build) build=0; shift ;;
    *=*) app_env+=("$1"); shift ;;
    *) usage ;;
  esac
done

if [[ $bundle_id == com.hitesh.SkinnyDip ]]; then
  echo "Refusing to soak with the real bundle ID: it shares the user's Scratch Documents." >&2
  exit 1
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
mkdir -p .build/soak
stamp=$(date +%Y%m%d-%H%M%S)${label:+-$label}
csv=.build/soak/$stamp.csv
app="$derived/Build/Products/Release/Skinny.app"
binary="$(cd "$(dirname "$app")" 2>/dev/null && pwd)/Skinny.app/Contents/MacOS/Skinny"
container="$HOME/Library/Containers/$bundle_id/Data"
log="$container/tmp/soak-$stamp.json"

if [[ $build == 1 ]]; then
  echo "Building $bundle_id into $derived ..."
  xcodebuild build -scheme SkinnyDip -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG' -quiet
  binary="$(cd "$(dirname "$app")" && pwd)/Skinny.app/Contents/MacOS/Skinny"
fi
[[ -x $binary ]] || { echo "No build at $app" >&2; exit 1; }

if pgrep -f "$binary" >/dev/null; then
  echo "This build is already running; quit it first." >&2
  exit 1
fi

# Start from no Scratch Documents and no saved windows, in this bundle's container only.
rm -rf "$container/Library/Application Support/Skinny Dip/Scratch" \
       "$container/Library/Saved Application State/$bundle_id.savedState"

before=$(pgrep -f com.apple.WebKit | sort -n || true)
env_args=(--env "SKINNYDIP_SOAK=$log" --env "SKINNYDIP_SOAK_MINUTES=$minutes" --env "SKINNYDIP_SOAK_IDLE_MINUTES=$idle")
for pair in "${app_env[@]+"${app_env[@]}"}"; do env_args+=(--env "$pair"); done
open -n -F "${env_args[@]}" "$app"

pid=""
for _ in $(seq 60); do
  pid=$(pgrep -f "$binary" | head -1 || true)
  [[ -n $pid ]] && break
  sleep 0.5
done
[[ -n $pid ]] || { echo "App did not start" >&2; exit 1; }
trap 'kill "$pid" 2>/dev/null || true' EXIT
# A sleeping Mac stalls both the driver and the sampler; the summary flags any gap.
caffeinate -dimsu -w "$pid" &

state() { python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("state","starting"))
except Exception: print("starting")' "$log"; }

# The driver opens the Tabs, then reports "typing" with each web view's process ID.
for _ in $(seq 180); do
  s=$(state)
  [[ $s != starting ]] && break
  sleep 0.5
done
[[ $(state) == typing ]] || { echo "Driver did not start typing (state: $(state)); see $log" >&2; exit 1; }

# Our helpers are the WebKit processes that appeared since launch. Other apps
# (Safari, another Skinny) can start helpers in the same window, so when the
# driver reported its own process IDs, keep only the ones both agree on.
after=$(pgrep -f com.apple.WebKit | sort -n || true)
new=$(comm -13 <(echo "$before") <(echo "$after") | grep -v '^$' || true)
labels=$(python3 - "$log" <<'PY'
import json, sys
log = json.load(open(sys.argv[1]))
for p in log.get("processes", []):
    name = p["role"] if p["tab"] == 0 else f'{p["role"]}{p["tab"]}'
    kind = "webcontent" if p["role"] in ("editor", "preview") else p["role"]
    print(p["pid"], name, kind)
PY
)
helpers=()
names=()
for p in $new; do
  kind=$(ps -o comm= -p "$p" 2>/dev/null | sed -E 's/.*com\.apple\.WebKit\.([A-Za-z]+).*/\1/' | tr 'A-Z' 'a-z')
  [[ -n $kind ]] || continue
  reported=$(echo "$labels" | awk -v p="$p" '$1 == p { print $2 }')
  if [[ -z $reported ]] && echo "$labels" | awk '{print $3}' | grep -qx "$kind"; then
    echo "Skipping WebKit $kind $p: new since launch but not reported by the driver." >&2
    continue
  fi
  helpers+=("$p")
  names+=("${reported:-$kind}_$p")
done
for line in $(echo "$labels" | awk '{print $1}'); do
  echo " $new " | tr '\n' ' ' | grep -q " $line " || echo "Driver reported pid $line, which the pgrep diff did not find." >&2
done

mb() { footprint -f bytes --noCategories "$1" 2>/dev/null \
  | awk '/Footprint:/ { for (i = 1; i <= NF; i++) if ($i == "Footprint:") { printf "%.1f", $(i+1) / 1048576; exit } }'; }

header="seconds,state,app"
for n in "${names[@]}"; do header+=",$n"; done
echo "$header" > "$csv"
echo "Sampling app $pid and ${#helpers[@]} WebKit helpers into $csv"
start=$(date +%s)
end=$(( start + ${minutes%.*} * 60 + ${idle%.*} * 60 + 60 ))
while :; do
  now=$(date +%s)
  s=$(state)
  row="$(( now - start )),$s,$(mb "$pid")"
  for p in "${helpers[@]}"; do row+=",$(mb "$p")"; done
  echo "$row" >> "$csv"
  [[ $s == done || $s == failed || $now -ge $end ]] && break
  kill -0 "$pid" 2>/dev/null || { echo "App exited" >&2; break; }
  sleep "$interval"
done

cp "$log" ".build/soak/$stamp.json" 2>/dev/null || true
python3 "$root/scripts/soak-summary.py" "$csv" ".build/soak/$stamp.json" | tee ".build/soak/$stamp.summary.txt"
