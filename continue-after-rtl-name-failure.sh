#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
root=$(cd "$(dirname "$0")" && pwd)
KVER=$(uname -r)
buildroot=/var/tmp/openhd-k3-consumer-build
src="$buildroot/rtl8812au"

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say 'Resume preflight'
command -v openhd >/dev/null || die 'OpenHD binary from interrupted install is missing'
command -v openhd_sys_utils >/dev/null || die 'OpenHD SysUtils binary from interrupted install is missing'
command -v ti-k3-self-test >/dev/null || die 'ti-k3-accelerators is missing'
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI RPMsg contract is not ready'
ti-k3-self-test >/dev/null || die 'TI self-test no longer passes'
[[ -d "$src" ]] || die "Interrupted RTL8812AU source tree missing: $src"
[[ -d "/lib/modules/$KVER/build" ]] || die "Kernel headers missing for $KVER"

# Verify this really is the observed naming failure before touching anything.
bad=$(find "$src" -type f -name '88XXau_ohd_ohd.ko' -print -quit)
[[ -s "$bad" ]] || die 'Expected failed-build artifact 88XXau_ohd_ohd.ko was not found; refusing an ambiguous resume'
echo "Observed failed-build artifact: $bad"

say 'Rebuilding only RTL8812AU with frozen-Alpha module-name contract'
# Clean just the driver build products. This does not touch OpenHD, TI remoteproc,
# firmware, camera state, or the already-qualified accelerator stack.
make -C "$src" ARCH=arm64 KVER="$KVER" KSRC="/lib/modules/$KVER/build" clean >/dev/null 2>&1 || true

cc=/usr/bin/gcc
wrapper="$root/helpers/openhd-gcc-kbuild-filter"
rtlcc="$cc"
printf 'int x(void){return 0;}\n' >/tmp/ohd-cc-probe.c
if ! "$cc" -fmin-function-alignment=8 -c /tmp/ohd-cc-probe.c -o /tmp/ohd-cc-probe.o >/dev/null 2>&1; then
  rtlcc="$wrapper"
fi
rm -f /tmp/ohd-cc-probe.c /tmp/ohd-cc-probe.o

OPENHD_REAL_CC="$cc" make -C "$src" -j"$(nproc)" ARCH=arm64 CC="$rtlcc" HOSTCC="$cc" \
  KVER="$KVER" KSRC="/lib/modules/$KVER/build" USER_MODULE_NAME=88XXau modules

module=$(find "$src" -type f \( -name '88XXau_ohd.ko' -o -name '88XXau.ko' \) -print -quit)
[[ -s "$module" ]] || {
  echo 'Produced .ko files:' >&2
  find "$src" -type f -name '*.ko' -print >&2
  die 'Correctly named RTL8812AU module was not produced'
}
echo "Produced module: $module"

say 'Installing RTL8812AU module'
install -D -m 0644 "$module" "/lib/modules/$KVER/updates/openhd/88XXau_ohd.ko"
cat >/etc/modprobe.d/openhd-rtl8812au.conf <<'EOF_RTL'
blacklist rtl8xxxu
options 88XXau_ohd rtw_led_ctrl=0 rtw_switch_usb_mode=1
EOF_RTL

depmod -a "$KVER"
modinfo -k "$KVER" 88XXau_ohd >/dev/null || die 'Installed RTL8812AU module is not discoverable as 88XXau_ohd'
modinfo -k "$KVER" 88XXau_ohd | sed -n '1,12p'

say 'Finishing application systemd boundary'
cat >/etc/systemd/system/openhd.service.d/20-ti-k3-consumer.conf <<'EOF_DROPIN'
[Unit]
After=ti-k3-accelerators.target openhd-ti-camera-bridge.service openhd-radio-network-guard.service
Wants=openhd-ti-camera-bridge.service openhd-radio-network-guard.service
EOF_DROPIN

cat >/etc/systemd/system/openhd-k3-consumer.target <<'EOF_TARGET'
[Unit]
Description=OpenHD consumer of TI K3 accelerator platform
Requires=ti-k3-accelerators.target
After=ti-k3-accelerators.target
Wants=openhd-sys-utils.service openhd-radio-network-guard.service openhd-radio-watch.service openhd-ti-camera-bridge.service openhd.service

[Install]
WantedBy=multi-user.target
EOF_TARGET

systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
systemctl daemon-reload
systemctl disable openhd-k3-consumer.target 2>/dev/null || true
systemctl stop openhd.service openhd-ti-camera-bridge.service openhd-radio-watch.service 2>/dev/null || true

role=air
if [[ -f /boot/openhd/ground.txt && ! -f /boot/openhd/air.txt ]]; then role=ground; fi
CC33_VERSION=1.7.0.323
OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac
SYSUTILS_COMMIT=aaf534d6d55f187d552837e0127ffdb6ba026e5b
RTL_COMMIT=28dee4c7d30dc4bc713bd259cbd88d8f44de89b7
mkdir -p /var/lib/openhd-k3
cat >/var/lib/openhd-k3/consumer.env <<EOF_META
format=1
openhd_commit=$OPENHD_COMMIT
sysutils_commit=$SYSUTILS_COMMIT
rtl8812au_commit=$RTL_COMMIT
cc33xx_version=$CC33_VERSION
role=$role
kernel=$KVER
platform_dependency=ti-k3-accelerators.target
camera_contract=/run/ti-k3/camera.env
EOF_META

say 'Consumer boundary verification'
test -x /usr/local/bin/openhd
test -x /usr/local/bin/openhd_sys_utils
test -x /usr/local/sbin/openhd-ti-camera-bridge
systemd-analyze verify /etc/systemd/system/openhd-ti-camera-bridge.service /etc/systemd/system/openhd-k3-consumer.target >/dev/null
modinfo -k "$KVER" 88XXau_ohd >/dev/null

echo
echo 'PASS: interrupted consumer install resumed successfully.'
echo 'OpenHD remains stopped/disabled for staged qualification.'
echo 'Next: start openhd-ti-camera-bridge.service and verify RTP on loopback.'
