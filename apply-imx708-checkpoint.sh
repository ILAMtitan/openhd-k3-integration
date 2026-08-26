#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")" && pwd)
BASE_SRC=${BASE_SRC:-/var/tmp/openhd-k3-consumer-build/OpenHD}
WORK=${WORK:-/var/tmp/openhd-k3-imx708-720p60-r2}
BUILD=${BUILD:-/var/tmp/openhd-k3-imx708-720p60-build}
OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac
PATCH9="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
PATCH10="$root/patches/openhd/0010-video-finalize-TI-J722S-IMX708-720p60.patch"
PATCH11="$root/patches/openhd/0011-video-qualify-TI-J722S-IMX708-720p60.patch"
PREP="$root/overlay/usr/local/sbin/openhd-ti-imx708-prepare"
CFG=/usr/local/share/openhd/video/air_camera_generic.json
CAMCFG=/usr/local/share/openhd/video/TI_J722S_IMX708_0.json
DROPIN=/etc/systemd/system/openhd.service.d/20-ti-k3-consumer.conf
GST_ENV=/etc/ti-k3/gstreamer.env
GST_OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say 'IMX708 720p60 accelerator/runtime preflight'
for cmd in ti-k3-rpmsg-ready ti-k3-configure-imx708-graph v4l2-ctl cmake ninja git readelf jq gst-inspect-1.0 strings sha256sum; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI K3 RPMsg contract is not ready'
[[ -s /opt/imaging/imx708/linear/dcc_viss_1536x864.bin ]] || die 'Missing IMX708 1536x864 VISS DCC'
[[ -s /opt/imaging/imx708/linear/dcc_2a_1536x864.bin ]] || die 'Missing IMX708 1536x864 2A DCC'
current_runtime=$(readlink -f /opt/ti-k3/runtime/current 2>/dev/null || true)
[[ "$current_runtime" == *imx708-raw10le-core-r1 ]] || die "Expected IMX708 RAW10LE compatibility runtime, got: $current_runtime"

[[ -r "$GST_ENV" ]] || die "Missing GStreamer environment: $GST_ENV"
[[ -s "$GST_OVERRIDE" ]] || die "Missing qualified GStreamer V4L2 CMA override: $GST_OVERRIDE"
set -a
# shellcheck source=/dev/null
source "$GST_ENV"
set +a
gst_registry=/tmp/gst-registry-openhd-imx708-checkpoint.bin
rm -f "$gst_registry"
gst_filename=$(GST_REGISTRY="$gst_registry" gst-inspect-1.0 v4l2h264enc 2>/dev/null |
  awk -F'[[:space:]]+' '/^[[:space:]]*Filename[[:space:]]/{print $3; exit}')
[[ "$gst_filename" == "$GST_OVERRIDE" ]] ||
  die "Qualified V4L2 override is not selected by $GST_ENV (got: $gst_filename)"

say 'Preserving installed OpenHD state'
install -d -m 0700 /root/openhd-imx708-checkpoint-backups
[[ -e /usr/local/bin/openhd ]] && cp -a /usr/local/bin/openhd "/root/openhd-imx708-checkpoint-backups/openhd.$STAMP"
[[ -e /usr/local/sbin/openhd-ti-imx708-prepare ]] &&
  cp -a /usr/local/sbin/openhd-ti-imx708-prepare "/root/openhd-imx708-checkpoint-backups/openhd-ti-imx708-prepare.$STAMP"
[[ -e "$CFG" ]] && cp -a "$CFG" "/root/openhd-imx708-checkpoint-backups/air_camera_generic.$STAMP.json"
[[ -e "$CAMCFG" ]] && cp -a "$CAMCFG" "/root/openhd-imx708-checkpoint-backups/TI_J722S_IMX708_0.$STAMP.json"
[[ -e "$DROPIN" ]] && cp -a "$DROPIN" "/root/openhd-imx708-checkpoint-backups/20-ti-k3-consumer.$STAMP.conf"
cp -a "$GST_ENV" "/root/openhd-imx708-checkpoint-backups/gstreamer.env.$STAMP"

