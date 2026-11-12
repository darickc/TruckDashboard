# ADR 0039 — audio-manager: Bluetooth audio through BlueZ and PipeWire, a pairing window, and the speakers' filter-chain

- **Status:** Proposed. [SIM] only:
  - `services/audio-manager`, `f250.audio.v1`, the Media screen and Settings → Speakers are tested
    (`make test`): a simulated phone, a fake `pipewire` and `pw-cli`, and the real binary end to end
    against the dashboard's client;
  - the BlueZ backend compiles and is linted on the Mac, and the service builds and its tests pass in Linux
    (`make linux-test`, Docker), but it has **never talked to a real BlueZ**; the filter-chain has **never run in a real PipeWire**; nothing has been heard;
  - the bench Pi didn't answer on 2026-11-12, and the DAC8x isn't fitted. Bench check 21 in
    [agl.md](../../setup/agl.md#5-bring-up-checks-phase-52) is the next step.
- **Date:** 2026-11-12. Amended the same day (owner): spoken directions pause the music instead of
  ducking it, and audio-manager says them (decision 9)
- **Refines:** [ADR-0014](0014-multichannel-dac8x.md) decision 5 (crossover, fader, balance, sub level
  in PipeWire, owned by audio-manager), [ADR-0023](0023-bluetooth-belongs-to-bluez.md) (the pairing
  policy it left to 6.1), [audio-routing.md](../audio-routing.md). Phase 6.1.

## Context

Phase 6.1 is the software side of audio: a phone streams music to the head
unit (A2DP sink), the screen shows and controls what it plays (AVRCP), new
phones pair only when the driver asks, and the PipeWire filter-chain in front
of the HiFiBerry DAC8x does the crossover, fader and sub level the Pioneer
did (ADR-0014). Mute sequencing (6.2) and the volume knob (6.3) are not part
of it.

What the platform gives, read on 2026-11-12. "Read" means the file itself,
from the AGL Vimba 22.0.1 tree and its downloads in the build VM
(`~/agl/vimba-22.0.1`, `~/agl/downloads`), unless a URL is given:

| Fact | Source | Status |
|---|---|---|
| The tree builds PipeWire **1.6.8**, WirePlumber **0.5.14**, BlueZ **5.86** | `build-raspberrypi5/tmp/buildstats`, `downloads/bluez-5.86.tar.xz` | Verified (the prebuilt demo image has PipeWire 1.6.6, audio-routing.md) |
| PipeWire is built with `bluez`, `bluez-aptx`, `bluez-opus` and `systemd-system-service` when the distro has Bluetooth and systemd; `pipewire-tools` (pw-cli) and `pipewire-modules-filter-chain` are packages | `meta-agl/meta-pipewire/.../pipewire_1.%.bbappend`; `tmp/work/.../pipewire/1.6.8/deploy-rpms` | Verified |
| PipeWire runs **system-wide** as user `pipewire`; its socket is `/run/pipewire/pipewire-0`, `pipewire:pipewire` `0660` | pipewire 1.6.8 `src/daemon/systemd/system/pipewire.socket` and `pipewire.service.in` | Verified (source; not seen on the Pi) |
| AGL splits WirePlumber into instances (`wireplumber@audio`, `@bluetooth`, `@video-capture`, `@policy`), systemwide and stateless | `wireplumber-config-agl_git.bb`, `20-AGL-profiles.conf`, `wireplumber-policy-config-agl_git.bb` | Verified |
| AGL's Bluetooth config gives a phone's A2DP stream `media.role = "Multimedia"` and auto-connects `[ hfp_hf hsp_hs a2dp_sink ]`; its HFP backend is `ofono` | `wireplumber-config-agl/30-AGL-bluetooth.conf` | Verified |
| AGL's policy has **role loopback sinks**: Multimedia priority 25; **Navigation priority 50, `lower-priority = "duck"`**; Emergency/Alert 99 corks; `linking.role-based.duck-level = 0.2` (linear); streams without a role become Multimedia | `wireplumber-policy-config-agl/50-AGL-media-role-nodes.conf` | Verified |
| AGL adds an equalizer **smart filter** `agl.filter.equalizer-sink` (flat by default) | `50-AGL-equalizer.conf` | Verified |
| `wireplumber-bluetooth.conf` lets user `pipewire` send to `org.bluez` | `wireplumber-config-agl/wireplumber-bluetooth.conf` | Verified |
| The build's configuration already includes `meta-agl/meta-pipewire` and `agl-pipewire.inc` | `build-raspberrypi5/conf/bblayers.conf`, `local.conf` | Verified |
| `bluez5.roles` default `[ a2dp_sink a2dp_source bap_sink bap_source hfp_hf hfp_ag ]`; set in `monitor.bluez.properties` | WirePlumber 0.5.14 `docs/rst/daemon/configuration/bluetooth.rst` | Verified |
| PipeWire's bluez5 monitor registers the A2DP endpoints with `org.bluez.Media1.RegisterApplication`; the phone's stream becomes a playback node linked like any stream; it does **not** control the phone's player | pipewire 1.6.6 `spa/plugins/bluez5/bluez5-dbus.c`, `media-source.c`; WirePlumber `scripts/monitors/bluez.lua` ([gitlab](https://gitlab.freedesktop.org/pipewire/pipewire/-/blob/1.6.6/spa/plugins/bluez5/bluez5-dbus.c)) | Verified from source (by a research agent; not in the docs) |
| `MediaPlayer1`: path `.../dev_XX/player#`; Play, Pause, Stop, Next, Previous; `Status` playing/stopped/paused/forward-seek/reverse-seek/error; `Position` uint32 **ms** (≥ duration or `u32::MAX` = ended); `Track` dict Title, Artist, Album, Genre, NumberOfTracks, TrackNumber, Duration (ms) | BlueZ 5.86 `doc/org.bluez.MediaPlayer.rst` | Verified |
| BlueZ sends no periodic Position updates (only on status changes; a Get extrapolates while playing) | BlueZ `profiles/audio/player.c`, `avrcp.c` (master, by the research agent) | Verified from source |
| `MediaControl1.Player` is the addressed player; its methods are deprecated | `doc/org.bluez.MediaControl.rst` | Verified |
| `MediaTransport1.State` idle/pending/broadcasting/active; `Volume` 0–127 for A2DP | `doc/org.bluez.MediaTransport.rst` | Verified |
| `Adapter1`: `Discoverable` (default false), `DiscoverableTimeout` (default 180 s, 0 = forever), `Pairable` (default true, incoming only), `PairableTimeout` (default 0), `Alias` | `doc/org.bluez.Adapter.rst` | Verified |
| `AgentManager1.RegisterAgent(path, capability)`, `RequestDefaultAgent`; `Agent1.RequestConfirmation(device, passkey)`, `RequestAuthorization`, `AuthorizeService(device, uuid)`, `Cancel`; refuse with `org.bluez.Error.Rejected` | `doc/org.bluez.AgentManager.rst`, `doc/org.bluez.Agent.rst` | Verified |
| With no agent and `AlwaysPairable=false` (the default) BlueZ refuses incoming pairing; with no agent an untrusted device's service connection is refused | BlueZ `src/agent.c`, `src/adapter.c`, `src/device.c` (master, by the research agent) | Verified from source; answers ADR-0023's open question in principle, UNVERIFIED on the Pi |
| BlueZ's D-Bus policy: the default context may send to `org.bluez`; root (bluetoothd) may call `Agent1` | BlueZ 5.86 `src/bluetooth.conf` | Verified (upstream file; the image's copy not read) |
| filter-chain: builtin `copy`, `mixer` ("In 1".."In 8", "Gain 1".."Gain 8"), `bq_highpass`/`bq_lowpass` ("Freq" Hz, "Q" RBJ-style, ≤ 0 = default); graph `inputs`/`outputs`, `null` for an unused channel; a whole config can be loaded by `pipewire -c <absolute path>` | pipewire 1.6.8 `src/modules/module-filter-chain.c`, `spa/plugins/audioconvert/biquad.c`, `src/pipewire/conf.c`, `src/daemon/filter-chain.conf.in` | Verified |
| Controls change at run time with `pw-cli set-param <node> Props '{ params = [ "node:port" value ] }'`; pw-cli finds a node by name | pipewire 1.6.8 `spa/plugins/filter-graph/filter-graph.c` (`parse_params`, `find_port`), `src/tools/pw-cli.c` (`find_global`); the form is documented generally in pipewire-props(7) | Verified from source; not documented for filter-chain |
| Smart filters: `filter.smart`, `filter.smart.name`, `.target`, `.before`, `.after` | WirePlumber 0.5.14 `docs/rst/policies/smart_filters.rst` | Verified |
| DAC8x: overlay `hifiberry-dac8x` (Pi 5 only), one 8-channel PCM on a dummy codec (no hardware volume), card `snd_rpi_hifiberry_dac8x` | Raspberry Pi kernel `rpi-6.12.y` overlay README and `sound/soc/bcm/rpi-simple-soundcard.c` (research agent) | Verified from source; **which channel is which jack: UNVERIFIED** |
| Linkwitz-Riley 4th order = two Butterworth (Q 0.7071) biquads in series | Filter theory; not in PipeWire's docs | Standard; nothing PipeWire-specific to verify |

