# OpenHD Native-R1 Qualification on TI K3 R3 — BeagleY-AI / J722S

Qualification date: 2026-08-16

## Status

**HARDWARE QUALIFIED**

This record binds the maintained OpenHD Native-R1 consumer integration to the
source-built, hardware-qualified TI K3 R3 platform. The qualification includes
an untouched physical cold boot and a verified physical air-to-ground RF video
link.

## Qualified integration source

Repository:

```text
ILAMtitan/openhd-k3-integration
```

Tested integration commit:

```text
803923790dadf33f429f7cceacc1601831fa8c82
```

The immutable qualification tag is intended to point to that exact tested
commit. Documentation committed after qualification must not move the tag away
from the tested source point.

Integration metadata version embedded by the tested installer:

```text
pass2-native-r1
```

## OpenHD source reconstruction

Upstream OpenHD repository:

```text
OpenHD/OpenHD
```

Pinned upstream commit:

```text
f07729b35e273fe3612e1aade030a7a86350d1ac
```

Integration patch stack:

```text
patches/openhd/0001 through 0008
```

Expected and installed patched Git tree:

```text
01fe7bf68d39ca6d9be747668910c841a11abe17
```

The patch stack therefore reconstructed the intended Native-R1 OpenHD source
identity before the AArch64 build.

## Qualified OpenHD and SysUtils executables

OpenHD:

```text
path:      /usr/local/bin/openhd
SHA-256:   bfb41ae46ad81410fa007f1fd7eeab15951debcc33e30bbaa77ef684ec2e4d6f
Build ID:  1f061a22a1efce6b53e27436b9a556792b571735
```

OpenHD SysUtils:

```text
path:      /usr/local/bin/openhd_sys_utils
SHA-256:   c60f9ce1305015c5758f14b7700b03a3670a44d8ce925f8e129ce0f1268716de
Build ID:  d55279050c1967675737645cd3269c3da1027e98
```

Pinned SysUtils source commit:

```text
aaf534d6d55f187d552837e0127ffdb6ba026e5b
```

## RF and management-WiFi inputs

Pinned RTL8812AU source commit:

```text
28dee4c7d30dc4bc713bd259cbd88d8f44de89b7
```

Installed OpenHD RF module name:

```text
88XXau_ohd
```

Qualified kernel:

```text
6.12.49-vendor-k3-beagle
```

CC33xx management-WiFi firmware:

```text
version: 1.7.0.323
commit:  0b4f850d6c0fd8e0fe0ae1d3e80ac6733aced29b
```

The final integration source adds persistent cold-boot loading of
`88XXau_ohd` through the OpenHD radio watcher and requires the RTL8812AU RF
interface to be present before the consumer verifier can pass.

## Qualified TI accelerator baseline

Repository:

```text
ILAMtitan/ti-k3-accelerators
```

Qualified source tag:

```text
beagley-ai-r3-source-hw-qualified-20260814
```

Exact tested TI K3 executable-source commit:

```text
83c62656be0a725c691cda8727421cba552c32bf
```

Armbian source commit:

```text
259c7b157f9cc7968f077f5483ff0537f691c712
```

Exact compressed Armbian image used as the OpenHD qualification base:

```text
Armbian-unofficial_26.08.0-trunk_Beagley-ai_noble_vendor_6.12.49_minimal.img.xz
SHA-256: 8e263e15bd7c436bd410b774427db0a50f365810e72f8e6859f9b0f47e0f89e5
```

Source-built TI firmware identities:

```text
Main R5  fc56b2a0e5110dac22ba3f25e997190aa07ccaf50bee36f21cc1703c61d6c41a
C7x 0    00ddc57e33a02a683c0077d9ef424aa1c3fa6b6a82935f335306052f355cb16b
C7x 1    10f3b472aa7d260c0f978356a12a539f15c5e49297b408f84ee92c66f91600d5
TI 2A    4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567
```

