# Signal calibration

Some readings are reported correctly by the truck but are consistently wrong
for this truck. The usual case is **vehicle speed on a different tire size.**
The PCM computes speed from the tire size programmed into it, so on bigger or
smaller tires every reading is off by the same ratio.

The head unit corrects this with a per-signal calibration:

```
displayed = raw × scale + offset
```

- Configured in [`apps/infotainment/assets/config/calibration.json`](../../apps/infotainment/assets/config/calibration.json).
- Adjustable live under **Diagnostics → Developer → Speed calibration**.
- Applied before range checks, warnings and computed signals, so everything
  downstream uses the corrected value.
- Visible in **Diagnostics → Signals**: the source column shows the factor, for
  example `SAE ×1.035`.
- **Read-only:** nothing is written to the truck (see
  [ADR-0007](../architecture/adr/0007-read-only-vehicle-access.md)).

## Measuring the speed factor

**What you need:** a GPS speed reference, such as a phone GPS speedometer app,
or later this head unit's own GPS (Phase 6). Use a straight, flat road.

1. Open **Diagnostics → Developer**. The calibration row shows
   `Truck reports X → shown Y`.
2. Hold a steady speed on cruise control. Use a high speed, since that makes
   the ratio more precise: at 60 mph, a 1 mph reading error is under 2 %.
3. Once the GPS speed has been steady for a few seconds, write down both
   numbers. **Use the "Truck reports" number, not the "shown" one.**
4. Work out:

   ```
   scale = GPS speed ÷ truck-reported speed
   ```

   For example: GPS 60 mph, truck reports 57 mph, so scale = 60 ÷ 57 = **1.0526**.
5. Repeat once or twice, ideally at a different speed. The results should
   agree to within about 0.5 %. If they don't, the error isn't a simple ratio;
   record the readings and investigate before trusting a single factor.
6. Make the factor permanent. Edit `calibration.json`:

   ```json
   "speed": { "scale": 1.0526, "offset": 0, "note": "GPS 60 vs 57 mph, 2026-11-02" }
   ```

   Rebuild or redeploy the app. The live buttons (±0.1 %, ±1 %) are for fine
   adjustment while driving. **They last only until the app restarts.** The
   app says so whenever the live value differs from the configured one.

From tire sizes, if both are known exactly:
`scale = programmed revolutions per mile ÷ actual revolutions per mile`, which
is the same as `actual diameter ÷ programmed diameter`. Measured GPS data beats
catalogue numbers, because tread wear and pressure both change the real
diameter.

## Before you rely on it

- If the PCM's speed is off, then so are the factory **speedometer, odometer**,
  and the transmission's speed-based shift scheduling, because they all use the
  same tire setting. The root-cause fix is to reprogram the tire size in the
  PCM, for example with FORScan. That is a module write, which this project
  deliberately never does; it's yours to do with the proper tool. After
  reprogramming, set the scale back to `1.0`.
- The ESP32 firmware (`firmware/esp32`) does **not** apply this calibration.
- Phase 3 moves calibration into the signal registry and the gateway, so the
  recorder logs corrected values. The raw value travels with every sample, so
  a wrong factor can be fixed afterwards.

## Allowed range

`scale` must be between 0.5 and 2.0. Anything outside that is treated as a
typo (for example 10.5 instead of 1.05), and the app refuses to start with it.
