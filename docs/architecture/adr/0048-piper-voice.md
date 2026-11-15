# ADR 0048 — A natural voice for spoken directions: Piper, kept loaded

- **Status:** Accepted (owner, 2026-11-15: "The voice used for navigation is
  very robotic. Can it be improved?"; ljspeech chosen by ear on the bench).
  `[BENCH]` with Piper installed on the bench Pi by hand; **not yet in the
  image** (see Consequences).
- **Date:** 2026-11-15
- **Refines:** [ADR-0039](0039-audio-manager.md) decision 9 (the voice:
  `speak-prompt`, Flite+hts_engine with cmu_us_arctic_slt).

## Context

Spoken directions (navigation, ADR-0040) go through audio-manager's `Speak`,
which runs `/opt/f250/libexec/speak-prompt`: Flite+hts_engine 1.06 with the
cmu_us_arctic_slt voice, an HMM voice from the 2010s. The owner finds it
robotic.

| Fact | Source | Status |
|---|---|---|
| Piper is maintained as OHF-Voice/piper1-gpl: v1.8.0 (2026-09-04), GPL-3.0; a C API, `libpiper` (`piper_create`, `piper_synthesize_start`/`_next`, `piper_free`), and a CLI | GitHub API and `libpiper/include/piper.h` at v1.8.0 | Verified |
| libpiper's CMake build fetches espeak-ng (commit `212928b3`, 2025-03-22) and Microsoft's prebuilt onnxruntime 1.22.0 for linux-aarch64 | `libpiper/CMakeLists.txt` at v1.8.0 | Verified |
| The macOS wheel of piper-tts 1.8.0 looks for espeak-ng data in its build machine's path and fails; the Linux aarch64 wheel works | the owner's Mac, 2026-11-15 | Tested |
| Voice licences (each voice's MODEL_CARD): ljspeech, kristin, john, norman public domain; joe CC0; ryan, hfc_male, hfc_female CC BY-NC-SA 4.0; lessac the Blizzard 2013 licence | rhasspy/piper-voices on Hugging Face | Verified |
| On the Pi 5 (AGL, kernel 6.18): loading en_US-ljspeech-medium takes 1.4 s; then "Turn left." 0.22 s, a one-sentence prompt about 0.85 s, two sentences (5.5 s of speech) 1.38 s; one thread (libpiper sets onnxruntime's intra-op threads to 1). Flite: 0.35 s | bench-log 2026-11-15 | `[BENCH]` |
| Run fresh for each prompt, Piper's CLI takes 1.6–2.9 s | bench-log 2026-11-15 | `[BENCH]` |

Navigation's near prompt comes about 8 s before the manoeuvre (an example
setting, `voice.rs`), so 1.5 s of loading on every prompt is too much.

## Decision

1. **Piper with en_US-ljspeech-medium** (public domain dataset), chosen by
   the owner from five voices with clean licences played through the DAC.
   `AUDIO_PIPER_VOICE` in `/etc/default/f250` names another voice in
   `/opt/f250/piper/voices`, or a path; `none` keeps Flite.
2. **The voice stays loaded in a service of its own,** `f250-tts.service`
   (`services/tts`, user f250, sandboxed, no network). `tts serve` loads
   the voice, then binds `/run/f250-tts/tts.sock`; for each request (the text,
   then the client's write side shut) it answers with a mono 16-bit WAV and
   closes. It is started with audio-manager and exits doing nothing when
   Piper or the voice isn't installed.
3. **`speak-prompt` asks it first** (`tts say --socket … --out …`) and plays
   the WAV with pw-play as before (media.role Speech-High, `exec` last, so
   audio-manager's cut-off still kills the player). With no socket, or a
   failed request, it uses Flite: a prompt is never lost to the new voice.
4. **libpiper is loaded at run time with dlopen** (libonnxruntime.so.1 first,
   global, since libpiper has no RUNPATH). The crate builds and tests on the
   Mac and in the image without Piper. This needs unsafe code, which the
   workspace forbids: `services/tts` alone sets `unsafe_code = "deny"`
   instead of inheriting `forbid`, and allows it only in `src/piper.rs` (the
   calls into libpiper) and one `poll(2)` in `src/server.rs`.
5. **Piper's tree is `/opt/f250/piper`**, libpiper's own CMake install
   layout (`lib/`, `share/espeak-ng-data/`) plus `voices/`.

## Alternatives considered

- **Piper's CLI per prompt.** No new code, but 1.6–2.9 s before each prompt.
- **Piper's CLI kept running, one line a prompt.** It prints each WAV's path
  through an unflushed stdout (stuck in the buffer when piped) and writes
  32-bit float WAVs with a placeholder length.
- **A Python service with ctypes.** The image has Python 3 with ctypes, but
  the daemons are Rust (ADR-0008) and built by `make deploy` and the image's
  recipe already.
- **Linking audio-manager to libpiper.** 110–170 MB and onnxruntime inside
  the service that runs the speakers and calls; a crash there takes the audio
  with it.
- **Kokoro** (82M parameters) is reported to sound better but to be several
  times slower than Piper on a Pi 5's CPU (secondary sources only, not
  tested here); a prompt has to come out within about a second.
- **Voices with non-commercial licences** (ryan, hfc_*): not offered, to keep
  the image's licences simple.

## Consequences

- Directions sound natural, about as quickly as Flite's: 0.8–0.9 s for a
  typical prompt through audio-manager on the bench. Flite stays in the image
  as the fallback.
- About 107 MB resident for the loaded voice; the voice file is 63 MB.
- **Licences:** Piper (libpiper) GPL-3.0; espeak-ng GPL-3.0-or-later (built
  in); onnxruntime MIT; ljspeech public domain. They are dynamically loaded by
  `tts`, which is never distributed.
- **The image doesn't carry Piper yet.** On the bench it was built in Docker
  (debian:trixie, aarch64) from v1.8.0 and copied to `/opt/f250/piper` by
  hand. Next: a meta-f250 recipe that builds libpiper with espeak-ng from a
  pinned fetch (the CMake ExternalProject can't fetch inside BitBake) and
  onnxruntime (prebuilt, or meta-oe's recipe if it has one), and installs
  the ljspeech voice with its checksum. Until then a reflash loses Piper and
  the voice falls back to Flite.
- `/proc/cpuinfo` must be readable: onnxruntime aborts without it, so the unit
  has no `ProcSubset=pid` (bench, 2026-11-15).
- Text normalisation is espeak-ng's: "US 36" was read acceptably on the bench;
  other road names are untested.

## Revisit if

- A prompt is noticeably late in the truck: then libpiper's thread count (1)
  or a smaller ("low") voice.
- A better offline voice runs within a second on the Pi 5.
