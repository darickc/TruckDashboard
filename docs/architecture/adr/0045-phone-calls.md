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
  second amendment.
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
| Which vCard version the owner's phones answer with, whether they ask before sharing, the call history's order, and the owner's own card (handle 0) in the list | — | **UNVERIFIED**: the bench, with the owner's phone |

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

- **PBAP with a real phone** on the bench: whether the owner's phone shares
  its contacts and history, asks first, and in which vCard version.
- **Dialling on the Pi** waits for the hands-free packaging above (S2, then
  the role and its D-Bus policy), like answering.

