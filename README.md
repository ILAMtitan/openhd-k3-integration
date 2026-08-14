# openhd-k3-integration — Native-R1

OpenHD consumer integration for the separately qualified
[`ti-k3-accelerators`](https://github.com/ILAMtitan/ti-k3-accelerators)
platform on BeagleY-AI / TI J722S (AM67A).

This repository adds OpenHD, SysUtils, application/network integration, and the
native TI-accelerated camera path **without taking ownership of the TI firmware,
remoteproc sequence, reserved memory, TIOVX installation, or Wave5 platform
bring-up**.

## Required bring-up order

Do not treat this repository as a replacement for the TI accelerator platform.
The supported order is:

```text
qualified ti-k3-accelerators image
  -> accelerator/RPMsg validation
  -> air only: IMX219 CSI0 camera validation
  -> OpenHD consumer installation
  -> manual software verification
  -> physical air/ground link verification
  -> enable automatic startup
```

If the TI platform does not pass its own tests, restore that layer before
changing OpenHD. The OpenHD integration must not select alternate TI firmware,
change memory carveouts, or manually manipulate remoteproc state.

See [`docs/DEPENDENCY-CONTRACT.md`](docs/DEPENDENCY-CONTRACT.md) for the exact
ownership boundary.

## Current Native-R1 baseline

The OpenHD patch stack is:

```text
patches/openhd/0001..0008
```

It is based on upstream OpenHD commit:

```text
f07729b35e273fe3612e1aade030a7a86350d1ac
```

The expected patched OpenHD source-tree identity is:

```text
01fe7bf68d39ca6d9be747668910c841a11abe17
```

The SysUtils integration is based on pinned commit:

```text
aaf534d6d55f187d552837e0127ffdb6ba026e5b
```

The earlier qualified Native-R1 point is preserved by tag:

```text
openhd-native-r1-20260812
```

Current `main` contains post-qualification maintenance and repository cleanup.
Use the historical tag to reproduce the original qualified point; use current
`main` when intentionally validating the maintained integration.

## Why the OpenHD patches are required

The installer starts from the pinned upstream source and applies the patches in
order. Each patch exists for a specific BeagleY-AI integration requirement.

### 0001 — BeagleY-AI platform identity

`patches/openhd/0001-ohd-common-add-beagley-ai-platform.patch`

Adds TI AM67A / BeagleY-AI platform type 70 so OpenHD has a stable identity for
platform-specific behavior rather than falling through generic defaults.

### 0002 — systemd ordering and explicit role

`patches/openhd/0002-systemd-order-sysutils-and-role.patch`

Orders OpenHD after SysUtils and allows the service to receive the selected air
or ground role through `/etc/default/openhd`.

### 0003 — ARM64/BeagleY-AI build support

`patches/openhd/0003-build-add-beagley-ai-arm64-packaging.patch`

Adds the BeagleY-AI/ARM64 dependency and package path required by the pinned
upstream tree. The installer independently verifies that the live build is an
AArch64 executable.

### 0004 — historical external-camera transition

`patches/openhd/0004-video-default-beagley-ai-to-external-rtp-camera.patch`

This is an intermediate migration patch from the earlier external-camera design.
It remains in the cumulative 0001..0008 reconstruction because it is part of the
qualified source history. **Patch 0008 supersedes its BeagleY-AI camera default.**
The final Native-R1 runtime does not use the old localhost camera bridge.

### 0005 — protect the Linux console UART

`patches/openhd/0005-telemetry-protect-console-uart.patch`

BeagleY-AI uses `ttyS2` for the Linux console. This patch prevents OpenHD's
generic serial fallback from claiming that console and requires FC telemetry to
use an explicitly safe non-console UART.

### 0006 — host networking compatibility

`patches/openhd/0006-networking-require-networkmanager-for-nmcli.patch`

Makes NetworkManager-specific operations conditional on NetworkManager actually
being present. This allows the qualified BeagleY-AI networking arrangement to
work without assuming every OpenHD platform is managed the same way.

### 0007 — pinned-tree compatibility fixes

`patches/openhd/0007-platform-restore-BeagleY-AI-OpenHD-compatibility-fix.patch`

Carries the small platform, wireless-card, frequency-format, and ARM64 source
compatibility fixes required by the qualified upstream revision.

### 0008 — native TI J722S IMX219 pipeline

`patches/openhd/0008-video-add-native-TI-J722S-IMX219-pipeline.patch`

Adds camera type 150 and makes BeagleY-AI consume the TI camera contract
directly. The final pipeline uses TIOVX ISP, TIOVX multiscaler, and Wave5 H.264
inside OpenHD instead of the retired external-camera bridge.

Native-R1 defaults for this path are:

- 1280x720
- 30 fps
- H.264
- 3000 kbit/s
- GOP 15
- 1024-byte RTP fragmentation

Live Wave5 bitrate changes are intentionally outside Native-R1.

## Why the SysUtils patches are required

`patches/openhd-sysutils/0001-platforms-add-beagley-ai-am67a.patch` adds the
same platform type 70 and detects BeagleY-AI from device-tree identity so
SysUtils and OpenHD agree on the platform.

`patches/openhd-sysutils/0002-install-systemd-unit-under-usr-lib.patch` installs
the SysUtils service under `/usr/lib/systemd/system`, preserving merged-`/usr`
behavior on the target distribution.

## Active host integration

The active application-side files are under `overlay/`. They provide:

- host-network ownership rules for OpenHD interfaces
- application interface preparation/readiness/watch services
- management-WiFi discovery/setup
- flight-controller UART setup

`reference/r73341/` is historical evidence only and is not consumed by the
current installer.

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
  -> physical link
```

There is no localhost `127.0.0.1:5500` UDP camera bridge in the normal Native-R1
path.

## Prerequisite TI platform

Start with a clean, hardware-qualified `ti-k3-accelerators` BeagleY-AI image.

The qualified TI baseline uses:

- BeagleY-AI / J722S / AM67A
- 4 GiB memory profile
- IMX219 on **CSI0** for the air-unit camera path
- qualified TI R2 remote firmware
- working RPMsg, TIOVX ISP, multiscaler, and Wave5 H.264

For both air and ground roles, verify the platform first:

```bash
systemctl is-active ti-k3-accelerators.target
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
```

For an air unit, the camera contract is additionally required:

```bash
sudo systemctl start ti-k3-imx219-prepare.service
test -r /run/ti-k3/camera.env
```

A ground unit does not require a local IMX219 camera or `/run/ti-k3/camera-*`
contract.

## Step-by-step: air unit

### Step 1 — Start from the qualified TI-only image

Do not install over an unknown or partially modified TI platform when trying to
reproduce the qualified configuration. The installer refuses to proceed if
OpenHD is already installed.

### Step 2 — Confirm the air-unit hardware assumptions

For the qualified path, the IMX219 is connected to **CSI0**. If flight-controller
telemetry is used, select a non-console UART; `ttyS2` remains reserved for Linux
console use.

### Step 3 — Clone the integration repository

```bash
git clone https://github.com/ILAMtitan/openhd-k3-integration.git
cd openhd-k3-integration
```

### Step 4 — Capture the clean TI-only baseline

Optional for normal use, recommended for qualification/development:

```bash
sudo ./capture-ti-baseline.sh
```

This preserves the TI-only state before the consumer is added, which makes later
failures easier to assign to the correct layer.

### Step 5 — Install the OpenHD air role

```bash
sudo ./install-live.sh --role air
```

The installer performs the following high-level sequence:

1. verifies the qualified TI accelerator, RPMsg, self-test, and camera contract
2. verifies the running kernel prerequisites for selected optional interfaces
3. installs the runtime/build dependencies used by this integration
4. installs the active `overlay/` host/application integration
5. reconstructs pinned OpenHD, applies `patches/openhd/`, and verifies the exact
   patched Git tree
6. builds and installs OpenHD for AArch64
7. reconstructs/builds pinned SysUtils with `patches/openhd-sysutils/`
8. installs the selected management-WiFi and OpenHD interface support
9. writes the air-role systemd dependency boundary and consumer metadata
10. validates the installed files while deliberately leaving the combined
    consumer target stopped and disabled

Optional development switches are available when a hardware portion is being
qualified separately:

```bash
sudo ./install-live.sh --role air --skip-rtl8812au
sudo ./install-live.sh --role air --skip-cc33xx
sudo ./install-live.sh --role air --skip-rtl8812au --skip-cc33xx
```

These are separation/debug options, not the complete qualified hardware path.

### Step 6 — Start the consumer manually

```bash
sudo systemctl start openhd-k3-consumer.target
```

Inspect the major units:

```bash
systemctl status openhd-k3-consumer.target --no-pager
systemctl status openhd.service --no-pager
systemctl status openhd-radio-watch.service --no-pager
```

For air, `openhd.service` requires the TI accelerator target and the IMX219
preparation service, and imports `/etc/ti-k3/gstreamer.env` so OpenHD uses the
qualified TI runtime.

### Step 7 — Verify the software contract

```bash
sudo ./verify-consumer.sh
```

The verifier checks that the TI platform remains healthy, the correct air role
is running, the TI runtime environment is inherited, the camera contract is
present and owned by OpenHD, and the retired localhost camera topology has not
returned.

### Step 8 — Verify the physical air-to-ground link

The software verifier does not prove the physical link. Confirm the complete
path through the intended OpenHD hardware and a receiving ground unit.

### Step 9 — Enable automatic startup only after verification

```bash
sudo systemctl enable openhd-k3-consumer.target
```

Then perform a complete physical cold power cycle and verify the software
contract and physical link again.

Do not warm-restart TI remote processors as an OpenHD qualification shortcut,
and do not manually write `/sys/class/remoteproc/*/state`.

## Step-by-step: ground unit

The ground role deliberately does not require a local camera.

### Step 1 — Verify the TI baseline

```bash
systemctl is-active ti-k3-accelerators.target
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
```

### Step 2 — Install ground role

```bash
sudo ./install-live.sh --role ground
```

The ground service boundary requires the accelerator baseline but does not
require `ti-k3-imx219-prepare.service` or any `/run/ti-k3/camera-*` file.

### Step 3 — Start and verify manually

```bash
sudo systemctl start openhd-k3-consumer.target
sudo ./verify-consumer.sh
```

Then verify the intended physical receive path with the paired air unit.

### Step 4 — Enable only after physical verification

```bash
sudo systemctl enable openhd-k3-consumer.target
```

## Required TI platform API

OpenHD consumes these interfaces from `ti-k3-accelerators` on both roles:

- `ti-k3-accelerators.target`
- `ti-k3-rpmsg-ready`
- `ti-k3-self-test`
- `/etc/ti-k3/gstreamer.env`

The air role additionally consumes:

- `ti-k3-imx219-prepare.service`
- `/run/ti-k3/camera.env`
- `/run/ti-k3/camera-video`
- `/run/ti-k3/camera-subdev`
- `tiovxisp`
- `tiovxmultiscaler`
- Wave5 `v4l2h264enc`

OpenHD does not own remoteproc sequencing, TI firmware, memory carveouts, DMA
heaps, TIOVX installation, Wave5 platform enablement, or IMX219 DCC
provisioning.

## Troubleshooting order

Debug bottom-up rather than changing multiple layers at once.

### TI platform

```bash
systemctl --failed --no-pager
systemctl status ti-k3-accelerators.target --no-pager
sudo ti-k3-rpmsg-ready
sudo ti-k3-self-test
```

### Air camera contract

```bash
systemctl status ti-k3-imx219-prepare.service --no-pager
cat /run/ti-k3/camera.env
```

### OpenHD consumer

```bash
systemctl status openhd-k3-consumer.target --no-pager
systemctl status openhd.service --no-pager
journalctl -b -u openhd.service --no-pager
sudo ./verify-consumer.sh
```

If the TI platform is not healthy, fix or restore that layer first rather than
restarting remote processors from OpenHD.

## Repository layout

- `patches/openhd/` — active OpenHD Native-R1 patch stack
- `patches/openhd-sysutils/` — active BeagleY-AI SysUtils integration
- `overlay/` — active application/network/UART/systemd integration
- `reference/r73341/` — historical R7.33.4.1 snapshot; not consumed by the
  installer
- `helpers/` — build helpers
- `docs/` — dependency and Native-R1 qualification documentation
- `install-live.sh` — install the consumer layer on a qualified board
- `capture-ti-baseline.sh` — capture the TI-only pre-install baseline
- `verify-consumer.sh` — validate the installed consumer contract
- `tests/` — static ownership/contract checks

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

## Further documentation

- [`docs/DEPENDENCY-CONTRACT.md`](docs/DEPENDENCY-CONTRACT.md) — TI/OpenHD
  ownership boundary.
- [`docs/OPENHD-NATIVE-R1-QUALIFICATION.md`](docs/OPENHD-NATIVE-R1-QUALIFICATION.md)
  — frozen source/executable identities and hardware qualification results.
