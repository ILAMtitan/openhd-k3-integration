# OpenHD BeagleY-AI unified camera selection R4 — final checkpoint 2026-09-02

R4 keeps the existing native TI J722S camera pipelines and adds one boot-time
camera selection/type handoff shared with `ti-k3-accelerators`.

## Frozen checkpoint

```text
repository: ILAMtitan/openhd-k3-integration
tag:        camera-r4-unified-20260902
commit:     6e046d23aa84eaef8c8f107fcad3b7cae7cd500f
TI tag:     camera-r4-unified-20260902
TI commit:  b32d11e99040042677ce318dcbf51b4c066ec529
```

The annotated tag is the immutable OpenHD R4 recovery point. The R4 branch was
fast-forward merged into `main` after qualification. Documentation-only commits
may therefore make `main` newer than the tag; the tag must not be moved.

## Camera map

| Sensor | OpenHD type | Native output profile | R4 status |
| --- | ---: | --- | --- |
| IMX219 | 150 | 1280x720p30 | Supported; not physically re-run during final R4 transition testing |
| IMX708 / Arducam B0310 | 151 | 1280x720p60 | R4 selection/type handoff qualified |
| IMX415 / Arducam B0569 | 152 | 1280x720p30 nominal | R4 selection/type handoff qualified |

The camera-specific OpenHD pipeline code is not retuned by R4. Physical camera
selection remains owned by the `ti-k3-accelerators` platform layer because CSI
routing, clocks, resets, and sensor endpoints are device-tree boot state.

## R4 application boundary

The user-facing wrapper delegates to the platform selector:

```bash
openhd-camera-select status
sudo openhd-camera-select imx219
sudo openhd-camera-select imx708
sudo openhd-camera-select imx415
```

After the platform layer has prepared the selected graph,
`openhd-ti-camera-prepare` reads `/run/ti-k3/camera.env` and maps the detected
sensor to the OpenHD camera type:

```text
imx219 -> 150
imx708 -> 151
imx415 -> 152
```

It validates configured-vs-detected sensor agreement and synchronizes both:

```text
/usr/local/share/OpenHD/SysUtils/config.json
/usr/local/share/openhd/video/air_camera_generic.json
```

Unrelated settings are preserved. `secondary_camera_type` is forced to 255 for
this single-camera TI boundary.

The R4 systemd drop-in clears stale camera-specific pre-start hooks and installs:

```text
ExecStartPre=/usr/local/sbin/openhd-ti-camera-prepare
```

while requiring the generic `ti-k3-camera-prepare.service`.

## Qualification results

### IMX415 — qualified

The R4 platform layer prepared the already-qualified IMX415 graph and published
the common camera contract. OpenHD then automatically synchronized to camera
type 152.

The qualification test deliberately used the previously qualified IMX415 OpenHD
binary/source state rather than changing transport behavior at the same time.
The service started successfully with:

```text
Camera: TI_J722S_IMX415
Gst state: SUCCESS / PLAYING
```

and OpenHD held the actual camera device:

```text
/dev/video2
```

The selected process was the qualified appsink256/drop=true binary used for the
R3 checkpoint.

### Physical IMX415 -> IMX708 transition — qualified

The platform selector was changed to IMX708 and the board was completely powered
off before physically replacing the IMX415 with the Arducam B0310 on CSI0.
After boot, `ti-k3-camera-prepare.service` automatically produced the IMX708
864p60 camera contract.

Without manually editing OpenHD settings, `openhd-ti-camera-prepare` reported:

```text
OpenHD TI camera ready: sensor=imx708 camera_type=151 mode=864p60
```

OpenHD then selected the expected native pipeline:

```text
Camera: TI_J722S_IMX708
```

and reached:

```text
Gst state: ret:SUCCESS state:PLAYING pending:VOID_PENDING ok_streaming:true
```

The running process held `/dev/video2`, confirming that the application was
consuming the camera selected through the R4 platform contract.

This demonstrated the complete R4 handoff:

```text
persistent camera selection
  -> different boot overlay
  -> different physical sensor
  -> generic TI camera graph preparation
  -> /run/ti-k3/camera.env
  -> automatic OpenHD camera_type 152 -> 151
  -> native IMX708 pipeline
  -> GStreamer PLAYING
```

### IMX219 — supported, not newly R4-qualified

IMX219 remains supported as camera type 150 on CSI1 and remains in the R4
selector/type mapping. The final package was frozen before performing a new
physical IMX219 transition, so it must not be described as newly R4-qualified.

## Qualified IMX415 transport state

The frozen R4 checkpoint intentionally retains the qualified IMX415 transport
state:

```text
appsink max-buffers=256
appsink drop=true
appsink sync=false
TI RTP fragment size=1024
```

A later temporary `drop=false` / `nodrop` experiment was present on the test AIR
at one point but was explicitly excluded from the R4 checkpoint and final
qualification path.

Visible IMX415 ground-side corruption investigation remains a separate
transport/RF/receiver work item. It is not part of the unified camera-selection
qualification.

## Install paths

For a fresh consumer install on a matching R4 accelerator platform:

```bash
sudo ./install-r4.sh --role air
```

For an already-installed AIR where only the R4 camera boundary is being added:

```bash
sudo ./install-camera-r4-live.sh
```

The live installer does not start OpenHD or reconfigure the camera by default.

R4 verification:

```bash
sudo ./verify-camera-r4.sh
```

## Source scope

R4 keeps the native camera patch stack based on upstream OpenHD commit:

```text
f07729b35e273fe3612e1aade030a7a86350d1ac
```

Camera patch sequence:

```text
0008  TI J722S IMX219 / type 150
0009  TI J722S IMX708 / type 151
0010  IMX708 720p60 finalization
0011  IMX708 720p60 qualification adjustments
0012  TI J722S IMX415 / type 152
```

R4 itself changes orchestration, settings synchronization, and systemd ordering;
it does not retune the underlying camera pipelines.

## Main-branch integration

The final R4 branch:

```text
camera-r4-unified-camera-selection-20260902
```

was strictly ahead of `main` with no divergent commits and was merged by
fast-forward. `main` is now the normal development baseline for unified camera
selection.

For exact reproduction or recovery, use the immutable tag:

```bash
git checkout camera-r4-unified-20260902
```
