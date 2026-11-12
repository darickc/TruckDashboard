# ADR 0040 — Saved places and spoken directions, in services/navigation

- **Status:** Accepted. [SIM] only:
  - the places store, the prompt scheduler, the service and the dashboard are tested (`make test`);
  - navigation ran on the Mac with the simulated receiver and the real Valhalla 3.9.1 (Docker, Kansas data): prompts
    came from Valhalla's own words for that route, and the destination went into the recent places;
  - **nothing on the Pi.** The bench Pi wasn't reachable on 2026-11-12, and **no prompt has been heard there**: the
    Pi has no speech engine in its image and no audio path for navigation yet (decision 15).
- **Date:** 2026-11-12
- **Refines:** [ADR-0035](0035-routing-with-valhalla.md) (its "no voice prompts … or saved places") and
  [ADR-0038](0038-offline-address-search.md) (its "no saved places and no recent searches"). Phase 6.5.2.
- **Depends on:** ADR-0039 (services/audio-manager, written in a parallel session on its own branch, not linked
  here until both are merged) for playing prompts and pausing the music around them (decision 16). Not connected
  yet.

## Context

Routing gives a destination by long-press or by search. The owner goes to
the same few places, and wants to get there in one or two taps: Home,
favourites with names, and the places routed to lately. Turn-by-turn guidance
is only on the screen; a driver should hear the next turn instead of reading
it.

Valhalla already writes the words. Its 3.9.1 answer (the test vector in
`services/navigation/tests/data/`, a real answer) has for each maneuver:

| Field | Example |
|---|---|
| `verbal_transition_alert_instruction` | "Turn right onto US 36." |
| `verbal_pre_transition_instruction` | "Turn right onto US 36, US 281." / "Turn left. Then You will arrive at your destination." |
| `verbal_post_transition_instruction` | "Continue for 19 kilometers." (absent on some, e.g. an exit) |
| `verbal_multi_cue` | true when the pre-transition words include the next maneuver ("Then …") |

The distances in them follow the request's units (kilometres, which the
guide's parser requires), so they can't be spoken as they are to an owner
who reads miles.

## Decision

### Saved places

1. **navigation keeps them**, in one JSON file (`places.json`), and serves
   `f250.nav.v1.PlacesService` (`shared/proto/f250/nav/v1/places.proto`):
   `ListPlaces`, `SavePlace`, `RenamePlace`, `DeletePlace`, each answering
   with all the places. The dashboard only talks to the service (CLAUDE.md
   rule 5).
2. **Kinds and limits:** one Home (saving another replaces it), favourites
   with a name (at most 50: more are refused, "delete one first"), and the
   recent destinations (10, newest first: the oldest drops). Names are at
   most 40 characters. These are sizes for an 800×480 list, not safety
   values.
3. **Recents come from routing.** `SetDestination` takes an optional `name`
   and `detail` (added compatibly, fields 2 and 3); every one adds a recent
   place, or moves one within 50 m to the top. Guidance carries the name
   back (`destination_name`), so the route can be saved under it.
4. **Where:** `/var/lib/f250/storage/navigation/places.json`. With
   `DATA_DRIVE=1` and nothing mounted at `/var/lib/f250/storage`, navigation
   uses `/var/lib/f250-nav/places.json` (its systemd `StateDirectory`, on the
   SD card) instead and the screen says "Kept on the SD card: the data drive
   isn't mounted, so places saved now stay there". It doesn't write under
   `storage/` then, because a drive mounted later would hide that file. With
   `DATA_DRIVE=0`, `storage/` is on the SD card anyway, like the map. The
   check is made at start (`navigation-start`, `--places-drive`).
5. **Written atomically:** a temporary file in the same directory, `fsync`,
   `rename`, then `fsync` of the directory. A change that can't be written
   is undone in memory and refused with the reason.