## Decisions

1. **`services/audio-manager`** (ADR-0008), a Rust daemon serving
   **`f250.audio.v1`** (`shared/proto/f250/audio/v1/audio.proto`) on
   `/run/f250-audio/audio.sock`. The dashboard talks only to it. It owns:
   pairing, the phone's player, and the speakers' filter-chain. It does
   **not** carry the audio: PipeWire's bluez5 plugin is the A2DP sink, and
   WirePlumber links the phone's stream as AGL configures it.

2. **BlueZ over the system D-Bus, with zbus**, behind a `Bluetooth` trait
   (snapshot, set_pairing, control, trust). zbus is pure Rust, so the same
   code builds and is linted on the Mac (no libdbus; the gateway's `bluer`
   needs libdbus and Linux). audio-manager reads BlueZ's whole object tree
   (`GetManagedObjects`) at start, after each burst of BlueZ signals, and
   every 5 s, and turns it into a snapshot in pure, tested code
   (`objects.rs`). A **simulated phone** implements the same trait for the
   Mac (`make sim`, `make audio`) and the tests.
   - A **phone** is a paired or connected device listing the A2DP Source
     UUID (`0000110a-...`). The MX+ (Serial Port only) is never one.
   - The **player** shown is the connected phone's addressed player
     (`MediaControl1.Player`), else its first `MediaPlayer1`. **Never a
     player of a phone that isn't connected** (rule 4): the track goes with
     the phone.
   - **Position**: BlueZ doesn't send it periodically, so audio-manager
     counts on from the last read while playing, never past the duration.
   - **Streaming** = a `MediaTransport1` of that phone is `active`.
   - bluetoothd restarting (`NameOwnerChanged`) drops everything, shows
     Bluetooth unavailable, and starts again on a new connection (the agent
     must be registered again).

