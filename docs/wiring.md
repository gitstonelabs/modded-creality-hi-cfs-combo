# Wiring

Every pin here matches the shipped config set in `config/`. If you change a connection, change the matching config line, not the other way around.

Boards in this build: BTT Octopus V1.0 (main MCU, USB), BTT EBB42 Gen2 (toolhead, CAN), BTT Eddy Duo (probe, CAN), and a CH340/CH341 USB-RS485 dongle for the CFS. All DC loads run on the printer's 24V PSU.

## Safety first

Read these before you power anything.

- **No mains AC on the Octopus. Ever.** The bed is an AC silicone pad switched by an SSR; the Octopus only drives the SSR's low-voltage trigger input. Before powering the bed, meter-verify that `BED_OUT` (PA1) drives the SSR trigger and that no AC-side wire can reach the board.
- **The cutter hall signal must be 3.3V.** The sensor's VCC goes through a 5V to 3.3V step-down, and the signal line must swing 0 to 3.3V. EBB PA5 is not 5V-tolerant; a 5V signal kills the pin.
- **Exactly two 120R terminators on the CAN bus.** One at the EBB42 (CAN-120R jumper), one at the host bridge end. Not one, not three.

## Octopus V1.0 (main MCU)

Connected to the host over USB. Build target: STM32F446, 32KiB bootloader, 12MHz crystal, USB on PA11/PA12.

### Steppers (all TMC2209)

| Axis | Socket | STEP | DIR | EN | UART | DIAG |
|---|---|---|---|---|---|---|
| X | Driver0 | PF13 | PF12 | !PF14 | PC4 | PG6 (cut calib) |
| Y | Driver1 | PG0 | PG1 | !PF15 | PD11 | PG9 |
| Z1 | Driver2 | PF11 | PG3 | !PG5 | PC6 | PG10 |
| Z2 | Driver3 | PG4 | PC1 | !PA0 | PC7 | PG11 |

The X DIAG line (PG6) is only used by `CALIBRATE_CUT_POS` to stallguard-find the cutter stopper at the right of travel; normal X homing uses the left switch on the toolhead. Install the Driver0 DIAG jumper so PG6 actually sees the driver's diag output.

### Bed

| Function | Pin | Connector |
|---|---|---|
| Bed heater (SSR trigger) | PA1 | BED_OUT |
| Bed thermistor (100K NTC) | PF3 | TB |

The stock Hi bed carries over: an AC silicone pad switched by an SSR. PA1 fires the SSR trigger; the NTC lands on PF3. The AC side of the SSR and the pad never touch the Octopus.

### Endstops

| Axis | Pin | Where |
|---|---|---|
| X | EBB:PA2 | left switch on the EBB42 toolhead, reaches the host over CAN |
| Y | PG9 | Octopus Driver1 STOP header |
| Z | none | Eddy Duo virtual endstop (`probe:z_virtual_endstop`) |

## EBB42 Gen2 (toolhead)

These are the official EBB42 **Gen2** silkscreen pins. The older EBB42 layout is different (the Gen2 STEP pin PD3 was the old board's RGB pin), so do not mix pinout references.

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
BTT EBB USB adapter (U2C bridge)          [120R terminator here]
  |
  CAN bus, 1M bitrate
  |-- EBB42 Gen2                          [CAN-120R jumper set]
  |-- Eddy Duo                            [no terminator]
```

The host bridge is the BTT EBB USB adapter. `scripts/setup-can.sh` brings up `can0` at 1000000 bit/s with txqueuelen 128; that bitrate must match what you compiled into the EBB and Eddy firmware. Two terminators total: the bridge end and the EBB42's CAN-120R jumper. The Eddy Duo sits on the same bus unterminated (the shipped `eddy.cfg` defaults to its USB path; switch to `canbus_uuid` once you flash it for CAN).

## CFS (USB-RS485)

The CFS talks RS485 at 230400 baud through a CH340/CH341 USB-RS485 dongle on the host, driven by the `creality_cfs` module.

| Dongle | CFS 6-pin connector |
|---|---|
| A+ | pin 1 (RS485-A) |
| B- | pin 6 (RS485-B) |
| GND | pin 5 (GND) |

**Power:** CFS pin 4 (+24V) comes from the printer's 24V PSU only. Never feed it from the dongle; RS485 dongles have no 24V rail and the CFS motors would try to pull load current through your data adapter.

Optional: CFS pin 2 is the buffer-empty switch. You can tap pin 2 plus pin 5 (GND) to any spare 3.3V GPIO and expose it as a `[filament_switch_sensor]`; the commented block at the bottom of `config/cfs.cfg` shows how.
