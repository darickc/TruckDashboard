# Torque Pro PID import

How the definitions in `exportedPIDs.csv` (Torque Pro custom PID export) become
firmware PID table rows.

## Column mapping

| CSV column | Firmware field | Notes |
|---|---|---|
| `Name` / `ShortName` | `PidDefinition::name` / `shortName` | `[FORD]` prefix dropped |
| `ModeAndPID` | `service` + `pid` | **Split, never treated as one SAE PID**: `0x221310` ⇒ service `0x22` (UDS read-by-identifier), DID `0x1310`. `0x0105` ⇒ service `0x01`, PID `0x05`. |
| `Equation` | `LinearDecode{byteOffset,width,isSigned,scale,bias}` | folded by the generator (below) |
| `Units` | `Unit` enum | decoder output unit; converted to the channel's display unit on store |
| `Header` | `ObdModule` enum | see header rules below |
| `Min/Max Value`, `scale` | (unused) | Torque display hints |
| `startDiagnostic`/`stopDiagnostic` | (unused) | empty in this export |
| `minimumRefreshDelayMillis` | (unused — all 0) | firmware poll intervals are set per-PID in the table |

## Header rules (important)

Torque's `Header` column is **not** an OBDLink `ATSH` value when it's symbolic:

- `Auto` → `ObdModule::Auto` → adapter default functional request header
  (`7DF`, ISO 15765-4 standard — the one thing safely assumed).
- `TCM`, `ABS` → `ObdModule::Tcm` / `Abs` → **ATSH unknown (`nullptr`)**. The
  firmware refuses to send these until the real header is verified on the truck
  (see [FORD_6_0_PIDS.md](FORD_6_0_PIDS.md)). Never invented.
- `726`, `C410F1` → literal headers, preserved verbatim
  (`ObdModule::Hdr726` / `HdrC410F1`).

## Equation folding

`scripts/gen_pids.py` reduces each Torque equation to `value = raw·scale + bias`:

- `A` alone ⇒ 1-byte field at offset 0 (`B`/`C`/`D` ⇒ offsets 1/2/3)
- `(A*256)+B` (or `(256*A)+B`) ⇒ 2-byte big-endian field at offset 0
- `signed(A)` ⇒ `isSigned = true` (two's-complement decode)
- constants are folded numerically and checked for linearity at three points
- anything non-linear — notably `BARO()` in the Ford boost equation — is flagged
  `// MANUAL:` and **excluded**. Boost is a *derived* value
  (`Derived.cpp`: boost = MAP − barometric from SAE `0133`), because the DID
  `1440` reading is absolute pressure, not boost.

Example: EOT `(((A*256)+B)/100)-40` ⇒ `{offset 0, width 2, unsigned, scale 0.01, bias −40}`.

## Workflow

```bash
python3 scripts/gen_pids.py exportedPIDs.csv
```

prints three sections:

1. **Active rows** — for the curated allowlist inside the script (the 6.0L
   gauges this project targets), ready to paste into `PidDefs.cpp`.
2. **Manual-attention rows** — non-linear/unmappable, listed with reasons.
3. **Reference comments** — everything else in the export, kept as comments at
   the bottom of `PidDefs.cpp` for future use.

The script runs **once per import**; its output is hand-reviewed and committed.
It is not a build step, and the generated rows always start `verified=false` —
"Torque says so" is the definition source, the truck is the verifier.

## What "verified from Torque" does and does not mean

- ✔ The DID and scaling were in daily use in Torque on this truck — the
  *definition* is trustworthy.
- ✘ It does **not** prove which module answers, on which header, through the
  OBDLink, from this firmware's request path. That's the on-truck verification
  step, one PID at a time with `kLogRawObdTraffic = true`.
