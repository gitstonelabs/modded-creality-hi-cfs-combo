# Bill of materials

Parts for converting a Creality Hi (or Hi Combo) to mainline Klipper with the CFS driven
directly, the stock AC bed kept, and the stock touchscreen reused.

**This is a draft and the build is not finished.** Two sections are still unvalidated and are
marked as such. Do not order the unvalidated parts yet. The source column is empty on purpose:
every link needs to be one that was actually bought and checked, not a guess, because several of
these parts have near-identical listings that are not the same part.

Status key: **WORKING** built and proven on the machine, **UNVALIDATED** designed but not yet
proven, **PLANNED** not built.

---

## 1. Control electronics

| Part | Qty | What matters | Status | Source |
|---|---|---|---|---|
| BTT Octopus v1.1 (STM32F446ZET6) | 1 | Main MCU. Also runs Klipper's USB-to-CAN bridge firmware, so no separate CAN adapter is needed | WORKING | |
| TMC2209 | 4 | X, Y, Z, Z1. The stock RS485 FOC servos come out | WORKING | |
| BTT EBB42 Gen2 (STM32G0B1) | 1 | Toolhead board over CAN: hotend, fans, runout, cutter hall, RGB, accelerometer | WORKING | |
| BTT Eddy Duo (RP2040) | 1 | Inductive bed probe over CAN. Not a Z endstop | WORKING | |
| BTT S2DW V1.0 (RP2040) | 1 | Y accelerometer for input shaping. Self-contained USB, mounts on the bed | WORKING | |
| BIQU Nebula | 1 | Extruder, on the EBB42 motor port | WORKING | |

The BTT EBB USB-to-CAN adapter (U2C) is **not required**. It was in the original topology and the
Octopus bridge firmware replaced it. Skip it unless you want a spare host CAN adapter.

## 2. CFS link

| Part | Qty | What matters | Status | Source |
|---|---|---|---|---|
| CH340 or CH341 USB-RS485 adapter | 1 | A+, B-, GND to the CFS 6-pin connector. 230400 baud | WORKING | |

The CFS takes **+24 V from the printer PSU, never from the dongle.** The adapter carries data
only.

## 3. AC bed control interface

The stock bed stays: AC silicone pad, the stock opto-isolated SSR board (EL3063 opto driving a
T1635 triac), and the 100K NTC. What you build is the low-voltage stage that drives the SSR
board's control input, because no Octopus output can source the current that input needs on its
own.

Full schematic and the reasoning are in [../hi-ac-bed-to-octopus-wiring.md](../hi-ac-bed-to-octopus-wiring.md).
Read it before building. It records a fault that stalled this build for a day.

| Part | Qty | What matters | Status | Source |
|---|---|---|---|---|
| AO3401 P-channel MOSFET | 1 | Low threshold voltage so a 5 V rail drives it fully. DMG3415 works too | WORKING | |
| 270 Ω resistor | 1 | R2, LED current limit. **Mandatory.** ~15 mA at 5.125 V, a stock match | WORKING | |
| 10 k resistor | 2 | R1 gate pull-up (default OFF, fail-safe) and R3 pin-2 pull-down | WORKING | |
| BOJACK SEFUSE SF139E thermal cutoff | 1 | Independent hardware cutoff in the bed's AC line. 142 C open, 10 A, 250 V. Sold in packs of 10, CSA/VDE/BEAB/KC marked. Mounts at the bed's AC connection | UNVALIDATED, part and placement chosen, not yet fitted | |

**Safety, read this part.**

- Mains never touches the Octopus. The Octopus only drives the SSR board's low-voltage input.
- `heater_pin` is **non-inverted**. An inverted pin idles HIGH and arms the bed whenever Klipper
  is idle.
- The SSR board's control pin 2 is the opto LED **anode** and there is no current-limit resistor
  on the board. Driving it off 5 V without R2 destroys the LED.
- Pin 3 is the LED cathode and needs its **own dedicated ground wire.** Grounding pin 1 alone does
  not complete the loop. That is the fault that stalled the build.
- Pin 1 is GND, pin 4 is the 5 V the board draws. Do not swap them.
- `verify_heater` does **not** catch a shorted triac. The thermal fuse is what covers that, which
  is why it is on this list even though its part and placement are still unconfirmed.
- Before any mains: meter the triac (MT1 to MT2 not shorted) and the AC-to-control isolation
  (open).

### Thermal cutoff notes

10 A matches the stock NTST10A fuse already on the SSR board, and 250 V covers mains either side
of the Atlantic.

**Why 142 C.** The bed never legitimately exceeds about 110 C, so 142 C leaves roughly 30 C of
headroom: far enough above any real setpoint to avoid nuisance trips, low enough that a runaway
is cut before the plate destroys the print surface and the silicone pad. A 216 C part was
considered and rejected as too late to protect anything but the building. These are one-shot
devices, so a trip means replacing the fuse before the bed works again, which is the reason not
to go lower still.

**Why at the bed's AC connection.** Placement decides what the fuse senses. Bonded at the
connection it reads bed temperature, which is what catches a runaway, and it also sits on the
joint itself, so it covers a high-resistance connection heating up. That is a real fire mode in
AC bed wiring and nothing in firmware or the thermistor would ever see it. A cutoff sitting out
in the AC line away from the heater reads almost nothing and protects almost nothing.

**Do not solder this part directly.** The heat of soldering can degrade or open a thermal cutoff
before it is ever installed. Crimp it, or heatsink the lead hard if there is no alternative.

## 4. Touchscreen port

Reusing the stock Hi 3.2 inch panel on a Raspberry Pi or on the Octopus. The panel is a GC9307
controller with a GT9xx touch controller, 320x240, driven over a parallel DPI bus at RGB565.

All 40 conductors on the panel's FPC have been identified by measurement. The breakout and the
overlay are **not finished**, so nothing here is confirmed yet.

| Part | Qty | What matters | Status | Source |
|---|---|---|---|---|
| 40-pin FPC breakout board | 1 | Must match the panel's pitch and contact side. Verify both before ordering | UNVALIDATED | |
| 40-pin FPC cable | 1 | Same pitch, correct contact orientation | UNVALIDATED | |
| Raspberry Pi | 1 | Only if driving the panel from a Pi rather than the Octopus. Undecided | PLANNED | |

Two pins in the map still rest on structural reasoning rather than a direct measurement, so treat
the pinout as provisional until the breakout is built and probed.

## 5. Wiring and consumables

| Part | Qty | What matters | Status | Source |
|---|---|---|---|---|
| CAN wiring, twisted pair plus power | 1 set | Octopus to EBB42 to Eddy Duo | WORKING | |
| 120 Ω CAN termination | as needed | Check what the boards already have fitted | WORKING | |
| Silicone hookup wire | some | The bed control stage and the dedicated pin 3 ground | WORKING | |
| JST connectors and crimps | some | Match the connectors already on the donor | WORKING | |

---

## Still outstanding before this BOM is final

1. Bed commissioning: PID tune, restore `max_power`, confirm fail-safe on reset, set
   `bed_commissioned=1`. Until this is done the bed heat macros refuse to run.
2. The thermal cutoff: part and placement settled (SF139E at 142 C, mounted at the bed's AC
   connection). Still to fit it and confirm it does not nuisance-trip at the highest bed
   temperature actually used.
3. The touchscreen breakout: build it, probe the two provisional pins, finish the DPI overlay.
4. Confirm every source link against a part that was actually bought and worked.
