#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

fail=0
pass(){ echo "PASS: $*"; }
fail_msg(){ echo "FAIL: $*" >&2; fail=1; }
check(){ local label=$1; shift; if "$@"; then pass "$label"; else fail_msg "$label"; fi; }

check 'ti-k3-accelerators.target active' systemctl is-active --quiet ti-k3-accelerators.target
check 'OpenHD active' systemctl is-active --quiet openhd.service
check 'IMX708 prepare helper installed' test -x /usr/local/sbin/openhd-ti-imx708-prepare
check 'camera.env readable' test -r /run/ti-k3/camera.env
check 'camera-video present' test -e /run/ti-k3/camera-video
check 'camera-subdev present' test -e /run/ti-k3/camera-subdev

if grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx708' /run/ti-k3/camera.env 2>/dev/null; then
  pass 'camera contract sensor is IMX708'
else
  fail_msg 'camera contract sensor is IMX708'
fi
if grep -Fq 'TI_K3_CAMERA_MODE=1296p56' /run/ti-k3/camera.env 2>/dev/null; then
  pass 'camera contract mode is 1296p56'
else
  fail_msg 'camera contract mode is 1296p56'
fi

GENERIC=/usr/local/share/openhd/video/air_camera_generic.json
CAMCFG=/usr/local/share/openhd/video/TI_J722S_IMX708_0.json

if [[ -r "$GENERIC" ]] && jq -e '.primary_camera_type == 151' "$GENERIC" >/dev/null 2>&1; then
  pass 'OpenHD primary camera type is 151 / IMX708'
else
  fail_msg 'OpenHD primary camera type is 151 / IMX708'
fi

if [[ -r "$CAMCFG" ]] && jq -e '.h26x_bitrate_kbits == 6000 and .h26x_keyframe_interval == 28' "$CAMCFG" >/dev/null 2>&1; then
  pass 'IMX708 bitrate/GOP checkpoint is 6000 kbit/s / 28'
else
  fail_msg 'IMX708 bitrate/GOP checkpoint is 6000 kbit/s / 28'
fi

pid=$(pgrep -x openhd | head -n1 || true)
if [[ -n "$pid" ]]; then
  pass "OpenHD process running (pid=$pid)"
  log=$(journalctl -b _PID="$pid" --no-pager 2>/dev/null || true)
  if grep -Fq 'Camera: TI_J722S_IMX708' <<<"$log"; then pass 'OpenHD selected TI_J722S_IMX708'; else fail_msg 'OpenHD selected TI_J722S_IMX708'; fi
  if grep -Fq 'video_bitrate=6000000' <<<"$log"; then pass 'Wave5 startup bitrate is 6 Mbit/s'; else fail_msg 'Wave5 startup bitrate is 6 Mbit/s'; fi
  if grep -Fq 'framerate=56/1' <<<"$log" && grep -Fq 'width=2304,height=1296' <<<"$log"; then pass 'pipeline is 2304x1296p56'; else fail_msg 'pipeline is 2304x1296p56'; fi
  if grep -Fq 'Gst state: ret:SUCCESS state:PLAYING' <<<"$log"; then pass 'GStreamer reached PLAYING'; else fail_msg 'GStreamer reached PLAYING'; fi

  camera_dev=$(readlink -f /run/ti-k3/camera-video 2>/dev/null || true)
  owns=no
  if [[ -n "$camera_dev" ]]; then
    for fd in /proc/"$pid"/fd/*; do
      [[ $(readlink -f "$fd" 2>/dev/null || true) == "$camera_dev" ]] && { owns=yes; break; }
    done
  fi
  if [[ $owns == yes ]]; then pass "OpenHD owns camera device $camera_dev"; else fail_msg "OpenHD owns camera device $camera_dev"; fi
else
  fail_msg 'OpenHD process running'
fi

SUB=/run/ti-k3/camera-subdev
if [[ -e "$SUB" ]]; then
  ctrls=$(v4l2-ctl -d "$SUB" --get-ctrl=exposure,analogue_gain,digital_gain 2>/dev/null || true)
  grep -Fq 'exposure: 1280' <<<"$ctrls" && pass 'manual exposure is 1280' || fail_msg 'manual exposure is 1280'
  grep -Fq 'analogue_gain: 512' <<<"$ctrls" && pass 'manual analogue gain is 512' || fail_msg 'manual analogue gain is 512'
  grep -Fq 'digital_gain: 256' <<<"$ctrls" && pass 'manual digital gain is unity (256)' || fail_msg 'manual digital gain is unity (256)'
fi

exit "$fail"
