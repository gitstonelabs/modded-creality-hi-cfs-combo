# Modded Creality Hi + CFS Combo

A Creality Hi with its stock mainboard removed, running mainline Klipper on a BTT Octopus (STM32F446) as the main MCU and USB-to-CAN bridge, a BTT EBB42 Gen2 (STM32G0B1) toolhead over CAN, a BTT Eddy Duo (RP2040) inductive bed probe over CAN, and a BIQU Nebula extruder. The Creality CFS multi-color unit stays, driven over a CH340/CH341 USB-RS485 adapter by the open [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper) module instead of the closed box.so stack. This repo packages the verified config set, the install scripts, and the wiring and bring-up docs to reproduce the build.

> **Status: Work In Progress. Assembled, mid-commissioning.**
> The motion system is validated on the real printer and all four stepper directions (X, Y, Z, Z1) are confirmed against hardware. Z homing into the dual Z-max switches, the Eddy frequency map, per-print auto Z0, and the 9x9 rapid_scan mesh are calibrated and running. The AC-mains bed driver is built and working: an AO3401 P-channel high-side stage fed from `heater_pin: PA1`, which triggers the bed on `M140 S60` and drops it on `S0`. The bed is **not** finished, though. Commissioning is still outstanding: PID tune, restore `max_power`, confirm fail-safe on reset, then set `bed_commissioned=1`. Until that flag is set every bed-heat macro path refuses, and the config ships duty-capped at `max_power: 0.4`. The Creality CFS is not wired yet, so its config include ships commented out, and the filament cutter still needs bench calibration before any tool change. Treat this as a bring-up config, not a release.

## Open prerequisites

Read these before you print anything.

1. **Bench-validate the cutter before trusting any tool change.** Verify hall polarity (`QUERY_BUTTON BUTTON=cutter_hall`), tune `driver_SGTHRS`, run `CALIBRATE_CUT_POS`, and test a resume after a jammed cut. Details in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).
2. **Fill every in-file placeholder** in `config/`: the three CAN UUIDs (Octopus bridge, EBB42, Eddy Duo, all from `canbus_query.py can0`), the S2DW serial by-id, the CH340 by-id, X/Y run currents, and Nebula `rotation_distance`. Each one is marked where it lives. The Eddy `z_offset` and frequency map are calibration steps, not edits.
3. **Meter-verify the bed SSR wiring** before powering the bed. The AC board's control input (4-pin connector pin 2) is the opto LED anode: ACTIVE-HIGH, and it needs about 15mA sourced into it, which is why it is driven through an AO3401 P-channel high-side stage rather than straight off a pin. `heater_pin: PA1` sinks the PMOS gate, non-inverted. Mains AC must never reach the Octopus. The definitive driver design is [hi-ac-bed-to-octopus-wiring.md](hi-ac-bed-to-octopus-wiring.md); the connection summary and the meter sweep are in [docs/wiring.md](docs/wiring.md) and [docs/bring-up-checklist.md](docs/bring-up-checklist.md).
4. **Fit an independent thermal cutoff on the AC bed.** A triac fails shorted more often than open, and a shorted triac cannot be turned off by any `heater_pin`. `verify_heater` does not catch it either. A bed thermal fuse or klixon in series with the AC load is the only thing that covers this failure.
5. **Meter the cutter hall SIGNAL line before connecting it**: it must swing 0 to 3.3V. EBB42 `PA5` is not 5V-tolerant; a 5V signal (VCC not stepped down) will kill the pin.
6. The CFS driver install pins commit `73731e9` (v1.4.0). A `v1.4.0` tag on that repo would make a cleaner pin; the commit pin works today.
7. `printer.cfg` starts with `[include mainsail.cfg]`, which the Mainsail install provides. On a Fluidd host, swap that include for fluidd-config's `client.cfg`; the `_CLIENT_VARIABLE` hooks in `client_macros.cfg` follow the same convention in both.

## Hardware

