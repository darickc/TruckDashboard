# Ford 6.0L Power Stroke PID reference (2007 F-250)

**Rule: nothing on this page is guessed.** Every Ford request/formula comes from
the owner's Torque Pro export (`exportedPIDs.csv`). "Definition imported from
Torque" and "verified on this truck" are different claims — the `Verified`
column below means *confirmed against the actual truck with a known-good tool*.
Unknowns are marked **TODO**, not filled in.

## Verification status legend

- **SAE** — published J1979 formula; trusted as-is.
- **Torque** — imported from the Torque export; formula trusted, but response,
  module addressing, and scaling must still be confirmed on the truck.
- **TODO** — missing information; do not use until resolved.

## Generic SAE Mode 01 (verified formulas)

| Parameter | Module | Request/Header | Formula | Verified | Notes |
|---|---|---|---|---|---|
| Engine RPM | functional (7DF) | `010C` | ((A·256)+B)/4 rpm | SAE | milestone-1 signal, enabled by default |
| Vehicle speed | functional (7DF) | `010D` | A km/h | SAE | |
| Engine coolant temp | functional (7DF) | `0105` | A−40 °C | SAE | |
| Barometric pressure | functional (7DF) | `0133` | A kPa | SAE | input for derived boost; enabled by default |
| Engine load | functional (7DF) | `0104` | A·100/255 % | SAE | |

## Ford enhanced (service 22) — imported from Torque export

All are in the firmware PID table (`lib/ObdCore/src/PidDefs.cpp`), **disabled by
default**, `verified=false`. Header "Auto" = adapter default functional request
(7DF) — Ford PCM DIDs are expected to answer there, but that expectation is part
of what on-truck verification confirms.

| Parameter | Module (Torque) | Request/Header | Formula | Verified | Notes |
|---|---|---|---|---|---|
| Engine oil temp (EOT) | Auto | `221310` / 7DF | (((A·256)+B)/100)−40 °C | Torque | |
| FICM main power | Auto | `2209D0` / 7DF | ((A·256)+B)/256 V | Torque | healthy ≈ 48 V |
| Injection control pressure (ICP) | Auto | `221446` / 7DF | ((A·256)+B)·0.57 psi | Torque | |
| IPR duty cycle | Auto | `221434` / 7DF | A·13.53/35 % | Torque | |
| VGT duty cycle | Auto | `22096D` / 7DF | ((A·256)+B)·100/32767 % | Torque | |
| MAP | Auto | `221440` / 7DF | ((A·256)+B)·0.03625 psi | Torque | **absolute** pressure — boost is derived as MAP − baro in `Derived.cpp` |
| Exhaust back pressure (EBP) | Auto | `221445` / 7DF | ((A·256)+B)·0.03625 psi | Torque | |
| Trans fluid temp (method 1) | Auto | `221674` / 7DF | ((A·256)+B)/8 °F | Torque | try first |
| Trans fluid temp (method 2) | **TCM** | `221674` / **TODO** | ((A·256)+B)/8 °F | TODO | blocked on TCM header (below) |
| Trans fluid temp (method 3) | header `C410F1` | `2211BD` / C410F1 | ((signed(A)·256)+B)·−0.0036+212.98 °F | Torque | KWP-style header — likely N/A on this CAN truck; kept verbatim |
| Trans temp (alt, not in table) | Auto | `221E1C` / 7DF | (((signed(A)·256)+B)·9/8+320)/10 °F | Torque | 4th option, in `PidDefs.cpp` reference comments |
| Transmission gear | Auto | `2211B3` / 7DF | A/2 | Torque | |
| Transmission gear (method 2) | **TCM** | `2211B3` / **TODO** | A/2 | TODO | |
| Battery voltage | Auto | `221172` / 7DF | A/16 V | Torque | |
| ICP **voltage** | — | **TODO** | **TODO** | TODO | not in the Torque export; find a FORScan/X-Gauge definition before implementing |

Additional imported-but-unused rows (misfire counters, CHT, FICM logic/vehicle
power, fuel level, IAT2, throttle, tire pressures via header `726`, ABS values,
etc.) are preserved as reference comments at the bottom of `PidDefs.cpp`.

## Module addressing — TODO, verify on truck

Torque's symbolic headers do **not** reveal the OBDLink `ATSH` values. In the
firmware these modules have `nullptr` headers and any PID using them is refused
until filled in (in `moduleAtshHeader()`, `PidDefs.cpp`):

| Module | Status | How to verify |
|---|---|---|
| PCM physical | TODO (likely `7E0` req / `7E8` resp per ISO 15765-4, but confirm) | see procedure below |
| TCM | TODO | see procedure below |
| ABS | TODO | see procedure below |
| `726` | literal from export (TPMS rows) | works as-is once tested |
| `C410F1` | literal from export | KWP-style 3-byte header; probably not applicable on CAN |

### Verification procedure (bench/driveway, engine running)

1. In `Config.h`: enable exactly one candidate PID, set `kLogRawObdTraffic = true`.
2. Flash, watch the monitor: every `TX>` / `RX<` line is printed.
3. Compare the decoded value against Torque/FORScan on a phone **(one at a time —
   the MX+ only accepts one Bluetooth master)**.
4. If the response is `NO DATA` on the functional header, the DID may need
   physical addressing. Documented next step: try `ATSH 7E0` (+ `ATCRA 7E8`) for
   the PCM and re-request — as an experiment, not an assumption.
5. When the value tracks the reference tool, set `verified=true` in
   `PidDefs.cpp` and update this table.

## Not available from the PCM at all

These must come from added hardware (see `lib/Sensors/`); do not fake them:

- **Low-pressure fuel pressure** — external transducer.
- **EGT** — thermocouple + amplifier (pre-turbo).