3. **The pairing window.** Not discoverable and not pairable except while
   the driver has asked, from the Media screen:
   - **Pair a phone** opens it for the configured length (**120 s, an
     example**; at most 300 s). audio-manager sets `DiscoverableTimeout` and
     `PairableTimeout` to the same length, then `Pairable` and
     `Discoverable`: **BlueZ closes it by itself** even if audio-manager
     dies.
   - It closes at the end of its countdown, on **Stop pairing**, **as soon
     as one phone has paired**, when Bluetooth goes away, and at
     audio-manager's start and stop.
   - A state machine (`pairing.rs`: closed, opening, open, closing, failed),
     pure and time-injected, with a test for every transition.
   - Pairing outside the window (the MX+ from `bluetoothctl`, which uses
     its own agent) changes nothing.

4. **The agent: "DisplayYesNo", the code confirmed on the screen.**
   audio-manager registers `org.bluez.Agent1` at `/org/f250/audio/agent`
   and asks to be the default agent.
   - `RequestConfirmation(device, passkey)` inside the window becomes a
     question on the Media screen: "Pixel 8 wants to pair. Does the phone
     show **246 810**?" **Yes, it matches** / **No**. Unanswered in 30 s:
     refused. One question at a time.
   - `RequestAuthorization` (pairing with no code) is asked the same way,
     with a warning to accept only the phone in your hand.
   - Anything outside the window, PIN codes and typed passkeys are refused
     (`org.bluez.Error.Rejected`).
   - `AuthorizeService` is allowed for paired devices, refused otherwise. A
     phone paired in the window is then marked **trusted**, so it
     reconnects without asking.
   - Just Works without the driver (NoInputNoOutput) was rejected: in a
     parking lot, anyone in range during the window could pair.

5. **AVRCP controls** go to the player's `MediaPlayer1` (Play, Pause, Next,
   Previous). Refused, with the reason on screen, without a phone or a
   player. Absolute volume (`MediaTransport1.Volume`) is left for 6.3.

