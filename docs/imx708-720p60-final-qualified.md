# IMX708 1280x720p60 final qualification

Date: 2026-08-26

This checkpoint is the end-to-end qualified OpenHD air-side path for the
Arducam B0310 / Sony IMX708 on BeagleY-AI (TI J722S / AM67A).

## Qualified pipeline

The camera path is:

1. IMX708 CSI0, 1536x864 RAW10, sensor-native ~60 fps.
2. `tiovxisp` / VPAC VISS, compatibility sensor slot
   `SENSOR_SONY_IMX219_RPI`, AE/AWB disabled.
3. TIOVX multiscaler to 1280x720 NV12 at 60 fps.
4. One-buffer leaky queue.
5. Wave5 H.264 at 6,000,000 bit/s, GOP 30.
6. Explicit H.264 1280x720p60 Baseline Level 3.2 caps.
7. OpenHD RTP fragmentation at 1024 bytes and the existing qualified
   64-buffer dropping appsink.
8. WiFiBroadcast MCS2 / 20 MHz.

The IMX708 sensor graph uses VBLANK 946 and the manual controls:

- exposure: 1280
- analogue gain: 512
- digital gain: 256

The TIOVX VISS pool sizes are 2/2.

## GStreamer V4L2 CMA prerequisite

Ubuntu Noble GStreamer 1.24.2 calculates encoded V4L2 `sizeimage` from the
driver maximum dimensions. Wave5 advertises an 8192-pixel maximum, causing
GStreamer to request a 33,554,432-byte encoded buffer even for 720p.

The accelerator checkpoint installs a patched
`libgstvideo4linux2.so` under:

`/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so`

`/etc/ti-k3/gstreamer.env` must put that directory before the TI runtime
plugin directories. The fix sizes encoded buffers from the negotiated width
and height. TI independently published the same functional fix in
meta-arago in 2026.

The plugin used for the final live qualification had SHA-256:

`85fee44325de66cd0ddb6e4470dc45d8282c82726a1ee9cbe147b220e4c46af1`

## End-to-end result

The final OpenHD binary built from the qualified scratch tree had SHA-256:

`3c41a5d31527aa12fde35070465fa94ba3f204d43a276819498ad006f773d658`

The first OpenHD RF start passed all automated gates:

- OpenHD selected camera type 151 / `TI_J722S_IMX708`.
- sensor/VISS input was 1536x864 RAW10 at 60 fps.
- multiscaler output was 1280x720p60.
- Wave5 used 6 Mbit/s and GOP 30.
- GStreamer reached PLAYING.
- OpenHD owned the camera video node.
- the patched V4L2 plugin was mapped in the OpenHD process.
- there were no GStreamer allocation errors.
- there was no 32 MiB / 8192-page CMA allocation failure.

RF video was received on the laptop and was visually clean.

## Reproduction

The OpenHD integration installer intentionally starts from the existing dirty
R3 consumer tree at commit `f07729b35e273fe3612e1aade030a7a86350d1ac`.
That tree contains consumer changes which are not represented by the upstream
commit, including the qualified 64-buffer appsink behavior. Do not reset or
replace that source tree with a pristine checkout before applying this
checkpoint.

Install the accelerator-side IMX708 720p60 checkpoint and GStreamer CMA
override first. Then run:

```sh
./apply-imx708-checkpoint.sh
systemctl start openhd.service
./verify-imx708-checkpoint.sh
```

The apply script leaves OpenHD stopped and disabled after installation so the
first RF start remains an explicit qualification action.
