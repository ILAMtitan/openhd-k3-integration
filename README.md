# openhd-k3-integration — Native-R1

OpenHD consumer integration for the separately qualified
[`ti-k3-accelerators`](https://github.com/ILAMtitan/ti-k3-accelerators)
platform on BeagleY-AI / TI J722S (AM67A).

This repository adds OpenHD, SysUtils, radio integration, and the native
TI-accelerated camera path **without taking ownership of the TI firmware,
remoteproc sequence, reserved memory, TIOVX installation, or Wave5 platform
bring-up**.

## Current Native-R1 baseline

The OpenHD patch stack is:

```text
reference/patches/openhd/0001..0008
```

It is based on upstream OpenHD commit:

```text
f07729b35e273fe3612e1aade030a7a86350d1ac
```

The expected patched OpenHD source-tree identity is:

```text
01fe7bf68d39ca6d9be747668910c841a11abe17
```

The earlier qualified Native-R1 point is preserved by tag:

```text
openhd-native-r1-20260812
```

## Prerequisites

Start with a clean, hardware-qualified `ti-k3-accelerators` BeagleY-AI image.

The current qualified TI baseline uses:

- BeagleY-AI / J722S / AM67A
- 4 GiB memory profile
- IMX219 on **CSI0**
- qualified TI R2 remote firmware
- working RPMsg, TIOVX ISP, multiscaler, and Wave5 H.264
- `/run/ti-k3/camera.env` published by the TI platform

Before installing OpenHD, these should pass:

```bash
systemctl is-active ti-k3-accelerators.target
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
sudo systemctl start ti-k3-imx219-prepare.service
test -r /run/ti-k3/camera.env
```

Do not install this layer over an unknown or partially modified TI platform if
you are trying to reproduce the qualified configuration.

## Native-R1 video architecture

The air-unit camera path is native end-to-end:

```text
IMX219 on CSI0
  -> /run/ti-k3/camera-video
  -> TIOVX ISP / VPAC VISS
  -> TIOVX MultiScaler
  -> Wave5 H.264
  -> OpenHD H.264 parse / RTP packetization / appsink
  -> wifibroadcast
  -> RF
```

There is no localhost `127.0.0.1:5500` UDP bridge in the normal Native-R1 path.

Native-R1 defaults for the J722S camera path are:

- 1280x720
- 30 fps
- H.264
- 3000 kbit/s
- GOP 15
- 1024-byte RTP fragmentation

Live Wave5 bitrate changes are intentionally outside Native-R1.

## Quick start: air unit

Clone the integration repository onto the already-qualified BeagleY-AI:

```bash
git clone https://github.com/ILAMtitan/openhd-k3-integration.git
cd openhd-k3-integration
```

### 1. Capture the clean TI-only baseline

This is optional for normal use but strongly recommended for qualification or
development:

```bash
sudo ./capture-ti-baseline.sh
```

By default this creates a TI-only evidence archive under `/root`.

### 2. Install the OpenHD consumer layer

For an air unit:

```bash
sudo ./install-live.sh --role air
```

For a ground unit:

```bash
sudo ./install-live.sh --role ground
```

The installer performs a TI-platform preflight, reconstructs OpenHD and SysUtils
from pinned revisions, installs the application/radio integration, and leaves
`openhd-k3-consumer.target` **stopped and disabled** so it can be verified
manually first.

Optional development switches:

```bash
sudo ./install-live.sh --role air --skip-rtl8812au
sudo ./install-live.sh --role air --skip-cc33xx
sudo ./install-live.sh --role air --skip-rtl8812au --skip-cc33xx
```

`--skip-rtl8812au` is useful when RF hardware/driver qualification is being
handled separately. `--skip-cc33xx` skips the TI CC33xx management-WiFi
firmware portion.

### 3. Start OpenHD manually

```bash
sudo systemctl start openhd-k3-consumer.target
```

Check the major units:

```bash
systemctl status openhd-k3-consumer.target --no-pager
systemctl status openhd.service --no-pager
systemctl status openhd-radio-watch.service --no-pager
```

### 4. Verify the consumer contract

```bash
sudo ./verify-consumer.sh
```

The verifier checks the deployed behavior that matters:

- TI accelerator target still active
- RPMsg and TI self-test still pass
- TI camera contract is present
- OpenHD and SysUtils are running
- the legacy camera bridge remains inactive
- there is no UDP listener on `127.0.0.1:5500`
- the OpenHD process has the selected air/ground role
- the OpenHD process inherited the private TI GStreamer runtime
- the configured air camera type is the Native-R1 J722S camera
- on an air unit, OpenHD owns the TI camera capture device
- remoteproc/firmware ownership remains with `ti-k3-accelerators`

### 5. Verify physical RF video

`verify-consumer.sh` validates the software contract, but the final air-unit
qualification still requires actual RF video through the intended OpenHD radio
hardware and a receiving ground unit.

Only after software verification **and** physical RF video pass:

```bash
sudo systemctl enable openhd-k3-consumer.target
```

Then perform a complete physical cold power cycle and verify both the software
contract and RF video again.

Do not use a warm remoteproc restart as a qualification shortcut, and do not
manually write `/sys/class/remoteproc/*/state`.

## Ground-unit usage

Install with:

```bash
sudo ./install-live.sh --role ground
```

The same consumer target and verification tooling are used, but the ground role
does not require ownership of the local IMX219 capture device.

The selected role is recorded by the installer and passed to OpenHD as
`--air` or `--ground`.

## Required TI platform API

OpenHD consumes these interfaces from `ti-k3-accelerators`:

- `ti-k3-accelerators.target`
- `ti-k3-rpmsg-ready`
- `ti-k3-self-test`
- `ti-k3-imx219-prepare.service`
- `/etc/ti-k3/gstreamer.env`
- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`
- `tiovxisp`
- `tiovxmultiscaler`
- Wave5 `v4l2h264enc`

OpenHD does not own remoteproc sequencing, TI firmware, memory carveouts, DMA
heaps, TIOVX installation, Wave5 platform enablement, or IMX219 DCC
provisioning.

## OpenHD ownership

This repository owns the consumer/application layer:

- OpenHD application camera lifecycle
- output resolution
- H.264 bitrate and GOP policy
- H.264 parse and RTP packetization
- RF / wifibroadcast
- OpenHD radio policy
- management-WiFi integration
- telemetry UART policy

## Legacy bridge

These files remain for rollback/reference:

```text
adapter/overlay/usr/local/sbin/openhd-ti-camera-bridge
adapter/overlay/etc/systemd/system/openhd-ti-camera-bridge.service
```

They are **not** part of the normal Native-R1 topology. Qualification requires
the bridge service to remain inactive and requires no UDP listener on
`127.0.0.1:5500`.

`continue-after-rtl-name-failure.sh` is retained only for the historical
interrupted RTL8812AU naming-failure case.

## Troubleshooting

Start with the TI platform before debugging OpenHD:

```bash
systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
systemctl status ti-k3-imx219-prepare.service --no-pager
cat /run/ti-k3/camera.env
```

Then inspect the consumer:

```bash
systemctl status openhd-k3-consumer.target --no-pager
systemctl status openhd.service --no-pager
journalctl -b -u openhd.service --no-pager
sudo ./verify-consumer.sh
```

If the TI platform is not healthy, fix or restore that layer first rather than
restarting remote processors from OpenHD.

## Repository layout

- `reference/patches/openhd/` - frozen OpenHD Native-R1 patch stack
- `reference/patches/openhd-sysutils/` - BeagleY-AI SysUtils integration
- `reference/r73341/` - retained RF/system integration reference material
- `adapter/` - application-side adapter and legacy rollback bridge
- `helpers/` - build helpers
- `docs/` - dependency and Native-R1 qualification documentation
- `install-live.sh` - install the consumer layer on a qualified board
- `capture-ti-baseline.sh` - capture the TI-only pre-install baseline
- `verify-consumer.sh` - validate the installed consumer contract
- `tests/` - static ownership/contract checks

## Repository checks

Before publishing changes:

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
```

These tests protect the TI/OpenHD ownership boundary and the actual Native-R1
consumer contract. Git provides integrity/versioning for ordinary repository
files, so the repository does not maintain a second whole-tree checksum
manifest.

For the detailed qualification procedure, see:

[`docs/OPENHD-NATIVE-R1-QUALIFICATION.md`](docs/OPENHD-NATIVE-R1-QUALIFICATION.md)
