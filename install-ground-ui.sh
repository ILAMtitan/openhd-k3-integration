#!/usr/bin/env bash
set -eu

usage()
{
    cat >&2 <<'USAGE'
Usage: ./install-ground-ui.sh [--jobs N]

Adds the QOpenHD/X11 ground UI layer to an already-installed ground-role
openhd-k3-integration consumer. The TI K3 accelerator platform remains owned by
ti-k3-accelerators; this installer does not manipulate remoteproc, firmware
aliases, reserved memory, TIOVX, or Wave5 platform state.
USAGE
    exit 2
}

[ "$(id -u)" -eq 0 ] || {
    echo 'Run as root.' >&2
    exit 1
}

root="$(cd "$(dirname "$0")" && pwd)"
jobs="$(nproc)"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --jobs)
            jobs="${2:?missing jobs}"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

case "$jobs" in
    ''|*[!0-9]*) usage ;;
esac
[ "$jobs" -gt 0 ] || usage

QOPENHD_REPOSITORY=https://github.com/OpenHD/QOpenHD.git
QOPENHD_BRANCH=2.7-evo
QOPENHD_COMMIT=6dd753d730bbd732dd747790b86e42ae6a5f6b2e
GROUND_UI_VERSION="$(cat "$root/GROUND-UI-VERSION")"

say()
{
    printf '\n=== %s ===\n' "$*"
}

die()
{
    echo "ERROR: $*" >&2
    exit 1
}

consumer=/var/lib/openhd-k3/consumer.env
[ -r "$consumer" ] || die 'OpenHD K3 consumer is not installed; run install-live.sh --role ground first'
role="$(sed -n 's/^role=//p' "$consumer" | tail -n 1)"
[ "$role" = ground ] || die "Ground UI can only be installed over role=ground (found ${role:-missing})"

say 'TI K3 platform preflight'
command -v ti-k3-rpmsg-ready >/dev/null 2>&1 || die 'ti-k3-rpmsg-ready is missing'
command -v ti-k3-self-test >/dev/null 2>&1 || die 'ti-k3-self-test is missing'
systemctl is-active --quiet ti-k3-accelerators.target || die 'ti-k3-accelerators.target is not active'
ti-k3-rpmsg-ready >/dev/null || die 'TI K3 RPMsg readiness failed'
ti-k3-self-test >/dev/null || die 'TI K3 self-test failed'

say 'Installing QOpenHD build and X11 runtime dependencies'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates git make build-essential pkg-config rsync procps \
    zenity polkitd pkexec mate-polkit \
    libjsoncpp-dev libtinyxml2-dev libdrm-dev libegl1-mesa-dev \
    libgles2-mesa-dev libgbm-dev libavcodec-dev libavformat-dev libavutil-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-gl gstreamer1.0-libav \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-qt5 \
    qtchooser qt5-qmake qtbase5-dev qtbase5-private-dev qtdeclarative5-dev \
    qttools5-dev-tools qtpositioning5-dev qtmultimedia5-dev \
    libqt5opengl5-dev libqt5charts5-dev libqt5texttospeech5-dev \
    libqt5svg5-dev libqt5x11extras5-dev libqt5location5-plugins \
    libqt5multimedia5-plugins libqt5positioning5-plugins \
    qml-module-qtcharts qml-module-qtgraphicaleffects \
    qml-module-qt-labs-platform qml-module-qt-labs-settings \
    qml-module-qtlocation qml-module-qtmultimedia qml-module-qtpositioning \
    qml-module-qtquick2 qml-module-qtquick-controls \
    qml-module-qtquick-controls2 qml-module-qtquick-dialogs \
    qml-module-qtquick-extras qml-module-qtquick-layouts \
    qml-module-qtquick-shapes qml-module-qtquick-window2

say 'Building pinned QOpenHD'
buildroot=/var/tmp/openhd-k3-ground-ui-build
src="$buildroot/QOpenHD"
build="$buildroot/qopenhd-build"
rm -rf "$buildroot"
mkdir -p "$buildroot"

git clone --recursive --branch "$QOPENHD_BRANCH" "$QOPENHD_REPOSITORY" "$src"
git -C "$src" checkout --detach "$QOPENHD_COMMIT"
git -C "$src" submodule update --init --recursive
[ "$(git -C "$src" rev-parse HEAD)" = "$QOPENHD_COMMIT" ] || die 'QOpenHD checkout mismatch'

