# Driving the Creality Hi "BED HEAT-AC-V2.5" from a BTT Octopus v1.1

Definitive port guide (researched + adversarially verified 2026-07-15). Supersedes the
earlier "let an Octopus low-side output sink pin 2" idea, which does **not** work with this
board and would fail **unsafe**.

**STATUS: BUILT + WORKING (2026-07-15).** AO3401 high-side stage on a stiff 5.1 V, R2 = 270 Ω,
R1/R3 = 10 k, `heater_pin: PA1` no `!`, pin 3 on its OWN dedicated ground. Bed triggers on
`M140 S60` and stops on `S0`. The one build gotcha that stalled it: pin 3 (LED cathode) needs a
dedicated direct ground — grounding pin 1 alone did not complete the LED loop. Remaining =
commissioning (PID tune, restore max_power, set bed_commissioned=1, confirm fail-safe-on-reset).

## Why not the simple low-side approach
Confirmed on the real board: **pin 2 is the opto LED _anode_**, the LED _cathode_ is hard-tied
to board GND (pins 1/3), and the stock mainboard **sources** ~15 mA into pin 2. An Octopus
HE/BED/FAN output is a low-side N-MOSFET that can only *sink* to GND, so it can never source the
positive current the LED needs. You must **source** ~15 mA at 5 V into pin 2. The clean, fail-safe
way is a small **P-channel high-side switch** gated by one Octopus low-side output.

## 1. Wiring map
| AC-board pin | What it is | Octopus | Polarity | Notes |
|---|---|---|---|---|
| 1 | GND (past the cathode via a small internal link; diode pin2->pin1 = 1.55V) | Octopus GND | — | common ground mandatory |
| 2 | control = LED **anode** (diode pin2->pin3 = 1.15V clean = BARE LED, no on-board series R), ~15 mA, active-high, back-drive sensitive | **PMOS drain** via **R2 (MANDATORY)** | sourced HIGH by PMOS | R2 is REQUIRED — no current limit on the AC board; a bare LED on 5V dies. R2 = **270 Ohm** (~15 mA @ 5.125V, stock-match) |
| 3 | **LED CATHODE** (diode-confirmed 2026-07-15), carries the LED return current | Octopus GND — **its OWN dedicated wire** | — | **BUILD-CONFIRMED FAULT: pin 3 needs a DEDICATED direct ground; grounding pin 1 alone does NOT complete the LED circuit** (the internal pin3->pin1 junction blocks the LED return -> pin2 floats to 5V, no current, no heat = exactly the symptom seen). Adding a direct pin3->GND wire made it heat. Also: do NOT low-side-switch pin3. |
| 4 | 5 V the AC board draws | Octopus **+5 V** (also PMOS source) | supply | confirm rail holds ~5.1 V under +15 mA |
| bed thermistor (separate 2-pin) | EPCOS 100K B57560G104F | **TB / PF3** (use the port it actually reads on) | analog | already works on the Octopus |

### The high-side driver (drives pin 2)
```
 +5V (Octopus rail, = pin 4) ──┬─────────────┐
                               │             │
                            R1 10k       Q1 source
                               │        ┌── PMOS (AO3401 / DMG3415, low |Vth|)
   Q1 gate ────────────────────┴────────┤ gate
        │                               └── Q1 drain ── R2 270Ω ── pin 2 (LED anode)
   Octopus BED low-side FET (PA1) ── sinks gate to GND when Klipper heat = ON
                                     (LED cathode is internal → GND on pins 1/3)

   ALSO fit R3 = 10k from pin 2 → GND (pull-down): when the PMOS is off, holds
   pin 2 firmly at 0 V so no stray leakage can relight the LED. (Added after a
   live stuck-on: the stock pin-2 driver only SOURCES and RELEASES, it does not
   pull low, so an off-state pin 2 must be actively grounded.) 10k shunts only
   ~0.5 mA of the ~15 mA drive = negligible.
```
- **Which output:** BED = **PA1** (keeps it semantically `[heater_bed]`). Wire the BED screw
  terminal's **switched/negative** pin to the Q1 gate node. **Leave BED+ (24 V) UNCONNECTED.**
  A spare FAN low-side (e.g. FAN2 = PD12) works identically; gate load < 1 mA.
- **Operation (NON-inverting overall):** Klipper heat ON → PA1 FET ON → gate to GND → PMOS ON →
  ~15 mA into pin 2 → opto LED lit → zero-cross triac fires → bed heats.
- **R2 = 270 Ω** (the built and working value) → (5.125−1.15)/270 = 14.7 mA, a stock match at
  ~15 mA and **3× the 5 mA IFT**, well under the 50–60 mA abs-max. 220 Ω also works, at ~17 mA,
  but 270 Ω is what is fitted and measured on this build. **R1 = 10 k** gate pull-up =
  default-OFF / fail-safe.
- **R2 IS MANDATORY (diode-test settled 2026-07-15):** diode pin2->pin3 = 1.15 V clean = a BARE
  LED, i.e. NO current-limit resistor on the AC board (the ~253 Ohm limit lived on the stock
  mainboard). Driving the bare LED off 5 V with no R2 destroys it. Use **R2 = 270 Ohm**
  ((5.125-1.15)/270 = 14.7 mA, stock-match ~15 mA; 220 Ohm ok at ~17 mA). Verify after build:
  ~4 V across R2 = ~15 mA.

