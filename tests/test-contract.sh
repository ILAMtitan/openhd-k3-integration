#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
installer="$root/install-live.sh"
patch8="$root/patches/openhd/0008-video-add-native-TI-J722S-IMX219-pipeline.patch"
watcher="$root/overlay/usr/local/sbin/openhd-radio-watch"
verifier="$root/verify-consumer.sh"

# The installer reconstructs the known Native-R1 tree from the pinned
# upstream source. The resulting Git tree is the source-identity invariant.
grep -Fq 'OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac' "$installer"
grep -Fq 'OPENHD_PATCHED_TREE=01fe7bf68d39ca6d9be747668910c841a11abe17' "$installer"

# Application policy for the qualified J722S camera path.
grep -Fq 'X_CAM_TYPE_TI_J722S_IMX219' "$patch8"
grep -Fq 'v4l2src device=/run/ti-k3/camera-video' "$patch8"
grep -Fq 'tiovxisp' "$patch8"
grep -Fq 'tiovxmultiscaler target=0' "$patch8"
grep -Fq 'v4l2h264enc name=ti_wave5_encoder' "$patch8"
grep -Fq 'ret.h26x_bitrate_kbits = 3000;' "$patch8"
grep -Fq 'ret.h26x_keyframe_interval = 15;' "$patch8"
grep -Fq 'camera.requires_ti_j722s_pipeline() ? 1024 : 1440;' "$patch8"

# Air consumes the TI camera service directly.
dropin=$(sed -n "/20-ti-k3-consumer.conf <<'EOF_DROPIN'/,/^EOF_DROPIN$/p" "$installer")
target=$(sed -n "/openhd-k3-consumer.target <<'EOF_TARGET'/,/^EOF_TARGET$/p" "$installer")

grep -Fq 'After=ti-k3-accelerators.target ti-k3-imx219-prepare.service openhd-radio-network-guard.service' <<<"$dropin"
grep -Fq 'Requires=ti-k3-accelerators.target ti-k3-imx219-prepare.service' <<<"$dropin"
grep -Fq 'EnvironmentFile=-/etc/ti-k3/gstreamer.env' <<<"$dropin"

# Ground consumes the accelerator baseline without requiring local camera
# preparation or a /run/ti-k3 camera contract.
grep -Fq 'After=ti-k3-accelerators.target openhd-radio-network-guard.service' "$installer"
grep -Fq 'camera_contract=none' "$installer"
grep -Fq 'camera_mode=none' "$installer"

grep -Fq 'Requires=ti-k3-accelerators.target' <<<"$target"
grep -Fq 'Wants=openhd-sys-utils.service openhd-radio-network-guard.service openhd-radio-watch.service openhd.service' <<<"$target"

# The retired localhost camera bridge must not return to the installer.
! grep -Fq 'openhd-ti-camera-bridge' "$installer"

# Preserve the RF module name expected by OpenHD/system integration.
grep -Fq 'USER_MODULE_NAME=88XXau modules' "$installer"
! grep -Fq 'USER_MODULE_NAME=88XXau_ohd modules' "$installer"

# Cold boot must not depend on a manual modprobe. The radio watcher loads the
# installed OpenHD module before watching for its interface and can then restart
# OpenHD if the interface appears after service startup.
grep -Fq 'modprobe 88XXau_ohd' "$watcher"
grep -Fq 'Initial RTL8812AU RF state:' "$watcher"
grep -Fq 'restarting OpenHD' "$watcher"

# Consumer verification must not pass merely because the OpenHD process is
# alive while RF discovery later fails. Require the RTL interface and reject
# the known delayed startup failure messages from the current OpenHD process.
grep -Fq 'OpenHD RTL8812AU RF interface present' "$verifier"
grep -Fq 'No openhd wifibroadcast card found' "$verifier"
grep -Fq 'Link not functional' "$verifier"
grep -Fq 'journalctl -b _PID=' "$verifier"

echo 'PASS: Native-R1 source, role, camera, systemd, and RF naming/readiness contract'
