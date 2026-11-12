# ADR 0036 — Advisories can be cleared from the alert banner; critical alerts can't

- **Status:** Accepted (owner asked, 2026-11-11). [SIM]: widget tests at
  800×480. [BENCH]: seen on the bench Pi 5's panel (bench-log 2026-11-11).
- **Date:** 2026-11-11
- **Refines:** Phase 2.4 (the alert banner "that can't be dismissed"),
  [ADR-0027](0027-front-and-rear-recording.md) decision 9 (the recording
  advisory)

## Context

The alert banner above every screen showed the most important active alert
until its condition cleared. A known, lasting problem, such as a rear camera
that isn't plugged in, then took the banner for good. The owner asked to be
able to clear notifications like "Rear camera not recording".

Clearing anything can hide something that matters. The safety assumptions
say critical alerts are visible on every screen
([assumptions.md](../../safety/assumptions.md)).

## Decision

1. **Advisories have a Clear button** at the banner's right, a 120 × 60 px
   touch target. The banner is now 62 px high (the target and its 2 px
   border), up from 52.
2. **Critical alerts have none**, and `ClearedAlerts.clear` refuses them:
   engine warnings, "Vehicle data lost", "Not polling the truck". A cleared
   advisory that turns critical is a different alert and shows.
3. **A cleared advisory stays hidden while it lasts**, on every screen,
   matched by its level and title (not its detail, which can change while
   the problem lasts). It shows again if it comes back after being gone for
   30 s (`kForgetClearedAfter`). Shorter gaps count as the same problem:
   camera-manager retries a camera every 10 s, and the advisory drops out
   while it tries.
4. **Nothing is saved.** After a dashboard restart every active advisory shows
   again.
5. **Only the banner is cleared.** The status bar's chips still say what's
   wrong ("NOT RECORDING: REAR"), and the "+N more" count leaves out the
   cleared ones.
6. **No Clear in camera mode**: the banner there is the status bar's 44 px,
   less than a touch target. An advisory cleared elsewhere stays cleared there.

## Consequences

- Every screen loses 10 px of height while an alert shows. Home's buttons
  under an alert are 256 × 167.
- A driver can clear a recording advisory and forget the camera isn't
  recording. The REC chip still says so, and a restart shows it again.
- `apps/infotainment/test/widget/alert_clear_test.dart` covers clearing,
  coming back, the retry gap, critical alerts and camera mode.
