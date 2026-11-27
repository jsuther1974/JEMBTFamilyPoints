#!/usr/bin/env bash
set -uo pipefail

# Runs or prints a realistic household matrix spanning iPhone, iPad, Watch, and local Mac Catalyst build coverage.
# Usage:
#   Tools/run_household_device_matrix.sh --dry-run
#   Tools/run_household_device_matrix.sh --run

MODE="dry-run"
if [[ "${1:-}" == "--run" ]]; then
  MODE="run"
elif [[ "${1:-}" != "" && "${1:-}" != "--dry-run" ]]; then
  echo "Usage: $0 [--dry-run|--run]" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

IOS_SCHEME="JEMBT Family Points Tracker"
WATCH_SCHEME="Family Points Watch App Watch App"

SIMCTL_DEVICES_JSON="$(xcrun simctl list devices available --json)"

resolve_device() {
  local candidates=("$@")
  CANDIDATES_NL="$(printf '%s\n' "${candidates[@]}")" SIMCTL_DEVICES_JSON="$SIMCTL_DEVICES_JSON" python3 - <<'PY'
import json
import os
import sys

devices = json.loads(os.environ["SIMCTL_DEVICES_JSON"]).get("devices", {})
candidates = [line for line in os.environ.get("CANDIDATES_NL", "").splitlines() if line]

def runtime_label(runtime_id: str) -> str:
    short = runtime_id.split("SimRuntime.")[-1]
    parts = short.split("-")
    if len(parts) >= 2:
        return f"{parts[0]} {'.'.join(parts[1:])}"
    return short

def runtime_rank(runtime_id: str):
    short = runtime_id.split("SimRuntime.")[-1]
    parts = short.split("-")
    platform = parts[0] if parts else short
    version = []
    for p in parts[1:]:
        try:
            version.append(int(p))
        except ValueError:
            version.append(-1)
    return (platform, tuple(version))

for candidate in candidates:
    matches = []
    for runtime_id, runtime_devices in devices.items():
        for d in runtime_devices:
            if not d.get("isAvailable", True):
                continue
            if d.get("name") == candidate:
                matches.append((runtime_rank(runtime_id), runtime_id, d))
    if matches:
        matches.sort(reverse=True)
        _, runtime_id, chosen = matches[0]
        print(f"{chosen['name']}|{chosen['udid']}|{runtime_label(runtime_id)}")
        sys.exit(0)

sys.exit(1)
PY
}

pick_first_available() {
  local candidate
  for candidate in "$@"; do
    if resolved="$(resolve_device "$candidate")"; then
      printf "%s" "$resolved"
      return 0
    fi
  done
  return 1
}

PARENT1_IPHONE_REQUESTED="iPhone 18 Pro Max"
PARENT1_IPHONE_MAPPED="$(pick_first_available "iPhone 18 Pro Max" "iPhone 17 Pro Max")"

PARENT1_IPAD_REQUESTED="iPad Pro M5"
PARENT1_IPAD_MAPPED="$(pick_first_available "iPad Pro 13-inch (M5)" "iPad Pro 11-inch (M5)")"

PARENT1_WATCH_REQUESTED="Apple Watch 12 46mm"
PARENT1_WATCH_MAPPED="$(pick_first_available "Apple Watch Series 12 (46mm)" "Apple Watch Series 11 (46mm)")"

PARENT2_IPHONE_REQUESTED="iPhone 16 Pro"
PARENT2_IPHONE_MAPPED="$(pick_first_available "iPhone 16 Pro" "iPhone 17 Pro" "iPhone 18 Pro" "iPhone 17" "iPhone Air" "iPhone 16e")"

PARENT2_IPAD_REQUESTED="iPad Pro M4"
PARENT2_IPAD_MAPPED="$(pick_first_available "iPad Pro 13-inch (M4)" "iPad Pro 11-inch (M4)" "iPad Air 13-inch (M4)" "iPad Air 11-inch (M4)" "iPad Pro 13-inch (M5)" "iPad Pro 11-inch (M5)" "iPad Air 13-inch (M3)" "iPad Air 11-inch (M3)" "iPad (A16)")"

CHILD_IPAD_REQUESTED="iPad Pro 11-inch M1"
CHILD_IPAD_MAPPED="$(pick_first_available "iPad Pro (11-inch) (3rd generation)" "iPad Pro (11-inch) (4th generation)" "iPad Pro 11-inch (M5)" "iPad Air 11-inch (M4)" "iPad Air 11-inch (M3)" "iPad (A16)" "iPad mini (A17 Pro)")"

CHILD_WATCH_REQUESTED="Apple Watch SE 2 40mm"
CHILD_WATCH_MAPPED="$(pick_first_available "Apple Watch SE (40mm) (2nd generation)" "Apple Watch SE 3 (40mm)")"

parse_resolved() {
  local resolved="$1"
  local field="$2"
  IFS='|' read -r resolved_name resolved_udid resolved_runtime <<<"$resolved"
  case "$field" in
    name) printf "%s" "$resolved_name" ;;
    udid) printf "%s" "$resolved_udid" ;;
    runtime) printf "%s" "$resolved_runtime" ;;
  esac
}

