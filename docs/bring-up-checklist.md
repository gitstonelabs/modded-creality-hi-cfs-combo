# Bring-up checklist

Work top to bottom. Wiring comes first (see [wiring.md](wiring.md)), then the safety gates, then firmware, then config, then calibration. Do not skip ahead: several later steps assume an earlier one passed.

The one subsystem that must be proven on the bench before you trust a real multi-color print is the **filament cutter**. Dry-run it with no filament loaded (section 6). A failed or half-confirmed cut followed by a retract is how you jam a hotend.

---

## 1. Safety gates

Clear all three before mains power touches the bed circuit and before the CAN bus or the hall sensor go live.

- [ ] **Bed SSR isolation.** With mains AC disconnected from the SSR output, meter-verify that `BED_OUT` (PA1) switches the SSR trigger input, and confirm that no mains AC path reaches the Octopus. Only the SSR's low-voltage trigger pair lands on the board; the AC side stays entirely on the SSR and the silicone pad. Do not connect mains until this checks out.
- [ ] **Cutter hall signal is 3.3V, not 5V.** The hall's VCC may run through a 5V-to-3.3V step-down, but what matters is the SIGNAL line: it must swing 0 to 3.3V. EBB42 PA5 is not 5V-tolerant. Meter the signal line before plugging it into the PROBE header.
- [ ] **Exactly two CAN 120R terminators.** One is the EBB42's CAN-120R jumper, the other is the bridge end (the BTT EBB USB adapter). No more, no fewer. With the bus unpowered, a meter across CAN-H/CAN-L should read about 60R.

## 2. Flash the boards, in this order

### Octopus V1.0 (main MCU, USB)

- [ ] Build Klipper: STM32F446, 32KiB bootloader, 12MHz crystal, USB (PA11/PA12).
- [ ] Flash per the board manual (SD card or DFU; the vendor docs are bundled in `docs/hardware/`).
- [ ] Confirm it enumerates: `ls /dev/serial/by-id/` shows a `usb-Klipper_stm32f446xx_...` entry.

### EBB42 Gen2 (USB first, then CAN)

- [ ] Set the USB/CAN jumper to USB. Flash Katapult, then Klipper, over USB. Build Klipper: STM32G0B1, 8KiB bootloader, 8MHz crystal.
- [ ] Move the jumper to CAN and set the CAN-120R jumper (this is one of the two terminators from gate 3).
- [ ] Bring up `can0` with `scripts/setup-can.sh` (bitrate 1000000, txqueuelen 128). The bitrate must match the firmware CAN speed.
- [ ] Find the UUID: `~/klipper/scripts/canbus_query.py can0` (or `~/katapult/scripts/flashtool.py -q`).

### Eddy Duo (USB first, CAN optional)

- [ ] Build Klipper: RP2040, USBSERIAL / GENERIC_03H, CLKDIV 4. Flash over USB and verify it enumerates.
- [ ] The shipped `eddy.cfg` uses the USB serial path; that is the confirmed configuration. If you want the Eddy on the CAN bus instead, reflash for CAN and switch `[mcu eddy]` from `serial:` to `canbus_uuid:`.

## 3. Fill the placeholders

Every placeholder is marked in-file. After filling them, restart Klipper yourself; the installer deliberately does not.

- [ ] `printer.cfg`: `[mcu] serial` by-id path for the Octopus.
- [ ] `printer.cfg`: X and Y `run_current`, roughly 0.7 x each motor's rated current.
- [ ] `ebb42.cfg`: `[mcu EBB] canbus_uuid` from the query above.
- [ ] `eddy.cfg`: `[mcu eddy] serial` by-id path (or `canbus_uuid` if you moved it to CAN).
- [ ] `cfs.cfg`: `[creality_cfs] serial_port`, the CH340 dongle's by-id path (`usb-1a86_USB_Single_Serial_...`). Find it with `ls /dev/serial/by-id/`.
- [ ] Sanity check: Klipper starts, all three MCUs plus the CFS connect, `CFS_STATUS` reports the box online.

Two values that look like placeholders get filled by calibration, not by editing: `cut_x` is written to `variables.cfg` by `CALIBRATE_CUT_POS` (section 5), and the Eddy frequency map is written by `PROBE_EDDY_CURRENT_CALIBRATE` (section 4).