say 'Building final-qualified IMX708 720p60 OpenHD checkpoint'
[[ -d "$BASE_SRC/.git" ]] || die "Missing existing R3 OpenHD source tree: $BASE_SRC"
[[ $(git -C "$BASE_SRC" rev-parse HEAD) == "$OPENHD_COMMIT" ]] || die 'Existing OpenHD source tree is not at the pinned R3 commit'

# The existing R3 consumer tree already contains the qualified 64-buffer
# appsink change. Do not replace or reset that dirty/staged consumer work.
grep -Fq 'appsink max-buffers=64 drop=true sync=false' \
  "$BASE_SRC/OpenHD/ohd_video/src/gstreamerstream.cpp" ||
  die 'Existing R3 consumer tree does not contain the qualified 64-buffer appsink behavior'

for p in "$PATCH9" "$PATCH10" "$PATCH11"; do
  [[ -s "$p" ]] || die "Missing OpenHD patch: $p"
done

rm -rf "$WORK" "$BUILD"
cp -a "$BASE_SRC" "$WORK"

# Patch 0009 contains an older appsink hunk that conflicts with the already
# qualified R3 consumer tree. Apply its IMX708 additions everywhere except
# gstreamerstream.cpp, then let patch 0011 add only the type-151 dispatch there.
git -C "$WORK" apply --check \
  --exclude='OpenHD/ohd_video/src/gstreamerstream.cpp' "$PATCH9"
git -C "$WORK" apply \
  --exclude='OpenHD/ohd_video/src/gstreamerstream.cpp' "$PATCH9"

git -C "$WORK" apply --check "$PATCH10"
git -C "$WORK" apply "$PATCH10"

git -C "$WORK" apply --check "$PATCH11"
git -C "$WORK" apply "$PATCH11"

git -C "$WORK" diff HEAD --check

grep -Fq 'create_ti_j722s_imx708_stream' "$WORK/OpenHD/ohd_video/inc/gst_helper.hpp" ||
  die 'Final source is missing IMX708 pipeline'
grep -Fq 'sink_0::pool-size=2' "$WORK/OpenHD/ohd_video/inc/gst_helper.hpp" ||
  die 'Final source is missing VISS sink pool-size=2'
grep -Fq 'src::pool-size=2' "$WORK/OpenHD/ohd_video/inc/gst_helper.hpp" ||
  die 'Final source is missing VISS src pool-size=2'
grep -Fq 'level=(string)3.2' "$WORK/OpenHD/ohd_video/inc/gst_helper.hpp" ||
  die 'Final source is missing H.264 Level 3.2 caps'
grep -Fq 'appsink max-buffers=64 drop=true sync=false' \
  "$WORK/OpenHD/ohd_video/src/gstreamerstream.cpp" ||
  die 'Qualified 64-buffer appsink behavior was not preserved'

cmake -S "$WORK/OpenHD" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_AIR=ON -DENABLE_USB_CAMERAS=ON
cmake --build "$BUILD" --target openhd --parallel "$(nproc)"

BIN="$BUILD/openhd"
[[ -x "$BIN" ]] || die "Built OpenHD binary missing: $BIN"
readelf -h "$BIN" | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'Built OpenHD binary is not AArch64'

STR="$BUILD/openhd.strings"
strings -a "$BIN" >"$STR"
for marker in \
  'TI_J722S_IMX708' \
  'dcc_viss_1536x864.bin' \
  'dcc_2a_1536x864.bin' \
  'rggb10le,width=1536,height=864' \
  'width=1280,height=720,framerate=60/1' \
  'sink_0::pool-size=2' \
  'src::pool-size=2' \
  'level=(string)3.2'; do
  grep -Fq "$marker" "$STR" || die "Built OpenHD binary is missing marker: $marker"
done

say 'Installing final-qualified IMX708 720p60 OpenHD checkpoint'
systemctl stop openhd.service 2>/dev/null || true
systemctl stop openhd-ti-camera-bridge.service 2>/dev/null || true
install -m 0755 "$BIN" /usr/local/bin/openhd
install -m 0755 "$PREP" /usr/local/sbin/openhd-ti-imx708-prepare

if [[ -r "$CFG" ]]; then
  python3 - "$CFG" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text())
old=d.get('primary_camera_type')
if old not in (150,151,152):
    raise SystemExit(f'Unexpected primary_camera_type={old}; expected TI camera type')
