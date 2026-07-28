# Wiring

Every pin here matches the shipped config set in `config/`. If you change a connection, change the matching config line, not the other way around.

Boards in this build: BTT Octopus (main MCU and USB-to-CAN bridge, USB to the host), BTT EBB42 Gen2 (toolhead, CAN), BTT Eddy Duo (probe, CAN), and a CH340/CH341 USB-RS485 dongle for the CFS. All DC loads run on the printer's 24V PSU.

## Safety first

Read these before you power anything.

- **No mains AC on the Octopus. Ever.** The bed is an AC silicone pad switched by the stock opto-isolated SSR board (BED-HEAT-AC-V2.5: EL3063 zero-cross opto driving a T1635 triac). The Octopus never touches the AC side. It drives the board's low-voltage control input through an AO3401 P-channel high-side stage: `heater_pin: PA1` sinks the PMOS gate, the PMOS sources roughly 15mA into the opto LED. `heater_pin` is NON-inverted (no `!`); an inverted pin idles HIGH, which arms the bed whenever Klipper is idle. Never put the control line on a thermistor input (PF3/PF4 and kin carry a 4.7k pullup that arms the SSR before Klipper even runs). Before energizing, meter the triac (MT1-MT2 not shorted) and the AC-to-control isolation (open). The full sweep is in [bring-up-checklist.md](bring-up-checklist.md); the definitive driver design is [hi-ac-bed-to-octopus-wiring.md](../hi-ac-bed-to-octopus-wiring.md).
- **A shorted triac cannot be switched off in software.** A triac fails closed more often than open, and `verify_heater` does not catch it. Fit an independent, non-firmware thermal cutoff: a bed thermal fuse or klixon in series with the AC bed load. Non-negotiable for an AC bed.
- **The cutter hall signal must be 3.3V.** The sensor's VCC goes through a 5V to 3.3V step-down, and the signal line must swing 0 to 3.3V. EBB PA5 is not 5V-tolerant; a 5V signal kills the pin.
- **Exactly two 120R terminators on the CAN bus.** One at the EBB42 (CAN-120R jumper), one at the host bridge end. Not one, not three.

## Octopus (main MCU, USB-to-CAN bridge)

Connected to the host over USB. Build target: STM32F446, 32KiB bootloader, 12MHz crystal, USB on PA11/PA12, with "USB to CAN bus bridge (USBCAN)" enabled. In bridge mode the board is both the main MCU (addressed by `canbus_uuid` in `printer.cfg`) and the host end of `can0`.

### Steppers (all TMC2209)

| Axis | Socket | STEP | DIR | EN | UART | DIAG |
|---|---|---|---|---|---|---|
| X | Driver0 | PF13 | PF12 | !PF14 | PC4 | PG6 (cut calib) |
| Y | Driver1 | PG0 | PG1 | !PF15 | PD11 | not used |
| Z (stepper_z) | Driver2 | PF11 | PG3 | !PG5 | PC6 | not used |
| Z1 (stepper_z1) | Driver3 | PG4 | PC1 | !PA0 | PC7 | not used |

The X DIAG line (PG6) is only used by `CALIBRATE_CUT_POS` to stallguard-find the cutter stopper at the right of travel; normal X homing uses the left switch on the toolhead. Install the Driver0 DIAG jumper so PG6 actually sees the driver's diag output. The other STOP headers carry physical switches (next tables), not stallguard.

### Bed

The stock Hi bed carries over: an AC silicone pad switched by the stock opto-isolated SSR board (EL3063 opto + T1635 triac), plus the pad's 100K NTC. The AC side of that board and the pad never touch the Octopus.

The control input is not a logic input. Pin 2 is the opto LED **anode** and the LED is bare, with no current-limit resistor on the AC board, so something has to **source** about 15mA into it through an external resistor. An Octopus low-side output can only sink, so the Octopus drives pin 2 through an **AO3401 P-channel high-side stage**. The schematic, the resistor values, the diode-test evidence, and the logic-analyzer capture are in [hi-ac-bed-to-octopus-wiring.md](../hi-ac-bed-to-octopus-wiring.md). That is the definitive guide. It is not duplicated here; the table below is only the connection summary.

| AC board 4-pin connector | Function | Octopus side |
|---|---|---|
| pin 1 | GND | Octopus GND (common ground mandatory) |
| pin 2 | control, opto LED **anode**, ACTIVE-HIGH, needs ~15mA sourced | PMOS drain through **R2 = 270R (mandatory)** |
| pin 3 | opto LED **cathode**, carries the LED return current | Octopus GND, on its **own dedicated wire**. Do not low-side-switch it |
| pin 4 | 5V the AC board draws | Octopus **+5V**, the same stiff node that feeds the PMOS source |

