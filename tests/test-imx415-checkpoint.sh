#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
patch9="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
patch10="$root/patches/openhd/0010-video-add-native-TI-J722S-IMX415-pipeline.patch"
apply="$root/apply-imx415-checkpoint.sh"
prep="$root/overlay/usr/local/sbin/openhd-ti-imx415-prepare"
verify="$root/verify-imx415-checkpoint.sh"

for f in "$patch9" "$patch10" "$apply" "$prep" "$verify"; do
  [[ -s "$f" ]]
done

grep -Fq 'X_CAM_TYPE_TI_J722S_IMX415' "$patch10"
grep -Fq '"id": 152' "$patch10"
grep -Fq 'format=gbrg10le,width=3864,height=2192' "$patch10"
grep -Fq 'capssetter caps=\"video/x-bayer,format=gbrg10\"' "$patch10"
grep -Fq 'dcc_viss_3864x2192.bin' "$patch10"
grep -Fq 'sink_0::ae-mode=AE_MODE_DISABLED' "$patch10"
grep -Fq 'sink_0::awb-mode=AWB_MODE_DISABLED' "$patch10"
grep -Fq 'tiovxmultiscaler target=0' "$patch10"
grep -Fq 'format=NV12,width=1280,height=720,framerate=30/1' "$patch10"
grep -Fq 'ret.h26x_bitrate_kbits = 6000;' "$patch10"
grep -Fq 'ret.h26x_keyframe_interval = 15;' "$patch10"

# IMX415 is not made the clean-install default before hardware qualification.
! grep -Fq 'ret.primary_camera_type = X_CAM_TYPE_TI_J722S_IMX415' "$patch10"

# The live apply path reconstructs and checks the R3 source before adding 9/10.
grep -Fq 'R3_TREE=01fe7bf68d39ca6d9be747668910c841a11abe17' "$apply"
grep -Fq '000[1-8]-*.patch' "$apply"
grep -Fq '0009-*.patch' "$apply"
grep -Fq '0010-*.patch' "$apply"
grep -Fq "d['primary_camera_type']=152" "$apply"

grep -Fq 'ti-k3-configure-imx415-graph' "$prep"
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx415' "$verify"

echo 'PASS: IMX415 R0 source contract'
