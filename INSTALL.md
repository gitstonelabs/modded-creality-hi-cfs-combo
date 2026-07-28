# Install and bring-up guide

This guide takes you from a bare Klipper host to a printing, CFS-fed, modded Creality Hi. Work the sections in order. Wiring detail lives in [docs/wiring.md](docs/wiring.md); the condensed flash-and-calibrate sequence lives in [docs/bring-up-checklist.md](docs/bring-up-checklist.md); the AC bed driver stage has its own definitive guide in [hi-ac-bed-to-octopus-wiring.md](hi-ac-bed-to-octopus-wiring.md).

Read section 6 (safety gates) before you power the assembled machine. The bed runs on mains AC through an SSR, and two of the checks can only be done with a meter before power is applied.

## 0. Prerequisites

- A working Klipper host: Raspberry Pi, Jetson, or any Linux SBC already running Klipper + Moonraker with a frontend. The install script expects the standard layout: `~/klipper` (the Klipper source tree) and `~/printer_data/config` (your config directory). The shipped `printer.cfg` starts with `[include mainsail.cfg]`, which the Mainsail install provides; on a Fluidd host swap that include for fluidd-config's `client.cfg`.
- `git` on the host.
- The hardware from the README: BTT Octopus (STM32F446ZET6) as main MCU and USB-to-CAN bridge, BTT EBB42 Gen2 (STM32G0B1), BTT Eddy Duo (RP2040), a BTT S2DW V1.0 USB accelerometer (RP2040, for Y-axis input shaping), BIQU Nebula extruder, a CH340/CH341 USB-RS485 dongle, and the Creality CFS.
- This repo cloned onto the host:

```sh
cd ~
git clone https://github.com/gitstonelabs/modded-creality-hi-cfs-combo.git
cd modded-creality-hi-cfs-combo
```

## 1. Build and flash firmware

Four boards, four builds. All from the same Klipper tree on the host:

```sh
cd ~/klipper
make clean
make menuconfig
make
```

| Board | Chip | menuconfig | Interface |
|---|---|---|---|
| Octopus | STM32F446 | 32KiB bootloader, 12MHz crystal, USB (PA11/PA12), USB to CAN bus bridge (USBCAN) | USB (main MCU + CAN bridge) |
| EBB42 Gen2 | STM32G0B1 | 8KiB bootloader, 8MHz crystal, USB first, then rebuild for CAN | Katapult + Klipper over USB, then CAN |
| Eddy Duo | RP2040 | USBSERIAL, flash chip GENERIC_03H with CLKDIV 4 | USB to flash, then CAN |
| BTT S2DW | RP2040 | USBSERIAL | USB only (self-contained accelerometer) |

### Octopus

Select STM32F446, 32KiB bootloader, 12MHz crystal, USB on PA11/PA12, and enable "USB to CAN bus bridge (USBCAN)". Flash the built `out/klipper.bin` with the stock BTT SD-card method: copy it to a FAT32 SD card as `firmware.bin`, insert, power-cycle the board, and confirm the file was renamed (that means the bootloader took it). Plugged into the host over USB, the bridge build does not appear under `/dev/serial/by-id/`; it enumerates as a gs_usb CAN adapter, and after section 3 brings up `can0`, `canbus_query.py` shows its bridge UUID. That UUID goes in `[mcu]` in section 4.

### EBB42 Gen2

The EBB42 gets flashed twice: once over USB for bring-up, then switched to CAN for normal operation.

1. Set the board's USB/CAN jumper to USB and connect it to the host over USB.
2. Flash Katapult (the bootloader) and then Klipper (STM32G0B1, 8KiB bootloader, 8MHz crystal) over USB. Verify the board enumerates as a Klipper USB serial device.
3. Rebuild Klipper for CAN: same chip and bootloader settings, but select CAN as the communication interface with a bitrate of 1000000. It must match the `can0` bitrate from section 3.
4. Flash the CAN build through Katapult, move the USB/CAN jumper to CAN, and set the board's CAN 120R jumper. That jumper is one of the exactly two terminators the bus is allowed to have; the bridge (Octopus) end of the bus carries the other.

### Eddy Duo

Select RP2040, USBSERIAL, and flash chip GENERIC_03H with CLKDIV 4. Hold BOOTSEL while plugging in USB so the board mounts as mass storage, then copy `out/klipper.uf2` onto it. Verify it enumerates, then rebuild for CAN (bitrate 1000000) and put it on the bus: the shipped `config/eddy.cfg` runs the probe via `canbus_uuid`, and the commented `serial:` line is the USB fallback for flashing and bench tests.

