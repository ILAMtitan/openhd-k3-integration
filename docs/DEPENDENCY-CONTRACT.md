# Dependency contract

The OpenHD integration layer consumes a separately qualified TI J722S
accelerator platform. It does not own or reproduce TI platform internals.

## Native-R1 camera flow

IMX219
-> TI camera device alias
-> TIOVX ISP
-> TIOVX multiscaler
-> NV12 1280x720
-> Wave5 H.264
-> OpenHD H.264 parse / RTP packetization / appsink
-> wifibroadcast
-> RF

The normal Native-R1 path has no localhost UDP `127.0.0.1:5500` bridge.

## Required TI platform API

OpenHD may depend on:

- `ti-k3-accelerators.target`
- `ti-k3-rpmsg-ready`
- `ti-k3-self-test`
- `ti-k3-imx219-prepare.service`
- `/etc/ti-k3/gstreamer.env`
- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`
- functional `tiovxisp`
- functional `tiovxmultiscaler`
- functional Wave5 `v4l2h264enc`
- TI-provided IMX219 DCC assets

## OpenHD ownership

OpenHD owns:

- camera application lifecycle
- output resolution
- H.264 bitrate/GOP configuration
- H.264 RTP packetization
- RF / wifibroadcast
- radio policy
- telemetry UART policy

For Native-R1, the qualified J722S defaults are 1280x720@30, H.264,
3000 kbit/s, GOP 15, and RTP fragmentation of 1024 bytes.

Runtime Wave5 bitrate control is intentionally outside Native-R1.

## TI platform ownership

The TI platform owns:

- remoteproc lifecycle and sequencing
- R5/C7x firmware aliases
- firmware binaries
- qualified firmware identity
- memory map
- DMA carveouts
- TIOVX runtime
- Wave5 platform enablement
- camera discovery and device aliases
- DCC assets

OpenHD integration must not write remoteproc state, choose firmware aliases,
encode TI memory-map addresses, enforce TI firmware hashes, create carveouts,
or build/install the TIOVX platform runtime.

## Transport boundary

Native-R1 does not use or ship a localhost camera bridge. The native path feeds the TI-accelerated H.264 stream directly into OpenHD, and consumer verification requires no UDP listener on `127.0.0.1:5500`.