| Function | Pin | Connector |
|---|---|---|
| Bed heater (PMOS gate drive, sinks) | PA1 | BED output, switched/negative pin. Leave BED+ (24V) UNCONNECTED |
| Bed thermistor (100K NTC, #13 pad) | PF3 | TB |

Build note, learned the hard way: **pin 3 needs a dedicated direct ground.** Grounding pin 1 alone does not complete the LED loop; pin 2 then floats to 5V, no current flows, and the bed simply never heats. Adding the direct pin 3 to GND wire is what made it work.

PA1 sinks the PMOS gate, the PMOS sources the LED current, so the stage as a whole is non-inverting: Klipper heat ON means pin 2 HIGH. `heater_pin` must stay NON-inverted (no `!`); an inverted pin idles HIGH, which arms the bed whenever Klipper is idle. With PA1 released (heat off, MCU reset, power loss) R1 pulls the gate to 5V, the PMOS turns off, and R3 holds pin 2 at 0V, so the bed is off. Do not move pin 2 to a thermistor input; the 4.7k pullup there arms the SSR at boot.

**If you are rebuilding from a repo revision before 2026-07-15, read this.** That revision drove the SSR control input directly from PG13 and warned in several places to never use `BED_OUT`/PA1 or a FAN/HE output. That warning was correct for direct drive: those pins are low-side FETs, they can only sink, and direct drive needs a pin that can source the LED current. It does not apply to the current design, where PA1 only sinks a MOSFET gate and the PMOS does the sourcing. The two designs are not interchangeable. No PMOS stage on your bench means you are on the old design: keep PG13 and do not move to PA1.

### Endstops

| Axis | Pin | Where |
|---|---|---|
| X | EBB:PA2 | left switch on the EBB42 toolhead, reaches the host over CAN |
| Y | PG11 | Octopus STOP header |
| Z (stepper_z, RIGHT screw) | PG10 | Z-max optical switch; Z homes UP |
| Z1 (stepper_z1, LEFT screw) | PG9 | Z-max optical switch; Z homes UP |

Each Z motor homes to its own Z-max optical switch, so every `G28 Z` mechanically squares the gantry. The Eddy Duo is the bed probe (auto print-Z0, mesh, manual `Z_TILT_ADJUST`), not a Z endstop; the earlier `probe:z_virtual_endstop` design is gone.

## EBB42 Gen2 (toolhead)

These are the official EBB42 **Gen2** silkscreen pins. The older EBB42 layout is different (the Gen2 STEP pin PD3 was the old board's RGB pin), so do not mix pinout references. Every pin in this table belongs to the EBB42's own MCU and is written `EBB:` prefixed in the configs, so the `PA1` below is the EBB42's hotend thermistor input and has nothing to do with the Octopus `PA1` that drives the bed.

| Function | Pin | Connector |
|---|---|---|
| Extruder | step PD3 / dir PD2 / en PB6 / uart PB3 | Motor |
| Hotend heater | PB0 | HE |
| Hotend thermistor | PA1 (pullup 2200) | TH |
| Part fan | PB8 | FAN0 |
| Hotend fan (+tach) | PB4 (+PB9) | FAN2 |
| EBB board fan | PB15 | FAN1 |
| Filament runout | PA3 | FIL |
| Nebula macro button | PA4 | PROBE/SERVOS |
| Cutter hall | PA5 | PROBE/PROBE |
| RGB | PB14 | RGB |
| Accelerometer | CS PB1 / SCLK PB10 / MOSI PB11 / MISO PB2 | onboard |

The extruder is the BIQU Nebula on the EBB motor header. The runout switch, macro button, cutter hall, and RGB are all Nebula harness lines; the accelerometer is the EBB42's onboard LIS2DW over software SPI (the X-axis input-shaping chip, `accel_chip_x`).

The Y-axis accelerometer is a separate BTT S2DW V1.0: a self-contained USB module with its own RP2040 and an internal LIS2DW12. It mounts on the bed and connects to the host over USB-C. Nothing wires to the Octopus or EBB42 for it. Klipper uses it as `accel_chip_y` while the EBB42 onboard accelerometer stays `accel_chip_x`, so both axes calibrate without moving a sensor between passes.

## CAN topology

```
Host (Pi/Jetson)
  |
  USB
  |
BTT Octopus (Klipper USB-to-CAN bridge firmware)   [terminate this end of the bus]
  |
  CAN bus, 1M bitrate
  |-- EBB42 Gen2                                   [CAN-120R jumper set]
  |-- Eddy Duo                                     [no terminator]
```

The host bridge is the Octopus itself, running Klipper's "USB to CAN bus bridge (USBCAN)" firmware; it enumerates as a gs_usb CAN adapter and the kernel exposes `can0`. All three boards are then CAN nodes with their own UUIDs: the Octopus bridge node (`[mcu]`), the EBB42 (`[mcu EBB]`), and the Eddy Duo (`[mcu eddy]`). `canbus_query.py can0` lists all three. `scripts/setup-can.sh` brings up `can0` at 1000000 bit/s with txqueuelen 128; that bitrate must match what you compiled into the EBB and Eddy firmware. Two terminators total: one at the bridge end of the bus, the other is the EBB42's CAN-120R jumper. Verify with a meter: roughly 60R across CAN-H/CAN-L, bus unpowered. The Eddy Duo sits mid-bus unterminated (its shipped `eddy.cfg` section uses `canbus_uuid`; the commented `serial:` line is the USB fallback for first flash and bench tests).

## CFS (USB-RS485)

The CFS talks RS485 at 230400 baud through a CH340/CH341 USB-RS485 dongle on the host, driven by the `creality_cfs` module.

| Dongle | CFS 6-pin connector |
|---|---|
| A+ | pin 1 (RS485-A) |
| B- | pin 6 (RS485-B) |
| GND | pin 5 (GND) |

**Power:** CFS pin 4 (+24V) comes from the printer's 24V PSU only. Never feed it from the dongle; RS485 dongles have no 24V rail and the CFS motors would try to pull load current through your data adapter.

Optional: CFS pin 2 is the buffer-empty switch. You can tap pin 2 plus pin 5 (GND) to any spare 3.3V GPIO and expose it as a `[filament_switch_sensor]`; the commented block at the bottom of `config/cfs.cfg` shows how.
