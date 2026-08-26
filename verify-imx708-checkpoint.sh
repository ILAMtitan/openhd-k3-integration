#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

fail=0
pass(){ echo "PASS: $*"; }
fail_msg(){ echo "FAIL: $*" >&2; fail=1; }
check(){ local label=$1; shift; if "$@"; then pass "$label"; else fail_msg "$label"; fi; }

GST_ENV=/etc/ti-k3/gstreamer.env
GST_OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so
GENERIC=/usr/local/share/openhd/video/air_camera_generic.json
CAMCFG=/usr/local/share/openhd/video/TI_J722S_IMX708_0.json

check 'ti-k3-accelerators.target active' systemctl is-active --quiet ti-k3-accelerators.target
check 'OpenHD active' systemctl is-active --quiet openhd.service
check 'IMX708 prepare helper installed' test -x /usr/local/sbin/openhd-ti-imx708-prepare
check 'camera.env readable' test -r /run/ti-k3/camera.env
check 'camera-video present' test -e /run/ti-k3/camera-video
check 'camera-subdev present' test -e /run/ti-k3/camera-subdev
check 'IMX708 1536x864 VISS DCC present' test -s /opt/imaging/imx708/linear/dcc_viss_1536x864.bin
check 'IMX708 1536x864 2A DCC present' test -s /opt/imaging/imx708/linear/dcc_2a_1536x864.bin
check 'qualified GStreamer V4L2 override present' test -s "$GST_OVERRIDE"

if grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx708' /run/ti-k3/camera.env 2>/dev/null; then
  pass 'camera contract sensor is IMX708'
else
  fail_msg 'camera contract sensor is IMX708'
fi
if grep -Fq 'TI_K3_CAMERA_MODE=864p60' /run/ti-k3/camera.env 2>/dev/null; then
  pass 'camera contract mode is 864p60'
else
  fail_msg 'camera contract mode is 864p60'
fi
if grep -Fq 'TI_K3_CAMERA_VBLANK=946' /run/ti-k3/camera.env 2>/dev/null; then
  pass 'sensor VBLANK is 946 for ~60 fps'
else
  fail_msg 'sensor VBLANK is 946 for ~60 fps'
fi

if [[ -r "$GENERIC" ]] && jq -e '.primary_camera_type == 151' "$GENERIC" >/dev/null 2>&1; then
  pass 'OpenHD primary camera type is 151 / IMX708'
else
  fail_msg 'OpenHD primary camera type is 151 / IMX708'
fi

if [[ -r "$CAMCFG" ]] && jq -e '
  .h26x_bitrate_kbits == 6000 and
  .h26x_keyframe_interval == 30 and
  .streamed_video_format.width == 1280 and
  .streamed_video_format.height == 720 and
  .streamed_video_format.framerate == 60 and
  .streamed_video_format.videoCodec == "h264"
' "$CAMCFG" >/dev/null 2>&1; then
  pass 'IMX708 config is 1280x720p60 H264 / 6000 kbit/s / GOP30'
else
  fail_msg 'IMX708 config is 1280x720p60 H264 / 6000 kbit/s / GOP30'
fi

