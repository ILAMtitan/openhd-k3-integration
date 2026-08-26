#!/usr/bin/env bash
set -Eeuo pipefail

fail=0
pass(){ echo "PASS: $*"; }
bad(){ echo "FAIL: $*" >&2; fail=1; }

systemctl is-active --quiet ti-k3-accelerators.target && pass 'ti-k3-accelerators.target active' || bad 'ti-k3-accelerators.target active'
systemctl is-active --quiet openhd.service && pass 'openhd.service active' || bad 'openhd.service active'

[[ -r /run/ti-k3/camera.env ]] && pass 'camera.env readable' || bad 'camera.env readable'
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx415' /run/ti-k3/camera.env 2>/dev/null && pass 'camera contract is IMX415' || bad 'camera contract is IMX415'
grep -Fq 'TI_K3_CAMERA_MODE=full30-r0' /run/ti-k3/camera.env 2>/dev/null && pass 'camera mode is full30-r0' || bad 'camera mode is full30-r0'

GEN=/usr/local/share/openhd/video/air_camera_generic.json
CAM=/usr/local/share/openhd/video/TI_J722S_IMX415_0.json
OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so
if [[ -r "$GEN" ]] && jq -e '.primary_camera_type == 152' "$GEN" >/dev/null; then pass 'primary camera type is 152'; else bad 'primary camera type is 152'; fi
if [[ -r "$CAM" ]] && jq -e '.h26x_bitrate_kbits == 6000 and .h26x_keyframe_interval == 15 and .streamed_video_format.width == 1280 and .streamed_video_format.height == 720 and .streamed_video_format.framerate == 30 and .streamed_video_format.videoCodec == "h264"' "$CAM" >/dev/null; then
  pass 'IMX415 persisted format/bitrate/GOP is 720p30/6000/15'
else
  bad 'IMX415 persisted format/bitrate/GOP is 720p30/6000/15'
fi

pid=$(pgrep -x openhd | head -n1 || true)
if [[ -n "$pid" ]]; then pass "OpenHD process running (pid=$pid)"; else bad 'OpenHD process running'; fi

camera_dev=$(readlink -f /run/ti-k3/camera-video 2>/dev/null || true)
owns=no
if [[ -n "$pid" && -n "$camera_dev" ]]; then
  for fd in /proc/"$pid"/fd/*; do
    [[ $(readlink -f "$fd" 2>/dev/null || true) == "$camera_dev" ]] && { owns=yes; break; }
  done
fi
[[ "$owns" == yes ]] && pass "OpenHD owns $camera_dev" || bad "OpenHD owns $camera_dev"

if [[ -n "$pid" ]] && grep -Fq "$OVERRIDE" /proc/"$pid"/maps 2>/dev/null; then
  pass 'OpenHD mapped qualified GStreamer V4L2 CMA override'
else
  bad 'OpenHD mapped qualified GStreamer V4L2 CMA override'
fi

log=$(journalctl -b -u openhd.service --no-pager 2>/dev/null || true)
for needle in \
  'Camera: TI_J722S_IMX415' \
  'format=gbrg10le,width=3864,height=2192,framerate=30/1' \
  'dcc_viss_3864x2192.bin' \
  'tiovxmultiscaler target=0' \
  'format=NV12,width=1280,height=720,framerate=30/1' \
  'video_bitrate=6000000' \
  'video_gop_size=15' \
  'Gst state: ret:SUCCESS state:PLAYING'; do
  grep -Fq "$needle" <<<"$log" && pass "log contains: $needle" || bad "log contains: $needle"
done

if grep -Eqi 'failed to allocate|cannot allocate memory|33554432|8192 pages|dma alloc of size 33554432 failed' <<<"$log"; then
  bad 'no historical CMA/allocation failure in OpenHD log'
else
  pass 'no historical CMA/allocation failure in OpenHD log'
fi

klog=$(journalctl -k -b --no-pager 2>/dev/null || true)
if grep -Eqi 'dma alloc of size 33554432 failed|req-size: 8192 pages' <<<"$klog"; then
  bad 'no historical 32 MiB CMA failure in current boot'
else
  pass 'no historical 32 MiB CMA failure in current boot'
fi

exit "$fail"