### BTT S2DW (Y-axis accelerometer)

Select RP2040 and USBSERIAL. Hold BOOTSEL while plugging in over USB, then copy `out/klipper.uf2` onto the mass-storage volume. The S2DW is a self-contained USB accelerometer, its own RP2040 plus an internal LIS2DW12, so nothing wires to the Octopus. Mount it on the bed, run its USB cable to the host, and note its `/dev/serial/by-id/` path (a `usb-Klipper_rp2040_...` entry; this build's unit reports a bare serial) for section 4. It is only needed for Y-axis input shaping.

## 2. Run the installer

From the repo root on the host:

```sh
bash scripts/install.sh
```

What it does:

- Checks that `~/klipper` and `~/printer_data/config` exist and that `git` is available.
- Clones https://github.com/gitstonelabs/creality-cfs-klipper pinned to commit `73731e9` (v1.4.0) and copies `src/creality_cfs.py` into `~/klipper/klippy/extras/`. The pin makes the install reproducible; a later tagged release works too if you know why you want it.
- Copies this repo's `config/*.cfg` (printer.cfg, ebb42.cfg, nebula.cfg, eddy.cfg, cfs.cfg, macros.cfg, client_macros.cfg) into `~/printer_data/config/`. An existing same-named file is backed up to `.bak` once; an existing `.bak` is never overwritten. On a re-run, any config you have edited (filled placeholders) is left alone unless you explicitly pass `FORCE=1`, so re-running the installer cannot wipe your serials and UUIDs. The repo's `config/moonraker.conf` is a reference file and is deliberately NOT copied (it is not a `.cfg`); merge what you need into your own moonraker.conf.

What it deliberately does NOT do:

- It does not install the CFS module's own `cfs_macros.cfg`. This repo's `config/macros.cfg` ships its own `T0` through `T3` tool-change, `CFS_PRINT_START`, and `CFS_PRINT_END`, so that the mechanical cut uses the stock-faithful stallguard + hall `CUT_FILAMENT` macro instead of the module's position-based `CFS_CUT`. The module's raw commands (`CFS_INIT`, `CFS_STATUS`, `CFS_RETRUDE`, `CFS_EXTRUDE`, `CFS_FLUSH`, `CFS_SET_PRELOAD`, `CFS_VERSION`) still come from `creality_cfs.py` and are what `macros.cfg` calls.
- It does not restart Klipper. The copied configs contain placeholders that will fail a config load until you fill them (section 4). Restart only after that.

`printer.cfg` already `[include]`s the other config files (plus `mainsail.cfg` from the frontend install), so once the placeholders are filled the whole set loads as one config. The `cfs.cfg` include ships commented out; enable it once the CFS dongle is attached and its by-id path is set.

## 3. CAN setup

The CAN bridge is the Octopus itself, running the USBCAN bridge firmware from section 1: plugged in over USB it enumerates as a gs_usb CAN adapter and the kernel exposes `can0`. The EBB42 and the Eddy Duo hang off that bus. Bring the interface up with:

```sh
bash scripts/setup-can.sh
```

This brings up `can0` at bitrate 1000000 with `txqueuelen 128`. The bitrate must match what you compiled into the EBB42 and Eddy CAN firmware in section 1.

Termination: the bus needs exactly two 120R terminators, no more, no fewer. On this build that is the EBB42's CAN 120R jumper plus the terminator at the bridge (Octopus) end. A bus with one or three terminators will produce intermittent CAN errors that look like firmware bugs.

With `can0` up and the EBB42 and Eddy jumpered/flashed for CAN, list the UUIDs:

```sh
~/klipper/scripts/canbus_query.py can0
```

(or `~/katapult/scripts/flashtool.py -q` if you have Katapult checked out). With all three boards up you get three UUIDs: the Octopus bridge node, the EBB42, and the Eddy. Note all three for the next section.

## 4. Fill the placeholders

Every placeholder is marked in-file. Go through all four:

**`printer.cfg`**: replace the `canbus_uuid: 0000000000000000` under `[mcu]` with the Octopus bridge UUID from section 3. Set the S2DW's by-id path under `[mcu btt_s2dw]` (find it with `ls /dev/serial/by-id/`, a `usb-Klipper_rp2040_...` entry). Then set `run_current` under `[tmc2209 stepper_x]` and `[tmc2209 stepper_y]` to roughly 0.7 times your motors' rated current (the shipped 0.800/0.850 are starting points, not a spec).

**`ebb42.cfg`**: replace the `canbus_uuid: 0000000000000000` under `[mcu EBB]` with the EBB42 UUID from section 3.

**`eddy.cfg`**: replace the `canbus_uuid: 0000000000000000` under `[mcu eddy]` with the Eddy UUID from section 3 (or, for USB bench use, comment `canbus_uuid:` and fill the `serial:` fallback line instead).

**`cfs.cfg`**: set `serial_port` to your CH340/CH341 dongle's by-id path. It starts with `usb-1a86_` (1a86 is the CH340 vendor id), for example `usb-1a86_USB_Single_Serial_XXXXXXXX-if00`. Leave `baud: 230400` alone; the CFS speaks 230400 and nothing else. The `[include cfs.cfg]` line in `printer.cfg` ships commented out; enable it when the dongle is attached.

When all four are filled, restart Klipper (`FIRMWARE_RESTART` from the console, or restart the klipper service). This is the first restart of the install; doing it earlier just gets you a config error.

## 5. Calibration

Do these in order. Each one feeds the next. The same list, condensed, is in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).