## 2. Klipper config
```ini
[heater_bed]
heater_pin: PA1                       # BED low-side sinks PMOS gate; PMOS sources 5V into pin 2.
                                      #   External PMOS re-inverts -> ACTIVE-HIGH, NO '!'.
sensor_type: EPCOS 100K B57560G104F   # confirmed stock bed thermistor
sensor_pin: PF3                       # Octopus TB (4.7k pullup); use the port it actually reads on
control: pid
pid_Kp: 20                            # stock Hi bed PID; carry over then re-tune on the Octopus
pid_Ki: 0.1
pid_Kd: 0.06
min_temp: 0
max_temp: 115
max_power: 1.0                        # safe: triac only fires at zero-cross
pwm_cycle_time: 0.100                 # slow soft-PWM; zero-cross switches per half-cycle, never fast

[verify_heater heater_bed]            # keep the runaway backstop; do NOT disable
max_error: 120
check_gain_time: 60
hysteresis: 5
heating_gain: 2
```

## 3. Fail-safe + mains safety
**Off when the Octopus is down (by topology):** MCU reset / power-loss / firmware_restart →
PA1 off → R1 pulls PMOS gate to 5 V → PMOS off → pin 2 = 0 V → LED dark → triac off. This is
exactly why the PMOS high-side stage is used and the "5 V→R→node, low-side shunts" trick is
rejected (that one fails *unsafe*: FET off at reset → LED gets full current → uncontrolled heat).

**#1 SAFETY ITEM — shorted-triac runaway (mains):** a triac SSR (T1635) fails **shorted** far
more often than open. If it fails closed, **Klipper cannot turn the ~1000 W / 8.3 A bed off** no
matter what `heater_pin` does, and `verify_heater` does NOT catch a shorted triac. Fit an
**independent, non-firmware thermal cutoff**: a bed thermal fuse / klixon in series with the AC
bed load (and/or a mains contactor Klipper can also drop). Non-negotiable for an AC bed.

**Bench checklist before any mains:**
1. Board unpowered: diode-check pin 2 → GND(1/3) to re-confirm pin 2 = LED **anode**. If it reads
   the opposite (anode→5 V, cathode→pin 2), drop the PMOS and use `heater_pin: !PA1` instead.
2. **Do NOT go looking for an on-board series resistor, and do NOT omit R2.** Settled by diode
   test 2026-07-15: pin2->pin3 reads 1.15 V clean, which is a BARE LED. The ~253 Ω limit lived on
   the stock mainboard, not on this board. Fitting the LED to 5 V without R2 destroys it.
3. Wire the PMOS stage with **R2 = 270 Ω**. Power the Octopus **only** (no mains on the bed).
   Command heat ON; verify ~15 mA into pin 2 (measure V across R2 → ~4 V = ~15 mA).
4. **Cut MCU power → confirm pin 2 = 0 V, LED dark.** Proves fail-safe before mains.
5. Everything stays on the isolated low-voltage side (EL3063 = 5000 Vrms). Never bridge the opto
   barrier; don't touch the T1635, the 1 µF X2 cap, the NTST10A 10 A fuse, or any AC copper.
6. One 5 V source (Octopus rail) feeds pin 4 + PMOS source; pins 1/3 = Octopus GND.
7. Verify the AC board's MB6S aux supply can't back-feed the 5 V rail from mains with the Octopus off.
8. Don't leave a scope/LA on pin 2 during operation (current-mode, back-drive sensitive).

## Capture results (2026-07-15, sigrok/PulseView, Ch0 on pin 2)
CONFIRMED live on the stock board:
- Polarity ACTIVE-HIGH: off = LOW (0 V), call-for-heat = HIGH -> `heater_pin` has NO `!`.
- PWM period = 100 ms (10 Hz) = Klipper default `pwm_cycle_time: 0.100`. Duty tracks PID:
  ~90% heating hard (H90.5/L9.5 ms), ~13-17% holding at target (H16.9/L83.1 ms).
- Pin 2 driver only SOURCES then RELEASES (does not pull low) -> off-state relies on no
  current, so a parasitic path (the LA, with pin 4 removed) latched the triac ON = the observed
  stuck-on. Hence R3 pull-down, and never leave a probe on pin 2 during operation.
STILL open: the pin-4 5 V dip under switching needs a SCOPE (the LA is digital-only) — or just
feed pin 4 from a stiff Octopus 5 V node rather than daisy-chaining.

## Verification verdicts
- Drive current (~3× IFT), no-`!` polarity, mains isolation, fail-safe-on-reset: **CONFIRMED**.
- Config thermal safety: **NEEDS the external thermal cutoff above** — the software config alone
  cannot protect against a shorted triac. That hardware cutoff is the fix.

## Open items to confirm on the bench
- pin 4 dip under load?  ·  thermistor port?

Settled during the 2026-07-15 build, no longer open: there is no on-board series resistor, so R2
stays and is 270 Ω. LED orientation is diode-confirmed, pin 2 anode and pin 3 cathode. The PMOS
part is an AO3401 class low-Vth device.
