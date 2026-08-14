#!/usr/bin/env bash
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"

for file in \
    "$root/install-ground-ui.sh" \
    "$root/verify-ground-ui.sh" \
    "$root/overlay/usr/local/bin/openhd-ground-launch" \
    "$root/overlay/usr/local/bin/openhd-ground-stop" \
    "$root/overlay/usr/local/sbin/openhd-ground-control" \
    "$root/overlay/usr/local/sbin/openhd-ground-key"; do
    bash -n "$file"
done

[ "$(cat "$root/GROUND-UI-VERSION")" = ground-qopenhd-r1 ]
grep -q 'QOPENHD_COMMIT=6dd753d730bbd732dd747790b86e42ae6a5f6b2e' "$root/install-ground-ui.sh"
grep -q '^OPENHD_QOPENHD_RENDER_MODE=software-x11$' "$root/overlay/etc/default/openhd-ground-ui"
grep -q '^OPENHD_QOPENHD_DISABLE_PRIMARY_VIDEO=yes$' "$root/overlay/etc/default/openhd-ground-ui"
grep -q '^net.core.rmem_max=26214400$' "$root/overlay/etc/sysctl.d/90-openhd-ground.conf"
grep -q '^net.core.rmem_default=26214400$' "$root/overlay/etc/sysctl.d/90-openhd-ground.conf"
grep -q 'systemctl start openhd-k3-consumer.target' "$root/overlay/usr/local/sbin/openhd-ground-control"
! grep -Rqs '/sys/class/remoteproc\|j722s-main-r5f0_0-fw\|j722s-c71_' \
    "$root/install-ground-ui.sh" \
    "$root/overlay/usr/local/bin/openhd-ground-launch" \
    "$root/overlay/usr/local/bin/openhd-ground-stop" \
    "$root/overlay/usr/local/sbin/openhd-ground-control"

grep -q 'include(app/videostreaming/avcodec/avcodec_video.pri)' "$root/patches/qopenhd/0003-beagley-software-ui-no-avcodec.patch"
grep -q 'QOPENHD_DISABLE_PRIMARY_VIDEO' "$root/patches/qopenhd/0003-beagley-software-ui-no-avcodec.patch"
grep -q 'QOPENHD_START_FULLSCREEN' "$root/patches/qopenhd/0002-fullscreen-from-environment.patch"

echo 'PASS: ground QOpenHD consumer contract'
