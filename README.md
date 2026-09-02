# openhd-k3-integration

OpenHD consumer integration for the separately qualified
[`ti-k3-accelerators`](https://github.com/ILAMtitan/ti-k3-accelerators)
platform on BeagleY-AI / TI J722S (AM67A).

This repository owns the OpenHD/SysUtils/application boundary. The underlying
TI firmware, remoteproc sequence, reserved memory, TIOVX runtime, DMA heaps,
Wave5 platform integration, and camera device-tree selection remain owned by
`ti-k3-accelerators`.

## Current main baseline: Camera R4 unified selection

`main` now contains the R4 unified camera-selection integration.

Final R4 checkpoint:

```text
OpenHD integration tag:    camera-r4-unified-20260902
OpenHD integration commit: 6e046d23aa84eaef8c8f107fcad3b7cae7cd500f
TI accelerator tag:        camera-r4-unified-20260902
TI accelerator commit:     b32d11e99040042677ce318dcbf51b4c066ec529
```

R4 keeps the existing native TI J722S camera pipelines and adds a common
boot-time camera selection/type handoff.

| Camera | OpenHD type | Native output profile | R4 status |
| --- | ---: | --- | --- |
| IMX219 | 150 | 1280x720p30 | Supported; not physically re-run during final R4 transition test |
| IMX708 / Arducam B0310 | 151 | 1280x720p60 | R4 selection/type handoff qualified |
| IMX415 / Arducam B0569 | 152 | 1280x720p30 nominal | R4 selection/type handoff qualified |

The R4 checkpoint physically demonstrated an IMX415 -> IMX708 change across a
power-off camera swap and boot-overlay transition, followed by automatic graph
selection, OpenHD camera-type synchronization, pipeline selection, and successful
GStreamer `PLAYING` state.

See
[`docs/OPENHD-CAMERA-R4-UNIFIED-SELECTION-20260902.md`](docs/OPENHD-CAMERA-R4-UNIFIED-SELECTION-20260902.md)
for the final qualification record.

## Camera selection

The platform selector is exposed through a small OpenHD wrapper:

```bash
sudo openhd-camera-select status
sudo openhd-camera-select imx219
sudo openhd-camera-select imx708
sudo openhd-camera-select imx415
```

Changing cameras updates the platform-owned selection and boot overlay. Power
the board off before physically changing CSI cameras, then boot with the camera
that matches the selected overlay.

On startup, `ti-k3-camera-prepare.service` validates and configures the selected
camera and publishes:

```text
/run/ti-k3/camera.env
/run/ti-k3/camera-video
/run/ti-k3/camera-subdev
```

Immediately before OpenHD starts, `openhd-ti-camera-prepare` maps the detected
sensor to OpenHD type 150/151/152 and synchronizes both:

```text
/usr/local/share/OpenHD/SysUtils/config.json
/usr/local/share/openhd/video/air_camera_generic.json
```

Existing unrelated settings in those files are preserved.

## Install

### Fresh R4 consumer install

Start from a BeagleY-AI image with the matching R4 `ti-k3-accelerators` camera
layer already installed, then use:

```bash
sudo ./install-r4.sh --role air
```

For a ground role:

```bash
sudo ./install-r4.sh --role ground
```

`install-r4.sh` runs the pinned OpenHD consumer installation and then installs
the R4 camera-selection boundary for an air unit.

### Add R4 to an existing installed AIR

For an AIR unit that already has the qualified OpenHD consumer stack installed:

```bash
sudo ./install-camera-r4-live.sh
```

This installs only the R4 camera helpers/drop-in and does **not** start OpenHD or
reconfigure the camera by default.

Optional camera preparation after installation:

```bash
sudo ./install-camera-r4-live.sh --prepare
```

## Verify

Use the R4 camera-boundary verifier:

```bash
sudo ./verify-camera-r4.sh
```

Useful direct checks are:

```bash
openhd-camera-select status
cat /run/ti-k3/camera.env
cat /usr/local/share/OpenHD/SysUtils/config.json
cat /usr/local/share/openhd/video/air_camera_generic.json
systemctl status ti-k3-camera-prepare.service --no-pager
systemctl status openhd.service --no-pager
```

The R4 verifier checks the selected/detected sensor agreement, common camera
aliases, mapped OpenHD camera type, and the R4 OpenHD pre-start boundary.

## Native camera architecture

The air-unit path is native end-to-end:

```text
selected CSI sensor
  -> TI CSI2RX / /run/ti-k3/camera-video
  -> TIOVX ISP / VPAC VISS
  -> TIOVX MultiScaler
  -> Wave5 H.264
  -> OpenHD H.264 parse / RTP / appsink
  -> wifibroadcast
  -> RF
  -> OpenHD ground receiver
```

There is no localhost camera bridge in the normal native TI path.

## Source basis

The integration remains based on pinned upstream OpenHD commit:

```text
f07729b35e273fe3612e1aade030a7a86350d1ac
```

The camera patch stack includes the native TI J722S paths for:

```text
0008  IMX219 / camera type 150
0009  IMX708 / camera type 151
0010  IMX708 720p60 finalization
0011  IMX708 720p60 qualification adjustments
0012  IMX415 / camera type 152
```

R4 itself is an orchestration/integration change; it does not retune the
camera-specific GStreamer pipelines.

## IMX415 transport note

The frozen R4 checkpoint uses the qualified IMX415 OpenHD source state with:

```text
appsink max-buffers=256
appsink drop=true
appsink sync=false
TI RTP fragment size=1024
```

The later `drop=false` / `nodrop` experiment was intentionally **not** included
in the R4 checkpoint. Remaining IMX415 ground-side corruption investigation is a
separate transport/RF/receiver work item, not part of camera-selection R4.

## Ownership boundary

`openhd-k3-integration` owns:

- OpenHD and SysUtils build/integration
- camera-type synchronization from the platform contract
- OpenHD service ordering against the generic TI camera prepare service
- RF/wifibroadcast consumer integration
- management Wi-Fi and application networking integration
- application-level verification

It does not own:

- TI remoteproc/RPMsg firmware lifecycle
- TI reserved-memory layout or DMA heaps
- TIOVX installation
- Wave5 platform bring-up
- CSI device-tree overlays or physical camera selection

See [`docs/DEPENDENCY-CONTRACT.md`](docs/DEPENDENCY-CONTRACT.md) for the layer
boundary.

## Recovery point

The current frozen R4 recovery tag is:

```text
camera-r4-unified-20260902
```

That tag remains fixed at the tested R4 integration commit. `main` may advance
with documentation or future development; do not move the checkpoint tag.

Older Native-R1/R2/R3 documentation and camera-specific qualification records
remain under `docs/` and `reference/` for historical recovery and comparison.
