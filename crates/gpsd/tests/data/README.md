# gpsd test vectors

`gpsd-3.27.5-nmea-udp.jsonl` is gpsd's own JSON output, captured on the Mac
on 2026-11-11 **[SIM]**. gpsd 3.27.5 (Homebrew) is the version in the AGL
22.0.1 image. The input is synthetic NMEA from `synthetic_nmea.py`, not a
receiver:

- 5 s with no fix
- 8 s of a 3D fix moving north-east at 30 kn (15.433 m/s)
- 3 s of a 2D fix
- 3 s with no fix

To capture it again:

```bash
gpsd -N -n -S 2948 udp://127.0.0.1:5948 &
gpspipe -w localhost:2948 > capture.jsonl &
python3 synthetic_nmea.py 5948
```

What it shows, and the tracker handles:

- gpsd sends one TPV per NMEA sentence, each with what it knows so far. A TPV
  from a GGA sentence has no course (`track`).
- The speed gpsd works out between sentences (28.04 m/s) differs from the
  RMC's (15.433 m/s).
- The first 3D TPV has no `time`.
- Once the fix is lost, the TPVs have no `lat` or `lon`.

**UNVERIFIED:** what a real receiver sends through gpsd. No receiver has been
chosen yet (H11). A u-blox receiver in binary mode gives gpsd fuller cycles.
Capture one with `gpspipe -w` once it's fitted, and add it here.
