# Bring-up checklist

Work top to bottom. Wiring comes first (see [wiring.md](wiring.md)), then the safety gates, then firmware, then config, then calibration. Do not skip ahead: several later steps assume an earlier one passed.

The one subsystem that must be proven on the bench before you trust a real multi-color print is the **filament cutter**. Dry-run it with no filament loaded (section 7). A failed or half-confirmed cut followed by a retract is how you jam a hotend. The AC-mains bed has its own gate: no bed-heat macro runs until commissioning (section 5) sets `bed_commissioned=1`.

---

## 1. Safety gates

Clear every one of these before mains power touches the bed circuit and before the CAN bus or the hall sensor go live. The first four are all bed gates.

- [ ] **Bed SSR board: isolation and control model.** The bed is switched by the stock opto-isolated SSR board (EL3063 opto + T1635 triac). Its control input on the 4-pin connector is pin 2, it is the opto LED anode, it is ACTIVE-HIGH, and it needs about 15mA **sourced** into it. The Octopus drives it through an AO3401 P-channel high-side stage; the schematic and the resistor values are in [hi-ac-bed-to-octopus-wiring.md](../hi-ac-bed-to-octopus-wiring.md), which is the definitive guide. Summary: pin 4 to a stiff Octopus 5V (also the PMOS source), pin 1 to Octopus GND, pin 2 to the PMOS drain through R2 = 270R, pin 3 (LED cathode) to GND on its own dedicated wire, and `heater_pin: PA1` NON-inverted (PA1 sinks the PMOS gate). With mains disconnected, meter the triac (MT1-MT2 not shorted) and the AC-to-control isolation (open). Confirm pin 2 sits at 0V with the Octopus powered but Klipper not driving it. Never put pin 2 on a thermistor input; its 4.7k pullup arms the SSR at boot. Do not connect mains until all of this checks out.
- [ ] **Fail-safe on reset, proven before mains.** With the Octopus powered and no mains on the bed, command heat on and confirm about 15mA into pin 2 (roughly 4V across R2). Then cut MCU power and confirm pin 2 falls to 0V and the LED goes dark. That test is what proves the stage fails safe; do it before the AC side is ever live.
- [ ] **Independent thermal cutoff fitted.** A T1635 triac fails **shorted** far more often than open. If it fails closed, no `heater_pin` value can turn the roughly 1000W bed off, and `verify_heater` does not catch a shorted triac. Fit a bed thermal fuse or klixon in series with the AC bed load, and/or a mains contactor Klipper can drop. Non-negotiable for an AC bed.
- [ ] **Rebuilding from a pre-2026-07-15 revision?** Older revisions of this repo drove the SSR control input straight from Octopus PG13 and warned never to use `BED_OUT`/PA1/FAN/HE outputs. That warning was correct **for direct drive**: those pins are low-side FETs, they can only sink, and direct drive needs a pin that can source the LED current. It does not apply once the PMOS high-side stage is fitted, because PA1 then only sinks a gate. Check which circuit is actually on your bench. No PMOS stage means the old design, so use PG13, not PA1.
- [ ] **Cutter hall signal is 3.3V, not 5V.** The hall's VCC may run through a 5V-to-3.3V step-down, but what matters is the SIGNAL line: it must swing 0 to 3.3V. EBB42 PA5 is not 5V-tolerant. Meter the signal line before plugging it into the PROBE header.
- [ ] **Exactly two CAN 120R terminators.** One is the EBB42's CAN-120R jumper, the other sits at the bridge (Octopus) end of the bus. No more, no fewer. With the bus unpowered, a meter across CAN-H/CAN-L should read about 60R.

## 2. Flash the boards, in this order

### Octopus (main MCU + USB-to-CAN bridge, USB)

- [ ] Build Klipper: STM32F446, 32KiB bootloader, 12MHz crystal, USB (PA11/PA12), with "USB to CAN bus bridge (USBCAN)" enabled.
- [ ] Flash per the board manual (SD card or DFU; the vendor docs are bundled in `docs/hardware/`).
- [ ] Confirm it enumerates as a gs_usb CAN adapter (`dmesg | tail` after plugging in) and bring up `can0` with `scripts/setup-can.sh`.
- [ ] Find its bridge UUID: `~/klipper/scripts/canbus_query.py can0`. That UUID goes in `printer.cfg` `[mcu]`.

### EBB42 Gen2 (USB first, then CAN)

- [ ] Set the USB/CAN jumper to USB. Flash Katapult, then Klipper, over USB. Build Klipper: STM32G0B1, 8KiB bootloader, 8MHz crystal.
- [ ] Move the jumper to CAN and set the CAN-120R jumper (this is one of the two terminators from gate 3).
- [ ] With `can0` up (previous section), find the UUID: `~/klipper/scripts/canbus_query.py can0` (or `~/katapult/scripts/flashtool.py -q`).

### Eddy Duo (USB to flash, CAN to run)

