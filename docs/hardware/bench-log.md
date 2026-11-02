# Bench and installation log

Hardware evidence goes here: measurements, photos, `dmesg` and command output.
A feature is "hardware-tested" only when it has an entry here or in
[../diagnostics/VERIFICATION_LOG.md](../diagnostics/VERIFICATION_LOG.md).

## Entry template

```
## YYYY-MM-DD — <what was tested>

Hardware: <Pi 5 rev, HAT rev, cables, adapters>
Image: <Raspberry Pi OS / AGL 22.0.x prebuilt / meta-f250 @ git rev>
Setup: <config.txt lines, commands>

Result:
    <output / measurement>

Verdict: works | fails | partial — <what this does and does not prove>
Closes: <open-questions.md item, if any>
```

## Entries

## 2026-11-01 — OBDLink MX+ pairing method (reported by the owner)

Hardware: OBDLink MX+ `00:04:3E:85:EA:FC`
Setup: Bluetooth pairing with the MX+ (host device not recorded)

Result:
    A pairing passkey was displayed. It was not 1234, and nothing had to be
    entered to complete pairing.

Verdict: the MX+ uses Secure Simple Pairing (passkey shown / confirmed), not
the legacy fixed PIN commonly documented as 1234. This doesn't yet show which
SSP variant the Pi's BlueZ will negotiate; record the `bluetoothctl` transcript
in Phase 3.5.2.
Closes: nothing; it corrects the pairing step in PROJECT_PLAN.md 3.5.2.
