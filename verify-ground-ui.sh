#!/usr/bin/env bash
set -eu

fail=0
pass()
{
    echo "PASS: $*"
}
fail_check()
{
    echo "FAIL: $*" >&2
    fail=1
}

consumer=/var/lib/openhd-k3/consumer.env
ui=/var/lib/openhd-k3/ground-ui.env

[ -r "$consumer" ] || fail_check 'consumer metadata present'
if [ -r "$consumer" ]; then
    role="$(sed -n 's/^role=//p' "$consumer" | tail -n 1)"
    [ "$role" = ground ] && pass 'consumer role is ground' || fail_check "consumer role is ground (found ${role:-missing})"
fi

systemctl is-active --quiet ti-k3-accelerators.target && pass 'TI K3 accelerator target active' || fail_check 'TI K3 accelerator target active'
if command -v ti-k3-rpmsg-ready >/dev/null 2>&1 && ti-k3-rpmsg-ready >/dev/null; then
    pass 'TI K3 RPMsg ready'
else
    fail_check 'TI K3 RPMsg ready'
fi
if command -v ti-k3-self-test >/dev/null 2>&1 && ti-k3-self-test >/dev/null; then
    pass 'TI K3 self-test'
else
    fail_check 'TI K3 self-test'
fi

if [ -x /usr/local/bin/QOpenHD ] && readelf -h /usr/local/bin/QOpenHD 2>/dev/null | grep -Eq 'Machine:[[:space:]]+AArch64'; then
    pass 'QOpenHD AArch64 binary'
else
    fail_check 'QOpenHD AArch64 binary'
fi

for executable in \
    /usr/local/bin/openhd-ground-launch \
    /usr/local/bin/openhd-ground-stop \
    /usr/local/sbin/openhd-ground-control \
    /usr/local/sbin/openhd-ground-key; do
    [ -x "$executable" ] && pass "executable $executable" || fail_check "executable $executable"
done

policy=/etc/default/openhd-ground-ui
if [ -r "$policy" ] &&
   grep -q '^OPENHD_QOPENHD_RENDER_MODE=software-x11$' "$policy" &&
   grep -q '^OPENHD_QOPENHD_DISABLE_PRIMARY_VIDEO=yes$' "$policy"; then
    pass 'stable QOpenHD software-X11 UI policy'
else
    fail_check 'stable QOpenHD software-X11 UI policy'
fi

ground_control=/usr/local/sbin/openhd-ground-control
if [ -r "$ground_control" ] &&
   ! grep -q '/sys/class/remoteproc\|j722s-main-r5f0_0-fw\|j722s-c71_' "$ground_control" &&
   grep -q 'ti-k3-accelerators.target' "$ground_control"; then
    pass 'ground control preserves TI remoteproc ownership boundary'
else
    fail_check 'ground control preserves TI remoteproc ownership boundary'
fi

key=/usr/local/share/openhd/txrx.key
if [ -f "$key" ] && [ "$(stat -c '%s' "$key")" -eq 128 ] && [ "$(stat -c '%a' "$key")" = 600 ]; then
    pass 'OpenHD link key is 128 bytes mode 0600'
else
    fail_check 'OpenHD link key is 128 bytes mode 0600'
fi

rmem_max="$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)"
rmem_default="$(sysctl -n net.core.rmem_default 2>/dev/null || echo 0)"
if [ "$rmem_max" -ge 26214400 ] && [ "$rmem_default" -ge 26214400 ]; then
    pass 'OpenHD UDP receive buffers'
else
    fail_check "OpenHD UDP receive buffers (max=$rmem_max default=$rmem_default)"
fi

if [ -r "$ui" ] &&
   grep -q '^qopenhd_primary_video=intentionally-disabled$' "$ui" &&
   grep -q '^platform_dependency=ti-k3-accelerators.target$' "$ui"; then
    pass 'ground UI provenance and intentional video-disable marker'
else
    fail_check 'ground UI provenance and intentional video-disable marker'
fi

if [ "$fail" -ne 0 ]; then
    echo 'OPENHD_GROUND_UI=FAIL' >&2
    exit 1
fi

echo 'OPENHD_GROUND_UI=PASS'
