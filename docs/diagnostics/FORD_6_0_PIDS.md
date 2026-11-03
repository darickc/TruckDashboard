# Ford 6.0L Power Stroke PID reference (2007 F-250)

**Rule: nothing on this page is guessed.** Every Ford request/formula comes from
the owner's Torque Pro export ([`exportedPIDs.csv`](../../shared/signals/imports/torque/exportedPIDs.csv)). "Definition imported from
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

All are in the firmware PID table (`lib/ObdCore/src/PidDefs.cpp`). Header "Auto" =
adapter default functional request (7DF) — Ford DIDs are expected to answer
there, but that expectation is part of what on-truck verification confirms.
Unverified rows are disabled by default; verified ones are listed in
`config::kEnabledPids`.

| Parameter | Module (Torque) | Request/Header | Formula | Verified | Notes |
|---|---|---|---|---|---|
| Engine oil temp (EOT) | **PCM (7E8)** | `221310` / 7DF | (((A·256)+B)/100)−40 °C | Torque; tracks ECT 9–59 °C (2026-11-03), not yet promoted | TCM answers `7F 22 12`. Pinned `rx_id = 7E8` so a window holding only the TCM's refusal is one miss, not a 60 s quarantine. Needs a fully warm reading and a FORScan cross-check |
| FICM main power | Auto | `2209D0` / 7DF | ((A·256)+B)/256 V | Torque | healthy ≈ 48 V |
| Injection control pressure (ICP) | Auto | `221446` / 7DF | ((A·256)+B)·0.57 psi | Torque | |
| IPR duty cycle | Auto | `221434` / 7DF | A·13.53/35 % | Torque | |
| VGT duty cycle | Auto | `22096D` / 7DF | ((A·256)+B)·100/32767 % | Torque | |
| MAP | Auto | `221440` / 7DF | ((A·256)+B)·0.03625 psi | Torque | **absolute** pressure — boost is derived as MAP − baro in `Derived.cpp` |
| Exhaust back pressure (EBP) | Auto | `221445` / 7DF | ((A·256)+B)·0.03625 psi | Torque | |
| Trans fluid temp (method 1) | **TCM (7E9)** | `221674` / 7DF | ((A·256)+B)/8 °F | **VERIFIED 2026-08-09** | PCM answers `7F 22 31` (does not have the DID); TCM returns 130.4 F vs Torque 132.1 F. Pinned `expectedResponder = 7E9`. |
| Trans fluid temp (method 2) | **TCM** | `221674` / **TODO** | ((A·256)+B)/8 °F | superseded | method 1 already reaches the TCM via 7DF + `expectedResponder`; this row only matters if physical addressing turns out to work |
| Trans fluid temp (method 3) | header `C410F1` | `2211BD` / C410F1 | ((signed(A)·256)+B)·−0.0036+212.98 °F | Torque | KWP-style header — likely N/A on this CAN truck; kept verbatim |
| Trans temp (alt, not in table) | Auto | `221E1C` / 7DF | (((signed(A)·256)+B)·9/8+320)/10 °F | Torque | 4th option, in `PidDefs.cpp` reference comments |
| Transmission gear | Auto | `2211B3` / 7DF | A/2 | Torque | |
| Transmission gear (method 2) | **TCM** | `2211B3` / **TODO** | A/2 | TODO | |
| Battery voltage | Auto | `221172` / 7DF | A/16 V | Torque | |
| Fuel level | Auto | `2216C1` / 7DF | ((A·256)+B)/328 % | Torque | shown on the head-unit dashboard as UNVERIFIED. Not in the ESP32 table (reference comment only), so verify with `raw 2216C1`. SAE `01 2F` (A·100/255 %) is an alternative **only if** `raw 0120` reports PID 2F as supported |
| ICP **voltage** | — | **TODO** | **TODO** | TODO | not in the Torque export; find a FORScan/X-Gauge definition before implementing |

Additional imported-but-unused rows (misfire counters, CHT, FICM logic/vehicle
power, IAT2, throttle, tire pressures via header `726`, ABS values,
etc.) are preserved as reference comments at the bottom of `PidDefs.cpp`.

## Module addressing — TODO, verify on truck

Torque's symbolic headers do **not** reveal the OBDLink `ATSH` values. In the
firmware these modules have `nullptr` headers and any PID using them is refused
until filled in (in `moduleAtshHeader()`, `PidDefs.cpp`):

**Module identity is a separate question from module addressing, and the first
one is now answered.** 7E9 is the TCM: it owns `22 1674` (transmission fluid
temp) and the PCM rejects that DID with `7F 22 31`. Selecting a module does
**not** require its request header — `PidDefinition::expectedResponder` picks the
answer by response ID over the functional broadcast, which is how `TransTemp1`
works today. The `ATSH` headers below only matter for the throughput work
(physical addressing + the response-count digit).

| Module | Status | How to verify |
|---|---|---|
| PCM physical | TODO (likely `7E0` req / `7E8` resp per ISO 15765-4, but confirm) | see procedure below |
| TCM | TODO — identity confirmed (7E9 responds), request header not. `ATSH 7E1` was tried and **both** modules answered, so it appears not to take effect while the protocol is on AUTO. Retest with `ATSP6` pinned. | see procedure below |
| ABS | TODO | see procedure below |
| `726` | literal from export (TPMS rows) | works as-is once tested |
| `C410F1` | literal from export | KWP-style 3-byte header; probably not applicable on CAN |

### Verification procedure (bench/driveway, engine running)

Run it from the [serial console](../esp32/CONSOLE.md) — no reflash per PID.

1. `pio run -e esp32dev -t upload && pio device monitor`, then `log raw on`.
2. `probe <pid> 10`. Each attempt prints **which CAN ID answered**, the raw
   payload, the decoded value and the latency. Two modules answering is flagged;
   two modules *disagreeing* is flagged loudly.
3. Compare against an independent reference. In descending order of strength:
   - a multimeter (battery voltage) — independent of the whole OBD stack;
   - agreement with an already-verified SAE PID (MAP vs `0133` baro at idle,
     EOT vs `0105` ECT on a cold engine);
   - physical plausibility with the reasoning written down (FICM ≈ 48 V running,
     ICP ≈ 500–600 psi at warm idle);
   - Torque/FORScan on a phone **(one at a time — the MX+ accepts a single
     Bluetooth master)**. Note that Torque uses the same definitions imported
     here, so agreement proves the transport works, not that the definition is
     right. It is a sanity check, not the reference.
4. If the response is `NO DATA` on the functional header, the DID may need
   physical addressing. Try a candidate — as an experiment, not an assumption:
   `hdr pcm 7E0` (add `7E8` as a filter only if something else still answers),
   then `probe` again. `hdr clear` takes it back; overrides die on reboot.
5. When the value holds up, record the evidence in
   [VERIFICATION_LOG.md](VERIFICATION_LOG.md), set `verified=true` in
   `PidDefs.cpp`, and update this table's Verified column with the date.
6. If two modules answered with different values, also set `expectedResponder`
   to the CAN ID that proved to own the DID — otherwise the reading is a race.

## Not available from the PCM at all

These must come from added hardware (see `lib/Sensors/`); do not fake them:

- **Low-pressure fuel pressure** — external transducer.
- **EGT** — thermocouple + amplifier (pre-turbo).