for patch_file in "$root"/patches/qopenhd/*.patch; do
    [ -f "$patch_file" ] || continue
    git -C "$src" apply --check "$patch_file"
    git -C "$src" apply "$patch_file"
done

find "$src/translations" -maxdepth 1 -type f -name '*.ts' -print |
while read -r ts; do
    base="$(basename "$ts" .ts)"
    lrelease "$ts" -qm "$src/qml/$base.qm"
done

mkdir -p "$build"
(
    cd "$build"
    QT_SELECT=qt5 qmake "$src/QOpenHD.pro" CONFIG+=release
    make -j"$jobs"
)

binary="$(find "$build" -type f -name QOpenHD -perm -0100 -print -quit)"
[ -n "$binary" ] && [ -s "$binary" ] || die 'QOpenHD binary was not produced'
install -D -m 0755 "$binary" /usr/local/bin/QOpenHD
readelf -h /usr/local/bin/QOpenHD | grep -Eq 'Machine:[[:space:]]+AArch64' || die 'QOpenHD build is not AArch64'

say 'Installing ground UI policy and launchers'
install -D -m 0644 "$root/overlay/etc/default/openhd-ground-ui" /etc/default/openhd-ground-ui
install -D -m 0644 "$root/overlay/etc/sysctl.d/90-openhd-ground.conf" /etc/sysctl.d/90-openhd-ground.conf
install -D -m 0644 "$root/overlay/etc/polkit-1/rules.d/49-openhd-ground-active-user.rules" /etc/polkit-1/rules.d/49-openhd-ground-active-user.rules
install -D -m 0644 "$root/overlay/usr/share/polkit-1/actions/com.axiom.openhd-ground.policy" /usr/share/polkit-1/actions/com.axiom.openhd-ground.policy
install -D -m 0644 "$root/overlay/usr/share/applications/openhd-ground.desktop" /usr/share/applications/openhd-ground.desktop
install -D -m 0644 "$root/overlay/usr/share/applications/openhd-ground-stop.desktop" /usr/share/applications/openhd-ground-stop.desktop
install -D -m 0755 "$root/overlay/usr/local/bin/openhd-ground-launch" /usr/local/bin/openhd-ground-launch
install -D -m 0755 "$root/overlay/usr/local/bin/openhd-ground-stop" /usr/local/bin/openhd-ground-stop
install -D -m 0755 "$root/overlay/usr/local/sbin/openhd-ground-control" /usr/local/sbin/openhd-ground-control
install -D -m 0755 "$root/overlay/usr/local/sbin/openhd-ground-key" /usr/local/sbin/openhd-ground-key

sysctl --system >/dev/null

say 'Provisioning OpenHD link key'
key=/usr/local/share/openhd/txrx.key
if [ -f "$key" ]; then
    [ "$(stat -c '%s' "$key")" -eq 128 ] || die "Existing OpenHD key has invalid size: $key"
    chmod 0600 "$key"
else
    /usr/local/sbin/openhd-ground-key generate
fi

say 'Publishing desktop launchers'
for home in /home/*; do
    [ -d "$home" ] || continue
    owner="$(stat -c '%U' "$home")"
    uid="$(id -u "$owner" 2>/dev/null || echo 0)"
    [ "$uid" -ge 1000 ] || continue
    install -d -m 0755 -o "$owner" -g "$(id -gn "$owner")" "$home/Desktop"
    install -m 0755 -o "$owner" -g "$(id -gn "$owner")" \
        "$root/overlay/etc/skel/Desktop/OpenHD Ground Station.desktop" \
        "$home/Desktop/OpenHD Ground Station.desktop"
    install -m 0755 -o "$owner" -g "$(id -gn "$owner")" \
        "$root/overlay/etc/skel/Desktop/Stop OpenHD Ground.desktop" \
        "$home/Desktop/Stop OpenHD Ground.desktop"
done

install -D -m 0755 "$root/overlay/etc/skel/Desktop/OpenHD Ground Station.desktop" \
    '/etc/skel/Desktop/OpenHD Ground Station.desktop'
install -D -m 0755 "$root/overlay/etc/skel/Desktop/Stop OpenHD Ground.desktop" \
    '/etc/skel/Desktop/Stop OpenHD Ground.desktop'

install -d -m 0755 /var/lib/openhd-k3
cat >/var/lib/openhd-k3/ground-ui.env <<EOF_META
format=1
ground_ui_version=$GROUND_UI_VERSION
qopenhd_commit=$QOPENHD_COMMIT
qopenhd_render_mode=software-x11
qopenhd_primary_video=intentionally-disabled
consumer_dependency=openhd-k3-consumer.target
platform_dependency=ti-k3-accelerators.target
EOF_META

systemctl daemon-reload

say 'Ground UI installation verification'
"$root/verify-ground-ui.sh"

echo
echo 'Ground QOpenHD layer installed but NOT started automatically.'
echo 'Primary QOpenHD video is intentionally disabled in this stable UI pass.'
echo 'Launch from the desktop icon or run /usr/local/bin/openhd-ground-launch as the graphical user.'