6. **The speakers' filter-chain runs as audio-manager's own child**,
   `pipewire -c /run/f250-audio/speakers.conf`: a PipeWire client process
   holding only `libpipewire-module-filter-chain` (as PipeWire's own
   `filter-chain.conf` does), generated from the settings (`dsp.rs`),
   restarted with a backoff if it stops.
   - **Graph:** stereo in; front L/R and rear L/R each through two
     `bq_highpass` (LR4) and a gain; the sub `(L+R)/2` through a mixer and
     two `bq_lowpass` (LR4), copied to both legs of its jack; the spare
     jack `null`. **No full-range signal reaches the sub's channels, and the
     speakers' high-pass is never off** (ADR-0014; rendered-config tests).
   - **A WirePlumber smart filter** (`filter.smart`, after
     `agl.filter.equalizer-sink`, targeting the DAC's node), so everything
     played reaches it after AGL's role loopbacks and equalizer.
   - **Fader, balance, sub level** change live with `pw-cli set-param
     f250.speakers Props '{ params = [ "gain_fl:Gain 1" … ] }'`. A
     **crossover** change, or a failed live change, restarts the child: a
     moment of silence, said on screen.
   - Fader and balance: ±10 steps of 2 dB, the last step mutes the far
     pair; sub −20..+6 dB; crossover 50–120 Hz in 10 Hz steps, default
     80 Hz. **All examples** (CLAUDE.md rule 10), validated (limits that
     would put bass on the doors or full range on the subs are refused).
   - **Which DAC channel is which jack, the DAC's node name and its channel
     positions are configuration** (`AUDIO_DAC_NODE`,
     `AUDIO_DAC_POSITIONS`, `AUDIO_FRONT/REAR/SUB`), UNVERIFIED until the
     bench's test tones (wiring/audio.md). Empty node: the default sink.
   - `audio-manager --print-dsp-config` prints what it would run.

7. **The driver's settings** (fader, balance, sub level, crossover) are on
   **Settings → Speakers**, one step a tap, applied at once, kept in
   `/var/lib/f250-audio/speakers.json` (a damaged file: the defaults, and
   the log says so). The Media screen says whether the filter-chain runs.

8. **Bluetooth is the A2DP sink only** (`60-f250-bluetooth.conf`:
   `bluez5.roles = [ a2dp_sink ]`, `bluez5.hfphsp-backend = "none"`). The
   head unit is offered to phones as a speaker, never as a headset or a
   source. oFono, which AGL's HFP backend names, is disabled in these
   images; calling is later (audio-routing.md).

9. **Spoken directions pause the music; audio-manager says them**
   (amended 2026-11-12, **owner's decision**, relayed from the navigation
   session: "I would like the music paused while directions are spoken, not
   ducked"; ADR-0040 decision 16). The first version had other services
   play prompts themselves with role "Navigation", which AGL's policy
   ducks to 0.2.
   - **`Speak(text)` / `StopSpeaking`** in `f250.audio.v1` (added, compatible).
     A new prompt cuts off one still being said; Speak returns at once.
     `WatchAudioResponse.prompts` says whether a voice is available, whether
     a prompt is being said, and whether the music is paused for prompts.
     Navigation needs no PipeWire access.
   - **Silence at once, never a delayed prompt:** the prompt plays with
     `media.role = "Speech-High"`. AGL's policy (22.0.1,
     `50-AGL-media-role-nodes.conf`) gives Speech-High priority 60 and
     `lower-priority = "cork"`, so the phone's Multimedia stream is corked
     while it plays. No change to AGL's configuration.
   - **None of the song is missed:** if the phone's player is playing when a
     prompt starts, audio-manager sends it AVRCP **Pause**. It sends **Play**
     **1 s** (`AUDIO_PROMPT_HOLD_MS`, an example; the owner chose 1 s over
     3 s on 2026-11-12) after the last prompt ends,
     so prompts close together don't let the music back in between, and
     **only if audio-manager paused it and it is still paused**. The
     driver's Play or Pause (on the screen) during that time wins: nothing
     is resumed. A phone that goes away is forgotten. (`prompts.rs`, pure,
     every case tested.)
   - A phone without a `MediaPlayer1` is silenced by the cork but plays on
     underneath: that part of the song is lost. Documented, not shown.
   - Muted directions are navigation's: it doesn't call Speak, and the music
     is untouched.
   - **The voice:** `/opt/f250/libexec/speak-prompt`, Flite+hts_engine 1.06
     (meta-agl-demo's `flite`, BSD-3-Clause, with `flite-voicedata`'s
     cmu_us_arctic_slt voice, CC-BY-3.0; already built in the VM's sstate)
     writes a WAV in `/run/f250-audio/`, then `exec pw-play --media-role
     Speech-High` plays it. audio-manager kills it to cut a prompt off.
     `AUDIO_VOICE` can name another program, or `none`. On the Mac,
     `--voice-command say`; with `--simulate` and no command, a silent
     simulated voice. pw-play is pipewire-tools' pw-cat, built when the
     distro has agl-devel, as this build configuration does (UNVERIFIED
     for any other).
   - An alert sound would use "Alert" (priority 99, corks everything).

10. **The dashboard never shows anything as current without audio-manager.**
    audio-manager publishes on each change and **at least once a second**;
    the dashboard's client treats 3 s of silence as a lost link, and then
    shows no phone, track or pairing window.

11. **Packaging** (as navigation and usb-export): `f250-audio-manager.service`
    runs as `f250` with `SupplementaryGroups=pipewire`, sandboxed: unix
    sockets only (`PrivateNetwork`, `AF_UNIX`), no devices, no capabilities,
    `ProtectSystem=strict` with only its runtime and state directories.
    Different from the others: **real-time allowed** for the filter-chain's
    audio thread (no `RestrictRealtime`, no `~@resources`, `LimitRTPRIO=88`)
    and **no `PrivateUsers`** (group pipewire must map). `audio-start`
    builds the options from `AUDIO_*` in `/etc/default/f250`. The images
    gain `packagegroup-pipewire`, `pipewire-tools`, `wireplumber-config-agl`
    and `wireplumber-policy-config-agl`. `make agl-test` checks it.

## Consequences

- The Media screen works on the Mac against a simulated phone, the same
  code paths as the Pi except the zbus calls and the `pipewire`/`pw-cli`
  processes.
- **The head unit needs PipeWire running system-wide.** The meta-f250 images
  haven't carried it before; an image build will show whether the four
  packages are enough (UNVERIFIED until `make agl-build`).
- A crash of audio-manager leaves the window closed (BlueZ's own timeouts)
  and the music playing (PipeWire carries it), without the crossover until
  audio-manager starts the filter-chain again: the stereo mix then goes
  straight to the default sink, unfiltered. Which DAC8x channels it reaches
  then (PipeWire's channel mixing of stereo onto 8 channels) is UNVERIFIED,
  and with it whether the subs or the doors get full range; check it on the
  bench (check 21) before the amps are connected.
- The pairing window answers ADR-0023's question about incoming pairing:
  refused unless audio-manager's agent says yes inside the window.
- A second filter-chain process means one more PipeWire client and its
  graph: CPU cost on the Pi 5 is UNVERIFIED (expected small: 10 biquads at
  48 kHz).

## Not decided here

- **Mute sequencing (6.2):** where it attaches is the filter-chain's start
  and stop (`runner.rs`) and the manager; nothing mutes the DAC yet.
- **The volume knob and its cap (6.3):** a master gain node and absolute
  volume over AVRCP go into the same filter-chain and manager.
- Album art (AVRCP 1.6 cover art over OBEX): not done.
- Several phones connected at once, and a preferred phone: the policy in
  audio-routing.md ("last connected wins") is BlueZ's own behaviour today;
  no switching UI.

## To verify on the Pi (bench check 21)

1. An image (or Stage 1 + `make deploy`) with PipeWire: `systemctl status
   pipewire wireplumber@audio wireplumber@bluetooth wireplumber@policy
   f250-audio-manager`. `systemd-analyze security f250-audio-manager`.
2. `bluetoothctl show`: `Discoverable: no`, `Pairable: no`. Media → **Pair
   a phone**: `Discoverable: yes`, `DiscoverableTimeout` 120; the phone
   finds "F-250", shows a code, the screen shows the same code; **Yes**:
   paired, trusted, the window closes. Let one window run out: it closes by
   itself. Kill audio-manager with the window open: BlueZ closes it.
3. Play music on the phone: `pw-cli ls Node` shows the bluez input node and
   `f250.speakers`; `pw-link -l` shows phone → Multimedia loopback →
   (equalizer) → `f250.speakers` → the DAC. Title, artist, position and
   Play/Pause/Next/Previous on the Media screen. Walk the phone out of
   range: the track disappears; back in range: it reconnects by itself.
4. With the DAC8x: the node name and positions (`pw-cli i <id>`), a test
   tone per jack to set `AUDIO_FRONT/REAR/SUB`, then the fader, balance and
   sub level live (no gap) and the crossover (a short gap). Record `top`
   for the filter-chain process and any xruns (`pw-top`).
5. Over music, `grpcurl`/navigation's Speak: the music stops at once (cork),
   the phone shows paused, the prompt is heard, and the music resumes about
   1 s later. Press Pause on the screen during a prompt: it stays paused.
   Record how the voice sounds through the speakers and how long Flite takes
   for a typical prompt.