6. **Never fatal:**
   - a file that isn't a places file, or isn't JSON, is renamed
     `places.json.bad` and reported ("…kept as places.json.bad and a new
     list started");
   - a file from a newer format version is left untouched and the places
     are read-only;
   - entries that make no sense (a latitude of 200, a duplicate id, a
     favourite without a name) are dropped and counted;
   - a file that can't be read at all (permissions, I/O) makes the places
     read-only, so nothing overwrites it.

   The Places panel shows any such problem first.
7. **No timestamps.** The Pi has no clock source in the truck (ADR-0035),
   so recents are kept in order rather than by time.
8. **On the Nav screen:**
   - **Places** (bottom left, when there's no route) opens the list;
   - each place has **Route here** (one tap) and **Edit**, which opens the
     editor with **Delete** (two taps), and for a renamed place **Save**;
   - **Save** appears on a map pin (long-press or Show), on each search
     result (a star), and with the route (the destination);
   - the editor names the place on the same on-screen keyboard as search,
     with every action in the field's row, so it fits under the alert banner.

   Typing while moving isn't locked out, as for search (the owner's decision,
   2026-11-12, [assumptions](../../safety/assumptions.md#driver-distraction)):
   the editor says "The truck is moving: type only when parked" above 8 km/h,
   an example. A refused save hides the keyboard so its reason shows.

### Spoken directions

9. **navigation decides what to say** (`services/navigation/src/voice.rs`),
   because only it knows whether the fix is current. A pure `Prompter` is
   shown the guide's state after every update and returns at most one
   prompt:
   - **start:** a new route's first instruction, Valhalla's
     pre-transition words ("Drive south. Then turn right onto East 1st
     Street."), only while still near the start;
   - **approaching:** "In half a mile, turn right onto US 36.", Valhalla's
     alert words with the distance composed in the configured units;
   - **at the maneuver:** Valhalla's pre-transition words. With
     `verbal_multi_cue`, the next maneuver gets no approaching prompt of its
     own;
   - **continue:** right after a maneuver, when the next is beyond the
     approaching distance: "Continue on US 36 for 12 miles." (Valhalla's
     words up to "for", then the distance from here);
   - **rerouting:** "Off the route. Finding a new one." when the guide asks
     for a new route, then "New route.";
   - **arrival:** Valhalla's arrival words.
10. **When:** the approaching prompt comes 30 s ahead at the current speed,
    kept between 400 m and 2,500 m. The at-the-maneuver prompt comes 8 s
    ahead, between 50 m and 300 m. An approaching or continue prompt waits
    4 s after another; the at-the-maneuver prompt never waits. These are
    **examples to tune on the truck** (CLAUDE.md rule 10), as flags
    (`--voice-far-s`, `--voice-far-min-m`, …). Distances are spoken in miles
    and feet, or metric with `NAV_VOICE_UNITS=metric`. The dashboard's unit
    setting isn't passed to navigation yet.
11. **Never from stale guidance** (rule 4). Every prompt needs progress the
    guide computed from a current fix in that same update. A prompt that
    came due while the fix was stale is not said late with old distances: a
    maneuver passed during an outage is never announced, and arrival is
    announced only from a current fix.
12. **Mute** is `RouteService.SetVoice` and a toggle with the route's
    buttons ("Voice", "Muted", or "No audio" when prompts only reach the
    log). Muted, prompts are still worked out but not spoken, so unmuting
    doesn't replay old ones; muting stops a prompt being spoken. The setting
    is kept (`voice.json`, next to the places) across restarts. `Guidance.voice`
    reports it, where prompts go, and the last prompt.
13. **Speech goes through a small trait**, `Speaker`: `speak(text)` (a newer
    prompt cuts off an older one), `stop()`, `status()`. Implementations
    today:
    - `LogSpeaker`, **the default**: prompts go to the journal, and the
      screen says "No audio";
    - `CommandSpeaker`: any program that speaks its last argument
      (`NAV_VOICE_COMMAND`, `--voice-command`). On the Mac, `make sim
      VOICE=say` uses macOS's `say`; without `VOICE` prompts go to the log.

### The speech engine on the Pi

14. **The candidate is Flite, not espeak-ng or Piper.** Checked on
    2026-11-12 in the project's own Vimba 22.0.1 tree (the build VM) and on
    the web:

    | Engine | In the Vimba 22.0.1 layers | Licence | Size on the Pi | Status |
    |---|---|---|---|---|
    | **Flite 1.06 + hts_engine** (`meta-agl-demo/recipes-multimedia/flite`, with `flite-voicedata` 1.05, the CMU ARCTIC "slt" HTS voice) | **Yes**, and already built in this tree's sstate. AGL's own demo navigation (`ondemandnavi`) speaks with it | BSD-3-Clause; voice CC-BY-3.0 | flite 0.9 MB + voice 1.7 MB + hts-engine 0.13 MB (pkgdata `PKGSIZE`) | V (recipes and sizes in the tree); not in our `agl-f250` image; never run on the Pi |
    | Flite 2.2 (`meta-multimedia/recipes-multimedia/flite/flite_2.2.bb`) | Yes | BSD-3-Clause | Not built here | V (recipe); unmeasured |
    | eSpeak (`meta-oe/recipes-support/espeak/espeak_1.48.04.bb`) | Only the old eSpeak 1.48.04, which pulls in PortAudio | GPL-3.0-only | Not built here | V (recipe) |
    | espeak-ng 1.52 | **No recipe** in this meta-openembedded checkout | GPL-3.0-or-later | — | V (absent from the tree); licence and version from distribution packages (forum-grade sources, see the matrix) |
    | Piper | **No recipe**, and no `onnxruntime` recipe (only a ROS vendor package in meta-ros). The original repository was archived on 2025-10-06; development moved to OHF-Voice/piper1-gpl, GPL-3.0, which embeds espeak-ng and needs ONNX Runtime and a voice model of tens of MB | GPL-3.0 (now) | Unmeasured; a large runtime | C (web sources disagree on -only vs -or-later) |

    Flite needs no new layer, is BSD-licensed, is small, and AGL already uses
    it for the same job. Its voice is plainer than Piper's. Choosing it, and
    packaging it into `agl-f250`, waits for decision 15: until something can
    play audio for navigation, a speech engine in the image would speak to
    nothing.
15. **What's left to connect** (with audio-manager, ADR-0039):
    - the image has **no audio userspace at all** today: the `agl-f250`
      manifest of 2026-11-12 has no PipeWire, WirePlumber or ALSA utilities
      (AGL's demo images have PipeWire 1.6.6);
    - `f250-navigation.service` has `PrivateDevices=yes` and no PipeWire
      socket, so even a `NAV_VOICE_COMMAND` can't make a sound from inside it,
      by design: playback is audio-manager's;
    - a `Speaker` that hands the prompt to audio-manager, which pauses the
      music (decision 16) and plays the prompt. Whether navigation
      synthesises (Flite as a library or a program) and sends audio, or
      sends text and audio-manager synthesises, is for ADR-0039 to say; the
      trait fits either;
    - then Flite in the image, a prompt heard on the bench, and on the truck
      the volume over road noise and the distances tuned.

### The music while a prompt is spoken

16. **The music is paused, not ducked** (owner's decision, 2026-11-12). This
    replaces the ducking ADR-0039 decision 9 describes (AGL's WirePlumber
    "Navigation" role, which lowers the music to 0.2 under the voice). What
    navigation needs from audio-manager; audio-manager decides how, in
    ADR-0039:
    - **No music under the voice, at once.** A prompt never waits for the
      phone: an at-the-maneuver prompt is late if it does. The phone's
      stream is silenced when the prompt starts (in AGL's role policy, the
      Navigation role's `lower-priority` action "cork" instead of "duck").
    - **The song itself stops,** so none of it is missed: AVRCP Pause
      (`MediaPlayer1.Pause`) when a prompt starts, if the player is playing,
      and Play when it ends, **only if audio-manager paused it and it is
      still paused**. The driver pausing or changing source meanwhile wins.
    - **Prompts close together keep it paused**: no resume between
      "Off the route. Finding a new one." and "New route.", or between an
      approaching prompt and the next one a few seconds later. The hold
      (about 3 s after the last prompt) is an example to tune.
    - **A phone without AVRCP control** (no `MediaPlayer1`): the music is
      silenced for the prompt but the phone plays on, so a few seconds of
      the song are missed. The screen needn't say so; the ADR does.
    - **Muted directions don't touch the music**: no prompt, no pause.

    So audio-manager has to know when a prompt starts and ends, which is the
    case ADR-0039 decision 9 left open for an API ("only if a service needs
    to know or change the music's state"). The simplest fit for the
    `Speaker` trait: navigation sends the prompt's text, `speak` starts it
    (cutting off an older one) and `stop` cancels it, and audio-manager does
    pause → speak → resume in one place. navigation's sandbox then stays
    without audio access.

## Consequences

- One or two taps to Home, a favourite or a recent destination; the route
  can be saved; every change is on disk before the screen shows it.
- On the Mac, `make sim` shows places and the voice toggle, and prints
  prompts in navigation's log (`VOICE=say` speaks them).
- On the Pi today, prompts go to the journal only and the screen says "No
  audio". That is the honest state until audio-manager is wired.
- Pausing rather than ducking: a prompt is heard clearly, and the music
  resumes where it stopped. AVRCP adds a round trip to the phone at each
  prompt; how long a phone takes to pause and resume is unmeasured.
- A drive that fails or isn't mounted leaves places on the SD card, saying
  so; places saved then don't move to the drive by themselves when it comes
  back.
- No sync of places between devices, no import, no places with opening
  hours or categories, no reordering of favourites. Spoken street names are
  Valhalla's English text; no lane guidance or speed-camera prompts.
