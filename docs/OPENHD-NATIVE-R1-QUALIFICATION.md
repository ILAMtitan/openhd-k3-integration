# OpenHD Native-R1 Qualification — BeagleY-AI / J722S

Qualification date: 2026-08-12

## Upstream basis

- Upstream repository: OpenHD/OpenHD
- Upstream commit: `f07729b35e273fe3612e1aade030a7a86350d1ac`
- Integration patch stack: `patches/openhd/0001` through `0008`

## Patch reconstruction proof

- Reconstructed tree: `01fe7bf68d39ca6d9be747668910c841a11abe17`
- Qualified source tree: `01fe7bf68d39ca6d9be747668910c841a11abe17`
- Reconstruction result: PASS

The complete 0001..0008 patch stack applied cleanly to the upstream
commit and reproduced the exact Git tree used for qualification.

## Qualified OpenHD source

- Qualification workspace commit:
  `04daf94fff63519f31cda1c5582792f1e52a45f8`

## Qualified ARM64 executable

- SHA256:
  `4d1fffcd9634e7ab284ed1875d0af5935b3e4742d52d8a3f8d5ca974a21ada36`
- GNU Build ID:
  `1878a57e2b803b7be473c2622f159b80a773467d`

## Native camera path

IMX219
→ TI TIOVX ISP
→ TI TIOVX multiscaler
→ Wave5 H.264
→ h264parse
→ RTP/H.264 MTU 1024
→ OpenHD appsink
→ wifibroadcast
→ RF

The legacy localhost UDP port 5500 bridge is not used by the qualified
native path.

## Qualified video configuration

- Sensor input: 1920x1080 @ 30 fps Bayer RGGB
- Output: 1280x720 @ 30 fps
- H.264 bitrate: 3,000 kbit/s
- GOP: 15
- RTP MTU: 1024
- H.264 profile control: 0
- SPS/PPS prepended to IDR

## Qualification results

- ARM64 build: PASS
- Patch reconstruction: PASS
- Native IMX219 capture: PASS
- TIOVX ISP: PASS
- TIOVX multiscaler: PASS
- Wave5 H.264 encode: PASS
- OpenHD native RTP/appsink: PASS
- Localhost RTP bridge removed: PASS
- Single-instance stability: PASS
- systemd ownership: PASS
- cold boot: PASS
- remoteproc state preserved: PASS
- physical RF video: PASS

## TI accelerator baseline

- TI accelerator generation: R2
- ti-k3-accelerators tag: `split-r2-20260812`
- ti-k3-accelerators commit:
  `812bfe23c9d6599006cc0bc080366e4b93e91669`

Remote processors must not be warm-restarted as part of qualification.
Firmware qualification uses a full cold power cycle.
