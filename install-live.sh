#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: sudo ./install-live.sh [--role air|ground] [--jobs N]
                              [--skip-rtl8812au] [--skip-cc33xx]

Installs only the OpenHD consumer layer on an already-qualified
`ti-k3-accelerators` BeagleY-AI system. It does not install Vision Apps
firmware, manipulate remoteproc, alter TI memory carveouts, or build TIOVX.
The services are installed but the combined OpenHD consumer target is NOT
started or enabled automatically.
USAGE
  exit 2
}

[[ $(id -u) -eq 0 ]] || { echo 'Run with sudo/root' >&2; exit 1; }
root=$(cd "$(dirname "$0")" && pwd)
role=air
jobs=$(nproc)
with_rtl=yes
with_cc33=yes
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) role=${2:?}; shift 2 ;;
    --jobs) jobs=${2:?}; shift 2 ;;
    --skip-rtl8812au) with_rtl=no; shift ;;
    --skip-cc33xx) with_cc33=no; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
[[ "$role" == air || "$role" == ground ]] || usage
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || usage

OPENHD_COMMIT=f07729b35e273fe3612e1aade030a7a86350d1ac
SYSUTILS_COMMIT=aaf534d6d55f187d552837e0127ffdb6ba026e5b
RTL_COMMIT=28dee4c7d30dc4bc713bd259cbd88d8f44de89b7
CC33_COMMIT=0b4f850d6c0fd8e0fe0ae1d3e80ac6733aced29b
CC33_VERSION=1.7.0.323
CC33_LOADER_SHA1=c364c4d89802bcac769ee6eebc08ae1c4ef5a205
CC33_CONF_SHA1=b39bfac65e0300e81dfcfee7301e07b4289df448
CC33_FIRMWARE_SHA1=821fa40f608e350baa9e4cdfea6719bf469c5220

