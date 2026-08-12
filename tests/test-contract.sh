#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

installer="$root/install-live.sh"
resume="$root/continue-after-rtl-name-failure.sh"
bridge="$root/adapter/overlay/usr/local/sbin/openhd-ti-camera-bridge"
bridge_service="$root/adapter/overlay/etc/systemd/system/openhd-ti-camera-bridge.service"
patch7="$root/reference/patches/openhd/0007-platform-restore-BeagleY-AI-OpenHD-compatibility-fix.patch"
patch8="$root/reference/patches/openhd/0008-video-add-native-TI-J722S-IMX219-pipeline.patch"

test -x "$bridge"
test -r "$bridge_service"
test -r "$patch7"
test -r "$patch8"

[[ $(sha256sum "$patch7" | awk '{print $1}') == 1f7a4b0fdc601b1c386edb77b47b0280aab844151b3ae2e92d892b05a3d897f1 ]]
[[ $(sha256sum "$patch8" | awk '{print $1}') == 7119e476ed51817822742e30b673de0fdd19dd48df8e84ee8119fbde4c931008 ]]

grep -Fq 'OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac' "$installer"
grep -Fq 'OPENHD_PATCHED_TREE=01fe7bf68d39ca6d9be747668910c841a11abe17' "$installer"
grep -Fq 'apply --index "$p"' "$installer"
grep -Fq 'write-tree' "$installer"

grep -Fq 'X_CAM_TYPE_TI_J722S_IMX219' "$patch8"
grep -Fq 'v4l2src device=/run/ti-k3/camera-video' "$patch8"
grep -Fq 'tiovxisp' "$patch8"
grep -Fq 'tiovxmultiscaler target=0' "$patch8"
grep -Fq 'v4l2h264enc name=ti_wave5_encoder' "$patch8"
grep -Fq 'ret.h26x_bitrate_kbits = 3000;' "$patch8"
grep -Fq 'ret.h26x_keyframe_interval = 15;' "$patch8"
grep -Fq 'camera.requires_ti_j722s_pipeline() ? 1024 : 1440;' "$patch8"

dropin=$(sed -n "/20-ti-k3-consumer.conf <<'EOF_DROPIN'/,/^EOF_DROPIN$/p" "$installer")
target=$(sed -n "/openhd-k3-consumer.target <<'EOF_TARGET'/,/^EOF_TARGET$/p" "$installer")

grep -Fq 'After=ti-k3-accelerators.target ti-k3-imx219-prepare.service openhd-radio-network-guard.service' <<<"$dropin"
grep -Fq 'Requires=ti-k3-accelerators.target ti-k3-imx219-prepare.service' <<<"$dropin"
grep -Fq 'Wants=openhd-radio-network-guard.service' <<<"$dropin"
grep -Fq 'EnvironmentFile=-/etc/ti-k3/gstreamer.env' <<<"$dropin"
! grep -Fq 'openhd-ti-camera-bridge.service' <<<"$dropin"
! grep -Fq 'ExecStart=' <<<"$dropin"

grep -Fq 'Requires=ti-k3-accelerators.target' <<<"$target"
grep -Fq 'Wants=openhd-sys-utils.service openhd-radio-network-guard.service openhd-radio-watch.service openhd.service' <<<"$target"
! grep -Fq 'openhd-ti-camera-bridge.service' <<<"$target"

resume_dropin=$(sed -n "/20-ti-k3-consumer.conf <<'EOF_DROPIN'/,/^EOF_DROPIN$/p" "$resume")
resume_target=$(sed -n "/openhd-k3-consumer.target <<'EOF_TARGET'/,/^EOF_TARGET$/p" "$resume")

grep -Fq 'Requires=ti-k3-accelerators.target ti-k3-imx219-prepare.service' <<<"$resume_dropin"
grep -Fq 'EnvironmentFile=-/etc/ti-k3/gstreamer.env' <<<"$resume_dropin"
! grep -Fq 'openhd-ti-camera-bridge.service' <<<"$resume_dropin"
! grep -Fq 'openhd-ti-camera-bridge.service' <<<"$resume_target"

grep -Fq "echo '  systemctl start openhd-k3-consumer.target'" "$installer"
! grep -Fq "echo '  systemctl start openhd-ti-camera-bridge.service'" "$installer"
! grep -Fq 'tcpdump -ni lo udp port 5500' "$installer"
! grep -Fq 'ExecStart=/usr/local/bin/openhd-native-r1' "$installer"

grep -Fq 'USER_MODULE_NAME=88XXau modules' "$installer"
! grep -Fq 'USER_MODULE_NAME=88XXau_ohd modules' "$installer"

echo 'PASS: frozen Native-R1 OpenHD patch identity'
echo 'PASS: Native-R1 direct TI camera consumer contract'
echo 'PASS: legacy bridge excluded from normal systemd topology'
echo 'PASS: RTL8812AU frozen-Alpha module naming contract'
