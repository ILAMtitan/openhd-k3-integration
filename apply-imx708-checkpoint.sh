#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")" && pwd)
BASE_SRC=${BASE_SRC:-/var/tmp/openhd-k3-consumer-build/OpenHD}
WORK=${WORK:-/var/tmp/openhd-k3-imx708-r1}
BUILD=${BUILD:-/var/tmp/openhd-k3-imx708-build}
OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac
PATCH="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
PREP="$root/overlay/usr/local/sbin/openhd-ti-imx708-prepare"
CFG=/usr/local/share/openhd/video/air_camera_generic.json
CAMCFG=/usr/local/share/openhd/video/TI_J722S_IMX708_0.json
DROPIN=/etc/systemd/system/openhd.service.d/20-ti-k3-consumer.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say 'IMX708 accelerator/runtime preflight'
for cmd in ti-k3-rpmsg-ready ti-k3-configure-imx708-graph v4l2-ctl cmake ninja git readelf jq; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI K3 RPMsg contract is not ready'
[[ -s /opt/imaging/imx708/linear/dcc_viss_2304x1296.bin ]] || die 'Missing IMX708 VISS DCC'
[[ -s /opt/imaging/imx708/linear/dcc_2a_2304x1296.bin ]] || die 'Missing IMX708 2A DCC'
current_runtime=$(readlink -f /opt/ti-k3/runtime/current 2>/dev/null || true)
[[ "$current_runtime" == *imx708-raw10le-core-r1 ]] || die "Expected IMX708 RAW10LE compatibility runtime, got: $current_runtime"

say 'Preserving installed R3 state'
install -d -m 0700 /root/openhd-imx708-checkpoint-backups
cp -a /usr/local/bin/openhd "/root/openhd-imx708-checkpoint-backups/openhd.$STAMP"
[[ -e "$CFG" ]] && cp -a "$CFG" "/root/openhd-imx708-checkpoint-backups/air_camera_generic.$STAMP.json"
[[ -e "$CAMCFG" ]] && cp -a "$CAMCFG" "/root/openhd-imx708-checkpoint-backups/TI_J722S_IMX708_0.$STAMP.json"
[[ -e "$DROPIN" ]] && cp -a "$DROPIN" "/root/openhd-imx708-checkpoint-backups/20-ti-k3-consumer.$STAMP.conf"

say 'Building IMX708 OpenHD checkpoint'
[[ -d "$BASE_SRC/.git" ]] || die "Missing existing R3 OpenHD source tree: $BASE_SRC"
[[ $(git -C "$BASE_SRC" rev-parse HEAD) == "$OPENHD_COMMIT" ]] || die 'Existing OpenHD source tree is not at the pinned R3 commit'
[[ -s "$PATCH" ]] || die "Missing IMX708 patch: $PATCH"

rm -rf "$WORK" "$BUILD"
cp -a "$BASE_SRC" "$WORK"

git -C "$WORK" apply --check "$PATCH"
git -C "$WORK" apply "$PATCH"

cmake -S "$WORK/OpenHD" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_AIR=ON -DENABLE_USB_CAMERAS=ON
cmake --build "$BUILD" --target openhd --parallel "$(nproc)"

BIN="$BUILD/openhd"
[[ -x "$BIN" ]] || die "Built OpenHD binary missing: $BIN"
readelf -h "$BIN" | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'Built OpenHD binary is not AArch64'

say 'Installing IMX708 OpenHD checkpoint'
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
if old not in (150,151):
    raise SystemExit(f'Unexpected primary_camera_type={old}; expected 150 or 151')
d['primary_camera_type']=151
p.write_text(json.dumps(d, indent=4)+'\n')
PY
fi

# If the camera-specific settings already exist, pin the physically qualified
# RF-clean R1 defaults. If they do not exist, the new OpenHD camera type creates
# them with these defaults on first start.
if [[ -r "$CAMCFG" ]]; then
  python3 - "$CAMCFG" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text())
d['h26x_bitrate_kbits']=6000
d['h26x_keyframe_interval']=28
p.write_text(json.dumps(d, indent=4)+'\n')
PY
fi

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
systemctl reset-failed openhd.service
systemctl disable openhd.service 2>/dev/null || true

say 'Checkpoint validation'
/usr/local/sbin/openhd-ti-imx708-prepare
[[ -r /run/ti-k3/camera.env ]] || die 'camera.env was not created'
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx708' /run/ti-k3/camera.env || die 'camera.env is not IMX708'
grep -Fq 'TI_K3_CAMERA_MODE=1296p56' /run/ti-k3/camera.env || die 'camera.env is not 1296p56'

printf 'binary_sha256=%s\n' "$(sha256sum /usr/local/bin/openhd | awk '{print $1}')"
printf 'runtime=%s\n' "$current_runtime"
printf 'backup_stamp=%s\n' "$STAMP"
printf '\nIMX708 R1 checkpoint installed but OpenHD remains stopped/disabled.\n'
printf 'Start manually with:\n  systemctl start openhd.service\n'
printf 'Then run:\n  %s/verify-imx708-checkpoint.sh\n' "$root"