| Part | Role | Notes |
|---|---|---|
| Creality Hi | Donor: frame, motion, bed, PSU | Stock mainboard, RS485 FOC servos, and prtouch probe come out |
| BTT Octopus (STM32F446ZET6) | Main MCU + USB-to-CAN bridge | USB to the host, bridge firmware exposes can0; X/Y/Z/Z1 on TMC2209 |
| BTT EBB42 Gen2 (STM32G0B1) | Toolhead board | Over CAN; hotend, fans, runout, cutter hall, RGB, accelerometer |
| BTT EBB USB adapter | Spare CAN bridge | Not used in the current topology; the Octopus bridge firmware took the host end of can0 |
| BTT Eddy Duo (RP2040) | Bed probe | Inductive coil over CAN; per-print auto Z0, rapid_scan mesh, manual Z_TILT_ADJUST, temp compensation. Not a Z endstop |
| BTT S2DW V1.0 (RP2040) | Y-axis accelerometer | Self-contained USB module (LIS2DW12); mounts on the bed, `accel_chip_y` for input shaping |
| BIQU Nebula | Extruder | On the EBB42 motor port; has its own macro button |
| 4x TMC2209 | Stepper drivers | X, Y, Z, Z1 (the stock FOC servos are gone) |
| CH340/CH341 USB-RS485 adapter | CFS link | A+/B-/GND to the CFS 6-pin; CFS +24V comes from the printer PSU, never the dongle |
| Creality CFS | 4-slot multi-color unit | 230400 baud, driven by creality-cfs-klipper |
| Stock bed: AC pad + SSR board + 100K NTC | Heated bed, kept | Active-high opto input driven by an AO3401 high-side stage off `PA1`, thermistor on PF3 |
| AO3401 P-channel MOSFET + 3 resistors | Bed control interface | Sources ~15mA into the SSR opto LED, which no Octopus output can do on its own |

Pin-level detail is in [docs/wiring.md](docs/wiring.md). The bed control stage has its own definitive guide in [hi-ac-bed-to-octopus-wiring.md](hi-ac-bed-to-octopus-wiring.md).

## Features

- **Mainline Klipper, no Creality fork.** Every fork-only section is gone: prtouch_v3, motor_control, box, z_align, io_remap, tmc_line_check, bl24c16f, timer_read, and the fork-only heater_bed keys. The config boots on stock upstream klippy.
- **CFS multi-color with no vendor blobs.** The GPL-3.0 [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper) module (pinned to `73731e9`, v1.4.0) speaks the CFS RS485 protocol directly.
- **Stock-faithful filament cut.** `CUT_FILAMENT` rams the cutter at a stallguard-calibrated stopper position and confirms with a hall two-check: released before, pressed at the ram, released after retreat. A cut that never triggers aborts the tool change before any retract, because retracting an uncut strand risks a clog. The print pauses for recovery instead of hard-stopping.
- **T0-T3 tool changes** plus `CFS_PRINT_START`/`CFS_PRINT_END` in `config/macros.cfg`. The toolhead runout switch gates every load and unload.
- **Switch-squared dual Z.** Z homes UP into two independent Z-max optical switches, one per Z motor, so every `G28 Z` mechanically squares the gantry. This replaces both the stock optical z_align and the earlier Eddy-virtual-endstop design.
- **Eddy Duo as the bed probe**, not a Z endstop: per-print auto print-Z0, a 9x9 `rapid_scan` mesh, manual `Z_TILT_ADJUST` fine squaring, and probe temperature compensation. Details in the next section.
- **Bed commissioning gate.** The AC-mains bed refuses to heat from any macro path until commissioning is complete and recorded in `variables.cfg`. See the bed section below.
- **Single-material and client macros** in `config/client_macros.cfg`: load/unload, preheats, purge and prime line, toolhead RGB status states, pause-on-error handling, and filament sensor toggles.
- **One CAN bus** for the EBB42 and the Eddy Duo through the Octopus USB-to-CAN bridge firmware; `scripts/setup-can.sh` brings up `can0` at 1 Mbit.

## Homing, probing, and bed mesh

The Z axis homes UP. Each Z motor drives into its own Z-max optical switch (`stepper_z` = right screw on PG10, `stepper_z1` = left screw on PG9), so every `G28 Z` mechanically squares the gantry against two fixed references. The earlier design that homed Z down onto the Eddy virtual endstop is gone; `[safe_z_home]` is gone with it.

The Eddy Duo is the bed probe, used three ways:

1. **Per-print auto print-Z0.** The `[homing_override]` ends every full home by parking at bed center on Z15 and running `SET_PRINT_Z0`, which probes twice and folds the switch-vs-bed difference into a gcode Z offset. The macro is split in two (`SET_PRINT_Z0` probes, `_APPLY_PRINT_Z0` reads and applies) because a Klipper macro renders its whole body before any line runs; a single macro would read the probe result from before its own probe. A result over 1mm aborts the home instead of applying a bad offset.
2. **Bed mesh.** `BED_MESH_CALIBRATE METHOD=rapid_scan` sweeps the 9x9 grid in about 12 seconds. The mesh is normalized at `zero_reference_position: 134.45, 107.23`, which is the same physical spot `SET_PRINT_Z0` probes (nozzle at 130,130 plus the coil offset), so auto-Z0 and mesh compensation compose without double-counting the absolute bed height.
3. **Manual fine squaring.** `Z_TILT_ADJUST` remains available for Eddy-based dual-Z fine squaring. `G28` never calls it; the switches already square the gantry mechanically.

