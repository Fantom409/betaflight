## Gazebo Harmonic (`gz sim`) with the runway world

The stock ArduPilot `iris_runway.sdf` loads `ArduPilotPlugin`, which does not
speak Betaflight's binary UDP protocol. Use the supplied Gazebo launcher with
the SITL launcher to keep that environment and replace the aircraft with a
Betaflight Iris. Gazebo Harmonic (gz-sim8), its development libraries, CMake,
Git, `patch`, and Python 3 are required.

Download the compatible bridge and model once, from the Betaflight repository
root (these assets and their build outputs stay in ignored `obj/`):

```sh
git clone --branch gz https://github.com/betaflight/aeroloop_gazebo.git obj/aeroloop_gazebo
git -C obj/aeroloop_gazebo checkout a6c16d2d653932a96ced279522ba39b6da15f78c
```

The launcher expects the existing ArduPilot Gazebo checkout at
`~/gz_ws/src/ardupilot_gazebo`. Set `ARDUPILOT_GAZEBO_DIR` to override it, or
`AEROLOOP_GAZEBO_DIR` to use a different Aeroloop checkout at the pinned revision.
Source your Gazebo / ROS environment first if its tools and libraries are
provided through ROS vendor packages.

Terminal 1, start Betaflight and the configurator proxy:

```sh
./src/platform/SIMULATOR/target/SITL/run_betaflight_sitl.sh
```

Terminal 2, start the runway simulation:

```sh
./src/platform/SIMULATOR/target/SITL/run_gazebo_sitl.sh
```

Connect the configurator to `ws://127.0.0.1:6761`. The Gazebo launcher builds
a patched copy of the external bridge and generates
`obj/sitl-gazebo/iris_runway_betaflight.sdf`, then runs `gz sim -v4 -r` on it.
Add `--headless` to run the server without the GUI. Stop each terminal with
Ctrl-C. Do not run the stock ArduPilot world alongside this one.

For independent Gaussian noise on all three IMU axes:

```sh
./src/platform/SIMULATOR/target/SITL/run_gazebo_sitl.sh --gyro-noise 0.01 --accel-noise 0.02
```

These values are standard deviations in rad/s and m/s² respectively; both
default to zero. The bridge consumes `/betaflight/imu` sensor messages, so
Gazebo's gravity, sensor orientation and noise reach Betaflight's virtual gyro
and accelerometer. Sensor data is sent even before motor commands arrive,
allowing the simulation to start disarmed. Motor joints are mapped to
Betaflight QUADX order (rear-right, front-right, rear-left, front-left).

This checkout runs its real attitude estimator. GPS is derived from Gazebo
position and world spherical coordinates; barometer pressure is derived from
altitude, and magnetometer readings are synthesized from attitude in `sitl.c`.
Adding separate Gazebo pressure or magnetic sensors alone will not affect
those Betaflight inputs. Independent GPS, barometer, or magnetometer noise and
failure models require extending that sensor path.

To change terrain, obstacles or physics, edit the generated SDF and launch it
directly with the same resource and plugin paths (the launcher regenerates it
on every invocation):

```sh
export GZ_SIM_RESOURCE_PATH="$PWD/obj/aeroloop_gazebo/models:$HOME/gz_ws/src/ardupilot_gazebo/models:$HOME/gz_ws/src/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH:-}"
export GZ_SIM_SYSTEM_PLUGIN_PATH="$PWD/obj/sitl-gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH:-}"
gz sim -v4 -r obj/sitl-gazebo/iris_runway_betaflight.sdf
```

Environment wind also needs Gazebo's WindEffects system and wind-enabled model
links; setting a world wind vector alone does not apply forces to this model.
RC control is separate: send receiver channels over UDP 9004 or use
`MSP_SET_RAW_RC` with an MSP receiver configuration. The configurator connection
alone does not provide continuous RC input.

The bridge patch is in `gazebo_imu.patch`. It also replaces upstream's ESC
telemetry extension with this checkout's 144-byte FDM packet ending in
pressure; electrical ESC behavior remains outside this simulation.

## Legacy: Gazebo Classic 8 with ArduCopterPlugin
SITL (software in the loop) simulator allows you to run betaflight/cleanflight without any hardware.
Currently only tested on Ubuntu 16.04, x86_64, gcc (Ubuntu 5.4.0-6ubuntu1~16.04.4) 5.4.0 20160609.

### install gazebo 8
see here: [Installation](http://gazebosim.org/tutorials?cat=install)

### copy & modify world
for Ubunutu 16.04:
`cp /usr/share/gazebo-8/worlds/iris_arducopter_demo.world .`

change `real_time_update_rate` in `iris_arducopter_demo.world`:
`<real_time_update_rate>0</real_time_update_rate>`
to
`<real_time_update_rate>100</real_time_update_rate>`
***this suggest set to non-zero***

`100` mean what speed your computer should run in (Hz).
Faster computer can set to a higher rate.
see [here](http://gazebosim.org/tutorials?tut=modifying_world&cat=build_world#PhysicsProperties) for detail.
`max_step_size` should NOT higher than `0.0025` as I tested.
smaller mean more accurate, but need higher speed CPU to run as realtime.

### build betaflight
run `make TARGET=SITL`

### settings
to avoid simulation speed slow down, suggest to set some settings belows:

In `configuration` page:

1. `ESC/Motor`: `PWM` or `DSHOT150`/`DSHOT300`/`DSHOT600`. DShot uses
   Betaflight's digital motor endpoints and command handling, then converts the
   throttle to the same normalised UDP output as PWM. Electrical signalling,
   ESC responses, and bidirectional DShot telemetry are not simulated.
2. `PID loop frequency` as high as it can.

To verify the virtual DShot backend from the CLI:

```
set motor_pwm_protocol = DSHOT300
save
```

After restarting SITL, its log should contain:

```
Initialized virtual DShot motor count 4
```

### start and run
1. start betaflight: `./obj/main/betaflight_SITL.elf`
2. start gazebo: `gazebo --verbose ./iris_arducopter_demo.world`
4. connect your transmitter and fly/test, I used a app to send `MSP_SET_RAW_RC`, code available [here](https://github.com/cs8425/msp-controller).

### online configurator

The included launcher builds and starts SITL, then exposes UART1 through
WebSockets for the online Betaflight Configurator:

```
./src/platform/SIMULATOR/target/SITL/run_betaflight_sitl.sh
```

The launcher requires `ss` from `iproute2` and
[`websockify`](https://github.com/novnc/websockify). If needed, install the
latter with `python3 -m pip install --user websockify`.

In the configurator, enable manual connection mode and connect to
`ws://127.0.0.1:6761`. Press Ctrl-C in the terminal to stop both websockify and
SITL. A compatible Gazebo world or another flight-dynamics simulator must be
started separately.

### note
betaflight	->	gazebo	`udp://127.0.0.1:9002`
gazebo	->	betaflight	`udp://127.0.0.1:9003`

UARTx will bind on `tcp://127.0.0.1:576x` when port been open.

`eeprom.bin`, size 8192 Byte, is for config saving.
size can be changed in `src/platform/SITL/link/SITL.ld` >> `__FLASH_CONFIG_Size`