The OpenHD consumer did not replace TI firmware, manipulate remoteproc state,
change the reserved-memory map, or take ownership of TIOVX/Wave5 bring-up.

## Qualified hardware scope

Air unit:

```text
BeagleY-AI / TI J722S / AM67A
4 GiB
Raspberry Pi IMX219 on CSI0
RTL8812AU USB OpenHD RF radio
CC33xx management Wi-Fi
```

The physical RF/video test used a receiving OpenHD ground side and verified
that live video was received over the intended wifibroadcast RF path.

## Native video path

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

Qualified OpenHD Native-R1 video policy:

```text
sensor input: 1920x1080 Bayer RGGB @ 30 fps
video output: 1280x720 @ 30 fps
codec:        H.264
bitrate:      3000 kbit/s
GOP:          15
RTP MTU:      1024
camera type:  150 (TI J722S IMX219)
```

There is no normal-path localhost `127.0.0.1:5500` camera bridge.

## Qualification sequence and results

### Static contract

The tested integration source passed:

```text
bash tests/test-boundary.sh
bash tests/test-contract.sh
```

The contract protects the TI/OpenHD ownership boundary, native camera pipeline,
RF module naming, RF autoload behavior, and RF-aware consumer verification.

### TI platform before and during OpenHD

The TI accelerator target remained active and healthy after OpenHD was started.
The following remained PASS:

```text
TI K3 RPMsg readiness
TI K3 memory-map verification
TI K3 firmware hashes
TIOVX ISP factory
TIOVX multiscaler factory
Wave5 H.264/H.265 encode/decode factories
TI K3 self-test
```

Main R5 and both C7x remote processors remained on their expected firmware and
in `running` state. No warm remoteproc restart was used.

### OpenHD software contract

The strengthened consumer verifier passed with:

```text
consumer role = air
exactly one OpenHD process
OpenHD process argument = --air
TI LD_LIBRARY_PATH inherited
TI GST_PLUGIN_PATH_1_0 inherited
TI camera contract present
camera type 150 selected
OpenHD owns /dev/video2 through /run/ti-k3/camera-video
no localhost UDP 5500 listener
RTL8812AU RF interface present
OpenHD RF discovery completed without wifibroadcast startup failure
```

### Physical RF/video

The manually started candidate produced a working physical air-to-ground RF
video link.

Result:

```text
PHYSICAL_RF_VIDEO=PASS
```

### Automatic startup and untouched cold boot

After the manual software and RF gates passed,
`openhd-k3-consumer.target` was enabled. The system was fully powered down and
physically power-cycled.

No manual `modprobe`, no manual OpenHD `systemctl start`, and no remoteproc
state manipulation were performed after the cold boot.

The final cold-boot validation passed:

```text
OpenHD consumer target enabled/active     PASS
openhd.service active                     PASS
openhd-sys-utils.service active           PASS
openhd-radio-watch.service active         PASS
88XXau_ohd loaded automatically           PASS
RTL8812AU RF interface present            PASS
TI RPMsg readiness                        PASS
TI K3 self-test                           PASS
RF-aware verify-consumer.sh               PASS
Main R5/C7x remoteprocs remain running    PASS
physical RF video restored automatically  PASS
```

## Final verdict

```text
TI_K3_R3_PLATFORM                    QUALIFIED
OPENHD_NATIVE_R1_CONSUMER           QUALIFIED
NATIVE_TI_CAMERA_PIPELINE           QUALIFIED
RTL8812AU_WIFIBROADCAST_RF          QUALIFIED
AUTOMATIC_COLD_BOOT_STARTUP         QUALIFIED
PHYSICAL_AIR_TO_GROUND_VIDEO        QUALIFIED
```

The qualified OpenHD integration source point is
`803923790dadf33f429f7cceacc1601831fa8c82`. Later documentation-only commits
may describe this result, but must not be substituted for the tested source
identity when creating the immutable qualification tag.
