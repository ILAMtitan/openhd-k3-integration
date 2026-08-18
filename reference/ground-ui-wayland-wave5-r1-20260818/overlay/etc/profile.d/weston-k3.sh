if [ -S /run/weston/wayland-0 ]; then
    export XDG_RUNTIME_DIR=/run/weston
    export WAYLAND_DISPLAY=wayland-0
    export XDG_SESSION_TYPE=wayland
fi
