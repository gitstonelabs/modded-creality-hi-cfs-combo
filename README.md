# Modded Creality Hi + CFS Combo

A Creality Hi with its stock mainboard removed, running mainline Klipper on a BTT Octopus V1.0 (STM32F446) as the main MCU, a BTT EBB42 Gen2 (STM32G0B1) toolhead over CAN, a BTT Eddy Duo (RP2040) inductive probe, and a BIQU Nebula extruder. The Creality CFS multi-color unit stays, driven over a CH340/CH341 USB-RS485 adapter by the open [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper) module instead of the closed box.so stack. This repo packages the verified config set, the install scripts, and the wiring and bring-up docs to reproduce the build.

## Open prerequisites

Read these before you print anything.

1. **Bench-validate the cutter before trusting any tool change.** Verify hall polarity (`QUERY_BUTTON BUTTON=cutter_hall`), tune `driver_SGTHRS`, run `CALIBRATE_CUT_POS`, and test a resume after a jammed cut. Details in [docs/bring-up-checklist.md](docs/bring-up-checklist.md).
2. **Fill every in-file placeholder** in `config/`: Octopus serial by-id, EBB CAN UUID, CH340 by-id, X/Y run currents, Eddy `y_offset` and `z_offset`, Nebula `rotation_distance`. Each one is marked where it lives.
3. **Meter-verify the bed SSR** before powering the bed: `BED_OUT` (PA1) must drive the SSR trigger only, and mains AC must never reach the Octopus.
4. **Meter the cutter hall SIGNAL line before connecting it**: it must swing 0 to 3.3V. EBB42 `PA5` is not 5V-tolerant; a 5V signal (VCC not stepped down) will kill the pin.
5. The CFS driver install pins commit `73731e9` (v1.4.0). A `v1.4.0` tag on that repo would make a cleaner pin; the commit pin works today.

## Hardware

| Part | Role | Notes |
|---|---|---|
| Creality Hi | Donor: frame, motion, bed, PSU | Stock mainboard, RS485 FOC servos, and prtouch probe come out |
| BTT Octopus V1.0 (STM32F446ZET6) | Main MCU | USB to the host; X/Y/Z1/Z2 on TMC2209 |
| BTT EBB42 Gen2 (STM32G0B1) | Toolhead board | Over CAN; hotend, fans, runout, cutter hall, RGB, accelerometer |
| BTT EBB USB adapter | USB-to-CAN bridge | Host end of the CAN bus; one of the two 120R terminators |
| BTT Eddy Duo (RP2040) | Z probe | Inductive coil; Z homing, bed mesh, temp compensation |
| BIQU Nebula | Extruder | On the EBB42 motor port; has its own macro button |
| 4x TMC2209 | Stepper drivers | X, Y, Z1, Z2 (the stock FOC servos are gone) |
| CH340/CH341 USB-RS485 adapter | CFS link | A+/B-/GND to the CFS 6-pin; CFS +24V comes from the printer PSU, never the dongle |
| Creality CFS | 4-slot multi-color unit | 230400 baud, driven by creality-cfs-klipper |
| Stock bed: AC pad + SSR + 100K NTC | Heated bed, kept | SSR trigger on PA1, thermistor on PF3 |

Pin-level detail is in [docs/wiring.md](docs/wiring.md).

## Features

- **Mainline Klipper, no Creality fork.** Every fork-only section is gone: prtouch_v3, motor_control, box, z_align, io_remap, tmc_line_check, bl24c16f, timer_read, and the fork-only heater_bed keys. The config boots on stock upstream klippy.
- **CFS multi-color with no vendor blobs.** The GPL-3.0 [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper) module (pinned to `73731e9`, v1.4.0) speaks the CFS RS485 protocol directly.
- **Stock-faithful filament cut.** `CUT_FILAMENT` rams the cutter at a stallguard-calibrated stopper position and confirms with a hall two-check: released before, pressed at the ram, released after retreat. A cut that never triggers aborts the tool change before any retract, because retracting an uncut strand risks a clog. The print pauses for recovery instead of hard-stopping.
- **T0-T3 tool changes** plus `CFS_PRINT_START`/`CFS_PRINT_END` in `config/macros.cfg`. The toolhead runout switch gates every load and unload.
- **Dual Z with `z_tilt`**, replacing the stock optical z_align.
- **Eddy Duo probing**: Z homing via `probe:z_virtual_endstop`, bed mesh, and probe temperature compensation.
- **One CAN bus** for the EBB42 (and optionally the Eddy) through the EBB USB bridge; `scripts/setup-can.sh` brings up `can0` at 1 Mbit.

## Quick start

```
git clone https://github.com/gitstonelabs/modded-creality-hi-cfs-combo.git
cd modded-creality-hi-cfs-combo
./scripts/install.sh
```

The installer copies the configs to `~/printer_data/config/` (backing up an existing file to `.bak` once, and never overwriting a config you have edited unless you pass `FORCE=1`) and installs `creality_cfs.py` into `~/klipper/klippy/extras/` from the pinned CFS repo commit. It does not restart Klipper; you fill the placeholders first.

The full walkthrough, including the firmware build matrix for all three boards and the flashing order (Octopus, then EBB over USB then CAN, then Eddy), is in [INSTALL.md](INSTALL.md).

## Repo layout

```
modded-creality-hi-cfs-combo/
  README.md                 this file
  INSTALL.md                step-by-step install and bring-up guide
  LICENSE                   GPL-3.0
  NOTICES.md                attribution for the CFS module and vendor docs
  config/                   the verified Klipper configs
    printer.cfg             Octopus MCU, X/Y/Z1/Z2, bed, z_tilt, plumbing
    ebb42.cfg               EBB42 toolhead: fans, runout, macro button, cutter hall, RGB
    nebula.cfg              Nebula extruder and hotend
    eddy.cfg                Eddy Duo probe, safe_z_home, bed_mesh
    cfs.cfg                 [creality_cfs] on the CH340 by-id path
    macros.cfg              START/END print, T0-T3, CUT_FILAMENT
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
- [docs/wiring.md](docs/wiring.md): Octopus stepper sockets, EBB42 connectors, CFS RS485 pinout, bed SSR
- [docs/bring-up-checklist.md](docs/bring-up-checklist.md): flashing order, calibration sequence, safety gates
- [creality-cfs-klipper](https://github.com/gitstonelabs/creality-cfs-klipper): the CFS driver module and its protocol docs

## Attribution and license

The Klipper config set in `config/` is original work for this build. The CFS driver module and the bundled vendor hardware documentation are attributed in [NOTICES.md](NOTICES.md). The repo is licensed GPL-3.0, matching the CFS module it installs.
