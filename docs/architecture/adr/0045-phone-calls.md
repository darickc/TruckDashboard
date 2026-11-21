# ADR 0045 — Phone calls over Bluetooth hands-free (plan)

- **Status:** Accepted for phase 1's software (owner asked to build calls in
  audio-manager, 2026-11-14); built `[SIM]` only, see the amendment. Nothing is
  enabled on the Pi: the hands-free role, its D-Bus policy and the call
  audio path wait for the bench (S2–S4). The facts below were read on the
  bench Pi (image f3bf43b, AGL 22.0.1) and from PipeWire 1.6.8's source on
  2026-11-14. **S1 done [BENCH] 2026-11-14:** call audio crosses into the Pi
  (mSBC, both ways), and a call was answered over D-Bus (bench-log); S2 is
  partly done with it. **Phase 2** (dialling, contacts and recent calls, the
  Phone screen) built `[SIM]` the same day at the owner's request: see the
  second amendment. **S3 (echo cancellation) [BENCH] 2026-11-15** with the
  DAC: no echo at the far end once WirePlumber honoured audio-manager's
  pins (amendment 2026-11-15b).
- **Date:** 2026-11-14
- **Refined by:** [ADR-0051](0051-five-way-switch-media-and-cameras.md)
  (2026-11-21): the 5-way switch's short centre press does what the knob's
  push does (answer, hang up, play/pause)
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
| PipeWire's echo-cancel module is installed, but only the **null** canceller (`libspa-aec-null.so`): AGL's `pipewire_1.%.bbappend` replaces PACKAGECONFIG without `webrtc-echo-cancelling`. The recipe has it (`-Decho-cancel-webrtc`, needs `webrtc-audio-processing-2`, which meta-multimedia has, 2.1) | the bench Pi; `meta-agl/meta-pipewire/…/pipewire_1.%.bbappend`; meta-oe `pipewire_1.6.8.bb` | Verified; meta-f250 adds it back (amendment 2026-11-14b) |
| PipeWire 1.6.8's echo-cancel module: `monitor.mode` captures the default sink's monitor (or a `target.object`) as the reference instead of making a sink; the capture stream is passive by default; `library.name` defaults to `aec/libspa-aec-webrtc`. The WebRTC plugin (webrtc-audio-processing 2.x) defaults: high-pass filter and noise suppression on, gain control off | 1.6.8 `src/modules/module-echo-cancel.c`, `spa/plugins/aec/aec-webrtc.cpp` | Verified from source |
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

## Amendment, 2026-11-14: phase 1 in software `[SIM]`

The owner chose to build calls in audio-manager before the remaining spikes.
What is built, and the decisions it made:

1. **Following the calls.** `services/audio-manager/src/telephony.rs` reads
   the Telephony tree whole: `GetManagedObjects` on
   `/org/pipewire/Telephony` (one `AudioGateway1` per phone, its `Address`),
   then on each gateway (its `Call1` objects), at start, on any signal under
   `/org/pipewire/Telephony` (debounced 100 ms), when the service's owner
   changes, and every 3 s. Never `Properties.Get` (the 1.6.8 bug). Property
   names and states are from 1.6.8's `telephony.c` and README; the parsing
   is pure (`calls.rs`) and tested on hand-built trees.
2. **Enabled by the microphone** (decision 4): `--call-mic <node.name>`.
   Without one, audio-manager doesn't look for calls and says "Calls stay on
   the phone: no call microphone is configured". The flag doesn't make the
   phone see a hands-free unit; WirePlumber's `hfp_hf` role does, and it is
   not shipped yet (below).
3. **Which call.** Only the phone in use (one phone at a time, ADR-0039);
   a gone phone's call is never shown. Shown first: ringing (incoming, then
   waiting), then active, then dialling or alerting, then held, with a count
   of the others. Ids are audio-manager's own (a new call, a new id), not
   object paths.
4. **Actions.** `AnswerCall` only for an incoming call (`Call1.Answer`). A
   waiting call is answered on the phone: hold-and-answer is phase 2.
   `HangUp` is `Call1.Hangup` for any call, which declines a ringing one (the
   README: a waiting call gets "busy"). `SetMicMuted` runs `pw-cli set-param
   <mic> Props '{ mute = true }'` (UNVERIFIED: no call microphone yet); every
   call starts unmuted (audio-manager unmutes after the last call).