d['primary_camera_type']=151
p.write_text(json.dumps(d, indent=4)+'\n')
PY
fi

if [[ -r "$CAMCFG" ]]; then
  python3 - "$CAMCFG" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text())
d['h26x_bitrate_kbits']=6000
d['h26x_keyframe_interval']=30
fmt=d.setdefault('streamed_video_format', {})
fmt['width']=1280
fmt['height']=720
fmt['framerate']=60
fmt['videoCodec']='h264'
p.write_text(json.dumps(d, indent=4)+'\n')
PY
fi

install -d -m 0755 "$(dirname "$DROPIN")"
cat >"$DROPIN" <<'EOF_DROPIN'
[Unit]
After=ti-k3-accelerators.target openhd-radio-network-guard.service
Requires=ti-k3-accelerators.target
Wants=openhd-radio-network-guard.service

[Service]
EnvironmentFile=-/etc/ti-k3/gstreamer.env
ExecStartPre=/usr/local/sbin/openhd-ti-imx708-prepare
EOF_DROPIN

systemctl daemon-reload
systemctl reset-failed openhd.service 2>/dev/null || true
systemctl disable openhd.service 2>/dev/null || true
systemctl stop openhd.service 2>/dev/null || true

say 'Checkpoint validation while OpenHD remains stopped'
/usr/local/sbin/openhd-ti-imx708-prepare
[[ -r /run/ti-k3/camera.env ]] || die 'camera.env was not created'
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx708' /run/ti-k3/camera.env || die 'camera.env is not IMX708'
grep -Fq 'TI_K3_CAMERA_MODE=864p60' /run/ti-k3/camera.env || die 'camera.env is not 864p60'
grep -Fq 'TI_K3_CAMERA_WIDTH=1536' /run/ti-k3/camera.env || die 'camera.env width is not 1536'
grep -Fq 'TI_K3_CAMERA_HEIGHT=864' /run/ti-k3/camera.env || die 'camera.env height is not 864'
grep -Fq 'TI_K3_CAMERA_FPS=60' /run/ti-k3/camera.env || die 'camera.env fps is not 60'
grep -Fq 'TI_K3_CAMERA_VBLANK=946' /run/ti-k3/camera.env || die 'camera.env VBLANK is not 946'

ctrls=$(v4l2-ctl -d /run/ti-k3/camera-subdev \
  --get-ctrl=vertical_blanking,exposure,analogue_gain,digital_gain 2>/dev/null || true)
grep -Fq 'vertical_blanking: 946' <<<"$ctrls" || die 'live vertical_blanking is not 946'
grep -Fq 'exposure: 1280' <<<"$ctrls" || die 'live exposure is not 1280'
grep -Fq 'analogue_gain: 512' <<<"$ctrls" || die 'live analogue gain is not 512'
grep -Fq 'digital_gain: 256' <<<"$ctrls" || die 'live digital gain is not 256'

if [[ -r "$CAMCFG" ]]; then
  jq -e '
    .h26x_bitrate_kbits == 6000 and
    .h26x_keyframe_interval == 30 and
    .streamed_video_format.width == 1280 and
    .streamed_video_format.height == 720 and
    .streamed_video_format.framerate == 60 and
    .streamed_video_format.videoCodec == "h264"
  ' "$CAMCFG" >/dev/null || die 'Persisted IMX708 config is not the qualified 720p60/6M/GOP30 checkpoint'
fi

[[ $(systemctl is-active openhd.service 2>/dev/null || true) != active ]] ||
  die 'OpenHD unexpectedly running after checkpoint install'

printf 'binary_sha256=%s\n' "$(sha256sum /usr/local/bin/openhd | awk '{print $1}')"
printf 'gstreamer_override_sha256=%s\n' "$(sha256sum "$GST_OVERRIDE" | awk '{print $1}')"
printf 'runtime=%s\n' "$current_runtime"
printf 'backup_stamp=%s\n' "$STAMP"
printf '\nFinal-qualified IMX708 720p60 checkpoint installed; OpenHD remains stopped/disabled.\n'
printf 'Start manually with:\n  systemctl start openhd.service\n'
printf 'Then run:\n  %s/verify-imx708-checkpoint.sh\n' "$root"
