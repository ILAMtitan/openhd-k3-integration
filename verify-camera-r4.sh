#!/usr/bin/env bash
set -Eeuo pipefail

fail=0
pass() { echo "PASS: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=1; }

[[ -r /run/ti-k3/camera.env ]] || { fail_msg '/run/ti-k3/camera.env readable'; exit "$fail"; }
source /run/ti-k3/camera.env
sensor=${TI_K3_CAMERA_DETECTED_SENSOR:-}
case "$sensor" in
  imx219) expected=150 ;;
  imx708) expected=151 ;;
  imx415) expected=152 ;;
  *) fail_msg "supported detected sensor (found ${sensor:-none})"; exit "$fail" ;;
esac
pass "detected supported camera $sensor"

if systemctl is-active --quiet ti-k3-camera-prepare.service; then
  pass 'ti-k3-camera-prepare.service active'
else
  fail_msg 'ti-k3-camera-prepare.service active'
fi

if [[ -e /run/ti-k3/camera-video && -e /run/ti-k3/camera-subdev ]]; then
  pass 'common TI K3 camera device contract present'
else
  fail_msg 'common TI K3 camera device contract present'
fi

settings=/usr/local/share/openhd/video/air_camera_generic.json
if [[ -r "$settings" ]] && jq -e --argjson type "$expected" '.primary_camera_type == $type' "$settings" >/dev/null 2>&1; then
  pass "OpenHD primary camera type matches $sensor ($expected)"
else
  fail_msg "OpenHD primary camera type matches $sensor ($expected)"
fi

sysutils=/usr/local/share/OpenHD/SysUtils/config.json
if [[ -r "$sysutils" ]] && jq -e --argjson type "$expected" '.camera_type == $type' "$sysutils" >/dev/null 2>&1; then
  pass "SysUtils camera type matches $sensor ($expected)"
else
  fail_msg "SysUtils camera type matches $sensor ($expected)"
fi

if [[ -r /etc/ti-k3/camera.conf ]]; then
  selected=$(sed -n 's/^TI_K3_CAMERA_SELECTED=//p' /etc/ti-k3/camera.conf | tail -n1)
  if [[ "$selected" == "$sensor" ]]; then
    pass "persistent camera selection matches active sensor ($sensor)"
  else
    fail_msg "persistent camera selection matches active sensor (configured=${selected:-none}, active=$sensor)"
  fi
else
  pass 'migration mode: no persistent camera selection yet'
fi

if systemctl cat openhd.service 2>/dev/null | grep -Fq 'ExecStartPre=/usr/local/sbin/openhd-ti-camera-prepare'; then
  pass 'OpenHD service has R4 camera synchronization preflight'
else
  fail_msg 'OpenHD service has R4 camera synchronization preflight'
fi

exit "$fail"