5. **The music and prompts.** When the first call starts, a playing phone is
   paused (AVRCP) and resumed `prompt_hold` after the last call ends, only if
   audio-manager paused it and it is still paused — the same rule as spoken
   directions (ADR-0039 decision 9). A prompt being said stops; `Speak`
   during a call is refused ("skipped, not queued"). Nothing resumes the
   music during a call.
6. **On screen.** A call bar over the top 84 px of the screen area, on every
   screen, below the status bar and the alert banner: the caller (name, else
   number, else "Number withheld"), Answer and Decline (incoming), Decline
   and "answer it on the phone" (waiting), the time, Mute and Hang up
   (active), Hang up (otherwise); a refusal is said on the bar for 5 s. It
   covers the screen's top instead of shrinking it, so no screen's layout
   changes during a call. The Phones screen says where calls go.
   **In camera mode** (camera-manager's window covers x 220–800, y 44–480,
   and nothing is drawn over it) the call takes the top of the left
   column: what it is, the caller, and its two buttons side by side, 60 px
   tall. The four cameras become a 2×2 grid of arrows (front and rear, then
   left and right), still 60 px or more, still highlighting the camera up;
   Save clip and Close keep their rows. The column goes back as it was when
   the call ends.
7. **Simulation.** audio-manager's simulated phone and the dashboard's both
   have calls (`SIM_CALL=<s>` with `make sim`, `make audio` or `make ui-web`
   rings a made-up caller every so often).

Tests `[SIM]`: the tree parsing and the order of calls; `pw-cli` muting
against a fake `pw-cli`; the simulated phone's calls (paused time); end to
end over gRPC: ringing, answered, muted, hung up with the music paused and
resumed and a prompt refused; declined, a withheld number, a waiting call;
a prompt cut off by a call; calls going and coming back with the phone;
calls off without a microphone. The dashboard: the gRPC mapping, the call
bar on every screen and under the alert banner, a refusal shown, nothing
from a lost link, and 800×480 in both themes with the longest texts; in
camera mode, the call in the column and never over the window, every camera
still a 60 px button that switches, with and without an alert and Save clip,
in both themes. It ran in the browser preview with a simulated call, on a
screen and in camera mode.

