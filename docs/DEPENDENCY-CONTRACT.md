# Dependency contract

The OpenHD integration layer consumes a separately qualified TI J722S
accelerator platform. It does not own or reproduce TI platform internals.

## Bring-up order

Use the layers in this order:

```text
qualified ti-k3-accelerators platform
-> verify accelerator and RPMsg readiness
-> air only: verify IMX219 camera contract
-> install OpenHD consumer integration
-> verify OpenHD software contract
-> verify the intended air/ground system
```

If the TI platform is unhealthy, fix or restore that layer first. OpenHD must
not change TI firmware, memory carveouts, or remoteproc state as a workaround.

## Native-R1 camera flow

For the air role:

```text
IMX219 on CSI0
-> TI camera device contract
-> TIOVX ISP
-> TIOVX multiscaler
-> NV12 1280x720
-> Wave5 H.264
-> OpenHD parse / RTP packetization / appsink
```

The final Native-R1 path has no localhost UDP `127.0.0.1:5500` camera bridge.

## Required TI platform API — both roles

Both air and ground consume:

- `ti-k3-accelerators.target`
- `ti-k3-rpmsg-ready`
- `ti-k3-self-test`
- `/etc/ti-k3/gstreamer.env`

## Additional TI platform API — air only

The air role additionally consumes:

- `ti-k3-imx219-prepare.service`
- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`
- functional `tiovxisp`
- functional `tiovxmultiscaler`
- functional Wave5 `v4l2h264enc`
- TI-provided IMX219 DCC assets

The ground role deliberately has no local camera requirement.

## OpenHD ownership

OpenHD owns:

- OpenHD/SysUtils platform recognition
- selected air/ground role
- camera application lifecycle on air units
- output resolution
- H.264 bitrate/GOP configuration
- H.264 RTP packetization
- application-side interface policy
- telemetry UART policy
- ordering between OpenHD, SysUtils, and the public TI platform services

For Native-R1, the qualified J722S defaults are 1280x720@30, H.264,
3000 kbit/s, GOP 15, and RTP fragmentation of 1024 bytes.

Runtime Wave5 bitrate control is intentionally outside Native-R1.

## TI platform ownership

The TI platform owns:

- remoteproc lifecycle and sequencing
- R5/C7x firmware aliases and binaries
- qualified firmware identity
- memory map and DMA carveouts
- TIOVX runtime
- Wave5 platform enablement
- camera discovery and device aliases
- DCC assets

OpenHD integration must not write remoteproc state, choose firmware aliases,
encode TI memory-map addresses, create carveouts, or build/install a separate
TIOVX platform runtime.

## Source-change rationale

The reason for each active OpenHD and SysUtils patch is documented in the
repository [`README.md`](../README.md), under **Why the OpenHD patches are
required** and **Why the SysUtils patches are required**.

## Host integration

The active application-side files are under `overlay/`. They contain the host
interface, management-network, UART, and service helpers needed by this
BeagleY-AI consumer.

`reference/r73341/` is historical evidence only and is not consumed by the
current installer.

## Role-specific systemd boundary

For **air**, `openhd.service` requires the TI accelerator target and IMX219
preparation service and imports `/etc/ti-k3/gstreamer.env`.

For **ground**, `openhd.service` requires the TI accelerator target but not the
IMX219 service or `/run/ti-k3/camera-*` contract.

The installer leaves `openhd-k3-consumer.target` stopped and disabled so manual
verification occurs before automatic startup.

## Verification boundary

`verify-consumer.sh` verifies TI platform health, selected role, process count,
runtime environment inheritance, and the air-only camera contract/ownership. It
also checks that the retired localhost UDP 5500 topology has not returned.

The frozen Native-R1 source and hardware results are documented in
[`OPENHD-NATIVE-R1-QUALIFICATION.md`](OPENHD-NATIVE-R1-QUALIFICATION.md).