describe_destination() {
  local name="$1"
  local udid="$2"
  if [[ -n "$name" && -n "$udid" ]]; then
    printf "%s (%s)" "$name" "$udid"
  else
    printf "UNRESOLVED"
  fi
}

build_destination_command() {
  local command_prefix="$1"
  local udid="$2"
  if [[ -n "$udid" ]]; then
    printf "%s -destination \"id=%s\"" "$command_prefix" "$udid"
  else
    printf ""
  fi
}

PARENT1_IPHONE_NAME="$(parse_resolved "$PARENT1_IPHONE_MAPPED" name)"
PARENT1_IPHONE_UDID="$(parse_resolved "$PARENT1_IPHONE_MAPPED" udid)"
PARENT1_IPHONE_RUNTIME="$(parse_resolved "$PARENT1_IPHONE_MAPPED" runtime)"

PARENT1_IPAD_NAME="$(parse_resolved "$PARENT1_IPAD_MAPPED" name)"
PARENT1_IPAD_UDID="$(parse_resolved "$PARENT1_IPAD_MAPPED" udid)"
PARENT1_IPAD_RUNTIME="$(parse_resolved "$PARENT1_IPAD_MAPPED" runtime)"

PARENT1_WATCH_NAME="$(parse_resolved "$PARENT1_WATCH_MAPPED" name)"
PARENT1_WATCH_UDID="$(parse_resolved "$PARENT1_WATCH_MAPPED" udid)"
PARENT1_WATCH_RUNTIME="$(parse_resolved "$PARENT1_WATCH_MAPPED" runtime)"

PARENT2_IPHONE_NAME="$(parse_resolved "$PARENT2_IPHONE_MAPPED" name)"
PARENT2_IPHONE_UDID="$(parse_resolved "$PARENT2_IPHONE_MAPPED" udid)"
PARENT2_IPHONE_RUNTIME="$(parse_resolved "$PARENT2_IPHONE_MAPPED" runtime)"

PARENT2_IPAD_NAME="$(parse_resolved "$PARENT2_IPAD_MAPPED" name)"
PARENT2_IPAD_UDID="$(parse_resolved "$PARENT2_IPAD_MAPPED" udid)"
PARENT2_IPAD_RUNTIME="$(parse_resolved "$PARENT2_IPAD_MAPPED" runtime)"

CHILD_IPAD_NAME="$(parse_resolved "$CHILD_IPAD_MAPPED" name)"
CHILD_IPAD_UDID="$(parse_resolved "$CHILD_IPAD_MAPPED" udid)"
CHILD_IPAD_RUNTIME="$(parse_resolved "$CHILD_IPAD_MAPPED" runtime)"

CHILD_WATCH_NAME="$(parse_resolved "$CHILD_WATCH_MAPPED" name)"
CHILD_WATCH_UDID="$(parse_resolved "$CHILD_WATCH_MAPPED" udid)"
CHILD_WATCH_RUNTIME="$(parse_resolved "$CHILD_WATCH_MAPPED" runtime)"

STEPS=()
REQUESTED=()
ACTUAL=()
RUNTIMES=()
COMMANDS=()
RESULTS=()

add_step() {
  STEPS+=("$1")
  REQUESTED+=("$2")
  ACTUAL+=("$3")
  RUNTIMES+=("$4")
  COMMANDS+=("$5")
  RESULTS+=("PENDING")
}

add_step "P1 iPhone iOS Unit Fast" "$PARENT1_IPHONE_REQUESTED" "$(describe_destination "$PARENT1_IPHONE_NAME" "$PARENT1_IPHONE_UDID")" "${PARENT1_IPHONE_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild test -scheme \"$IOS_SCHEME\" -testPlan \"iOS Unit Fast\"" "$PARENT1_IPHONE_UDID")"
add_step "P1 iPad iOS UI Functional" "$PARENT1_IPAD_REQUESTED" "$(describe_destination "$PARENT1_IPAD_NAME" "$PARENT1_IPAD_UDID")" "${PARENT1_IPAD_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild test -scheme \"$IOS_SCHEME\" -testPlan \"iOS UI Functional\"" "$PARENT1_IPAD_UDID")"
add_step "P2 iPhone iOS build" "$PARENT2_IPHONE_REQUESTED" "$(describe_destination "$PARENT2_IPHONE_NAME" "$PARENT2_IPHONE_UDID")" "${PARENT2_IPHONE_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild build -scheme \"$IOS_SCHEME\"" "$PARENT2_IPHONE_UDID")"
add_step "P2 iPad iOS build" "$PARENT2_IPAD_REQUESTED" "$(describe_destination "$PARENT2_IPAD_NAME" "$PARENT2_IPAD_UDID")" "${PARENT2_IPAD_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild build -scheme \"$IOS_SCHEME\"" "$PARENT2_IPAD_UDID")"
add_step "Local Mac Catalyst build" "Host macOS" "platform=macOS,variant=Mac Catalyst" "host" "xcodebuild build -scheme \"$IOS_SCHEME\" -destination \"platform=macOS,variant=Mac Catalyst\""
add_step "Child iPad iOS build" "$CHILD_IPAD_REQUESTED" "$(describe_destination "$CHILD_IPAD_NAME" "$CHILD_IPAD_UDID")" "${CHILD_IPAD_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild build -scheme \"$IOS_SCHEME\"" "$CHILD_IPAD_UDID")"
add_step "P1 Watch tests" "$PARENT1_WATCH_REQUESTED" "$(describe_destination "$PARENT1_WATCH_NAME" "$PARENT1_WATCH_UDID")" "${PARENT1_WATCH_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild test -scheme \"$WATCH_SCHEME\"" "$PARENT1_WATCH_UDID")"
add_step "Child Watch tests" "$CHILD_WATCH_REQUESTED" "$(describe_destination "$CHILD_WATCH_NAME" "$CHILD_WATCH_UDID")" "${CHILD_WATCH_RUNTIME:-N/A}" "$(build_destination_command "xcodebuild test -scheme \"$WATCH_SCHEME\"" "$CHILD_WATCH_UDID")"

