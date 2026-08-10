# openhd-k3-integration — split pass 1 r0.2

This tree is the OpenHD-specific consumer of a separately-qualified
`ti-k3-accelerators` platform. It does **not** own the J722S memory map,
Vision Apps firmware, remoteproc sequencing, DMA heaps, TIOVX runtime, VPAC
platform setup, or Wave5 platform enablement.

Required platform API:

- `ti-k3-accelerators.target`
- `ti-k3-rpmsg-ready`
- `ti-k3-self-test`
- `ti-k3-imx219-prepare.service`
- `/etc/ti-k3/gstreamer.env`
- `/run/ti-k3/camera.env`
- functioning Wave5 V4L2 encoder

OpenHD owns RF, role, bitrate/GOP, output resolution, RTP localhost:5500,
camera application lifecycle, and telemetry UART policy.

## Live qualification flow

1. Preserve the already-qualified TI-only boot with `capture-ti-baseline.sh`.
2. Run `sudo ./install-live.sh --role air` on that same TI-only image.
3. The installer leaves `openhd-k3-consumer.target` disabled and stopped.
4. Start the camera bridge alone and verify localhost RTP.
5. Start OpenHD and verify the RF path.
6. Only after qualification, enable `openhd-k3-consumer.target` and cold boot.

The installer refuses to proceed if the TI platform self-test or RPMsg contract
is unhealthy. It never manipulates remoteproc or installs Vision Apps firmware.

## r0.3 fix

r0.3 restores the frozen R7.33.4.1 RTL8812AU build contract: pass
`USER_MODULE_NAME=88XXau` to the pinned driver build and install the resulting
`88XXau_ohd.ko`. r0.2 incorrectly passed the already-suffixed name and could
produce `88XXau_ohd_ohd.ko`.

If r0.2 already failed after successfully compiling that double-suffixed module,
run `continue-after-rtl-name-failure.sh` as root. It rebuilds only RTL8812AU,
reuses the already-installed OpenHD/SysUtils outputs, and completes the systemd
consumer boundary without touching TI remoteproc or firmware state.