## 4. Calibration

### Eddy Duo: drive current, frequency map, z_offset

Run these in order; the comments in `eddy.cfg` carry the same sequence.

- [ ] `G28 X Y`, then `G0 X130 Y130 F6000`.
- [ ] Lower the nozzle to about 2mm above the bed (FORCE_MOVE or the paper method).
- [ ] `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy`
- [ ] `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy`
- [ ] `SAVE_CONFIG`
- [ ] Tune `z_offset` manually (paper method, then `Z_OFFSET_APPLY_PROBE`). The frequency map from the previous step is a separate thing; it does not set `z_offset` for you.
- [ ] `BED_MESH_CALIBRATE`, and optionally `TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy_temp_probe`.

### Eddy y_offset

- [ ] Measure the real coil-to-nozzle Y distance on your toolhead. The shipped `y_offset: 21.42` is a Voron-mount placeholder, not your geometry.
- [ ] Update the two values that track it: `home_xy_position` in `[safe_z_home]` and `mesh_min` in `[bed_mesh]` (both in `eddy.cfg`, both annotated).

### Nebula rotation_distance

- [ ] Heat the hotend, mark filament at 120mm, extrude 100mm, measure what actually fed.
- [ ] New value = 4.6 x (100 / actually_extruded). Edit `rotation_distance` in `nebula.cfg`.
- [ ] Do NOT add `gear_ratio: 11.25:1`. The 4.6 already bakes the gearing in; adding the ratio again drops the effective distance to about 0.4mm/rev and massively over-extrudes.

### Heater PID

- [ ] `PID_CALIBRATE HEATER=extruder TARGET=220`
- [ ] `PID_CALIBRATE HEATER=heater_bed TARGET=60`
- [ ] `SAVE_CONFIG`

### Input shaper, X then Y

- [ ] X: `SHAPER_CALIBRATE AXIS=X` using the EBB42's onboard LIS2DW12.
- [ ] Y: the stock bed-mounted accelerometer is gone with the leveling MCU, so temporarily mount the toolhead accelerometer on the bed, then `SHAPER_CALIBRATE AXIS=Y`.
- [ ] Re-tune `max_accel` in `printer.cfg` afterward. The shipped 12000 is the stock Hi value and assumes the stock toolhead mass.

## 5. Cutter setup

- [ ] **Hall polarity.** `QUERY_BUTTON BUTTON=cutter_hall` must read RELEASED at rest and PRESSED with the lever held against the stopper. If it reads backwards, flip `^` / `^!` on `[gcode_button cutter_hall]` in `ebb42.cfg`.
- [ ] **Stallguard.** Install the Driver0 DIAG jumper on the Octopus. Tune `driver_SGTHRS` under `[tmc2209 stepper_x]` on the bench (shipped at 90; higher is more sensitive). This diag is only for the cutter-position ram; normal `G28 X` still homes to the left switch.
- [ ] **Cut position.** Jog X until the cutter just touches the stopper (sensorless approach once SGTHRS is tuned, or jog by hand), then run `CALIBRATE_CUT_POS`. It saves `cut_x` to `variables.cfg`, so it survives restarts.

## 6. Cutter dry-run: do this before any multi-color print

This is the one subsystem to validate end to end with **no filament loaded**. Everything else on this rig fails loudly; a bad cut fails by clogging your hotend two layers into a color change.

- [ ] Run `CUT_FILAMENT` empty and watch the two-check messages: hall RELEASED before the ram, PRESSED at the stopper, RELEASED again after the retreat, then "CUT ok".
- [ ] Confirm the failure path: block or trip the hall deliberately and check that the macro aborts with an error and the tool-change stops BEFORE any retract. That abort-before-retract is the whole point; retracting an uncut or half-cut strand is a clog risk.
- [ ] Walk the recovery once: after a deliberate abort, clear the fault, then RESUME (or CANCEL). Resume-after-jam mid-print is a bench-validation item, not something to discover during a print.
- [ ] Only after all of the above: load filament, run a manual `T0` then `T1` tool change, and watch a full cut-retrude-extrude cycle complete before starting a real multi-color job.