- [ ] Build Klipper: RP2040, USBSERIAL / GENERIC_03H, CLKDIV 4. Flash over USB and verify it enumerates.
- [ ] Reflash for CAN (bitrate 1000000) and put it on the bus. The shipped `eddy.cfg` runs it via `canbus_uuid`; the commented `serial:` line is the USB fallback for flashing and bench tests.
- [ ] Find its UUID with the same `canbus_query.py can0` run; with all three boards up the query lists three UUIDs.

### BTT S2DW (Y-axis accelerometer, USB)

- [ ] Build Klipper: RP2040, USBSERIAL. Hold BOOTSEL, plug in over USB, copy `out/klipper.uf2` onto the mass-storage volume.
- [ ] It is self-contained (its own RP2040 + LIS2DW12); nothing wires to the Octopus. Mount the module ON THE BED and run its USB cable to the host.
- [ ] Confirm it enumerates: `ls /dev/serial/by-id/` shows a new `usb-Klipper_rp2040_...` entry for it (this build's unit reports a bare serial, no `btt_acc` marker).

## 3. Fill the placeholders

Every placeholder is marked in-file. After filling them, restart Klipper yourself; the installer deliberately does not.

- [ ] `printer.cfg`: `[mcu] canbus_uuid`, the Octopus bridge UUID from `canbus_query.py can0`.
- [ ] `printer.cfg`: X and Y `run_current`, roughly 0.7 x each motor's rated current.
- [ ] `ebb42.cfg`: `[mcu EBB] canbus_uuid` from the query above.
- [ ] `eddy.cfg`: `[mcu eddy] canbus_uuid` from the query above (or the commented `serial:` fallback if you are running it over USB on the bench).
- [ ] `cfs.cfg`: `[creality_cfs] serial_port`, the CH340 dongle's by-id path (`usb-1a86_USB_Single_Serial_...`). Find it with `ls /dev/serial/by-id/`.
- [ ] `printer.cfg`: `[mcu btt_s2dw] serial` by-id for the S2DW accelerometer (`usb-Klipper_rp2040_...`).
- [ ] Sanity check: Klipper starts, all four MCUs (Octopus, EBB, Eddy, S2DW) plus the CFS connect, `CFS_STATUS` reports the box online.

Three values that look like placeholders get filled by calibration, not by editing: `cut_x` is written to `variables.cfg` by `CALIBRATE_CUT_POS` (section 6), the Eddy frequency map is written by `PROBE_EDDY_CURRENT_CALIBRATE` (section 4), and `bed_commissioned` is set at the end of bed commissioning (section 5).

## 4. Calibration

### Z switches and position_endstop

Z homes UP: each Z motor drives into its own Z-max optical switch, which squares the gantry on every `G28 Z`. The shipped `position_endstop: 307.2` under `[stepper_z]` is this build's paper-measured switch-to-bed distance.

- [ ] `QUERY_ENDSTOPS` with each Z switch held: both must report triggered.
- [ ] After the first `G28 X Y` and `G28 Z`, paper-test at bed center and adjust `position_endstop` until Z0 is a real paper grip.

On a fresh install, any `G28` that includes Z ends by probing for the auto print-Z0; with an uncalibrated Eddy that final probe errors AFTER homing completed. The axes stay homed; calibrate the probe (next block) and the error goes away.

### Eddy Duo: drive current, frequency map, z_offset

Run these in order; the comments in `eddy.cfg` carry the same sequence.

- [ ] Home, then `G0 X130 Y130 F6000` and bring the nozzle to about 2mm above the bed (`G1 Z2` once `position_endstop` is verified, or the paper method).
- [ ] `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy`
- [ ] `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy`
- [ ] `SAVE_CONFIG`
- [ ] Tune `z_offset` manually (paper method, then `Z_OFFSET_APPLY_PROBE`, which shifts the saved frequency map). The map from the previous step does not set `z_offset` for you.
- [ ] `BED_MESH_CALIBRATE METHOD=rapid_scan` (the 9x9 grid takes about 12 seconds), and optionally `TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy_temp_probe`.
- [ ] Sanity-check the auto print-Z0: run a full `G28`; `SET_PRINT_Z0` must apply a sub-mm `Z_ADJUST`. It aborts the home if the probe returns more than 1mm (uncalibrated `z_offset` guard). Paper-test at the applied Z0 before the first print.

### Eddy coil offsets

The shipped offsets are measured on this build's toolhead and verified against hardware: `x_offset: 4.45` (coil right of the nozzle), `y_offset: -22.77` (coil in front of the nozzle). If your mount matches this build, keep them.

- [ ] If your mount differs, re-measure both and set them in `eddy.cfg`.
- [ ] Then update `zero_reference_position` in `[bed_mesh]`: it is the `SET_PRINT_Z0` probe spot in probe coordinates, nozzle 130,130 plus the coil offsets (shipped `134.45, 107.23`). If it drifts from the auto-Z0 spot, mesh and auto-Z0 stop composing and the absolute bed height gets double-counted.
- [ ] Re-check `mesh_min`/`mesh_max` still keep the coil over the bed across the whole grid.

### Nebula rotation_distance

- [ ] Heat the hotend, mark filament at 120mm, extrude 100mm, measure what actually fed.
- [ ] New value = 4.6 x (100 / actually_extruded). Edit `rotation_distance` in `nebula.cfg`.
- [ ] Do NOT add `gear_ratio: 11.25:1`. The 4.6 already bakes the gearing in; adding the ratio again drops the effective distance to about 0.4mm/rev and massively over-extrudes.

### Heater PID (extruder now, bed during commissioning)

- [ ] `PID_CALIBRATE HEATER=extruder TARGET=220`
- [ ] `SAVE_CONFIG`

Bed PID runs inside bed commissioning (section 5); its supervised low-duty heat comes first.

### Input shaper, X then Y

- [ ] X: `SHAPER_CALIBRATE AXIS=X` using the EBB42's onboard LIS2DW12.
- [ ] Y: `SHAPER_CALIBRATE AXIS=Y` using the bed-mounted BTT S2DW (`[lis2dw bed]`, wired as `accel_chip_y`). First confirm its orientation: `ACCELEROMETER_QUERY CHIP=bed` at rest must read about +9800 on Z only, and `TEST_RESONANCES AXIS=Y` must show a clean dominant peak. The shipped `axes_map: y, -x, z` matches this build's mount (board +Y along printer +X); if AXIS=Y comes back flat and AXIS=X lights up, X and Y are swapped in your `axes_map`.
- [ ] Re-tune `max_accel` in `printer.cfg` afterward. The shipped 3000 is a deliberate bring-up cap for the modded toolhead mass; raise it based on the shaper results.

## 5. Bed commissioning (AC mains, supervised)

**Status on this build: the driver stage is built and working, commissioning is NOT done.** The AO3401 high-side stage triggers the bed on `M140 S60` and drops it on `S0`, confirmed 2026-07-15. Everything below this line is still outstanding, so the bed is not finished and the macro gate is still closed.

The config ships with the bed locked three ways: every bed-heat macro path (`START_PRINT`, `_PREHEAT` and the `PREHEAT_*` macros, `HEAT_SOAK`) refuses until `bed_commissioned` is 1 in `variables.cfg`; `[heater_bed]` is duty-capped at `max_power: 0.4`; and `[verify_heater heater_bed]` carries deliberately generous commissioning values (a slow silicone pad at 40% duty would false-trip the extruder-style 30s check). Direct commands like `M140` and `PID_CALIBRATE` bypass the macro gate; that is exactly how you commission, supervised, at the machine.

- [ ] The bed safety gates in section 1 all passed, including the fail-safe-on-reset test and the thermal cutoff, then connect mains.
- [ ] Supervised low-duty first heat: `M140 S60` and stay at the machine. Confirm the pad climbs, holds target, and drops the load when you set `M140 S0`.
- [ ] Raise `max_power` toward 1.0 in `printer.cfg` and restart Klipper.
- [ ] `PID_CALIBRATE HEATER=heater_bed TARGET=60`, then `SAVE_CONFIG`.
- [ ] Re-tighten `[verify_heater heater_bed]` after PID; the shipped values are commissioning slack, not run values.
- [ ] Re-confirm fail-safe with the AC side live and supervised: mid-heat, cut MCU power and watch the bed stop.
- [ ] Only after all of the above: `SAVE_VARIABLE VARIABLE=bed_commissioned VALUE=1`. This unlocks the bed-heat macro paths.

## 6. Cutter setup

- [ ] **Hall polarity.** `QUERY_BUTTON BUTTON=cutter_hall` must read RELEASED at rest and PRESSED with the lever held against the stopper. If it reads backwards, flip `^` / `^!` on `[gcode_button cutter_hall]` in `ebb42.cfg`.
- [ ] **Stallguard.** Install the Driver0 DIAG jumper on the Octopus. Tune `driver_SGTHRS` under `[tmc2209 stepper_x]` on the bench (shipped at 90; higher is more sensitive). This diag is only for the cutter-position ram; normal `G28 X` still homes to the left switch.
- [ ] **Cut position.** Jog X until the cutter just touches the stopper (sensorless approach once SGTHRS is tuned, or jog by hand), then run `CALIBRATE_CUT_POS`. It saves `cut_x` to `variables.cfg`, so it survives restarts.

## 7. Cutter dry-run: do this before any multi-color print

This is the one subsystem to validate end to end with **no filament loaded**. Everything else on this rig fails loudly; a bad cut fails by clogging your hotend two layers into a color change.

- [ ] Run `CUT_FILAMENT` empty and watch the two-check messages: hall RELEASED before the ram, PRESSED at the stopper, RELEASED again after the retreat, then "CUT ok".
- [ ] Confirm the failure path: block or trip the hall deliberately and check that the macro aborts with an error and the tool-change stops BEFORE any retract. That abort-before-retract is the whole point; retracting an uncut or half-cut strand is a clog risk.
- [ ] Walk the recovery once: after a deliberate abort, clear the fault, then RESUME (or CANCEL). Resume-after-jam mid-print is a bench-validation item, not something to discover during a print.
- [ ] Only after all of the above: load filament, run a manual `T0` then `T1` tool change, and watch a full cut-retrude-extrude cycle complete before starting a real multi-color job.
