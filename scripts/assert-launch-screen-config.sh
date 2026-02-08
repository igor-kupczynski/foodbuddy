#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failed=0

assert_launch_screen_key() {
  local scheme="$1"
  local plist_file

  plist_file="$(xcodebuild -project FoodBuddy.xcodeproj -scheme "$scheme" -showBuildSettings 2>/dev/null | awk -F' = ' '/ INFOPLIST_FILE = / { print $2; exit }')"

  if [[ -z "$plist_file" ]]; then
    echo "ERROR: Could not resolve INFOPLIST_FILE for scheme '$scheme'."
    failed=1
    return
  fi

  if [[ ! -f "$plist_file" ]]; then
    echo "ERROR: Info.plist for scheme '$scheme' does not exist at '$plist_file'."
    failed=1
    return
  fi

  if /usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$plist_file" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Print :UILaunchStoryboardName" "$plist_file" >/dev/null 2>&1; then
    echo "OK: '$scheme' launch screen metadata is present in '$plist_file'."
  else
    echo "ERROR: '$scheme' is missing UILaunchScreen/UILaunchStoryboardName in '$plist_file'."
    failed=1
  fi
}

assert_launch_screen_key "FoodBuddy"
assert_launch_screen_key "FoodBuddyDev"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

