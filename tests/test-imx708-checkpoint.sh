#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
patch9="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
prep="$root/overlay/usr/local/sbin/openhd-ti-imx708-prepare"
apply="$root/apply-imx708-checkpoint.sh"
verify="$root/verify-imx708-checkpoint.sh"
doc="$root/docs/OPENHD-IMX708-R1-20260821.md"

for f in "$patch9" "$prep" "$apply" "$verify" "$doc"; do
  [[ -s "$f" ]]
done

grep -Fq 'X_CAM_TYPE_TI_J722S_IMX708' "$patch9"
grep -Fq '"id": 151' "$patch9"
grep -Fq 'rggb10le' "$patch9"
grep -Fq 'dcc_viss_2304x1296.bin' "$patch9"
grep -Fq 'sink_0::ae-mode=AE_MODE_DISABLED' "$patch9"
grep -Fq 'sink_0::awb-mode=AWB_MODE_DISABLED' "$patch9"
grep -Fq 'ret.h26x_bitrate_kbits = 6000;' "$patch9"
grep -Fq 'ret.h26x_keyframe_interval = 28;' "$patch9"
grep -Fq 'max-buffers=64 drop=true sync=false' "$patch9"

grep -Fq 'OPENHD_IMX708_EXPOSURE:-1280' "$prep"
grep -Fq 'OPENHD_IMX708_ANALOGUE_GAIN:-512' "$prep"
grep -Fq 'OPENHD_IMX708_DIGITAL_GAIN:-256' "$prep"
grep -Fq 'ti-k3-configure-imx708-graph --mode "$MODE"' "$prep"

grep -Fq 'primary_camera_type' "$apply"
grep -Fq "d['primary_camera_type']=151" "$apply"
grep -Fq "d['h26x_bitrate_kbits']=6000" "$apply"
grep -Fq 'ExecStartPre=/usr/local/sbin/openhd-ti-imx708-prepare' "$apply"
grep -Fq 'systemctl disable openhd.service' "$apply"

grep -Fq 'Wave5 startup bitrate is 6 Mbit/s' "$verify"
grep -Fq 'manual analogue gain is 512' "$verify"

echo 'PASS: IMX708 R1 OpenHD checkpoint contract'
