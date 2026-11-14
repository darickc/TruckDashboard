# ADR 0045 — Phone calls over Bluetooth hands-free (plan)

- **Status:** Proposed (owner asked for a plan, 2026-11-14). Nothing is built.
  The facts below were read on the bench Pi (image f3bf43b, AGL 22.0.1) and
  from PipeWire 1.6.8's source on 2026-11-14; the open questions are bench
  spikes S1–S4, in order, before any code. **S1 done [BENCH] 2026-11-14:**
  call audio crosses into the Pi (mSBC, both ways), and a call was answered
  over D-Bus (bench-log); S2 is partly done with it.
- **Date:** 2026-11-14
- **Refines:** [ADR-0039](0039-audio-manager.md) (audio-manager; A2DP sink
  only, "HFP: not part of release 1"), [ADR-0043](0043-master-volume-and-the-volume-knob.md)
  (volume, the knob), [ADR-0044](0044-knob-display.md) (the knob display).
  audio-routing.md: "Future HFP … keep a route for microphone and echo
  cancellation".

## Context

The owner wants to take phone calls in the truck, possibly with the knob
display's microphone. Today audio-manager offers phones only an A2DP sink:
`60-f250-bluetooth.conf` sets `bluez5.roles = [ a2dp_sink ]` and
`bluez5.hfphsp-backend = "none"`, and oFono is disabled (ADR-0039 decision 7).

| Fact | Source | Status |
|---|---|---|
| BlueZ 5.86, PipeWire 1.6.8; WirePlumber runs as user `pipewire`, one instance per profile (`wireplumber -p bluetooth` among them) | the bench Pi, 2026-11-14 | Verified |
| PipeWire's bluez5 plugin has the HFP codecs CVSD and mSBC (`libspa-codec-bluez5-hfp-cvsd.so`, `-hfp-msbc.so`); no LC3-SWB | the bench Pi, `/usr/lib/spa-0.2/bluez5/` | Verified |
| `bluez5.hfphsp-backend`: `any`, `none`, `hsphfpd`, `ofono`, `native` (default `native`) | PipeWire 1.6.8 `doc/dox/config/pipewire-props.7.md` | Verified |
| The native backend, in the Hands-Free role, runs a **Telephony D-Bus service** (`org.pipewire.Telephony`): `AudioGateway1` per phone (`Dial`, `HangupAll`, `SwapCalls`, `HoldAndAnswer`, `ReleaseAndAnswer`, `SendTones`, …) and `Call1` per call (`Answer`, `Hangup`; properties `State` — incoming, dialing, alerting, active, held, waiting, disconnected — `LineIdentification`, `Name`, `Multiparty`), announced through ObjectManager; ofono-compatible interfaces too | PipeWire 1.6.8 `spa/plugins/bluez5/README-Telephony.md` | Verified from source |
| It is on the session bus unless `bluez5.telephony.use-system-bus = true`; `bluez5.telephony-dbus-service = false` turns it off; `bluez5.telephony.default-reject-sco` | 1.6.8 `spa/plugins/bluez5/telephony.c` | Verified from source |
| oFono 2.19 is installed and disabled; `/usr/share/dbus-1/system.d/ofono.conf` exists; nothing for `org.pipewire.Telephony` | the bench Pi | Verified |
| PipeWire's echo-cancel module is installed, but only the **null** canceller (`libspa-aec-null.so`): AGL's `pipewire_1.%.bbappend` replaces PACKAGECONFIG without `webrtc-echo-cancelling`. The recipe has it (`-Decho-cancel-webrtc`, needs `webrtc-audio-processing-2`, which meta-multimedia has, 2.1) | the bench Pi; `meta-agl/meta-pipewire/…/pipewire_1.%.bbappend`; meta-oe `pipewire_1.6.8.bb` | Verified |
| The controller is a BCM4345C0 (CYW43455) on the UART (`hci_uart_bcm`, `brcm/BCM4345C0.hcd`) | the bench Pi's kernel log | Verified |
| SCO reaches the host over HCI on this chip, with no vendor command: eSCO, transparent air mode (mSBC), about 133 packets a second each way; the forum claim that it goes to the PCM pins by default doesn't hold here (kernel 6.18.33, BCM4345C0 003.001.025) | btmon on the bench Pi during calls to the owner's Z Fold8, 2026-11-14 | [BENCH] |
| BlueZ 5.86's own Hands-Free unit (`profiles/audio/hfp-hf.c`, profile `hfp`, experimental) comes on with `--experimental`, competes with PipeWire's for the phone's gateway, and on its own connected to the owner's phone with the shipped config (a phone would then route calls to a truck with no call audio) | bluez-5.86 source; the bench Pi, 2026-11-14 | [BENCH]; `--noplugin=hfp` shipped (ADR-0042 amended) |
| PipeWire's native backend made the service level connection with an iPhone and the Z Fold8 (both offer CVSD and mSBC), registered the gateway on the system bus, showed an incoming call (`State` incoming, caller ID over `+CLIP`), and `Call1.Answer`/`Hangup` over D-Bus worked; a tone sent to the phone was heard by the caller | the bench Pi, 2026-11-14 | [BENCH]; a voice through the Pi not yet tested |
| PipeWire 1.6.8 bug: `Properties.Get` on `Call1` answers "No such interface" for `org.pipewire.Telephony.Call1` itself (inverted check in `call_properties_get`); `GetAll` and the gateway's ObjectManager work. Fixed on PipeWire's master | 1.6.8 `telephony.c`; the bench Pi | Verified; audio-manager must use GetAll/ObjectManager |
| The knob display has a microphone; which of its two chips it reaches, and whether the S3 could present it to the Pi as a USB microphone | Waveshare's page (ADR-0044) | **UNVERIFIED**: spike S4 |