**The knob** (decision 6, also 2026-11-14): the push, the same HID
play/pause key on the knob display and on any volume knob (ADR-0043), is
handled in audio-manager: it answers a ringing call, hangs up the call in
progress (also one being dialled or held), leaves a waiting call alone
(answering it would end or hold the first: that is the screen's or the
phone's), and plays or pauses without a call. knob-link sends the call to
the dial as `P1` with each media frame (ADR-0044 decision 9); the firmware
parses it, lets it take over every page while its frames keep coming, and
ignores touches during it. Tests `[SIM]`: the push end to end over the
simulated phone; `P1` written in knob-link and the same golden line parsed
in the firmware's host tests; the takeover, its timeout and the hints;
knob-link ran on the Mac against the simulated audio-manager into a
pseudo-terminal and sent `P1 none`, then `P1 ring` when a simulated call
rang. The S3 firmware builds; no board, so nothing is drawn.

**The ring tone** (decision 7, also 2026-11-14). Which phones ring in-band
isn't a list to keep: PipeWire's gateway reports its call audio link
(`AudioGatewayTransport1.State`: error, idle, pending, active, from
1.6.8's `telephony.c`), and a phone that rings in-band has it active while
the call rings (the Z Fold8 did, bench-log 2026-11-14). So audio-manager
rings through the speakers only while the call shown is incoming, its
phone's link isn't active, and it has rung `--ring-after-ms` (1500 ms, an
example: the phone's own ring may take a moment). It stops when the call is
answered, declined, stops ringing, or the phone's ring starts. A waiting call
is never rung (it would sound over the call in progress); the phone beeps
for it. The tone (examples): 660 and 880 Hz together, 0.4 s on, 0.2 s off,
0.4 s on, 2 s off, at −12 dBFS with 10 ms fades, a 16-bit mono WAV
generated by audio-manager (`ring.rs`), played a cycle at a time by
`--ring-command` (a program playing the file named by its argument; killed
to stop). Without one, such a phone rings only on the phone. On the Pi the
player is part of the packaging below, with its PipeWire role (UNVERIFIED:
how it mixes with the call audio and the master volume). `Calls.local_ring`
says when it rings. Tests `[SIM]`: the WAV's header, length, level and gaps;
the player run, cut off and missing; end to end: rung until answered, a
waiting call not rung, a phone ringing in-band not rung. The binary ran on
the Mac with `afplay` as the player; `afinfo` reads the tone as a 3 s WAV.

Not done, in order:

- **S2 with audio-manager itself** on the bench: the D-Bus client above has
  only run against the simulation.
- **Packaging**, after S2: the `hfp_hf` role and the Telephony service on the
  system bus in WirePlumber's Bluetooth config, `f250-telephony.conf`, and
  `AUDIO_CALL_MIC` in `/etc/default/f250` passed as `--call-mic`; all off
  unless a microphone is configured.
- **The call audio** (S3, then S4): the phone's voice through the
  filter-chain, and the microphone through WebRTC echo cancellation.
- **The knob display's drawing** of the call: the frame, the model and the
  push are done (below); the dial draws nothing until its drivers exist
  (ADR-0044, no board yet).

## Amendment, 2026-11-14: phase 2 in software `[SIM]`

The owner asked for the Phone screen on Home to dial numbers, call
contacts and show the call (decision 8, brought forward). The owner chose:
**contacts and recent calls usable while moving** (a tap on Call, nothing
to type), **the keypad only when stopped**; the lists: **contacts and
recent calls** (not favourites).

| Fact | Source | Status |
|---|---|---|
| `void Dial(string number)` on `AudioGateway1`, number `[0-9+*#,ABCD]{1,80}`; an active call is put on hold if dialling succeeds; the new call is announced through the signals | PipeWire 1.6.8 `spa/plugins/bluez5/README-Telephony.md` (tag 1.6.8, read in the build VM) | Verified from source |
| obexd's PBAP client: `Client1.CreateSession(address, {Target: "pbap"})`; `PhonebookAccess1.Select(location, phonebook)` with `"int"` and `"pb"`, `"cch"` (and ich, och, mch, spd, fav); `PullAll(targetfile, filters)` returns a `Transfer1`; filters `Format` (`vcard21`, `vcard30`), `Order`, `Offset`, `MaxCount` (uint16), `Fields`; errors include `Forbidden` | BlueZ 5.86 `doc/org.bluez.obex.PhonebookAccess.rst`, `obexd/client/pbap.c`, `obexd/client/manager.c` (`pbap` is built into obexd's client) | Verified from source |
| The filter's field names, among them `VERSION`, `FN`, `N`, `TEL`, `X-IRMC-CALL-DATETIME` | BlueZ 5.86 `obexd/client/pbap.c` | Verified from source |
| The owner's Z Fold8 didn't answer the PBAP connect (obexd's 10 s `connect_cb` timeout) until its user allowed contact sharing; then it gave its contacts and call history (202 contacts, 100 calls: the most asked for) | the bench Pi, 2026-11-14 (bench-log) | [BENCH] |
| Which vCard version the owner's phones answer with, the call history's order, the owner's own card (handle 0) in the list, the iPhone | — | **UNVERIFIED** |

1. **Dialling.** `Dial(number)` on audio-manager calls `AudioGateway1.Dial`
   on the phone in use's gateway (its path is now kept with the gateway).
   The number is cleaned first (`phonebook::dial_number`: digits, a leading
   `+`, `*`, `#`; spaces, dashes, dots, slashes and brackets dropped), which
   is stricter than PipeWire's rule. Refused when calls are off, without a
   phone, and **during another call** (holding and swapping are the
   phone's). The number isn't logged, only its length. The call then shows
   like any other (dialling, alerting, active); the music is paused for it
   as for any call (amendment 1, decision 5). **A call the phone gives no
   name for** (many give none for a call out) is named from the phone's
   contacts: the same digits, or one number ending with the other when the
   shorter has at least 7 digits (a country code on one side only); the
   Phone screen, the bar and the knob display all get that name.
2. **The phone's lists**, `phonebook.rs`: on the phone becoming the one in
   use, after each call ends (it is in the history now), and on
   `RefreshPhonebook`, audio-manager opens a PBAP session through obexd and
   pulls `pb` (fields VERSION, FN, N, TEL; vCard 3.0 asked) and `cch` (the
   same and X-IRMC-CALL-DATETIME, at most 100), then closes the session. A
   phone without call history over PBAP still gives its contacts. The
   newest request wins; a phone's lists stay shown while they are read
   again; another phone's are never shown. **Kept in memory only**: obexd
   writes each list into `/run/f250-obex/phonebook.vcf` (tmpfs), which is
   read and removed at once (`--phonebook-file`; `AUDIO_PHONEBOOK=0` turns
   it off). The parsing is pure and tested on hand-written cards: vCard 2.1
   and 3.0, folded lines, quoted-printable, TYPE parameters, `tel:` and
   group prefixes; contacts without a number and fax numbers are left out,
   each number once per contact, sorted by name; calls newest first.
   `WatchAudioResponse.phonebook` says where they are (none, loading,
   ready, failed with why, off) and a version; the dashboard fetches them
   whole with `GetPhonebook` when the version changes.
3. **The Phone screen** (Home's Phone button, ADR-0034 amendment): four
   views, kept between visits: **Contacts** (one row per number, its label,
   a Call button; letter groups ABC … WXYZ to jump), **Recent** (missed,
   incoming, outgoing, the phone's own time, Call back), **Keypad** and
   **Phones** (the paired phones and the pairing window, as before; Media's
   Phones button opens this one). Call buttons are dimmed, with the reason
   said, when calls can't be placed (no call microphone yet on the Pi).
4. **The keypad only when stopped**: a current vehicle speed below
   **1 km/h (an example)**; a stale or missing speed counts as moving (rule
   4), so on the bench without the truck's bus the keypad stays locked. The
   keys stay on screen, dimmed, and say why. The check is the dashboard's:
   audio-manager has no speed (rule 5 keeps vehicle data in the gateway).
5. **The call, large.** While a call is up the Phone screen shows it
   instead of its views: what is happening ("Calling…", "Ringing…", "In
   call · 0:42", "On hold"), the caller, and 76 px Answer, Decline, Mute
   and Hang up. The bar over the top of the screen (amendment 1, decision 6)
   is hidden there so a call never shows twice; every other screen keeps it.
   A phone asking to pair likewise takes the Phone screen (its code and Yes
   and No), whichever view was showing.
6. **Simulation.** audio-manager's simulated phone dials (dialling, the
   other phone ringing after 1 s, answered 3 s later) and has made-up
   contacts and calls; so does the dashboard's.

Tests `[SIM]`: the vCard parsing and number cleaning; the lists' runner
(the newest request wins, kept while read again, cleared with the phone,
a refusal said); the file removed after reading; the simulated phone's
dialling; end to end over gRPC: dialled, ringing, answered, refused during
a call and for a bad number, hung up, the lists read again after it; the
lists following the phone; dialling refused without a microphone. The
dashboard: contacts and recent calls listed and called, the letter jump,
the keypad locked without a current speed and while moving and working
when stopped, the call view and the bar hidden on the Phone screen only,
calls that stay on the phone said, no lists without a phone, every view at
800×480 under an alert in both themes with 60 px targets, and the real
audio-manager binary through the Dart client. `make agl-test`: the
wrapper's `--phonebook-file`.

Not done:

- **PBAP with a real phone**: the Z Fold8 shares its contacts and history
  once allowed ([BENCH] 2026-11-14); its vCard version and the iPhone are
  still to see.
- **Dialling on the Pi** waits for the hands-free packaging above (S2, then
  the role and its D-Bus policy), like answering.

## Amendment, 2026-11-15: calls on the bench Pi `[BENCH]`

The owner had the call microphone set up (the C920 webcam's, for a bench
test; the DAC not yet here; echo cancellation after a first call).

1. **Packaging** (256cda1, efd97ce): `AUDIO_CALL_MIC` in
   `/etc/default/f250` turns calls on. `f250-calls-config.service` (root,
   before `wireplumber@bluetooth`) then installs `61-f250-calls.conf`
   (`bluez5.roles = [ a2dp_sink hfp_hf ]`, the native backend, Telephony on
   the system bus), and removes it without a microphone;
   `f250-telephony.conf` lets `pipewire` own the name and `f250` and root
   call it. A phone connected before has to reconnect to open hands-free.
2. **The call audio is two streams** (bench, owner's Z Fold8): the phone's
   voice (`Stream/Output/Audio`, `bluez_input.<addr>.0`) and the way to the
   phone (`Stream/Input/Audio`, `bluez_output.<addr>.1`), `media.role`
   Communication, made when the phone opens SCO. WirePlumber links them like
   an application's; audio-manager pins the input to `AUDIO_CALL_MIC` with
   `target.object` (verified: the C920 was linked to the phone, and the
   far end heard it, 2026-11-15; **corrected in amendment 2026-11-15b**:
   the C920 was the default source, and the pin wasn't read). The
   voice's pin to `AUDIO_CALL_SPEAKER` loses to AGL's role routing (the
   Communication role loopback, then the EQ), so the caller's voice follows
   AGL's Communication route: the DAC's, once it is there. No loopbacks.
3. **WirePlumber's policy instance once stopped linking every new stream**
   (a deploy's restarts; cured only by restarting it). Found and fixed
   `[BENCH]` (bench-log 2026-11-15): WirePlumber 0.5.14 leaves a moved
   stream's role-based link recorded as the priority link (upstream #1030,
   fixed in 0.5.19), AGL's `link:reset ()` patch empties that link, and the
   next role link removed crashes `rescan-media-role-links.lua`, whose
   unfinished hook stops WirePlumber's one-at-a-time event dispatcher.
   - **Decision:** ship the image's three linking scripts with the upstream
     fixes backported (and a guard of ours that never uses a removed
     priority link) in `/usr/local/share/wireplumber/scripts`, which
     WirePlumber reads before `/usr/share`; drop them once the image has
     WirePlumber 0.5.19 or later. Bumping WirePlumber in the image instead
     is a larger change to AGL's pinned stack for three script files.
   - **Decision:** audio-manager checks that what should be heard is linked
     (the call's streams during an active call; the phone's music while it
     streams with nothing above it) and, after 6 s without a link, logs it
     and puts "Audio not playing" in the banner, rather than staying
     silent. Not an automatic restart of WirePlumber: audio-manager runs
     unprivileged, and a restart rebuilds AGL's whole audio graph.
     Detection is `[SIM]`; on the Pi it has not yet fired (it needs the
     owner's phone during a failure).
   - With no real sink at all, AGL's equalizer output links into the
     emergency role loopback and corks the role streams until a sink
     appears (upstream behaviour): the bench keeps its null sink.
4. Still to do: hear the caller (the DAC), echo cancellation (S3), the
   truck's microphone (S4 or a USB microphone near the driver).

## Amendment, 2026-11-14b: echo cancellation in the image `[SIM]`

The owner asked for the echo canceller to be built into the image, ahead
of S3's bench checks.

1. **Built:** `meta-f250/recipes-multimedia/pipewire/pipewire_%.bbappend`
   adds `webrtc-echo-cancelling` back to PipeWire's PACKAGECONFIG (after
   AGL's replacement). `bitbake pipewire` in the build VM (2026-11-14) gave
   `-Decho-cancel-webrtc=enabled` and `pipewire-spa-plugins-aec-webrtc`
   (`/usr/lib/spa-0.2/aec/libspa-aec-webrtc.so`, needing
   `webrtc-audio-processing-2` 2.1). `agl-f250-base.inc` installs it and
   `pipewire-modules-echo-cancel` by name.
2. **Decision: the echo-cancel module in monitor mode, in a unit of its
   own.** `f250-echo-cancel.service` (user f250, a client of the system
   PipeWire like the speakers' filter-chain) runs
   `/opt/f250/libexec/echo-cancel-start`, which writes the module's
   configuration from `/etc/default/f250`: capture `AUDIO_CALL_MIC`
   (passive, so the microphone and the canceller run only while a call
   takes the source), the reference from the monitor ports of
   `AUDIO_DAC_NODE` (the default sink without one), mono at 48 kHz, the
   WebRTC module's defaults. audio-start then passes the module's source,
   `f250.call-aec`, as `--call-mic`, so audio-manager's pin and mute act on
   the cleaned signal; `AUDIO_CALL_ECHO_CANCEL=0` gives the phone the
   microphone itself. Started by `f250-audio-manager.service`; it exits
   doing nothing when calls are off.
   - Monitor mode, not the module's own sink: the reference is everything
     the speakers play (the caller, a ring tone), and the caller's voice
     keeps AGL's Communication route; pinning the voice to a sink lost to
     AGL's role routing on the bench (amendment above).
   - Its own unit, not audio-manager's child: nothing in it changes during
     a call, systemd restarts it, and audio-manager needs no new code.
3. **UNVERIFIED until S3 on the bench, with the DAC:** that WirePlumber
   links the reference stream to the DAC's monitor under AGL's policy
   (`stream.capture.sink`; AGL's role rules skip monitor streams in
   `lutils.is_role_policy_target`), that the far end hears no echo at a
   normal volume, the CPU it costs on the Pi 5, and muting the module's
   source. Not yet in a built image (the next `make agl-build`).


## Amendment, 2026-11-15b: echo cancellation on the bench, with the DAC `[BENCH]`

The DAC came (a RaspiAudio 8xOUT, [ADR-0014](0014-multichannel-dac8x.md)
amendment), and S3 ran on the bench Pi with the owner's Z Fold8, the C920's
microphone and a powered speaker on the front jack (bench-log 2026-11-15).

1. **The first call had a strong echo, because the canceller was
   bypassed.** audio-manager pinned the way to the phone to `f250.call-aec`
   ("call audio: f250.call-aec → phone" in its log), but WirePlumber linked
   it to the C920, the default source. Cause: AGL's
   `50-AGL-media-role-nodes.conf` sets `linking.allow-moving-streams =
   false`, and with it WirePlumber 0.5.14 reads no `target.object`
   metadata (`find-defined-target.lua`) and rescans on no change of it
   (`rescan.lua`). Reproduced with a test capture stream: pinned, it
   stayed on the C920; with the setting on, it moved to `f250.call-aec`.
   - **This corrects amendment 2026-11-15 item 2.** The microphone pin was
     never in effect: the C920 reached the phone because it was the
     default source. The voice's pin to `AUDIO_CALL_SPEAKER` didn't lose to
     the role routing; it wasn't read either.
   - **Decision:** `61-f250-calls.conf` (installed only with calls on) sets
     `linking.allow-moving-streams = true`, and `f250-calls-config` restarts
     the policy instance too when it installs or removes the file.
     audio-manager is the only writer of `target.object` metadata on this
     image, and the policy instance is stateless (`mixin.stateless`), so
     nothing else moves. Rejected: setting `target.object` as a property of
     the phone's streams through `monitor.bluez.rules`, which works without
     the setting but would freeze the choice between the canceller and the
     raw microphone into WirePlumber's configuration, where audio-manager
     already makes it at runtime.
   - `AUDIO_CALL_SPEAKER` now takes effect. Leave it empty: the caller then
     keeps AGL's Communication route into the speakers' filter-chain, which
     the canceller hears. The bench's `f250-bench-null` setting, a stand-in
     from before the DAC, was cleared.
2. **The reference is the speakers' filter-chain input, not the DAC's
   monitor.** `f250.speakers` is a smart filter targeting the DAC, so
   WirePlumber sends the reference (which targets the DAC) to
   `f250.speakers:monitor_FL/FR`: the stereo mix before the crossover and
   the master volume. The canceller models a linear echo path, so this
   worked; a volume change during a call is a change in that path, which it
   has to re-learn (not tested).
3. **Second call, with the setting on: no echo `[BENCH]`.** Links during the
   call: C920 → `f250.call-aec.mic`; `f250.speakers` monitor → the
   reference; `f250.call-aec` → `bluez_output.<addr>.1`; the caller's
   voice → the Communication loopback → `eq-sink` → `f250.speakers` → the
   DAC. The owner heard the caller clearly; the far end heard the owner
   clearly and no echo of themselves. The first call (the raw microphone)
   is the comparison with the canceller off: a strong echo.
4. **CPU:** the canceller's client (`pipewire -c`, user f250) used 5.3 s
   of CPU over the 109 s call, about 5 % of one core (about 1.2 % of the
   Pi 5's four); idle, 0.07 s over 16 s.
5. **Not tested yet:** muting `f250.call-aec` from the screen, a volume
   change during a call, a louder speaker or a real amplifier, the truck's
   cab and microphone (S4).


## Amendment, 2026-11-18: the Phone screen's call view `[SIM]`

From the design review (owner, 2026-11-18: "In-call screen"). The call
shown large on the Phone screen (phase 2) changes layout only; the bar
over other screens and camera mode's panel are unchanged.

- **The middle:** the caller's initials in a circle (up to two, from
  words that start with a letter; a person icon for a number or a
  withheld caller), the caller, the details line as before, and, while the
  call is active, its time large under them. The status line at the top
  then reads "In call" without the time.
- **The bottom:** a full-width row of 80 px buttons. Active: Mute, and a
  wider, filled red Hang up. Incoming: filled red Decline and filled green
  Answer, equal. Dialling, ringing out, on hold, waiting: Hang up alone,
  centred. `TapTarget` gains an optional fill colour; the label on it is
  white or near-black, whichever reads.
- Not added: a line saying the call's audio is on the truck's speakers
  (the mockup had one); the dashboard doesn't know where the phone sends
  a call's audio.

[SIM]: `test/widget/phone_test.dart` (the initials and the person icon,
the timer, the buttons' sizes, fills and span, an incoming call's two
filled buttons, under an alert in both themes) and `call_test.dart`;
checked in the browser at 800×480.


## Amendment, 2026-11-18b: a slimmer call bar `[SIM]`

From the design review (owner, 2026-11-18: "Work on the next screen", the
call bar). Decision 6's bar over the top of the screen area stays over it
(no screen's layout changes during a call), but is **68 px instead of
84**: it hid the top of every screen more than it needed to (on Cameras,
the panel's title and half of the Front button).

- The caller on one line, with its label ("Incoming call", "Call") in
  small type, and **the call's time beside the caller** while it is
  active; the details line under it (number, other calls, "answer it on
  the phone", which phone) no longer carries the time. A refusal still
  takes the details line for 5 s.
- **Icon buttons**, each a 60 px touch target with its word as its label:
  Mute (64 px wide, highlighted while muted), and Hang up, Decline and
  Answer (96 px wide) filled red or green like the Phone screen's.
- Camera mode's panel keeps its worded buttons; the Phone screen keeps its
  large view.

[SIM]: `test/widget/call_test.dart` (the bar's height, its buttons'
size, fill and place inside it, the time beside the caller, the details
without it, a refusal) and the existing call and phone tests; checked in
the browser at 800×480.


## Amendment, 2026-11-18c: the Phone screen's lists `[SIM]`

From the design review (owner, 2026-11-18: "Work on the next screen", the
contacts). Contacts and Recent share their row:

- **Call is a green phone icon** (72 × 60, a light green fill), its own
  touch target as before: a tap on the row never dials. Its label says
  whom it calls ("Call Alex Rivera, work"), and it dims, as before, when
  calls stay on the phone.
- **Contacts:** the contact's initials in a circle on its first number's
  row (a person icon for a name without letters); its further numbers keep
  the arrow that marks them as the same person.
- **Recent** keeps its missed / incoming / outgoing icons.

[SIM]: `test/widget/phone_test.dart` (initials once per person, the arrow,
the button's label and size, Recent's icons, the initials rule, under an
alert in both themes); checked in the browser at 800×480.


## Amendment, 2026-11-18d: a sheet for a ringing call `[SIM]`

**Owner's decision** (2026-11-18: "Do the next screen", after the design
review named this one as the owner's call). It replaces decision 6's bar
for one state only: **a phone ringing** (`incoming`).

- Over the top of whatever screen shows, below the status bar and the
  alert banner (vehicle alerts stay above it): a sheet 236 px high with
  "Incoming call", the caller's initials (a person icon for a number or a
  withheld caller), the caller large, the details, and **Decline and
  Answer as 80 px filled buttons** (red and green), the Phone screen's.
  Easier to hit at a glance than the bar's 60 px icons.
- **Nothing behind it is dimmed or blocked:** the screen below the sheet
  still works, as decision 6 wanted (no screen's layout changes during a
  call; the sheet covers, it doesn't push).
- Answered, it becomes the 68 px bar (amendment 2026-11-18b); declined or
  ended, it goes. A **waiting** call (one ringing during another) stays a
  bar: it is answered on the phone.
- Camera mode (the left column) and the Phone screen (its own large view)
  are unchanged.

[SIM]: `test/widget/call_test.dart` (the sheet on every screen but Phone,
below the alert banner; its height and 80 px filled buttons; the screen
under it still tappable; answered becomes the bar; the longest texts in
both themes); checked in the browser at 800×480.