### 5.1 Eddy probe

Home, move to bed center, and bring the nozzle to about 2mm above the bed. Z homes UP on the dual Z-max switches, so absolute Z works before the probe is calibrated; paper-verify `position_endstop` first (bring-up checklist section 4). On a fresh install a full `G28` homes fine and then errors at the trailing auto-Z0 probe until the Eddy map exists; that is expected. Then:

```
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
SAVE_CONFIG
```

Note that `PROBE_EDDY_CURRENT_CALIBRATE` writes the probe's frequency map; the `z_offset` in `eddy.cfg` is separate and gets tuned manually (paper method, then `Z_OFFSET_APPLY_PROBE`).

### 5.2 Eddy coil offsets

The shipped `x_offset: 4.45` and `y_offset: -22.77` are measured on this build's toolhead and verified against hardware; if your mount matches, keep them. If it differs, re-measure both, then update `zero_reference_position` under `[bed_mesh]` in `eddy.cfg`: it is the auto print-Z0 probe spot in probe coordinates (nozzle 130,130 plus the coil offsets, shipped `134.45, 107.23`), and the mesh normalizes there so auto-Z0 and mesh compensation compose. Re-check `mesh_min`/`mesh_max` keep the coil over the bed.

### 5.3 Nebula rotation_distance

The shipped `rotation_distance: 4.6` is the Nebula's effective value with the 11.25:1 gearing already baked in. Do not add a `gear_ratio` line; that double-counts the reduction and produces massive over-extrusion. Calibrate it: heat the hotend, mark the filament 120mm above the extruder entry, extrude 100mm, measure how much actually fed, then:

```
rotation_distance_new = 4.6 * (100 / measured_mm)
```

Set the result in `nebula.cfg`.

### 5.4 Heater PID

```
PID_CALIBRATE HEATER=extruder TARGET=220
SAVE_CONFIG
```

The shipped extruder PID values are placeholders for a different heater sample. The bed PID is part of bed commissioning (bring-up checklist section 5), which on this build is still outstanding: the driver stage switches the bed correctly, but the PID tune, the `max_power` restore, and the fail-safe-on-reset confirmation have not been done. The bed ships duty-capped at `max_power: 0.4` and every bed-heat macro refuses until `SAVE_VARIABLE VARIABLE=bed_commissioned VALUE=1` after the supervised first heat.

### 5.5 Input shaper

X is straightforward: the EBB42's onboard LIS2DW12 is already configured as the resonance accelerometer, so run `SHAPER_CALIBRATE AXIS=X`.

Y uses the bed-mounted BTT S2DW (`[lis2dw bed]`, configured as `accel_chip_y`). Mount the module on the bed, plug it into the host over USB, and run `SHAPER_CALIBRATE AXIS=Y`. Before trusting the result, check orientation: `ACCELEROMETER_QUERY CHIP=bed` at rest should read about +9800 on Z only, and `TEST_RESONANCES AXIS=Y` should show a clean dominant peak. The shipped `axes_map: y, -x, z` matches this build's mount (board +Y along printer +X). After shaper calibration, revisit `max_accel` in `printer.cfg`: the shipped 3000 is a deliberate bring-up cap; raise it based on the shaper results.

### 5.6 Cutter

