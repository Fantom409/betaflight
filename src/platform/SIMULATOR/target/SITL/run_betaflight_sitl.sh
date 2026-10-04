#!/usr/bin/env bash

set -Eeuo pipefail

readonly SITL_HOST="127.0.0.1"
readonly SITL_PORT="5761"
readonly WEBSOCKET_HOST="127.0.0.1"
readonly WEBSOCKET_PORT="6761"

usage() {
    cat <<'EOF'
Usage: run_betaflight_sitl.sh [BETAFLIGHT_DIR]

Build Betaflight's SITL target, start it, and expose UART1 to the online
Betaflight Configurator through websockify.

By default, the script uses the Betaflight checkout that contains it. A
different checkout may be supplied as an argument or via BETAFLIGHT_DIR:
  BETAFLIGHT_DIR=/path/to/betaflight ./run_betaflight_sitl.sh

In the configurator, enable manual connection mode and connect to:
  ws://127.0.0.1:6761
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

port_is_listening() {
    local port="$1"
    ss -ltnH "sport = :${port}" 2>/dev/null | grep -q .
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
default_betaflight_dir="$(realpath "$script_dir/../../../../..")"
betaflight_dir="${1:-${BETAFLIGHT_DIR:-$default_betaflight_dir}}"
betaflight_dir="$(realpath "$betaflight_dir")"

[[ -f "$betaflight_dir/Makefile" ]] || die "$betaflight_dir does not look like a Betaflight source checkout"
command_exists make || die "make is not installed"
command_exists ss || die "ss is not installed (install the iproute2 package)"

if command_exists websockify; then
    websockify_command=(websockify)
elif python3 -c 'import websockify' >/dev/null 2>&1; then
    websockify_command=(python3 -m websockify)
else
    die "websockify is not installed; run: python3 -m pip install --user websockify"
fi

if port_is_listening "$WEBSOCKET_PORT"; then
    die "TCP port $WEBSOCKET_PORT is already in use; stop the existing websockify process first"
fi

printf 'Building Betaflight SITL in %s ...\n' "$betaflight_dir"
make -C "$betaflight_dir" TARGET=SITL

sitl_binary="$betaflight_dir/obj/main/betaflight_SITL.elf"
[[ -x "$sitl_binary" ]] || die "build completed but $sitl_binary was not created"

sitl_pid=''
cleanup() {
    if [[ -n "$sitl_pid" ]] && kill -0 "$sitl_pid" 2>/dev/null; then
        printf '\nStopping Betaflight SITL (PID %s) ...\n' "$sitl_pid"
        kill "$sitl_pid" 2>/dev/null || true
        wait "$sitl_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

printf 'Starting Betaflight SITL ...\n'
(
    cd "$betaflight_dir"
    exec "$sitl_binary"
) &
sitl_pid=$!

for _ in {1..100}; do
    if port_is_listening "$SITL_PORT"; then
        break
    fi
    if ! kill -0 "$sitl_pid" 2>/dev/null; then
        wait "$sitl_pid" || true
        die "Betaflight SITL exited before opening TCP port $SITL_PORT"
    fi
    sleep 0.1
done

port_is_listening "$SITL_PORT" || die "timed out waiting for Betaflight SITL on TCP port $SITL_PORT"

printf '\nSITL is ready. In the online configurator, connect to:\n'
printf '  ws://%s:%s\n\n' "$WEBSOCKET_HOST" "$WEBSOCKET_PORT"
printf 'Press Ctrl-C to stop websockify and SITL.\n'

"${websockify_command[@]}" \
    "$WEBSOCKET_HOST:$WEBSOCKET_PORT" \
    "$SITL_HOST:$SITL_PORT"
