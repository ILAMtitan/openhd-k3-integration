#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
root=$(cd "$(dirname "$0")" && pwd)
prepare=no
case "${1:-}" in
  "") ;;
  --prepare) prepare=yes ;;
  -h|--help)
    echo "Usage: sudo $0 [--prepare]"
    exit 0
    ;;
  *) echo "Usage: sudo $0 [--prepare]" >&2; exit 2 ;;
esac

command -v ti-k3-camera-select >/dev/null || {
  echo 'R4 ti-k3-accelerators camera selector is not installed.' >&2
  exit 1
}
[[ -s /etc/systemd/system/ti-k3-camera-prepare.service || -s /usr/lib/systemd/system/ti-k3-camera-prepare.service ]] || {
  echo 'ti-k3-camera-prepare.service is not installed.' >&2
  exit 1
}

for path in \
  overlay/usr/local/sbin/openhd-ti-camera-prepare \
  overlay/usr/local/sbin/openhd-camera-select \
  overlay/etc/systemd/system/openhd.service.d/50-ti-k3-camera-r4.conf; do
  [[ -s "$root/$path" ]] || { echo "Missing R4 integration file: $root/$path" >&2; exit 1; }
done

install -d -m 0755 /usr/local/sbin /etc/systemd/system/openhd.service.d
install -m 0755 "$root/overlay/usr/local/sbin/openhd-ti-camera-prepare" /usr/local/sbin/
install -m 0755 "$root/overlay/usr/local/sbin/openhd-camera-select" /usr/local/sbin/
install -m 0644 "$root/overlay/etc/systemd/system/openhd.service.d/50-ti-k3-camera-r4.conf" \
  /etc/systemd/system/openhd.service.d/

systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/openhd.service >/dev/null

echo 'Installed OpenHD R4 unified camera boundary.'
openhd-camera-select status || true

if [[ "$prepare" == yes ]]; then
  systemctl stop ti-k3-imx219-prepare.service ti-k3-camera-prepare.service 2>/dev/null || true
  systemctl start ti-k3-camera-prepare.service
  /usr/local/sbin/openhd-ti-camera-prepare
  echo
  echo 'Prepared hardware and synchronized OpenHD camera settings:'
  cat /run/ti-k3/camera.env
else
  echo 'OpenHD was not started and the camera was not reconfigured.'
fi
