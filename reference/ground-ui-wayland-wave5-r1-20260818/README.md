# BeagleY-AI Ground UI Checkpoint

Date: 2026-08-18

## Qualified state

- BeagleY-AI / AM67A
- Weston/Wayland on Waveshare 5-inch DSI display
- DSI native mode 720x1280 with Weston rotate-90
- QOpenHD internal rotation = 0
- Weston dynamically selects the DRM card owning the connected DSI connector
- seatd + weston-k3.service survive cold boot
- Qt5 Wayland EGL / PowerVR GLES rendering
- Patched GStreamer 1.24.2 Qt5 qmlglsink with GLES2 precision directives
- QOpenHD H.264 decode explicitly uses TI Wave5 v4l2h264dec
- Wave5 output: I420 1280x720 at 30 fps
- qmlgl input: RGBA GLMemory 1280x720 at 30 fps
- qmlgl binds live changing GL texture IDs
- Low-latency queue: 1 buffer, downstream leaky
- Synthetic RTP bouncing-ball test rendered smoothly inside QOpenHD

## Qualified QOpenHD video path

udpsrc -> rtph264depay -> h264parse ->
v4l2h264dec capture-io-mode=dmabuf ->
queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream ->
glupload -> glcolorconvert -> qmlglsink sync=false

## Weston

weston-k3.service uses /usr/local/sbin/weston-k3-launch.
The launcher discovers the connected card*-DSI-* connector instead of assuming card0/card1.

## Remaining qualification

This checkpoint proves synthetic localhost RTP H.264 through Wave5 and QOpenHD.
Real OpenHD Ground RF/Air video input has not yet been qualified against this UI checkpoint.
