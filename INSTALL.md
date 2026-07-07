# Install and bring-up guide

This guide takes you from a bare Klipper host to a printing, CFS-fed, modded Creality Hi. Work the sections in order. Wiring detail lives in [docs/wiring.md](docs/wiring.md); the condensed flash-and-calibrate sequence lives in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).

Read section 6 (safety gates) before you power the assembled machine. The bed runs on mains AC through an SSR, and two of the checks can only be done with a meter before power is applied.

## 0. Prerequisites

- A working Klipper host: Raspberry Pi, Jetson, or any Linux SBC already running Klipper + Moonraker with a frontend (Mainsail or Fluidd). The install script expects the standard layout: `~/klipper` (the Klipper source tree) and `~/printer_data/config` (your config directory).
- `git` on the host.
- The hardware from the README: BTT Octopus V1.0 (STM32F446ZET6), BTT EBB42 Gen2 (STM32G0B1), BTT EBB USB adapter (U2C) as the host CAN bridge, BTT Eddy Duo (RP2040), a BTT S2DW V1.0 USB accelerometer (RP2040, for Y-axis input shaping), BIQU Nebula extruder, a CH340/CH341 USB-RS485 dongle, and the Creality CFS.
- This repo cloned onto the host:

```sh
cd ~
git clone https://github.com/gitstonelabs/modded-creality-hi-cfs-combo.git
cd modded-creality-hi-cfs-combo
```

## 1. Build and flash firmware

Three boards, three builds. All from the same Klipper tree on the host:

```sh
cd ~/klipper
make clean
make menuconfig
make
```

| Board | Chip | menuconfig | Interface |
|---|---|---|---|
| Octopus V1.0 | STM32F446 | 32KiB bootloader, 12MHz crystal, USB (PA11/PA12) | USB (main MCU) |
| EBB42 Gen2 | STM32G0B1 | 8KiB bootloader, 8MHz crystal, USB first, then rebuild for CAN | Katapult + Klipper over USB, then CAN |
| Eddy Duo | RP2040 | USBSERIAL, flash chip GENERIC_03H with CLKDIV 4 | USB first, then optionally CAN |
| BTT S2DW | RP2040 | USBSERIAL | USB only (self-contained accelerometer) |

### Octopus V1.0

Select STM32F446, 32KiB bootloader, 12MHz crystal, USB on PA11/PA12. Flash the built `out/klipper.bin` with the stock BTT SD-card method: copy it to a FAT32 SD card as `firmware.bin`, insert, power-cycle the board, and confirm the file was renamed (that means the bootloader took it). Plug the Octopus into the host over USB and note its `/dev/serial/by-id/` path; you will need it in section 4.

### EBB42 Gen2

The EBB42 gets flashed twice: once over USB for bring-up, then switched to CAN for normal operation.

1. Set the board's USB/CAN jumper to USB and connect it to the host over USB.
2. Flash Katapult (the bootloader) and then Klipper (STM32G0B1, 8KiB bootloader, 8MHz crystal) over USB. Verify the board enumerates as a Klipper USB serial device.
3. Rebuild Klipper for CAN: same chip and bootloader settings, but select CAN as the communication interface with a bitrate of 1000000. It must match the `can0` bitrate from section 3.
4. Flash the CAN build through Katapult, move the USB/CAN jumper to CAN, and set the board's CAN 120R jumper. That jumper is one of the exactly two terminators the bus is allowed to have; the U2C bridge end is the other.

### Eddy Duo

Select RP2040, USBSERIAL, and flash chip GENERIC_03H with CLKDIV 4. Hold BOOTSEL while plugging in USB so the board mounts as mass storage, then copy `out/klipper.uf2` onto it. The shipped `config/eddy.cfg` runs the probe over USB, which is the confirmed path; you can move it onto the CAN bus later by reflashing for CAN and swapping the `serial:` line for `canbus_uuid:` in `eddy.cfg`.

### BTT S2DW (Y-axis accelerometer)

Select RP2040 and USBSERIAL. Hold BOOTSEL while plugging in over USB, then copy `out/klipper.uf2` onto the mass-storage volume. The S2DW is a self-contained USB accelerometer, its own RP2040 plus an internal LIS2DW12, so nothing wires to the Octopus. Mount it on the bed, run its USB cable to the host, and note its `/dev/serial/by-id/` path (`usb-Klipper_rp2040_btt_acc...`) for section 4. It is only needed for Y-axis input shaping.

## 2. Run the installer

From the repo root on the host:

```sh
bash scripts/install.sh
```

What it does:

- Checks that `~/klipper` and `~/printer_data/config` exist and that `git` is available.
- Clones https://github.com/gitstonelabs/creality-cfs-klipper pinned to commit `73731e9` (v1.4.0) and copies `src/creality_cfs.py` into `~/klipper/klippy/extras/`. The pin makes the install reproducible; a later tagged release works too if you know why you want it.
- Copies this repo's `config/*.cfg` (printer.cfg, ebb42.cfg, nebula.cfg, eddy.cfg, cfs.cfg, macros.cfg) into `~/printer_data/config/`. An existing same-named file is backed up to `.bak` once; an existing `.bak` is never overwritten. On a re-run, any config you have edited (filled placeholders) is left alone unless you explicitly pass `FORCE=1`, so re-running the installer cannot wipe your serials and UUIDs.

What it deliberately does NOT do:

- It does not install the CFS module's own `cfs_macros.cfg`. This repo's `config/macros.cfg` ships its own `T0` through `T3` tool-change, `CFS_PRINT_START`, and `CFS_PRINT_END`, so that the mechanical cut uses the stock-faithful stallguard + hall `CUT_FILAMENT` macro instead of the module's position-based `CFS_CUT`. The module's raw commands (`CFS_INIT`, `CFS_STATUS`, `CFS_RETRUDE`, `CFS_EXTRUDE`, `CFS_FLUSH`, `CFS_SET_PRELOAD`, `CFS_VERSION`) still come from `creality_cfs.py` and are what `macros.cfg` calls.
- It does not restart Klipper. The copied configs contain placeholders that will fail a config load until you fill them (section 4). Restart only after that.

`printer.cfg` already `[include]`s the other five files, so once the placeholders are filled the whole set loads as one config.

## 3. CAN setup

The EBB42 talks to the host over CAN through the BTT EBB USB adapter (U2C). Bring the interface up with:

```sh
bash scripts/setup-can.sh
```

This brings up `can0` at bitrate 1000000 with `txqueuelen 128`. The bitrate must match what you compiled into the EBB42 CAN firmware in section 1.

Termination: the bus needs exactly two 120R terminators, no more, no fewer. On this build that is the EBB42's CAN 120R jumper plus the terminator at the U2C bridge end. A bus with one or three terminators will produce intermittent CAN errors that look like firmware bugs.

With `can0` up and the EBB42 jumpered to CAN, find its UUID:

```sh
~/klipper/scripts/canbus_query.py can0
```

(or `~/katapult/scripts/flashtool.py -q` if you have Katapult checked out). Note the UUID for the next section.

## 4. Fill the placeholders

Every placeholder is marked in-file. Go through all four:

**`printer.cfg`**: set the Octopus by-id path under `[mcu]`. Find it with:

```sh
ls /dev/serial/by-id/
```

and replace `usb-Klipper_stm32f446xx_XXXXXXXXXXXXXXXX-if00` with yours. Then set `run_current` under `[tmc2209 stepper_x]` and `[tmc2209 stepper_y]` to roughly 0.7 times your motors' rated current (the shipped 0.800 is a starting point, not a spec).

**`ebb42.cfg`**: replace the `canbus_uuid: 0000000000000000` under `[mcu EBB]` with the UUID from section 3.

**`eddy.cfg`**: the shipped `serial:` under `[mcu eddy]` is a placeholder by-id path. Replace it with your own from `ls /dev/serial/by-id/` (or, if you flashed the Eddy for CAN, comment `serial:` and set `canbus_uuid:` instead).

**`cfs.cfg`**: set `serial_port` to your CH340/CH341 dongle's by-id path. It starts with `usb-1a86_` (1a86 is the CH340 vendor id), for example `usb-1a86_USB_Single_Serial_XXXXXXXX-if00`. Leave `baud: 230400` alone; the CFS speaks 230400 and nothing else.

When all four are filled, restart Klipper (`FIRMWARE_RESTART` from the console, or restart the klipper service). This is the first restart of the install; doing it earlier just gets you a config error.

## 5. Calibration

Do these in order. Each one feeds the next. The same list, condensed, is in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).

### 5.1 Eddy probe

Home X and Y, move to bed center, and bring the nozzle to about 2mm above the bed (FORCE_MOVE or the paper method), then:

```
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
SAVE_CONFIG
```

Note that `PROBE_EDDY_CURRENT_CALIBRATE` writes the probe's frequency map; the `z_offset` in `eddy.cfg` is separate and gets tuned manually (paper method, then `Z_OFFSET_APPLY_PROBE`).

