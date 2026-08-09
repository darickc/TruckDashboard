# Display plan

## Today

The exact display is not selected yet (target: 1.75" round AMOLED, ~466×466).
Therefore the firmware is display-agnostic:

- `lib/Display/src/IDisplay.h` — the only contract a renderer must satisfy:
  `begin()`, `render(const DisplaySnapshot&)`, `setPage(PageId)`.
- `DisplaySnapshot` is a **value copy** (channels + warnings + link state), so a
  renderer can be as slow as it likes without ever blocking the OBD task.
- `SerialDisplay` renders the pages as text on USB Serial and is the permanent
  bench/debug renderer.

Nothing in the OBD stack, warnings, or data model references any graphics type.

## Page model

| Page | Contents |
|---|---|
| 1 — ENGINE HEALTH | ECT, EOT, ECT/EOT delta, FICM V, ICP, IPR |
| 2 — DRIVETRAIN | Boost, trans temp, RPM, VGT, battery, load |
| 3 — LARGE GAUGE | one big value (boost) |

Warning levels (caution/critical/stale) ride along in the snapshot; a real
renderer should color values accordingly and may auto-switch to a warning page.

## Adding the real AMOLED later

1. Pick the panel and identify its controller (round 466×466 AMOLEDs commonly
   use SPI/QSPI controllers such as the CO5300 or SH8601 — verify for the actual
   part) and note the touch controller if any.
2. Add the display driver dependency (e.g. Arduino_GFX or LovyanGFX if the
   controller is supported, or the vendor's driver) to `platformio.ini`
   `lib_deps` — firmware env only.
3. Implement `AmoledDisplay : public IDisplay` in `lib/Display/src/`:
   - `begin()`: init bus + panel, clear screen
   - `render()`: draw the current page from the snapshot; internally throttle to
     the panel's comfortable frame rate; consider drawing to a small canvas and
     pushing, to avoid flicker
   - keep all drawing inside this class
4. Swap `SerialDisplay` for `AmoledDisplay` in `main.cpp` (one line, or keep
   both behind a config flag).
5. Rendering stays on the UI task. If drawing turns out heavy, raise
   `kUiTickMs`/frame throttle first; the OBD task is unaffected either way.

## Input / page navigation (future)

- Physical button (GPIO, debounced) and/or the panel's touch controller.
- Input handling belongs in the UI tick; it just calls `setPage()` / cycles
  `PageId`.
- Auto page switching on warnings: when `warnings.anyCritical` goes true, jump
  to the page showing the offending channel (page metadata mapping channel →
  page is a small addition to the page model).

## Memory note

466×466 @ 16 bpp is ~425 KB — a full framebuffer does NOT fit in ESP32 internal
RAM. Plan on partial/windowed redraws, or a board with PSRAM if a full
framebuffer is wanted. This constraint is one more reason the renderer is
isolated behind `IDisplay`.
