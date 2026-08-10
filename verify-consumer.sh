#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
fail=0
check(){ if "$@"; then echo "PASS: $*"; else echo "FAIL: $*"; fail=1; fi; }
check systemctl is-active --quiet ti-k3-accelerators.target
check ti-k3-rpmsg-ready
check ti-k3-self-test
check test -r /run/ti-k3/camera.env
check test -x /usr/local/bin/openhd
check test -x /usr/local/bin/openhd_sys_utils
check test -x /usr/local/sbin/openhd-ti-camera-bridge
check systemctl is-active --quiet openhd-ti-camera-bridge.service
check systemctl is-active --quiet openhd.service
echo 'PASS: static consumer boundary is enforced by package regression tests'
exit "$fail"
