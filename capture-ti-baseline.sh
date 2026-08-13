#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root on the BeagleY-AI' >&2; exit 1; }
out=${1:-/root/ti-k3-standalone-qualified}
if [[ -e "$out" || -e "$out.tar.gz" || -e "$out.tar.gz.sha256" ]]; then
  echo "Refusing to overwrite existing evidence output: $out" >&2
  exit 1
fi
mkdir -p "$out"
{
  echo '=== date ==='; date -Is
  echo '=== uname ==='; uname -a
  echo '=== platform ==='; cat /var/lib/ti-k3/platform.env
  echo '=== config ==='; cat /etc/ti-k3/accelerators.env
  echo '=== failed units ==='; systemctl --failed --no-pager
  echo '=== target ==='; systemctl status ti-k3-accelerators.target --no-pager --full
  echo '=== memory ==='; ti-k3-memory-map-verify
  echo '=== firmware ==='; sha256sum -c /etc/ti-k3/vision-apps-firmware.sha256
  echo '=== rpmsg ==='; ti-k3-rpmsg-ready
  echo '=== info ==='; ti-k3-info
  echo '=== self-test ==='; ti-k3-self-test; echo "SELF_TEST_RC=$?"
  echo '=== camera contract ==='
  if [[ -r /run/ti-k3/camera.env ]]; then
    cat /run/ti-k3/camera.env
  else
    echo 'camera contract not present'
  fi
  echo '=== camera service ==='
  systemctl status ti-k3-imx219-prepare.service --no-pager --full || true
  echo '=== OpenHD absence ===';
  if command -v openhd >/dev/null 2>&1; then echo 'FAIL: openhd executable present'; else echo 'PASS: no openhd executable'; fi
} >"$out/summary.txt" 2>&1
journalctl -b --no-pager >"$out/full-boot-journal.txt" 2>&1
journalctl -k -b --no-pager >"$out/kernel-journal.txt" 2>&1
cp -a /run/ti-k3/camera.env "$out/camera.env" 2>/dev/null || true
cp -a /var/lib/ti-k3/platform.env "$out/platform.env" 2>/dev/null || true
cp -a /etc/ti-k3/accelerators.env "$out/accelerators.env" 2>/dev/null || true
sha256sum $(find "$out" -type f ! -name SHA256SUMS -print | sort) >"$out/SHA256SUMS"
tar -C "$(dirname "$out")" -czf "$out.tar.gz" "$(basename "$out")"
sha256sum "$out.tar.gz" >"$out.tar.gz.sha256"
echo "Created $out.tar.gz"
cat "$out.tar.gz.sha256"