### 5.2 Eddy y_offset

The shipped `y_offset: 21.42` is a placeholder from a Voron mount. Measure the actual nozzle-to-coil Y distance on your toolhead and set it. If your measured value differs, also update the two places that derive from it: `home_xy_position` under `[safe_z_home]` and `mesh_min` under `[bed_mesh]`, both in `eddy.cfg`.

### 5.3 Nebula rotation_distance

The shipped `rotation_distance: 4.6` is the Nebula's effective value with the 11.25:1 gearing already baked in. Do not add a `gear_ratio` line; that double-counts the reduction and produces massive over-extrusion. Calibrate it: heat the hotend, mark the filament 120mm above the extruder entry, extrude 100mm, measure how much actually fed, then:

```
rotation_distance_new = 4.6 * (100 / measured_mm)
```

Set the result in `nebula.cfg`.

### 5.4 Heater PID

```
PID_CALIBRATE HEATER=extruder TARGET=220
PID_CALIBRATE HEATER=heater_bed TARGET=60
SAVE_CONFIG
```

The shipped PID values are placeholders for a different heater sample; run both.

### 5.5 Input shaper

X is straightforward: the EBB42's onboard LIS2DW12 is already configured as the resonance accelerometer, so run `SHAPER_CALIBRATE AXIS=X`.

Y uses the bed-mounted BTT S2DW (`[lis2dw bed]`, configured as `accel_chip_y`). Mount the module on the bed, plug it into the host over USB, and run `SHAPER_CALIBRATE AXIS=Y`. Before trusting the result, run `TEST_RESONANCES AXIS=Y` and confirm the `axes_map` (shipped `-y, x, -z`) matches the module's mounted orientation. After shaper calibration, revisit `max_accel` in `printer.cfg`: the shipped 12000 is the stock Hi value and the new toolhead mass will want a different number.

### 5.6 Cutter

The cutter is the one subsystem you must bench-validate before trusting a multi-color print. Its failure mode is not cosmetic: retracting an uncut or half-cut strand into the CFS path risks a clog, which is exactly why the tool-change macro gates the retract on a confirmed cut.

1. Check hall polarity: `QUERY_BUTTON BUTTON=cutter_hall` must read RELEASED at rest and PRESSED with the cutter held against the stopper. If it reads backwards, flip the `^` / `^!` on `[gcode_button cutter_hall]` in `ebb42.cfg`.
2. Tune `driver_SGTHRS` under `[tmc2209 stepper_x]` in `printer.cfg` (higher is more sensitive; the Driver0 DIAG jumper must be installed for the stallguard signal to reach `PG6`).
3. Jog X until the cutter lever just touches the stopper, then run `CALIBRATE_CUT_POS`. It saves the position as `cut_x` via `save_variables`, so it persists across restarts.
4. Dry-run `CUT_FILAMENT` with no filament loaded and watch the two-check messages: the hall must trigger at the stopper and clear again after the retreat. Any failed check aborts before the retract and pauses the print.

## 6. Safety gates: verify before applying power

These are not optional and two of them require a meter with the machine unpowered. Do them before the first power-on of the assembled machine, and re-check the bed gate before the first heat cycle.

**Bed SSR isolation.** The bed is the stock AC silicone pad switched by an SSR; the Octopus only drives the SSR trigger from `BED_OUT` (PA1). Meter-verify two things: that PA1 actually switches your SSR's trigger input, and that mains AC never reaches the Octopus under any wiring fault you can probe for. A miswired SSR puts mains on a 3.3V logic board.

**Cutter hall signal level.** The hall sensor's VCC goes through a 5V-to-3.3V step-down, but the check that matters is the SIGNAL line: it must swing 0 to 3.3V. `PA5` on the EBB42 is not 5V-tolerant, and a 5V signal will damage the pin. Meter the signal line before connecting it.

**CAN termination.** Exactly two 120R terminators on the bus (measure roughly 60R across CAN-H and CAN-L with everything connected and unpowered). See section 3 for which two.

The wiring these gates protect is documented pin by pin in [docs/wiring.md](docs/wiring.md).

## What next

Run through [docs/bring-up-checklist.md](docs/bring-up-checklist.md) end to end, then bench-validate the cutter (section 5.6) before your first multi-color print. The CFS itself needs no calibration beyond a working `CFS_INIT` at startup; `cfs.cfg` sets `auto_init: True` so it runs on every Klipper start.
