# OpenHD BeagleY-AI unified camera selection R4 — final checkpoint 2026-09-02

R4 keeps the three existing native TI J722S OpenHD pipelines and adds one
boot-time camera selection boundary shared with `ti-k3-accelerators`.

| Sensor | OpenHD type | Output profile | R4 status |
| --- | ---: | --- | --- |
| IMX219 | 150 | 1280x720p30 | Supported; not re-qualified during the R4 checkpoint |
| IMX708 | 151 | 1280x720p60 | R4 selection/type handoff qualified |
| IMX415 | 152 | 1280x720p30 nominal (currently ~27 fps complete path) | R4 selection/type handoff qualified |

The camera-specific OpenHD pipeline code is not changed by R4. Selection is
owned by the `ti-k3-accelerators` platform layer because sensor identity, CSI
routing, clocks and reset controls are device-tree boot state.

User interface:

```sh
openhd-camera-select status
sudo openhd-camera-select imx219
sudo openhd-camera-select imx708
sudo openhd-camera-select imx415
```

Changing the camera overlay requires a reboot. On startup,
`ti-k3-camera-prepare.service` validates that the selected and probed sensors
match, configures the correct media graph, and publishes `/run/ti-k3/camera.env`.

`openhd-ti-camera-prepare` then maps the detected sensor immediately before
`openhd.service` starts:

- IMX219 -> OpenHD type 150
- IMX708 -> OpenHD type 151
- IMX415 -> OpenHD type 152

It synchronizes both:

- `/usr/local/share/OpenHD/SysUtils/config.json`
- `/usr/local/share/openhd/video/air_camera_generic.json`

Existing unrelated JSON settings are preserved. The hardware-selected sensor is
therefore authoritative even if OpenHD persisted a different camera type from a
previous boot.

The R4 systemd drop-in explicitly clears stale camera-specific `ExecStartPre`
entries before installing the generic `openhd-ti-camera-prepare` hook. This was
required on the qualification AIR unit because older IMX708 and appsink A/B
experiments had left multiple ordered drop-ins in place.

## Qualified OpenHD source/binary baseline

R4 was intentionally tested without changing the previously qualified OpenHD
transport implementation. The tested executable was:

`/usr/local/bin/openhd-native-imx415-full-appsink256`

Qualified SHA256:

`c5b506b717ddc72f029a9a5f03bfa60fa05f99d80ab80618d1888a92668acffd`

The filename is historical: the source tree contains the combined TI J722S
IMX219, IMX708 and IMX415 camera paths. The exact tracked source checkpoint is
stored under:

`reference/imx415-r3-20260902/openhd-r3-full-live-diff.patch`

against upstream OpenHD commit:

`f07729b35e273fe3612e1aade030a7a86350d1ac`

That checkpoint uses:

- TI RTP fragment size 1024
- appsink `max-buffers=256`
- appsink `drop=true`
- appsink `sync=false`

The later `openhd-native-imx415-full-appsink256-nodrop` / `drop=false`
experiment was not qualified and is explicitly outside this R4 checkpoint.

## R4 qualification results

### IMX415 -> OpenHD type 152

With the R4 generic TI camera service prepared on the R3-qualified B0569 sensor,
`openhd-ti-camera-prepare` selected camera type 152 successfully. `openhd.service`
then started with the exact qualified appsink256/drop=true executable.

Observed acceptance points:

- `ExecStartPre=/usr/local/sbin/openhd-ti-camera-prepare` completed successfully.
- OpenHD reported `Camera: TI_J722S_IMX415`.
- GStreamer transitioned to `PLAYING` with `ok_streaming:true`.
- OpenHD owned the resolved TI capture node `/dev/video2`.
- No camera-specific pipeline changes were introduced by R4.

### Physical IMX415 -> IMX708 transition

The camera was selected with R4, the AIR was fully powered off, the B0569 was
replaced with the B0310 on CSI0, and the board was powered back on. The generic
accelerator layer detected and prepared IMX708 in `864p60` mode.

Without manually editing OpenHD settings, `openhd-ti-camera-prepare` produced:

`OpenHD TI camera ready: sensor=imx708 camera_type=151 mode=864p60`

OpenHD then started with the same qualified combined executable. Observed
acceptance points:

- OpenHD reported `Camera: TI_J722S_IMX708`.
- GStreamer transitioned to `PLAYING` with `ok_streaming:true`.
- OpenHD owned `/dev/video2`.
- The existing native IMX708 path was selected automatically from type 151.

This validates the R4 chain from persistent camera selection through a different
DT overlay and physical sensor to automatic OpenHD camera-type/pipeline
selection.

No new R4 claim is made here about RF-link visual quality beyond the earlier
camera pipeline qualifications; this checkpoint specifically qualifies the new
selection/orchestration boundary through successful OpenHD pipeline startup and
camera ownership.

### IMX219

IMX219 type 150 remains present in the combined branch and selector, but the R4
package was frozen before a new physical IMX219 transition was performed. It
must therefore be described as supported but not newly R4-qualified.

## Scope and recovery

R4 deliberately does not change camera-specific GStreamer pipeline tuning, RTP
fragmentation, Wave5 settings or the qualified appsink behavior. The IMX415
transport-artifact investigation remains a separate work item.

For migration on an already-installed AIR unit,
`./install-camera-r4-live.sh` installs only the R4 camera boundary and does not
replace the current OpenHD executable. `./install-r4.sh` remains the wrapper for
a fresh consumer installation on an R4 accelerator platform.

Canonical R4 branch:

`camera-r4-unified-camera-selection-20260902`

R4 starts from OpenHD integration R3 checkpoint
`7656aa08591aa9e4e57a8619925344e143dc980a`.
