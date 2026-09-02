#!/usr/bin/env bash
set -Eeuo pipefail

helper=${1:-./overlay/usr/local/sbin/openhd-ti-camera-prepare}
[[ -x "$helper" ]] || { echo "Helper is not executable: $helper" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run" "$tmp/etc" "$tmp/sysutils" "$tmp/openhd/video"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/v4l2-ctl"
chmod +x "$tmp/bin/v4l2-ctl"
touch "$tmp/video" "$tmp/subdev"

for row in 'imx219 150 imx219-ti-isp' 'imx708 151 864p60' 'imx415 152 full30-r0'; do
  read -r sensor type mode <<<"$row"
  cat > "$tmp/run/camera.env" <<EOF_ENV
TI_K3_CAMERA_DETECTED_SENSOR=$sensor
TI_K3_CAMERA_VIDEO_DEVICE=$tmp/video
TI_K3_CAMERA_SUBDEV_DEVICE=$tmp/subdev
TI_K3_CAMERA_MODE=$mode
EOF_ENV
  printf 'TI_K3_CAMERA_SELECTED=%s\n' "$sensor" > "$tmp/etc/camera.conf"
  printf '{"platform_type":70,"preserve":"yes"}\n' > "$tmp/sysutils/config.json"
  printf '{"switch_primary_and_secondary":false,"dualcam_primary_video_allocated_bandwidth_perc":75,"primary_camera_type":999,"secondary_camera_type":255,"enable_audio":1}\n' > "$tmp/openhd/video/air_camera_generic.json"

  PATH="$tmp/bin:$PATH" \
  OPENHD_TI_CAMERA_ENV="$tmp/run/camera.env" \
  OPENHD_TI_CAMERA_SELECTION_ENV="$tmp/etc/camera.conf" \
  OPENHD_SYSUTILS_CONFIG="$tmp/sysutils/config.json" \
  OPENHD_CAMERA_SETTINGS="$tmp/openhd/video/air_camera_generic.json" \
    "$helper" >/dev/null

  python3 - "$tmp/sysutils/config.json" "$tmp/openhd/video/air_camera_generic.json" "$type" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
a = json.load(open(sys.argv[2]))
t = int(sys.argv[3])
assert s["camera_type"] == t
assert s["preserve"] == "yes"
assert a["primary_camera_type"] == t
assert a["secondary_camera_type"] == 255
assert a["dualcam_primary_video_allocated_bandwidth_perc"] == 75
PY
done

echo 'PASS: R4 OpenHD camera synchronization maps 150/151/152 and preserves unrelated settings'
