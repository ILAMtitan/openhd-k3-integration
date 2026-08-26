#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
patch9="$root/patches/openhd/0009-video-add-native-TI-J722S-IMX708-pipeline.patch"
patch10="$root/patches/openhd/0010-video-finalize-TI-J722S-IMX708-720p60.patch"
patch11="$root/patches/openhd/0011-video-qualify-TI-J722S-IMX708-720p60.patch"
patch12="$root/patches/openhd/0012-video-add-native-TI-J722S-IMX415-pipeline.patch"
apply="$root/apply-imx415-checkpoint.sh"
prep="$root/overlay/usr/local/sbin/openhd-ti-imx415-prepare"
verify="$root/verify-imx415-checkpoint.sh"

for f in "$patch9" "$patch10" "$patch11" "$patch12" "$apply" "$prep" "$verify"; do
  [[ -s "$f" ]]
done

# Final-qualified IMX708 base must remain intact under the IMX415 layer.
grep -Fq 'width=1536,height=864' "$patch10"
grep -Fq 'framerate=60/1' "$patch10"
grep -Fq 'tiovxmultiscaler target=0' "$patch10"
grep -Fq 'sink_0::pool-size=2' "$patch11"
grep -Fq 'src::pool-size=2' "$patch11"
grep -Fq 'level=(string)3.2' "$patch11"
grep -Fq 'create_ti_j722s_imx708_stream' "$patch11"

# IMX415 remains a separate type152 R0 layer.
grep -Fq 'X_CAM_TYPE_TI_J722S_IMX415' "$patch12"
grep -Fq '"id": 152' "$patch12"
grep -Fq 'format=gbrg10le,width=3864,height=2192' "$patch12"
grep -Fq 'capssetter caps=\"video/x-bayer,format=gbrg10\"' "$patch12"
grep -Fq 'dcc_viss_3864x2192.bin' "$patch12"
grep -Fq 'sink_0::ae-mode=AE_MODE_DISABLED' "$patch12"
grep -Fq 'sink_0::awb-mode=AWB_MODE_DISABLED' "$patch12"
grep -Fq 'tiovxmultiscaler target=0' "$patch12"
grep -Fq 'format=NV12,width=1280,height=720,framerate=30/1' "$patch12"
grep -Fq 'ret.h26x_bitrate_kbits = 6000;' "$patch12"
grep -Fq 'ret.h26x_keyframe_interval = 15;' "$patch12"
! grep -Fq 'ret.primary_camera_type = X_CAM_TYPE_TI_J722S_IMX415' "$patch12"

# Reproducible combined apply path must preserve qualified R3 appsink and CMA fix.
grep -Fq "BASE_SRC=\${BASE_SRC:-/var/tmp/openhd-k3-consumer-build/OpenHD}" "$apply"
grep -Fq "--exclude='OpenHD/ohd_video/src/gstreamerstream.cpp'" "$apply"
grep -Fq '0011-video-qualify-TI-J722S-IMX708-720p60.patch' "$apply"
grep -Fq '0012-video-add-native-TI-J722S-IMX415-pipeline.patch' "$apply"
grep -Fq 'GST_OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so' "$apply"
grep -Fq 'appsink max-buffers=64 drop=true sync=false' "$apply"
grep -Fq "d['primary_camera_type']=152" "$apply"
grep -Fq "fmt['framerate']=30" "$apply"

grep -Fq 'ti-k3-configure-imx415-graph' "$prep"
grep -Fq 'TI_K3_CAMERA_DETECTED_SENSOR=imx415' "$verify"
grep -Fq 'gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so' "$verify"

echo 'PASS: final IMX708 base + IMX415 R0 source contract'
