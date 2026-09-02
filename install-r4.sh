#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")" && pwd)

role=air
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ ${args[$i]} == --role && $((i + 1)) -lt ${#args[@]} ]]; then
    role=${args[$((i + 1))]}
  fi
done

if [[ "$role" == air ]]; then
  command -v ti-k3-camera-select >/dev/null || {
    echo 'R4 ti-k3-accelerators camera layer must be installed first.' >&2
    exit 1
  }
  systemctl cat ti-k3-camera-prepare.service >/dev/null 2>&1 || {
    echo 'ti-k3-camera-prepare.service is not installed.' >&2
    exit 1
  }
fi

"$root/install-live.sh" "$@"
if [[ "$role" == air ]]; then
  "$root/install-camera-r4-live.sh"
fi
