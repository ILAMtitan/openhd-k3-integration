#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-/var/tmp/openhd-k3-camera-r2-imx415}
BUILD=${BUILD:-/var/tmp/openhd-k3-camera-r2-imx415-build}
OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac
R3_TREE=01fe7bf68d39ca6d9be747668910c841a11abe17
PREP="$root/overlay/usr/local/sbin/openhd-ti-imx415-prepare"
CFG=/usr/local/share/openhd/video/air_camera_generic.json
CAMCFG=/usr/local/share/openhd/video/TI_J722S_IMX415_0.json
DROPIN=/etc/systemd/system/openhd.service.d/20-ti-k3-consumer.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say 'IMX415 accelerator/runtime preflight on camera R2 base'
for cmd in ti-k3-rpmsg-ready ti-k3-configure-imx415-graph v4l2-ctl cmake ninja git readelf jq; do
  command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI K3 RPMsg contract is not ready'
[[ -s /opt/imaging/imx415/linear/dcc_viss_3864x2192.bin ]] || die 'Missing IMX415 VISS DCC'
[[ -s /opt/imaging/imx415/linear/dcc_2a_3864x2192.bin ]] || die 'Missing IMX415 2A DCC'
current_runtime=$(readlink -f /opt/ti-k3/runtime/current 2>/dev/null || true)
[[ "$current_runtime" == *imx708-raw10le-core-r1 ]] || die "Expected qualified RAW10LE compatibility runtime, got: $current_runtime"

say 'Preserving installed OpenHD state'
install -d -m 0700 /root/openhd-camera-r2-checkpoint-backups
[[ -x /usr/local/bin/openhd ]] && cp -a /usr/local/bin/openhd "/root/openhd-camera-r2-checkpoint-backups/openhd.$STAMP"
[[ -e "$CFG" ]] && cp -a "$CFG" "/root/openhd-camera-r2-checkpoint-backups/air_camera_generic.$STAMP.json"
[[ -e "$CAMCFG" ]] && cp -a "$CAMCFG" "/root/openhd-camera-r2-checkpoint-backups/TI_J722S_IMX415_0.$STAMP.json"
[[ -e "$DROPIN" ]] && cp -a "$DROPIN" "/root/openhd-camera-r2-checkpoint-backups/20-ti-k3-consumer.$STAMP.conf"

say 'Reconstructing pinned OpenHD source'
rm -rf "$WORK" "$BUILD"
git clone --recursive --branch 2.7-evo https://github.com/OpenHD/OpenHD.git "$WORK"
git -C "$WORK" checkout --detach "$OPENHD_COMMIT"
git -C "$WORK" submodule update --init --recursive

# Reconstruct and verify the pre-camera qualified R3 tree first.
for p in "$root"/patches/openhd/000[1-8]-*.patch; do
  git -C "$WORK" apply --index --check "$p"
  git -C "$WORK" apply --index "$p"
done
base_tree=$(git -C "$WORK" write-tree)
[[ "$base_tree" == "$R3_TREE" ]] || die "R3 tree mismatch before camera checkpoints: expected $R3_TREE, got $base_tree"

# Camera stack order is intentional:
# 0009 = native IMX708/type151 base
# 0010 = finalized IMX708 1536x864p60 -> 1280x720p60
# 0011 = IMX415/type152 layered on that finalized base
for p in \
  "$root"/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch \
  "$root"/patches/openhd/0010-video-finalize-TI-J722S-IMX708-720p60.patch \
  "$root"/patches/openhd/0011-video-add-native-TI-J722S-IMX415-pipeline.patch; do
  git -C "$WORK" apply --index --check "$p"
  git -C "$WORK" apply --index "$p"
done

say 'Building OpenHD camera R2 + IMX415 R0'
cmake -S "$WORK/OpenHD" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_AIR=ON -DENABLE_USB_CAMERAS=ON
cmake --build "$BUILD" --target openhd --parallel "$(nproc)"

BIN="$BUILD/openhd"
[[ -x "$BIN" ]] || die "Built OpenHD binary missing: $BIN"
readelf -h "$BIN" | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'Built OpenHD binary is not AArch64'

say 'Installing IMX415 OpenHD checkpoint'
systemctl stop openhd.service 2>/dev/null || true
systemctl stop openhd-ti-camera-bridge.service 2>/dev/null || true
install -m 0755 "$BIN" /usr/local/bin/openhd
install -m 0755 "$PREP" /usr/local/sbin/openhd-ti-imx415-prepare

if [[ -r "$CFG" ]]; then
  python3 - "$CFG" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text())
old=d.get('primary_camera_type')
if old not in (150,151,152):
    raise SystemExit(f'Unexpected primary_camera_type={old}; expected TI type 150/151/152')
d['primary_camera_type']=152
p.write_text(json.dumps(d,indent=4)+'\n')
PY
fi

if [[ -r "$CAMCFG" ]]; then
  python3 - "$CAMCFG" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); d=json.loads(p.read_text())
d['h26x_bitrate_kbits']=6000
d['h26x_keyframe_interval']=15
p.write_text(json.dumps(d,indent=4)+'\n')
PY
fi

cat >"$DROPIN" <<'EOF_DROPIN'
[Unit]
After=ti-k3-accelerators.target openhd-radio-network-guard.service
Requires=ti-k3-accelerators.target
Wants=openhd-radio-network-guard.service

[Service]
EnvironmentFile=-/etc/ti-k3/gstreamer.env
ExecStartPre=/usr/local/sbin/openhd-ti-imx415-prepare
EOF_DROPIN

systemctl daemon-reload
systemctl reset-failed openhd.service
systemctl disable openhd.service 2>/dev/null || true

say 'Checkpoint validation'
/usr/local/sbin/openhd-ti-imx415-prepare
[[ -r /run/ti-k3/camera.env ]] || die 'camera.env was not created'
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx415' /run/ti-k3/camera.env || die 'camera.env is not IMX415'
grep -Fq 'TI_K3_CAMERA_MODE=full30-r0' /run/ti-k3/camera.env || die 'camera.env is not IMX415 R0 full30'

printf 'binary_sha256=%s\n' "$(sha256sum /usr/local/bin/openhd | awk '{print $1}')"
printf 'runtime=%s\n' "$current_runtime"
printf 'backup_stamp=%s\n' "$STAMP"
printf '\nCamera R2 + IMX415 R0 installed but OpenHD remains stopped/disabled.\n'
printf 'Start manually with:\n  systemctl start openhd.service\n'
printf 'Then run:\n  %s/verify-imx415-checkpoint.sh\n' "$root"