say() { printf '\n=== %s ===\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

say 'TI K3 consumer preflight'
command -v ti-k3-self-test >/dev/null || die 'ti-k3-accelerators is not installed'
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI K3 RPMsg contract is not ready'
ti-k3-self-test || die 'TI K3 self-test failed; refusing to layer OpenHD over an unqualified platform'
systemctl start ti-k3-imx219-prepare.service
[[ -r /run/ti-k3/camera.env ]] || die 'TI K3 camera contract is unavailable'
if command -v openhd >/dev/null 2>&1; then
  die 'OpenHD is already installed. Use a clean TI-only baseline for this qualification.'
fi
KVER=$(uname -r)
[[ -s /boot/config-$KVER ]] || die "Missing /boot/config-$KVER"
if [[ "$with_rtl" == yes ]]; then
  [[ -d /lib/modules/$KVER/build ]] || die "Kernel headers missing for $KVER"
fi
if [[ "$with_cc33" == yes ]]; then
  grep -q '^CONFIG_CC33XX=m$' /boot/config-$KVER || die 'Kernel lacks CONFIG_CC33XX=m; rerun with --skip-cc33xx or qualify a board kernel with CC33xx support'
  grep -q '^CONFIG_CC33XX_SDIO=m$' /boot/config-$KVER || die 'Kernel lacks CONFIG_CC33XX_SDIO=m; rerun with --skip-cc33xx or qualify a board kernel with CC33xx support'
  modinfo -k "$KVER" cc33xx >/dev/null || die 'cc33xx module missing'
  modinfo -k "$KVER" cc33xx_sdio >/dev/null || die 'cc33xx_sdio module missing'
fi

say 'Installing build/runtime dependencies'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates git curl rsync build-essential cmake ninja-build pkg-config python3 patch xz-utils \
  libpoco-dev libusb-1.0-0-dev libpcap-dev libsodium-dev \
  libnl-3-dev libnl-genl-3-dev libnl-route-3-dev libsdl2-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libv4l-dev \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav \
  v4l-utils iw rfkill wireless-regdb wpasupplicant usbutils i2c-tools nmap \
  bc libelf-dev jq ethtool tcpdump kmod util-linux

say 'Installing OpenHD application-side adapters'
install -d -m 0755 /usr/local/sbin /etc/default /etc/systemd/system /etc/systemd/system/openhd.service.d \
  /etc/NetworkManager/conf.d /etc/systemd/network /etc/udev/rules.d /usr/local/share/OpenHD/SysUtils \
  /var/lib/openhd-k3 /boot/openhd
install -m 0755 "$root/adapter/overlay/usr/local/sbin/openhd-ti-camera-bridge" /usr/local/sbin/
install -m 0644 "$root/adapter/overlay/etc/systemd/system/openhd-ti-camera-bridge.service" /etc/systemd/system/
install -m 0644 "$root/adapter/overlay/etc/default/openhd-ti-camera.example" /etc/default/openhd-ti-camera

for s in openhd-fc-uart-setup openhd-find-management-wifi openhd-management-wifi-setup \
         openhd-radio-network-guard openhd-radio-prepare openhd-radio-watch openhd-wait-radio-ready; do
  install -m 0755 "$root/reference/r73341/overlay/usr/local/sbin/$s" /usr/local/sbin/
done
for u in openhd-radio-network-guard.service openhd-radio-network-guard@.service openhd-radio-watch.service; do
  install -m 0644 "$root/reference/r73341/overlay/etc/systemd/system/$u" /etc/systemd/system/
done
install -m 0644 "$root/reference/r73341/overlay/etc/NetworkManager/conf.d/90-openhd-radios-unmanaged.conf" /etc/NetworkManager/conf.d/
install -m 0644 "$root/reference/r73341/overlay/etc/systemd/network/05-openhd-radio-unmanaged.network" /etc/systemd/network/
install -m 0644 "$root/reference/r73341/overlay/etc/udev/rules.d/70-openhd-radio-unmanaged.rules" /etc/udev/rules.d/

cat >/etc/default/openhd <<EOF_ROLE
OPENHD_ARGS=--$role
EOF_ROLE
rm -f /boot/openhd/air.txt /boot/openhd/ground.txt
touch "/boot/openhd/$role.txt"

say 'Building pinned OpenHD'
buildroot=/var/tmp/openhd-k3-consumer-build
rm -rf "$buildroot"
mkdir -p "$buildroot"
git clone --recursive --branch 2.7-evo https://github.com/OpenHD/OpenHD.git "$buildroot/OpenHD"
git -C "$buildroot/OpenHD" checkout --detach "$OPENHD_COMMIT"
git -C "$buildroot/OpenHD" submodule update --init --recursive
for p in "$root"/reference/patches/openhd/*.patch; do
  git -C "$buildroot/OpenHD" apply --check "$p"
  git -C "$buildroot/OpenHD" apply "$p"
done
cmake -S "$buildroot/OpenHD/OpenHD" -B "$buildroot/openhd-build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DENABLE_AIR=ON -DENABLE_USB_CAMERAS=ON
cmake --build "$buildroot/openhd-build" --target openhd --parallel "$jobs"
DESTDIR="$buildroot/openhd-stage" cmake --install "$buildroot/openhd-build"
install -D -m 0644 "$buildroot/OpenHD/systemd/openhd.service" "$buildroot/openhd-stage/etc/systemd/system/openhd.service"
readelf -h "$buildroot/openhd-stage/usr/local/bin/openhd" | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'OpenHD build is not AArch64'
rsync -a --keep-dirlinks "$buildroot/openhd-stage/" /

say 'Building pinned OpenHD SysUtils'
git clone --branch main https://github.com/OpenHD/OpenHD-SysUtils.git "$buildroot/OpenHD-SysUtils"
git -C "$buildroot/OpenHD-SysUtils" checkout --detach "$SYSUTILS_COMMIT"
for p in "$root"/reference/patches/openhd-sysutils/*.patch; do
  git -C "$buildroot/OpenHD-SysUtils" apply --check "$p"
  git -C "$buildroot/OpenHD-SysUtils" apply "$p"
done
cmake -S "$buildroot/OpenHD-SysUtils" -B "$buildroot/sysutils-build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build "$buildroot/sysutils-build" --target openhd_sys_utils --parallel "$jobs"
DESTDIR="$buildroot/sysutils-stage" cmake --install "$buildroot/sysutils-build"
readelf -h "$buildroot/sysutils-stage/usr/local/bin/openhd_sys_utils" | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'SysUtils build is not AArch64'
rsync -a --keep-dirlinks "$buildroot/sysutils-stage/" /

cat >/usr/local/share/OpenHD/SysUtils/config.json <<EOF_SYS
{
  "platform_type": 70,
  "platform_name": "BEAGLEY-AI (AM67A)",
  "run_mode": "$role",
  "init_system": "systemd",
  "wifi_enable_autodetect": true,
  "firstboot": false
}
EOF_SYS
cat >/usr/local/share/OpenHD/SysUtils/wifi_overrides.conf <<'EOF_WIFI'
# Optional per-interface OpenHD Wi-Fi overrides.
EOF_WIFI
cat >/usr/local/share/OpenHD/SysUtils/wifi_txpower.conf <<'EOF_WIFI'
# Optional OpenHD Wi-Fi transmit-power overrides.
EOF_WIFI
cat >/usr/local/share/OpenHD/SysUtils/wifi_cards.json <<'EOF_CARDS'
{
  "cards": [
    {"vendor_id":"0x02D0","device_id":"0xA9A6","chipset":"BROADCOM","name":"Raspberry Internal","power_mode":"fixed"},
    {"vendor_id":"0x0BDA","device_id":"0xA81A","chipset":"OPENHD_RTL_88X2EU","name":"LB-Link 8812eu","power_mode":"mw","min_mw":25,"max_mw":1000,"levels_mw":{"lowest":25,"low":100,"mid":500,"high":1000}}
  ]
}
EOF_CARDS

say 'Installing CC33xx management-WiFi firmware'
if [[ "$with_cc33" == yes ]]; then
  cc="$buildroot/cc33xx-fw"
  git clone -q --no-checkout https://git.ti.com/git/cc33xx-wlan/cc33xx-fw.git "$cc"
  git -C "$cc" checkout -q --detach "$CC33_COMMIT"
  [[ $(git -C "$cc" rev-parse HEAD) == "$CC33_COMMIT" ]] || die 'CC33xx checkout mismatch'
  find_blob(){ find "$cc" -type f -name "$1" -print -quit; }
  loader=$(find_blob cc33xx_2nd_loader.bin); fw=$(find_blob cc33xx_fw.bin); conf=$(find_blob cc33xx-conf.bin)
  [[ -s "$loader" && -s "$fw" && -s "$conf" ]] || die 'CC33xx firmware set incomplete'
  [[ $(sha1sum "$loader" | awk '{print $1}') == "$CC33_LOADER_SHA1" ]] || die 'CC33 loader hash mismatch'
  [[ $(sha1sum "$fw" | awk '{print $1}') == "$CC33_FIRMWARE_SHA1" ]] || die 'CC33 firmware hash mismatch'
  [[ $(sha1sum "$conf" | awk '{print $1}') == "$CC33_CONF_SHA1" ]] || die 'CC33 config hash mismatch'
  install -d -m 0755 /lib/firmware/ti-connectivity
  install -m 0644 "$loader" /lib/firmware/ti-connectivity/cc33xx_2nd_loader.bin
  install -m 0644 "$fw" /lib/firmware/ti-connectivity/cc33xx_fw.bin
  install -m 0644 "$conf" /lib/firmware/ti-connectivity/cc33xx-conf.bin
  cat >/var/lib/openhd-k3/cc33xx-firmware.env <<EOF_CC
version=$CC33_VERSION
commit=$CC33_COMMIT
loader_sha1=$CC33_LOADER_SHA1
config_sha1=$CC33_CONF_SHA1
firmware_sha1=$CC33_FIRMWARE_SHA1
EOF_CC
  cat >/etc/modules-load.d/cc33xx.conf <<'EOF_MOD'
cc33xx
cc33xx_sdio
EOF_MOD
else
  echo 'Skipped CC33xx firmware by request.'
fi

say 'Building pinned RTL8812AU OpenHD RF module'
if [[ "$with_rtl" == yes ]]; then
  src="$buildroot/rtl8812au"
  archive="$buildroot/rtl8812au.tar.gz"
  curl --fail --location --retry 5 --retry-delay 2 --retry-all-errors \
    "https://github.com/aircrack-ng/rtl8812au/archive/$RTL_COMMIT.tar.gz" -o "$archive"
  mkdir -p "$src"
  tar -xzf "$archive" --strip-components=1 -C "$src"
  sed -i 's/^CONFIG_PLATFORM_I386_PC = y$/CONFIG_PLATFORM_I386_PC = n/' "$src/Makefile"
  sed -i 's/^CONFIG_PLATFORM_ARM64_RPI = n$/CONFIG_PLATFORM_ARM64_RPI = y/' "$src/Makefile"
  cc=/usr/bin/gcc
  wrapper="$root/helpers/openhd-gcc-kbuild-filter"
  rtlcc="$cc"
  printf 'int x(void){return 0;}\n' >/tmp/ohd-cc-probe.c
  if ! "$cc" -fmin-function-alignment=8 -c /tmp/ohd-cc-probe.c -o /tmp/ohd-cc-probe.o >/dev/null 2>&1; then rtlcc="$wrapper"; fi
  rm -f /tmp/ohd-cc-probe.c /tmp/ohd-cc-probe.o
  OPENHD_REAL_CC="$cc" make -C "$src" -j"$jobs" ARCH=arm64 CC="$rtlcc" HOSTCC="$cc" \
    KVER="$KVER" KSRC="/lib/modules/$KVER/build" USER_MODULE_NAME=88XXau modules
  module=$(find "$src" -type f \( -name '88XXau_ohd.ko' -o -name '88XXau.ko' \) -print -quit)
  [[ -s "$module" ]] || die 'RTL8812AU module was not produced'
  install -D -m 0644 "$module" "/lib/modules/$KVER/updates/openhd/88XXau_ohd.ko"
  cat >/etc/modprobe.d/openhd-rtl8812au.conf <<'EOF_RTL'
blacklist rtl8xxxu
options 88XXau_ohd rtw_led_ctrl=0 rtw_switch_usb_mode=1
EOF_RTL
  depmod -a "$KVER"
  modinfo -k "$KVER" 88XXau_ohd >/dev/null || die 'Installed RTL8812AU module is not discoverable'
else
  echo 'Skipped RTL8812AU by request.'
fi

say 'Installing application systemd boundary'
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
# Deliberately do not enable/start the target during qualification.
systemctl disable openhd-k3-consumer.target 2>/dev/null || true
systemctl stop openhd.service openhd-ti-camera-bridge.service openhd-radio-watch.service 2>/dev/null || true

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
echo
echo 'OpenHD consumer layer installed but NOT activated.'
echo 'Next qualification steps:'
echo '  systemctl start openhd-ti-camera-bridge.service'
echo '  tcpdump -ni lo udp port 5500 -c 10'
echo '  systemctl start openhd-sys-utils.service openhd-radio-network-guard.service'
echo '  systemctl start openhd.service'
echo 'After RF qualification: systemctl enable --now openhd-k3-consumer.target'
