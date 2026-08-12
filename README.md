# openhd-k3-integration — Native-R1

This repository is the OpenHD consumer layer for a separately qualified
TI J722S / AM67A `ti-k3-accelerators` platform on BeagleY-AI.

The frozen Native-R1 OpenHD patch stack is `reference/patches/openhd/0001..0008`,
based on upstream OpenHD commit:

`f07729b35e273fe3612e1aade030a7a86350d1ac`

The qualified reconstructed OpenHD source tree is:

`01fe7bf68d39ca6d9be747668910c841a11abe17`

The earlier qualification point is preserved by tag:

`openhd-native-r1-20260812`

## Native-R1 architecture

Normal air-unit video flow:

IMX219
-> `/run/ti-k3/camera-video`
-> TIOVX ISP
-> TIOVX multiscaler
-> Wave5 H.264
-> OpenHD H.264 parse / RTP packetization / appsink
-> wifibroadcast
-> RF

There is no localhost UDP `127.0.0.1:5500` bridge in the normal Native-R1 path.

The old `openhd-ti-camera-bridge` artifacts remain installed only as
legacy rollback/reference material. They are not Wanted or Required by the
normal Native-R1 systemd topology.

## Required TI platform API

OpenHD consumes these public TI K3 interfaces:

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

OpenHD does not own remoteproc sequencing, TI firmware, memory carveouts,
DMA heaps, TIOVX installation, Wave5 platform enablement, or DCC provisioning.

## OpenHD ownership

OpenHD owns:

- application camera lifecycle
- output resolution
- configured H.264 bitrate and GOP
- H.264 parse and RTP packetization
- RF / wifibroadcast
- radio policy
- telemetry UART policy

Native-R1 defaults are 1280x720@30 H.264, 3000 kbit/s, GOP 15, and
1024-byte RTP fragmentation for the J722S camera path.

Live Wave5 bitrate changes are intentionally not part of Native-R1.

## Clean-install qualification flow

1. Begin with a clean, already-qualified TI R2 baseline.
2. Preserve that baseline with `capture-ti-baseline.sh`.
3. Run `sudo ./install-live.sh --role air`.
4. The installer reconstructs OpenHD from the pinned upstream commit plus frozen
   patches and verifies the resulting Git tree identity.
5. The installer leaves `openhd-k3-consumer.target` disabled and stopped.
6. Start it manually with `systemctl start openhd-k3-consumer.target`.
7. Run `sudo ./verify-consumer.sh`.
8. Verify physical RF video.
9. Enable `openhd-k3-consumer.target`.
10. Perform a full physical cold power cycle.
11. Re-run verification and confirm physical RF video again.

Do not warm-restart remoteprocs during qualification.

## Legacy bridge

The following remain only for rollback/reference:

- `adapter/overlay/usr/local/sbin/openhd-ti-camera-bridge`
- `adapter/overlay/etc/systemd/system/openhd-ti-camera-bridge.service`

Native-R1 verification requires the bridge service to remain inactive and
requires no UDP listener on `127.0.0.1:5500`.

`continue-after-rtl-name-failure.sh` is retained for the historical interrupted
RTL8812AU naming-failure case, but now finishes the Native-R1 systemd topology
rather than restoring the old bridge topology.