pid=$(pgrep -x openhd | head -n1 || true)
if [[ -n "$pid" ]]; then
  pass "OpenHD process running (pid=$pid)"
  log=$(journalctl -b _PID="$pid" --no-pager 2>/dev/null || true)

  grep -Fq 'Camera: TI_J722S_IMX708' <<<"$log" &&
    pass 'OpenHD selected TI_J722S_IMX708' ||
    fail_msg 'OpenHD selected TI_J722S_IMX708'

  grep -Fq 'video_bitrate=6000000' <<<"$log" &&
    pass 'Wave5 startup bitrate is 6 Mbit/s' ||
    fail_msg 'Wave5 startup bitrate is 6 Mbit/s'

  grep -Fq 'video_gop_size=30' <<<"$log" &&
    pass 'Wave5 GOP is 30' ||
    fail_msg 'Wave5 GOP is 30'

  grep -Fq 'video/x-bayer,format=rggb10le,width=1536,height=864,framerate=60/1' <<<"$log" &&
    pass 'sensor/VISS input is 1536x864p60 RAW10' ||
    fail_msg 'sensor/VISS input is 1536x864p60 RAW10'

  if grep -Fq 'tiovxmultiscaler target=0' <<<"$log" &&
     grep -Fq 'video/x-raw,format=NV12,width=1280,height=720,framerate=60/1' <<<"$log"; then
    pass 'pipeline output is 1280x720p60 through TIOVX multiscaler'
  else
    fail_msg 'pipeline output is 1280x720p60 through TIOVX multiscaler'
  fi

  grep -Fq 'sink_0::pool-size=2 src::pool-size=2' <<<"$log" &&
    pass 'VISS pool sizes are 2/2' ||
    fail_msg 'VISS pool sizes are 2/2'

  grep -Fq 'profile=(string)baseline,level=(string)3.2' <<<"$log" &&
    pass 'Wave5 H264 caps are Baseline Level 3.2' ||
    fail_msg 'Wave5 H264 caps are Baseline Level 3.2'

  grep -Fq 'Gst state: ret:SUCCESS state:PLAYING' <<<"$log" &&
    pass 'GStreamer reached PLAYING' ||
    fail_msg 'GStreamer reached PLAYING'

  camera_dev=$(readlink -f /run/ti-k3/camera-video 2>/dev/null || true)
  owns=no
  if [[ -n "$camera_dev" ]]; then
    for fd in /proc/"$pid"/fd/*; do
      [[ $(readlink -f "$fd" 2>/dev/null || true) == "$camera_dev" ]] && { owns=yes; break; }
    done
  fi
  [[ $owns == yes ]] &&
    pass "OpenHD owns camera device $camera_dev" ||
    fail_msg "OpenHD owns camera device $camera_dev"

  if grep -Fq "$GST_OVERRIDE" /proc/"$pid"/maps 2>/dev/null; then
    pass 'OpenHD mapped the qualified GStreamer V4L2 override'
  else
    fail_msg 'OpenHD mapped the qualified GStreamer V4L2 override'
  fi

  if grep -Eqi \
    'failed to allocate|cannot allocate memory|buffer pool activation failed|not-negotiated|internal data stream error|pipeline.*error' \
    <<<"$log"; then
    fail_msg 'no GStreamer allocation/negotiation errors'
  else
    pass 'no GStreamer allocation/negotiation errors'
  fi
else
  fail_msg 'OpenHD process running'
fi

SUB=/run/ti-k3/camera-subdev
if [[ -e "$SUB" ]]; then
  ctrls=$(v4l2-ctl -d "$SUB" --get-ctrl=vertical_blanking,exposure,analogue_gain,digital_gain 2>/dev/null || true)
  grep -Fq 'vertical_blanking: 946' <<<"$ctrls" && pass 'live vertical_blanking is 946' || fail_msg 'live vertical_blanking is 946'
  grep -Fq 'exposure: 1280' <<<"$ctrls" && pass 'manual exposure is 1280' || fail_msg 'manual exposure is 1280'
  grep -Fq 'analogue_gain: 512' <<<"$ctrls" && pass 'manual analogue gain is 512' || fail_msg 'manual analogue gain is 512'
  grep -Fq 'digital_gain: 256' <<<"$ctrls" && pass 'manual digital gain is unity (256)' || fail_msg 'manual digital gain is unity (256)'
fi

# Scope kernel CMA validation to the current service activation so historical
# qualification failures earlier in the boot do not create a false negative.
since=$(systemctl show openhd.service -p ActiveEnterTimestamp --value 2>/dev/null || true)
if [[ -n "$since" && "$since" != n/a ]]; then
  klog=$(journalctl -k --since "$since" --no-pager 2>/dev/null || true)
  if grep -Eqi '33554432|8192 pages|dma alloc of size 33554432 failed' <<<"$klog"; then
    fail_msg 'no historical 32 MiB Wave5/CMA allocation failure in this OpenHD run'
  else
    pass 'no historical 32 MiB Wave5/CMA allocation failure in this OpenHD run'
  fi
fi

if command -v iw >/dev/null 2>&1 && iw dev 2>/dev/null | grep -Fq 'type monitor'; then
  pass 'WiFiBroadcast monitor interface present'
else
  fail_msg 'WiFiBroadcast monitor interface present'
fi

exit "$fail"