The cutter is the one subsystem you must bench-validate before trusting a multi-color print. Its failure mode is not cosmetic: retracting an uncut or half-cut strand into the CFS path risks a clog, which is exactly why the tool-change macro gates the retract on a confirmed cut.

1. Check hall polarity: `QUERY_BUTTON BUTTON=cutter_hall` must read RELEASED at rest and PRESSED with the cutter held against the stopper. If it reads backwards, flip the `^` / `^!` on `[gcode_button cutter_hall]` in `ebb42.cfg`.
2. Tune `driver_SGTHRS` under `[tmc2209 stepper_x]` in `printer.cfg` (higher is more sensitive; the Driver0 DIAG jumper must be installed for the stallguard signal to reach `PG6`).
3. Jog X until the cutter lever just touches the stopper, then run `CALIBRATE_CUT_POS`. It saves the position as `cut_x` via `save_variables`, so it persists across restarts.
4. Dry-run `CUT_FILAMENT` with no filament loaded and watch the two-check messages: the hall must trigger at the stopper and clear again after the retreat. Any failed check aborts before the retract and pauses the print.

## 6. Safety gates: verify before applying power

These are not optional and two of them require a meter with the machine unpowered. Do them before the first power-on of the assembled machine, and re-check the bed gate before the first heat cycle.

**Bed SSR board isolation and control model.** The bed is the stock AC silicone pad switched by the stock opto-isolated SSR board (EL3063 opto + T1635 triac). Its control input (4-pin connector pin 2) is the opto LED anode: ACTIVE-HIGH, and it needs roughly 15mA **sourced** into it. No Octopus output can source that, so the Octopus drives it through an AO3401 P-channel high-side stage with `heater_pin: PA1` sinking the PMOS gate, non-inverted. The definitive design, with the schematic, the resistor values, and the evidence behind each of them, is [hi-ac-bed-to-octopus-wiring.md](hi-ac-bed-to-octopus-wiring.md). Build it from that document, not from this paragraph. Connection summary: pin 4 to a stiff Octopus 5V that also feeds the PMOS source, pin 1 to Octopus GND, pin 2 to the PMOS drain through R2 = 270R, pin 3 to GND on its own dedicated wire.

With mains disconnected, meter the triac (MT1-MT2 not shorted) and the AC-to-control isolation (open), and confirm pin 2 sits at 0V with Klipper not driving it. Then prove the fail-safe before mains: command heat on with the Octopus powered, confirm about 15mA into pin 2, cut MCU power, and confirm pin 2 drops to 0V. Mains AC never reaches the Octopus under any wiring fault you can probe for; a miswire puts mains on a 3.3V logic board. Never put the control line on a thermistor input, whose 4.7k pullup would arm the SSR at boot. The bed then stays macro-locked until commissioning (bring-up checklist section 5) sets `bed_commissioned=1`.

**Independent thermal cutoff on the AC bed.** A T1635 triac fails **shorted** far more often than open. If it fails closed, Klipper cannot turn the bed off no matter what `heater_pin` does, and `verify_heater` does **not** catch a shorted triac. Fit a bed thermal fuse or klixon in series with the AC bed load, and/or a mains contactor Klipper can also drop. This is the only protection that covers that failure, and it is not optional on an AC bed.

**If you are building from a repo revision older than 2026-07-15:** that revision drove the SSR control input directly from Octopus PG13 and told you never to use `BED_OUT`/PA1 or a FAN/HE output. That instruction was right for direct drive, where the pin itself has to source the opto LED current and a low-side FET can only sink. It does not apply to the PMOS design, where PA1 only sinks a gate. Identify which circuit is physically on your machine before choosing a pin. No PMOS stage means the old design, so use PG13.

**Cutter hall signal level.** The hall sensor's VCC goes through a 5V-to-3.3V step-down, but the check that matters is the SIGNAL line: it must swing 0 to 3.3V. `PA5` on the EBB42 is not 5V-tolerant, and a 5V signal will damage the pin. Meter the signal line before connecting it.

**CAN termination.** Exactly two 120R terminators on the bus (measure roughly 60R across CAN-H and CAN-L with everything connected and unpowered). See section 3 for which two.

The wiring these gates protect is documented pin by pin in [docs/wiring.md](docs/wiring.md).

## What next

Run through [docs/bring-up-checklist.md](docs/bring-up-checklist.md) end to end, then bench-validate the cutter (section 5.6) before your first multi-color print. The CFS itself needs no calibration beyond a working `CFS_INIT` at startup; `cfs.cfg` sets `auto_init: True` so it runs on every Klipper start.
