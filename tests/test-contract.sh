#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bridge="$root/adapter/overlay/usr/local/sbin/openhd-ti-camera-bridge"
service="$root/adapter/overlay/etc/systemd/system/openhd-ti-camera-bridge.service"
camera_policy="$root/adapter/overlay/etc/default/openhd-ti-camera"
camera_policy_example="$root/adapter/overlay/etc/default/openhd-ti-camera.example"
installer="$root/install-live.sh"

grep -Fq '/usr/local/sbin/ti-k3-rpmsg-ready' "$bridge"
grep -Fq 'source /run/ti-k3/camera.env' "$bridge"
grep -Fq 'TI_K3_CAMERA_VIDEO_DEVICE' "$bridge"
grep -Fq 'TI_K3_CAMERA_DCC_VISS' "$bridge"
grep -Fq 'EnvironmentFile=/etc/default/openhd-ti-camera' "$service"
grep -Fq 'EnvironmentFile=-/etc/ti-k3/gstreamer.env' "$service"
grep -Fq '127.0.0.1' "$bridge"
grep -Fq '5500' "$bridge"
grep -Fq 'Requires=ti-k3-accelerators.target ti-k3-imx219-prepare.service' "$service"
[[ -s "$camera_policy" ]]
[[ -s "$camera_policy_example" ]]
cmp -s "$camera_policy" "$camera_policy_example"
grep -Fxq 'OPENHD_CAMERA_MODE=imx219-ti-isp' "$camera_policy"
grep -Fxq 'OPENHD_CAMERA_RTP_HOST=127.0.0.1' "$camera_policy"
grep -Fxq 'OPENHD_CAMERA_RTP_PORT=5500' "$camera_policy"
grep -Fq 'ti-k3-self-test' "$installer"
grep -Fq 'OpenHD consumer layer installed but NOT activated.' "$installer"
! grep -Eq '/sys/class/remoteproc|j722s-main-r5f0_0-fw|214ee24d|fcfd8a38|23d2c02c|0xa5000000|0xc0000000' "$bridge"
! grep -Eq 'OPENHD_REMOTEPROC|OPENHD_C7X_LOAD_DELAY|OPENHD_TI_REMOTE_LOGGER|OPENHD_CAMERA_DCC' "$camera_policy"
echo 'PASS: OpenHD pass-1 r0.3 consumer contract'

grep -Fq 'USER_MODULE_NAME=88XXau modules' "$root/install-live.sh"
! grep -Fq 'USER_MODULE_NAME=88XXau_ohd modules' "$root/install-live.sh"
echo 'PASS: RTL8812AU frozen-Alpha module naming contract'