## Bed commissioning gate

The bed is the stock AC-mains silicone pad behind an opto-isolated SSR board, and an AC heater is not something to first-energize casually. The driver stage is built and proven to switch the bed, but commissioning is still outstanding: PID tune, restore `max_power`, confirm fail-safe on reset, then set the flag. Until that completes, the config holds three locks:

- Every bed-heat macro path (`START_PRINT`, `_PREHEAT` and the `PREHEAT_*` macros, `HEAT_SOAK`) checks `save_variables` and refuses with an error until you run `SAVE_VARIABLE VARIABLE=bed_commissioned VALUE=1`.
- `[heater_bed]` ships duty-capped at `max_power: 0.4` so the first supervised heat cannot slam full mains duty. Raise it toward 1.0 only after that heat passes.
- `[verify_heater heater_bed]` ships with deliberately generous commissioning values for a slow silicone pad at 40% duty; re-tighten after `PID_CALIBRATE HEATER=heater_bed`.

The repo does not ship `variables.cfg` (it is per-machine runtime state). The macros read `bed_commissioned` with a default of 0, so a fresh install is safe by default: the bed cannot heat through any macro until you explicitly set the flag. The commissioning procedure is in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).

None of these software locks protect against a shorted triac. A T1635 fails closed more often than open, and once it does, no `heater_pin` value and no `verify_heater` setting can stop the bed. Fit an independent thermal fuse or klixon in series with the AC load. That hardware cutoff is the only thing covering this failure.

## Quick start

```
git clone https://github.com/gitstonelabs/modded-creality-hi-cfs-combo.git
cd modded-creality-hi-cfs-combo
./scripts/install.sh
```

The installer copies the configs to `~/printer_data/config/` (backing up an existing file to `.bak` once, and never overwriting a config you have edited unless you pass `FORCE=1`) and installs `creality_cfs.py` into `~/klipper/klippy/extras/` from the pinned CFS repo commit. It does not restart Klipper; you fill the placeholders first.

The full walkthrough, including the firmware build matrix for all four boards and the flashing order (Octopus bridge, then EBB over USB then CAN, then Eddy, then the S2DW), is in [INSTALL.md](INSTALL.md).

## Repo layout

```
modded-creality-hi-cfs-combo/
  README.md                 this file
  INSTALL.md                step-by-step install and bring-up guide
  hi-ac-bed-to-octopus-wiring.md   definitive AC-bed driver guide (PMOS high-side stage)
  LICENSE                   GPL-3.0
  NOTICES.md                attribution for the CFS module and vendor docs
  config/                   the verified Klipper configs
    printer.cfg             Octopus MCU/bridge, X/Y/Z/Z1, bed + gate, homing_override, auto Z0
    ebb42.cfg               EBB42 toolhead: fans, runout, macro button, cutter hall, RGB
    nebula.cfg              Nebula extruder and hotend
    eddy.cfg                Eddy Duo probe and the rapid_scan bed_mesh
    cfs.cfg                 [creality_cfs] on the CH340 by-id path
    macros.cfg              START/END print, T0-T3, CUT_FILAMENT
    client_macros.cfg       load/unload, preheats, prime, RGB states, pause-on-error
    moonraker.conf          reference Moonraker config (not copied by the installer)
  scripts/
    install.sh              configs + CFS driver installer
    setup-can.sh            can0 bring-up for the EBB + Eddy
  docs/
    wiring.md               pin tables for every connection
    bring-up-checklist.md   flashing order, calibration, safety gates
    hardware/               bundled vendor pinouts and schematics
  reference/
    stock-hi/               factory Creality Hi configs, for provenance
```

## Documentation

- [INSTALL.md](INSTALL.md): install scripts, firmware build matrix, placeholder fill-in
- [hi-ac-bed-to-octopus-wiring.md](hi-ac-bed-to-octopus-wiring.md): the definitive AC-bed driver guide. Schematic, resistor values, polarity evidence, fail-safe reasoning, mains safety. Anything about the bed control stage elsewhere in this repo is a summary of this file
- [docs/wiring.md](docs/wiring.md): Octopus stepper sockets, EBB42 connectors, CFS RS485 pinout, bed connection summary
- [docs/bring-up-checklist.md](docs/bring-up-checklist.md): flashing order, calibration sequence, safety gates
- [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper): the CFS driver module and its protocol docs

## Attribution and license

The Klipper config set in `config/` is original work for this build. The CFS driver module and the bundled vendor hardware documentation are attributed in [NOTICES.md](NOTICES.md). The repo is licensed GPL-3.0, matching the CFS module it installs.
