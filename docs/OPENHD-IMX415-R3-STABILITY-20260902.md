# OpenHD TI J722S IMX415 R3 stability checkpoint

Date: 2026-09-02

OpenHD base:

f07729b35e273fe3612e1aade030a7a86350d1ac

Camera:
- TI_J722S_IMX415
- camera type 152
- 3864x2192 RAW10
- VISS
- 1280x720 NV12
- Wave5 H.264
- 6 Mbit/s
- GOP 15

Transport checkpoint:
- TI RTP fragmentation: 1024 bytes
- appsink max-buffers=256
- drop=true
- sync=false

Camera-side R3:
- active-low reset on MCU_GPIO0_15
- 20-22 ms IMX415 post-reset settling interval
- warm reboot recovery qualified
- runtime-PM resume qualified

Long-run OpenHD qualification:
- continuous operation for more than one hour
- same OpenHD PID
- zero no-frame events
- zero camera restarts
- zero pipeline restarts

A local H.264 recording directly after Wave5/h264parse was clean during the
same motion stimulus that causes visible corruption on the ground stream.

Therefore the remaining artifact is downstream of local H.264 encoding:
RTP/appsink/WiFiBroadcast/RF/ground receive/decode.

The next proposed experiment is appsink drop=false. That experiment is not part
of this qualified checkpoint.

Performance remains a separate open item: the complete processing path is
stable but presently runs at approximately 27 fps rather than the requested
30 fps.
