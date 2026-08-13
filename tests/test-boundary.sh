#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

if grep -RniE '/sys/class/remoteproc|vision_apps_evm|j722s-main-r5f0_0-fw|214ee24d51bd8f|fcfd8a387e93fb23|23d2c02c0eba51b|0xA5000000|0xC0000000' \
  "$root/install-live.sh" \
  "$root/verify-consumer.sh" \
  "$root/overlay/usr/local/sbin"; then
  echo 'OpenHD boundary violation' >&2
  exit 1
fi

find "$root" -type f \( -name '*.sh' -o -path '*/usr/local/sbin/*' \) -print0 |
while IFS= read -r -d '' f; do
  bash -n "$f"
done

echo 'PASS: OpenHD consumer boundary and shell syntax'