cat <<EOF
Household matrix mapping
- Parent 1 iPhone: $PARENT1_IPHONE_REQUESTED -> $(describe_destination "$PARENT1_IPHONE_NAME" "$PARENT1_IPHONE_UDID"), ${PARENT1_IPHONE_RUNTIME:-N/A}
- Parent 1 iPad:   $PARENT1_IPAD_REQUESTED -> $(describe_destination "$PARENT1_IPAD_NAME" "$PARENT1_IPAD_UDID"), ${PARENT1_IPAD_RUNTIME:-N/A}
- Parent 1 Watch:  $PARENT1_WATCH_REQUESTED -> $(describe_destination "$PARENT1_WATCH_NAME" "$PARENT1_WATCH_UDID"), ${PARENT1_WATCH_RUNTIME:-N/A}
- Parent 2 iPhone: $PARENT2_IPHONE_REQUESTED -> $(describe_destination "$PARENT2_IPHONE_NAME" "$PARENT2_IPHONE_UDID"), ${PARENT2_IPHONE_RUNTIME:-N/A}
- Parent 2 iPad:   $PARENT2_IPAD_REQUESTED -> $(describe_destination "$PARENT2_IPAD_NAME" "$PARENT2_IPAD_UDID"), ${PARENT2_IPAD_RUNTIME:-N/A}
- Parent 2 Watch:  absent (no watch destination executed)
- Parent 1 Macs:   Mac Studio M4 Max + MacBook Pro M4 (manual Catalyst sanity on physical Macs)
- Parent 2 Mac:    MacBook Air M1 (2020) (manual Catalyst sanity on physical Mac)
- Local Mac lane:  Host macOS -> platform=macOS,variant=Mac Catalyst (scripted build-only)
- Child iPad:      $CHILD_IPAD_REQUESTED -> $(describe_destination "$CHILD_IPAD_NAME" "$CHILD_IPAD_UDID"), ${CHILD_IPAD_RUNTIME:-N/A}
- Child Watch:     $CHILD_WATCH_REQUESTED -> $(describe_destination "$CHILD_WATCH_NAME" "$CHILD_WATCH_UDID"), ${CHILD_WATCH_RUNTIME:-N/A}
EOF

run_failures=0
for i in "${!COMMANDS[@]}"; do
  command="${COMMANDS[$i]}"
  if [[ -z "$command" ]]; then
    echo
    echo "Skipping ${STEPS[$i]}: no simulator destination resolved."
    RESULTS[$i]="UNRESOLVED"
    if [[ "$MODE" == "run" ]]; then
      run_failures=$((run_failures + 1))
    fi
    continue
  fi
  echo
  echo "$command"
  if [[ "$MODE" == "run" ]]; then
    if eval "$command"; then
      RESULTS[$i]="PASS"
    else
      RESULTS[$i]="FAIL"
      run_failures=$((run_failures + 1))
    fi
  else
    RESULTS[$i]="DRY-RUN"
  fi
done

echo
printf "%-30s | %-26s | %-48s | %-12s | %-8s\n" "Step" "Requested model" "Actual destination" "Runtime" "Result"
printf '%s\n' "--------------------------------------------------------------------------------------------------------------------------------------------------------------"
for i in "${!COMMANDS[@]}"; do
  printf "%-30s | %-26s | %-48s | %-12s | %-8s\n" "${STEPS[$i]}" "${REQUESTED[$i]}" "${ACTUAL[$i]}" "${RUNTIMES[$i]}" "${RESULTS[$i]}"
done

if [[ "$MODE" == "dry-run" ]]; then
  echo
  echo "Dry-run complete. Re-run with --run to execute all commands."
elif (( run_failures > 0 )); then
  echo
  echo "Matrix complete with $run_failures failing step(s)."
  exit 1
else
  echo
  echo "Matrix complete with all steps passing."
fi
