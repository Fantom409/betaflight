#!/usr/bin/env python3
"""Prepare a patched bridge and runway world without changing external assets."""

import argparse
import math
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


# Keep the source patch reproducible as upstream evolves.
AEROLOOP_REVISION = "a6c16d2d653932a96ced279522ba39b6da15f78c"


def nonnegative(value):
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise argparse.ArgumentTypeError("must be finite and nonnegative")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--ardupilot-assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--gyro-noise", type=nonnegative, default=0.0, help="rad/s standard deviation")
    parser.add_argument("--accel-noise", type=nonnegative, default=0.0, help="m/s^2 standard deviation")
    args = parser.parse_args()
    revision = subprocess.check_output(
        ["git", "-C", str(args.assets), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != AEROLOOP_REVISION:
        parser.error(f"Aeroloop must be at revision {AEROLOOP_REVISION}; got {revision}")

    tree = ET.parse(args.ardupilot_assets / "worlds/iris_runway.sdf")
    world = tree.getroot().find("world")
    # Replace only the aircraft; retain runway, lighting, coordinates and physics.
    aircraft = [node for node in world.findall("include")
                if node.findtext("uri") == "model://iris_with_gimbal"]
    if len(aircraft) != 1:
        parser.error("expected one iris_with_gimbal include in iris_runway.sdf")
    model = ET.parse(args.assets / "models/betaloop_iris_with_standoffs/model.sdf").getroot().find("model")
    model.set("name", "iris")
    model.find("pose").text = aircraft[0].findtext("pose")
    model.find("pose").set("degrees", "true")
    world.remove(aircraft[0])
    world.append(model)
    world.find("physics/max_step_size").text = "0.001"

    imu = model.find(".//sensor[@type='imu']")
    ET.SubElement(imu, "topic").text = "/betaflight/imu"
    settings = ET.SubElement(imu, "imu")
    for kind, stddev in (("angular_velocity", args.gyro_noise),
                         ("linear_acceleration", args.accel_noise)):
        group = ET.SubElement(settings, kind)
        for axis in "xyz":
            noise = ET.SubElement(ET.SubElement(group, axis), "noise", type="gaussian")
            ET.SubElement(noise, "mean").text = "0"
            ET.SubElement(noise, "stddev").text = str(stddev)

    # The bridge consumes motor_speed in array order: BF QUADX rear-right,
    # front-right, rear-left, front-left. Pair each joint with its spin direction.
    plugin = model.find("plugin[@filename='BetaflightPlugin']")
    # At 1 ms physics steps, tolerate brief scheduling gaps without repeatedly
    # dropping motor control. Valid motor packets reset the bridge's counter.
    plugin.find("connectionTimeoutMaxCount").text = "500"
    for rotor, joint, direction in zip(plugin.findall("rotor"),
                                     (3, 0, 1, 2), ("cw", "ccw", "ccw", "cw")):
        rotor.find("jointName").text = f"rotor_{joint}_joint"
        rotor.find("turningDirection").text = direction

    plugin_dir = args.output / "plugin"
    plugin_dir.mkdir(parents=True, exist_ok=True)
    for name in ("CMakeLists.txt", "BetaflightPlugin.hh", "BetaflightPlugin.cc"):
        shutil.copyfile(args.assets / "plugins" / name, plugin_dir / name)
    subprocess.run(["patch", "--batch", "-p1", "-i",
                    str(Path(__file__).with_name("gazebo_imu.patch").resolve())],
                   cwd=plugin_dir, check=True)
    ET.indent(tree)
    tree.write(args.output / "iris_runway_betaflight.sdf", encoding="utf-8", xml_declaration=True)
    print(f"World prepared: gyro noise {args.gyro_noise} rad/s, accel noise {args.accel_noise} m/s^2")


if __name__ == "__main__":
    main()
