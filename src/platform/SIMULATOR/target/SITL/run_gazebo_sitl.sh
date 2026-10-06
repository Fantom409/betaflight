#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
betaflight_dir="$(realpath "$script_dir/../../../../..")"
assets="${AEROLOOP_GAZEBO_DIR:-$betaflight_dir/obj/aeroloop_gazebo}"
ardupilot_assets="${ARDUPILOT_GAZEBO_DIR:-$HOME/gz_ws/src/ardupilot_gazebo}"
build_dir="$betaflight_dir/obj/sitl-gazebo"

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<'EOF'
Usage: run_gazebo_sitl.sh [--headless] [WORLD_GENERATOR_OPTIONS]

Start Gazebo Harmonic with a Betaflight Iris in the installed ArduPilot runway
world. Start run_betaflight_sitl.sh in another terminal first.

World options: --gyro-noise STDDEV (rad/s), --accel-noise STDDEV (m/s^2)
Environment: AEROLOOP_GAZEBO_DIR, ARDUPILOT_GAZEBO_DIR
EOF
    exit 0
fi

gz_args=(-v4 -r)
if [[ "${1:-}" == --headless ]]; then
    gz_args+=(-s)
    shift
fi

[[ -f "$assets/plugins/BetaflightPlugin.cc" ]] || {
    printf 'Missing Aeroloop Gazebo assets. See %s/README.md\n' "$script_dir" >&2
    exit 1
}

python3 "$script_dir/prepare_gazebo_sitl.py" \
    --assets "$assets" --ardupilot-assets "$ardupilot_assets" \
    --output "$build_dir" "$@"
cmake -S "$build_dir/plugin" -B "$build_dir/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir/build" --parallel 4

export GZ_SIM_RESOURCE_PATH="$assets/models:$ardupilot_assets/models:$ardupilot_assets/worlds:${GZ_SIM_RESOURCE_PATH:-}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$build_dir/build:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
printf 'Starting Betaflight runway world: %s\n' "$build_dir/iris_runway_betaflight.sdf"
exec gz sim "${gz_args[@]}" "$build_dir/iris_runway_betaflight.sdf"
