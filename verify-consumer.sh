#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

fail=0

pass_msg() {
  echo "PASS: $*"
}

fail_msg() {
  echo "FAIL: $*" >&2
  fail=1
}

check_cmd() {
  local label=$1
  shift
  if "$@"; then
    pass_msg "$label"
  else
    fail_msg "$label"
  fi
}

check_cmd 'ti-k3-accelerators.target active' systemctl is-active --quiet ti-k3-accelerators.target
check_cmd 'TI K3 RPMsg contract ready' ti-k3-rpmsg-ready
check_cmd 'TI K3 self-test passes' ti-k3-self-test
check_cmd '/etc/ti-k3/gstreamer.env readable' test -r /etc/ti-k3/gstreamer.env
check_cmd '/run/ti-k3/camera.env readable' test -r /run/ti-k3/camera.env
check_cmd '/run/ti-k3/camera-video present' test -e /run/ti-k3/camera-video
check_cmd '/run/ti-k3/camera-subdev present' test -e /run/ti-k3/camera-subdev
check_cmd 'OpenHD executable present' test -x /usr/local/bin/openhd
check_cmd 'OpenHD SysUtils executable present' test -x /usr/local/bin/openhd_sys_utils
check_cmd 'openhd-k3-consumer.target active' systemctl is-active --quiet openhd-k3-consumer.target
check_cmd 'openhd.service active' systemctl is-active --quiet openhd.service

if systemctl is-active --quiet openhd-ti-camera-bridge.service; then
  fail_msg 'legacy openhd-ti-camera-bridge.service must remain inactive'
else
  pass_msg 'legacy openhd-ti-camera-bridge.service inactive'
fi

if ss -H -lunp 2>/dev/null | grep -Eq '127\.0\.0\.1:5500([[:space:]]|$)'; then
  fail_msg 'unexpected UDP listener on 127.0.0.1:5500'
else
  pass_msg 'no UDP listener on 127.0.0.1:5500'
fi

role=unknown
if [[ -r /var/lib/openhd-k3/consumer.env ]]; then
  role=$(sed -n 's/^role=//p' /var/lib/openhd-k3/consumer.env | tail -n 1)
fi

if [[ "$role" == air || "$role" == ground ]]; then
  pass_msg "consumer role is $role"
else
  fail_msg "consumer role is valid (found: $role)"
fi

mapfile -t openhd_pids < <(pgrep -x openhd || true)

openhd_pid=
if (( ${#openhd_pids[@]} == 1 )); then
  openhd_pid=${openhd_pids[0]}
  pass_msg "exactly one OpenHD process running (pid=$openhd_pid)"
else
  fail_msg "exactly one OpenHD process running (found ${#openhd_pids[@]})"
fi

if [[ -n "$openhd_pid" && "$role" != unknown ]]; then
  cmdline=$(tr '\0' ' ' <"/proc/$openhd_pid/cmdline")
  if [[ " $cmdline " == *" --$role "* ]]; then
    pass_msg "OpenHD process role argument is --$role"
  else
    fail_msg "OpenHD process role argument is --$role (cmdline: $cmdline)"
  fi

  proc_env=$(tr '\0' '\n' <"/proc/$openhd_pid/environ")

  if grep -Fq 'LD_LIBRARY_PATH=/opt/ti-k3/runtime/current/ti' <<<"$proc_env"; then
    pass_msg 'OpenHD process has TI LD_LIBRARY_PATH'
  else
    fail_msg 'OpenHD process has TI LD_LIBRARY_PATH'
  fi

  if grep -Fq 'GST_PLUGIN_PATH_1_0=/opt/ti-k3/runtime/current/gstreamer/gstreamer-1.0:/opt/ti-k3/runtime/current/ti/gstreamer-1.0' <<<"$proc_env"; then
    pass_msg 'OpenHD process has TI GST_PLUGIN_PATH_1_0'
  else
    fail_msg 'OpenHD process has TI GST_PLUGIN_PATH_1_0'
  fi
fi

if [[ "$role" == air ]]; then
  generic=/usr/local/share/openhd/video/air_camera_generic.json

  if [[ -r "$generic" ]] && jq -e '.primary_camera_type == 150' "$generic" >/dev/null 2>&1; then
    pass_msg 'air primary_camera_type is Native-R1 J722S camera type 150'
  else
    fail_msg 'air primary_camera_type is Native-R1 J722S camera type 150'
  fi

  camera_dev=$(readlink -f /run/ti-k3/camera-video 2>/dev/null || true)

  owns_camera=no
  if [[ -n "$openhd_pid" && -n "$camera_dev" ]]; then
    for fd in /proc/"$openhd_pid"/fd/*; do
      fd_target=$(readlink -f "$fd" 2>/dev/null || true)
      if [[ "$fd_target" == "$camera_dev" ]]; then
        owns_camera=yes
        break
      fi
    done
  fi

  if [[ "$owns_camera" == yes ]]; then
    pass_msg "OpenHD owns TI camera device $camera_dev"
  else
    fail_msg "OpenHD owns TI camera device $camera_dev"
  fi
fi

echo 'PASS: TI remoteproc/firmware ownership remains delegated to ti-k3-accelerators APIs; this verifier performs no remoteproc state writes.'

exit "$fail"
