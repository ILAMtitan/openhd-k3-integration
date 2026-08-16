# openhd-k3-integration — Native-R1

OpenHD consumer integration for the separately qualified
[`ti-k3-accelerators`](https://github.com/ILAMtitan/ti-k3-accelerators)
platform on BeagleY-AI / TI J722S (AM67A).

This repository adds OpenHD, SysUtils, application/network integration, and the
native TI-accelerated camera path **without taking ownership of the TI firmware,
remoteproc sequence, reserved memory, TIOVX installation, or Wave5 platform
bring-up**.

## Current hardware-qualified baseline

The current qualified pairing is OpenHD Native-R1 on the source-built TI K3 R3
platform.

```text
OpenHD integration source:
803923790dadf33f429f7cceacc1601831fa8c82

Qualification tag:
openhd-native-r1-r3-hw-qualified-20260816

TI K3 platform tag:
beagley-ai-r3-source-hw-qualified-20260814

TI K3 tested source:
83c62656be0a725c691cda8727421cba552c32bf

Qualified TI base image SHA-256:
8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5
```

Installed executable identities from the qualified air unit:

```text
OpenHD SHA-256:
bfb41ae46ad81410fa007f1fd7eeab15951debcc33e30bbaa77ef684ec2e4d6f

OpenHD Build ID:
1f061a22a1efce6b53e27436b9a556792b571735

OpenHD SysUtils SHA-256:
c60f9ce1305015c5758f14b7700b03a3670a44d8ce925f8e129ce0f1268716de

OpenHD SysUtils Build ID:
d55279050c1967675737645cd3269c3da1027e98
```

The qualified scope includes:

- BeagleY-AI / J722S / AM67A, 4 GiB
- source-built TI R5/C7x firmware and source-built TI 2A from the R3 platform
- Raspberry Pi IMX219 on **CSI0**
- native TIOVX ISP + TIOVX multiscaler + Wave5 H.264 camera path
- RTL8812AU OpenHD wifibroadcast RF
- CC33xx management Wi-Fi
- manual software verification
- physical air-to-ground RF video
- automatic OpenHD startup after a complete physical cold power cycle
- automatic `88XXau_ohd` loading with no manual `modprobe`
- TI RPMsg/self-test and remoteproc state preserved while OpenHD is running

See
[`docs/OPENHD-NATIVE-R1-R3-QUALIFICATION-20260816.md`](docs/OPENHD-NATIVE-R1-R3-QUALIFICATION-20260816.md)
for the exact qualification record.

The qualification tag points to the exact **tested integration source commit**.
This README and the qualification record are documentation committed after the
hardware test and must not be used as a reason to move the qualification tag.

The older `openhd-native-r1-20260812` tag remains a frozen historical
qualification against the older TI R2 platform.

## Required bring-up order

Do not treat this repository as a replacement for the TI accelerator platform.
The supported order is:

```text
qualified ti-k3-accelerators image
  -> accelerator/RPMsg validation
  -> air only: IMX219 CSI0 camera validation
  -> OpenHD consumer installation
  -> manual software/RF-aware verification
  -> physical air/ground link verification
  -> enable automatic startup
  -> complete physical cold power cycle
  -> repeat software and physical RF verification
```

If the TI platform does not pass its own tests, restore that layer before
changing OpenHD. The OpenHD integration must not select alternate TI firmware,
change memory carveouts, or manually manipulate remoteproc state.

See [`docs/DEPENDENCY-CONTRACT.md`](docs/DEPENDENCY-CONTRACT.md) for the exact
ownership boundary.

## Native-R1 source basis

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

The RTL8812AU OpenHD RF module is built from pinned commit:

```text
28dee4c7d30dc4bc713bd259cbd88d8f44de89b7
```

The qualified CC33xx management-WiFi firmware input is:

```text
version: 1.7.0.323
commit:  0b4f850d6c0fd8e0fe0ae1d3e80ac6733aced29b
```

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
- automatic `88XXau_ohd` load and RTL8812AU appearance/removal handling
- management-WiFi discovery/setup
- flight-controller UART setup

`openhd-radio-watch` ensures the selected OpenHD RTL module is loaded before it
watches for the RF interface. If the RTL interface disappears while OpenHD is
running, the watcher stops OpenHD; if it appears or changes, the watcher restarts
OpenHD so RF discovery is repeated against the current interface.

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
  -> RTL8812AU physical RF
  -> ground receiver
```

There is no localhost `127.0.0.1:5500` UDP camera bridge in the normal Native-R1
path.

## Prerequisite TI platform

Start with a clean, hardware-qualified `ti-k3-accelerators` BeagleY-AI image.
The current OpenHD qualification used the TI R3 source-built baseline:

```text
TI K3 tag:
beagley-ai-r3-source-hw-qualified-20260814

TI K3 tested source:
83c62656be0a725c691cda8727421cba552c32bf

Armbian source:
259c7b157f9cc7968f077f5483ff0537f691c712

Qualified image SHA-256:
8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5
```

That platform provides:

- BeagleY-AI / J722S / AM67A
- 4 GiB `j722s-beagley-ai-4gb-r73341` memory profile
- source-built Main R5 and both C7x Vision Apps firmware images
- source-built TI 2A provider
- IMX219 on **CSI0** for the air-unit camera path
- RPMsg, TIOVX ISP, multiscaler, and Wave5 H.264

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

For the qualified path, the IMX219 is connected to **CSI0**. Connect the intended
RTL8812AU OpenHD RF adapter before qualification. If flight-controller telemetry
is used, select a non-console UART; `ttyS2` remains reserved for Linux console
use.

### Step 3 — Clone the integration repository

For normal use:

```bash
git clone https://github.com/ILAMtitan/openhd-k3-integration.git
cd openhd-k3-integration
```

To reproduce the exact executable/integration source point that passed the R3
hardware qualification:

```bash
git checkout openhd-native-r1-r3-hw-qualified-20260816
```

### Step 4 — Run repository checks

```bash
bash tests/test-boundary.sh
bash tests/test-contract.sh
```

These checks enforce the TI/OpenHD ownership boundary, native J722S camera
pipeline, OpenHD RF module naming/autoload behavior, and RF-aware verification
contract.

### Step 5 — Capture the clean TI-only baseline

Optional for normal use, recommended for qualification/development:

```bash
sudo ./capture-ti-baseline.sh
```

This preserves the TI-only state before the consumer is added, which makes later
failures easier to assign to the correct layer.

### Step 6 — Install the OpenHD air role

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
8. installs CC33xx management-WiFi firmware when selected
9. builds and installs the pinned `88XXau_ohd` OpenHD RF module when selected
10. writes the air-role systemd dependency boundary and consumer metadata
11. validates the installed files while deliberately leaving the combined
    consumer target stopped and disabled

Optional development switches are available when a hardware portion is being
qualified separately:

```bash
sudo ./install-live.sh --role air --skip-rtl8812au
sudo ./install-live.sh --role air --skip-cc33xx
sudo ./install-live.sh --role air --skip-rtl8812au --skip-cc33xx
```

These are separation/debug options, not the complete qualified hardware path.

### Step 7 — Start the consumer manually

```bash
sudo systemctl start openhd-k3-consumer.target
```

Inspect the major units:

```bash
systemctl status openhd-k3-consumer.target --no-pager
systemctl status openhd.service --no-pager
systemctl status openhd-sys-utils.service --no-pager
systemctl status openhd-radio-watch.service --no-pager
```

For air, `openhd.service` requires the TI accelerator target and the IMX219
preparation service, and imports `/etc/ti-k3/gstreamer.env` so OpenHD uses the
qualified TI runtime.

### Step 8 — Verify the software and RF-discovery contract

```bash
sudo ./verify-consumer.sh
```

For the air role, the verifier requires all of the following before returning
PASS:

- TI accelerator target active
- TI RPMsg contract and TI self-test pass
- exactly one OpenHD process running with `--air`
- TI GStreamer runtime inherited by OpenHD
- camera type 150 selected
- OpenHD owns the TI camera device
- no localhost UDP 5500 bridge
- RTL8812AU OpenHD RF interface present
- OpenHD has completed its delayed RF-discovery window without logging a current
  `No openhd wifibroadcast card found` or `Link not functional` startup failure

The verifier proves the local software/RF-discovery contract; it does not prove
the over-the-air link.

### Step 9 — Verify the physical air-to-ground link

Confirm the complete path with a receiving OpenHD ground unit. For the qualified
R3 pairing, live IMX219 video was verified over the physical RTL8812AU
wifibroadcast RF link.

### Step 10 — Enable automatic startup only after verification

```bash
sudo systemctl enable openhd-k3-consumer.target
```

Then shut the board down completely and perform a **physical cold power cycle**.
Do not use a warm `reboot` as the final qualification boundary.

After the cold boot, do not manually run `modprobe 88XXau_ohd` and do not
manually start the OpenHD target. Verify that the module/interface and OpenHD
services came up automatically, rerun `verify-consumer.sh`, verify the TI
platform again, and confirm the physical RF video link returns.

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

For a release qualification, perform a complete physical cold power cycle and
repeat the ground-side software and physical-link checks without manual service
or module intervention.

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

### RTL8812AU RF

```bash
modinfo -k "$(uname -r)" 88XXau_ohd
lsmod | grep -E '^88XXau_ohd|^88XXau'
iw dev
journalctl -b -u openhd-radio-watch.service --no-pager
```

On the qualified path the radio watcher loads `88XXau_ohd` automatically. A
release cold-boot test must not depend on a manual `modprobe`.

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
- `docs/` — dependency and qualification documentation
- `install-live.sh` — install the consumer layer on a qualified board
- `capture-ti-baseline.sh` — capture the TI-only pre-install baseline
- `verify-consumer.sh` — validate the installed consumer and RF-discovery
  contract
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
- [`docs/OPENHD-NATIVE-R1-R3-QUALIFICATION-20260816.md`](docs/OPENHD-NATIVE-R1-R3-QUALIFICATION-20260816.md)
  — current qualification on the source-built TI K3 R3 platform.
- [`docs/OPENHD-NATIVE-R1-QUALIFICATION.md`](docs/OPENHD-NATIVE-R1-QUALIFICATION.md)
  — historical 2026-08-12 Native-R1 qualification on the older TI R2 platform.
