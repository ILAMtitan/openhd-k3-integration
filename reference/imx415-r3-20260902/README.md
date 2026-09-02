# IMX415 R3 exact OpenHD checkpoint — 2026-09-02

Base OpenHD commit:

f07729b35e273fe3612e1aade030a7a86350d1ac

`openhd-r3-full-live-diff.patch` is the complete tracked working-tree delta
against that upstream commit from the qualified IMX415 R3 test tree.

The checkpoint source contains:

- TI J722S IMX415 camera type 152
- full-array 3864x2192 RAW10 input
- TI VISS processing
- 1280x720 multiscaler output
- one-buffer downstream-leaky queue before Wave5
- Wave5 H.264 at 6 Mbit/s / GOP 15
- 1024-byte RTP fragmentation for TI J722S pipelines
- appsink max-buffers=256
- appsink drop=true
- appsink sync=false

The local Wave5 H.264 stream was clean during motion testing. Remaining visible
ground-side corruption is downstream of local H.264 encoding.

Important:

`captured-runtime-state.txt` records a later temporary systemd selection of the
`openhd-native-imx415-full-appsink256-nodrop` experimental binary. That
drop=false experiment was NOT qualified and is not represented by the
checkpoint source.

The qualified source checkpoint is the drop=true version contained in
`openhd-r3-full-live-diff.patch`.

The two local `*.before-*` backup files from the AIR test tree are intentionally
excluded.
