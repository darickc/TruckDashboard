# ADR 0034 — Screens are reached from Home and left by Back; Power and Restart move to Settings

- **Status:** Accepted (owner). [SIM] only: widget tests at 800×480. Not
  yet seen on the Pi's panel
- **Date:** 2026-11-11
- **Refines:** [ADR-0029](0029-settings-screen.md) decision 1 (the Settings
  tab), [ADR-0016](0016-stage1-sideload-layout.md) decision 6 (the Power
  button's exit status)

## Context

The dashboard had a row of eight tab buttons along the bottom of the screen
(Home, Gauges, Media, Nav, Cameras, Settings, Diagnostics, Power), 64 px
high, on every screen. Home showed four gauges, a vehicle-health panel and
three shortcuts. The owner wants a simpler head-unit layout: Home is just
buttons to the other screens, each screen has Back at its top left, and the
Power button lives in Settings beside a new Restart.

## Decision

1. **No bottom bar.** The screen area runs from under the alert banner to
   the bottom of the panel.
2. **Home is a 3 × 2 grid of large buttons**: Gauges, Media, Nav, Cameras,
   Settings, Diagnostics (`lib/ui/screens/home_screen.dart`). Each is
   256 × 206 px (256 × 180 under an alert), well above the 60 px minimum.
3. **Back at the top left of every other screen**, in a 60 px header with
   the screen's name (`lib/ui/shell/screen_header.dart`; since the
   [amendment](#amendment-back-in-the-status-bar-2026-11-11), Back is in the
   status bar). Screens are a
   stack whose bottom is always Home (`ScreenHistory` in
   `lib/ui/app_scope.dart`): Back pops one, and a screen already in the
   stack is returned to rather than stacked twice, so Back never cycles.
   **Home beside Back** only when Back would go somewhere other than Home,
   that is, on a screen opened from another screen. No screen opens another
   today; the stack and the header handle it when one does.
4. **Power and Restart on Settings**, at the right of the section buttons,
   shown only when the launcher allows them (`F250_POWER_OFF=1`, as
   before). Each asks first: the question takes the row's place for 8 s
   with Cancel and the action, in place rather than as a dialog, so the
   alert banner stays visible.
5. **Restart is exit status 43**, beside Power's 42
   (`lib/core/power.dart`). On AGL the dashboard unit treats both as success
   (`SuccessExitStatus=42 43`) and `dashboard-stopped` runs
   `systemctl reboot --no-block` for 43, as it runs
   `systemctl poweroff --no-block` for 42. On Raspberry Pi OS
   `tools/pi/run.sh` stops the recorder and gateway, then reboots.

## Consequences

- Every screen but Home gives up a 60 px header plus an 8 px gap for the
  64 px bar it no longer has: 4 px less height than before.
- Reaching another screen takes two taps (Back, then its button) instead of
  one. The owner chose this for a calmer screen.
- Home no longer shows gauges or the vehicle-health summary. Alerts still
  show above every screen, Home included; the gauges are one tap away.
- `make agl-test` checks that the app, `dashboard-stopped`, the unit and
  `run.sh` agree on 42 and 43.

## To verify on the Pi

1. Home's buttons and Back respond to touch on the 7" panel (agl.md check 3).
2. Settings → Restart → Restart: the Pi reboots, and after the reboot
   `journalctl -b -1 -u f250-dashboard` shows "restart: requested from the
   dashboard" (agl.md check 7).

## Amendment: Back in the status bar (2026-11-11)

The owner wants Back at the very top of the screen, level with the clock,
and the link status centred. Decision 3 changes:

- **Back is at the status bar's left**, 12 px from the panel's edge
  (`lib/ui/shell/nav_buttons.dart`). There is no header row and no screen
  title: the screen starts right under the status bar and the alert banner.
- **The status bar is 60 px high** outside camera mode, Home included, so
  Back is a full touch target and the clock doesn't move between screens.
  Camera mode keeps it 44 px high: it has no Back, and the camera's window
  sits right under it (`kStatusBarHeight`).
- **The data source and link status are centred** on the panel. The scenario
  name follows Back at the left. The REC, map and camera chips and the clock
  are at the right, and the chips shorten rather than overflow.
- **Home beside Back is a 60 × 60 house**, without the word, so Back, Home
  and the centred link status fit on one row.

Every screen but Home gains 52 px of height: the 60 px header and its 8 px
gap are gone, and the bar is 16 px taller. Home loses 16 px, so its buttons
are 256 × 198 (256 × 172 under an alert; 256 × 167 since the banner grew
for Clear, [ADR-0036](0036-clear-advisories.md)). [SIM]: widget tests at 800×480.
Checked on the bench Pi's panel: see the bench log.


## Amendment: Phones on Home, Diagnostics in Settings (2026-11-14)

The owner wants a phone button on Home and Diagnostics moved to Settings.
Decision 2 changes:

- **Home has a Phone button** (the Phone screen: contacts, recent calls, a
  keypad and the paired phones, [ADR-0045](0045-phone-calls.md)'s second
  amendment; a smartphone icon, as on Media's Phones button, which stays and
  opens the paired phones). Home is still 3 × 2: Gauges, Media, Nav,
  Cameras, Phone, Settings.
- **Diagnostics opens from Settings**: a button after the four sections
  (Display, Cameras, Speakers, Units), left of Restart and Power. It opens
  the Diagnostics screen rather than being a fifth section, so Diagnostics
  keeps its full height and its own section row. Back returns to Settings,
  with Home beside it (decision 3). It is 150 px wide, enough for its icon
  and word at full size.
- **Restart and Power are icons** (72 × 60 each; decision 4 otherwise
  unchanged: each still asks first, in words). With their words, on the
  bench Pi's font (DejaVu Sans Bold) the row had no room for a fifth
  button: Diagnostics' word was scaled down until it was unreadable, and
  Cameras and Speakers touched their edges. Words for all seven do not fit
  in 800 px.

[SIM]: widget tests at 800×480 (`navigation_test.dart`). [BENCH]: on the
bench Pi's panel, see the bench log (2026-11-14).


## Amendment: a live line on each Home button (2026-11-18)

The owner approved Home "live tiles" from a design review (a Claude Design
canvas, 2026-11-18). Decision 2's grid stays 3 × 2 with the same six buttons;
each button now says what the screen it opens would show, so a glance at Home
answers the usual question without opening it. Each whole button is still one
touch target that opens its screen; nothing inside it is tappable.

Each button has an icon in a tinted square, its name, a status line (and a
second, dimmer one where useful), and a chip at the top right:

| Button | Chip | Line(s) |
|---|---|---|
| Gauges | NORMAL / ADVISORY / CRITICAL / CONNECTING / NO DATA | the first alert's title when there is one, then the selected gauge profile's first two tiles ("EOT 198 °F · ECT 190 °F") |
| Media | PLAYING / PAUSED / STOPPED / OFFLINE | track and artist, or why nothing plays |
| Nav | ROUTE / ROUTING / ARRIVED / NO ROUTE, else GPS FIX / NO FIX / GPS STALE / NO GPS | "To <destination>"; no route: "No route · Places, Search" |
| Cameras | REC / NOT REC (SIM in front with the simulated camera-manager) / OFFLINE | which cameras record, or which set to record don't |
| Phone | CONNECTED / CALL / BLUETOOTH OFF / OFFLINE | the connected phone, or why there is none |
| Settings | — | the theme and its brightness, and "Diagnostics" |

Rules it keeps:

- **No value that isn't current** (CLAUDE.md rule 4): a gauge readout that
  isn't current shows as "—" on Home, not its last reading; Home has no room
  for the age and hatch the Gauges screen shows. Nav shows the destination
  only, never distances: whether guidance is current is the Nav screen's to
  judge.
- **Simulated stays marked**: SIM on the camera and GPS chips with simulated
  sources; the status bar's SIMULATED badge covers the vehicle data.
- **Alerts still show in the banner above Home**; the Gauges chip repeats
  only the worst level, so the banner stays the one place to read and clear
  them.
- Which two readouts Gauges shows follows `gauge_profiles.json` (the
  selected profile's first two tiles), so no signal is chosen in code.

The derivations are plain functions (`gaugesStatus`, `mediaStatus`,
`navStatus`, `camerasStatus`, `phoneStatus`, `settingsStatus` in
`lib/ui/screens/home_screen.dart`). [SIM]: `test/widget/home_test.dart` (each
state of each button; Gauges through the simulator, including the EOT/ECT
freeze) and the existing layout and touch-target tests at 800×480, with and
without an alert. Not yet on the bench Pi's panel.
