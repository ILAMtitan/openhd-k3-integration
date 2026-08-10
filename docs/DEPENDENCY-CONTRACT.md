# Dependency contract

OpenHD may depend on **public TI K3 interfaces**, but must not:

- write `/sys/class/remoteproc/*`
- choose R5/C7x firmware aliases
- encode memory-map addresses
- enforce firmware SHA-256 values
- build/install TIOVX itself
- create DMA carveouts

Those are platform responsibilities.

The BeagleY-AI camera application flow remains:

IMX219 -> TIOVX ISP -> TIOVX multiscaler -> NV12 1280x720 -> Wave5 H.264 ->
RTP 127.0.0.1:5500 -> OpenHD.
