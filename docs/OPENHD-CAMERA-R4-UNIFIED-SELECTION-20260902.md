# OpenHD BeagleY-AI unified camera selection R4

R4 keeps the three existing native TI J722S OpenHD pipelines and adds one
boot-time camera selection boundary.

| Sensor | OpenHD type | Output profile |
| --- | ---: | --- |
| IMX219 | 150 | 1280x720p30 |
| IMX708 | 151 | 1280x720p60 |
| IMX415 | 152 | 1280x720p30 nominal (currently ~27 fps complete path) |

The camera-specific OpenHD pipeline code is not changed by R4. Selection is
performed by the `ti-k3-accelerators` platform layer because the sensor, CSI
routing, clocks and reset controls are device-tree boot state.

User interface:

```sh
openhd-camera-select status
sudo openhd-camera-select imx219
sudo openhd-camera-select imx708
sudo openhd-camera-select imx415
```

Changing the boot overlay requires a reboot. On startup,
`ti-k3-camera-prepare.service` validates that the selected and probed sensors
match, configures the correct media graph, and publishes `/run/ti-k3/camera.env`.

`openhd-ti-camera-prepare` then maps the detected sensor to OpenHD type
150/151/152 immediately before `openhd.service` starts. It updates both:

- `/usr/local/share/OpenHD/SysUtils/config.json`
- `/usr/local/share/openhd/video/air_camera_generic.json`

Existing non-camera settings in those JSON files are preserved. This makes the
hardware-selected sensor authoritative even if OpenHD previously persisted a
different camera type.

The R4 integration deliberately does not change the qualified camera-specific
GStreamer pipelines, RTP fragmentation, Wave5 settings or appsink behavior.
The IMX415 transport-artifact investigation remains a separate work item.

For a fresh OpenHD consumer install on an R4 accelerator image, use
`./install-r4.sh` instead of invoking `install-live.sh` directly. On an already
installed AIR unit, `./install-camera-r4-live.sh` installs only the R4 camera
boundary and leaves the OpenHD binary/transport experiment untouched.