## Decision (proposed)

1. **Hands-free through PipeWire's native backend**, not oFono (which stays
   disabled), and never BlueZ's own experimental one (`--noplugin=hfp`,
   shipped 2026-11-14): `bluez5.roles = [ a2dp_sink hfp_hf ]`,
   `bluez5.hfphsp-backend = "native"`, the Telephony service on the
   **system bus** (`bluez5.telephony.use-system-bus = true`), and a D-Bus
   policy (`f250-telephony.conf`) letting user `pipewire` own
   `org.pipewire.Telephony` and user `f250` call it, nobody else. The phone
   sees a hands-free unit only once this is enabled (`AUDIO_CALLS=1`).
2. **audio-manager owns calls** (rule 5: the dashboard never talks to
   Bluetooth). It follows the Telephony service's ObjectManager and
   publishes a `Call` in `WatchAudioResponse` (state, caller's number and
   name as the phone gives them, since when), with `AnswerCall`, `HangUp`
   (an incoming call: decline) and `SetMicMuted` RPCs. Dialling comes in
   phase 2.
3. **Call audio:** the phone's voice to the speakers through the same
   filter-chain (the master volume applies; front only, an example to try),
   the music paused over AVRCP as for spoken directions and resumed after
   the call, prompts held during a call. The microphone to the phone through
   PipeWire's echo-cancel module with the **WebRTC** canceller, the
   speakers' feed as its reference: meta-f250 adds `webrtc-echo-cancelling`
   back to PipeWire's PACKAGECONFIG.
4. **The microphone is configuration** (`AUDIO_CALL_MIC`: a PipeWire source
   node). **Without one, calls aren't enabled** and stay on the phone as
   today: a hands-free unit that can't hear the driver would be worse than
   none. Candidates, chosen after spikes S3 and S4: a small USB microphone
   near the driver (headliner or visor: the usual place, the best placement),
   or the knob display's microphone if the S3 can present it as a USB
   microphone on its existing cable.
5. **On screen:** an incoming call shows on every screen, below the status
   bar and **under the alert banner** (vehicle alerts stay on top), with
   Answer and Decline (60 px) and the caller as the phone gives it; during a
   call: the caller, the time, Mute and Hang up. Nothing to type while
   driving: no dial pad in phase 1.
6. **The knob display:** an incoming call takes over the dial (the caller,
   "push to answer"); its push answers and, during a call, hangs up; a tap
   is ignored during a call (too easy by accident). The knob stays the
   volume.
7. **Ringing:** the phone's in-band ring tone if it sends one over SCO, else
   a local tone through the speakers. Which phones send it: UNVERIFIED (S2).
8. **Phase 2 (not now):** recent calls and contacts over PBAP (obexd is
   already running, ADR-0042), call back and call a favourite from lists;
   a dial pad only when stopped (speed from the gateway, never a stale one).

## Bench spikes before any code

- **S1 — SCO on the BCM4345C0. Done [BENCH] 2026-11-14** (bench-log): mSBC
  both ways over HCI, a call answered over D-Bus, a tone heard by the
  caller. Left for the bench with the DAC: a voice through the Pi both ways,
  and CVSD (only mSBC was negotiated).
- **S2 — Telephony on the system bus.** `busctl --system tree
  org.pipewire.Telephony` shows `ag0`; an incoming call appears as `call0`
  with `State` "incoming" and `LineIdentification`; `Answer` and `Hangup`
  work from `busctl`. Note whether the phone sends an in-band ring.
- **S3 — Echo cancellation.** Build PipeWire with WebRTC AEC (meta-f250
  bbappend), run the echo-cancel module between a test microphone and the
  DAC8x speakers; the far end hears no echo at a normal volume.
- **S4 — The knob display's microphone** (when the board is here): which
  chip it reaches; whether the S3 can be a USB microphone alongside the
  serial port and the HID knob (TinyUSB's audio class, below the Arduino
  layer the firmware uses now); how it sounds against a USB mic.

## Alternatives considered

- **oFono** as the HFP backend: installed, and AGL's own Bluetooth config
  names it; a second daemon and another D-Bus API, where PipeWire 1.6.8's
  native backend now carries the same call control. Kept as the fallback if
  S2 fails.
- **The phone's speakerphone**, nothing in the truck: what the owner does
  today.
- **A hands-free kit** separate from the head unit: no shared speakers or
  screen.

## Consequences

- The phone will see a hands-free unit, and will route calls to the truck
  while connected: the dashboard must make it clear where the call is and
  offer to keep it on the phone (decline transfer).
- `bluez5.roles` gains `hfp_hf`: AGL's WirePlumber auto-connect list already
  has it (ADR-0039 facts).
- Echo cancellation adds CPU on the Pi 5 (to measure in S3).
- Calls hold spoken directions; a prompt during a call is skipped, not
  queued (ADR-0039 decision 9's rule).
