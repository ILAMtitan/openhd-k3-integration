#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
patch9="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
patch10="$root/patches/openhd/0010-video-finalize-TI-J722S-IMX708-720p60.patch"
prep="$root/overlay/usr/local/sbin/openhd-ti-imx708-prepare"
apply="$root/apply-imx708-checkpoint.sh"
verify="$root/verify-imx708-checkpoint.sh"
doc="$root/docs/OPENHD-IMX708-720P60-R2-20260825.md"

for f in "$patch9" "$patch10" "$prep" "$apply" "$verify" "$doc"; do
  [[ -s "$f" ]]
done

grep -Fq 'X_CAM_TYPE_TI_J722S_IMX708' "$patch9"
grep -Fq '"id": 151' "$patch9"
grep -Fq 'ret.h26x_bitrate_kbits = 6000;' "$patch9"
grep -Fq 'max-buffers=64 drop=true sync=false' "$patch9"

grep -Fq 'width=1536,height=864' "$patch10"
grep -Fq 'framerate=60/1' "$patch10"
grep -Fq 'dcc_viss_1536x864.bin' "$patch10"
grep -Fq 'dcc_2a_1536x864.bin' "$patch10"
grep -Fq 'tiovxmultiscaler target=0' "$patch10"
grep -Fq 'width=1280,height=720' "$patch10"
grep -Fq 'ret.h26x_keyframe_interval = 30;' "$patch10"
grep -Fq '{"width": 1280, "height": 720, "fps": 60}' "$patch10"

grep -Fq 'OPENHD_IMX708_MODE:-864p60' "$prep"
grep -Fq 'OPENHD_IMX708_EXPOSURE:-1280' "$prep"
grep -Fq 'OPENHD_IMX708_ANALOGUE_GAIN:-512' "$prep"
grep -Fq 'OPENHD_IMX708_DIGITAL_GAIN:-256' "$prep"
grep -Fq 'dcc_viss_1536x864.bin' "$prep"

grep -Fq 'git -C "$WORK" apply "$PATCH9"' "$apply"
grep -Fq 'git -C "$WORK" apply "$PATCH10"' "$apply"
grep -Fq "d['primary_camera_type']=151" "$apply"
grep -Fq "d['h26x_bitrate_kbits']=6000" "$apply"
grep -Fq "d['h26x_keyframe_interval']=30" "$apply"
grep -Fq 'TI_K3_CAMERA_MODE=864p60' "$apply"
grep -Fq 'ExecStartPre=/usr/local/sbin/openhd-ti-imx708-prepare' "$apply"

grep -Fq 'pipeline output is 1280x720p60 through TIOVX multiscaler' "$verify"
grep -Fq 'sensor VBLANK is 946 for ~60 fps' "$verify"

echo 'PASS: IMX708 720p60 R2 OpenHD checkpoint contract'
