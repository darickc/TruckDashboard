# ADR 0042 — The phone's cover art on the Media screen, through obexd

- **Status:** Accepted (owner asked, 2026-11-12). [SIM] only:
  - audio-manager's cover art (the simulated phone's pictures), `GetCoverArt`, the Media screen's picture and its
    placeholder are tested (`make test`), and seen in the browser preview;
  - the obexd client compiles and is linted on the Mac; it has **never talked to a real obexd or phone**;
  - **not on the Pi**: bench check 23 ([setup/agl.md](../../setup/agl.md)). Whether the owner's iPhone offers cover
    art over AVRCP is UNVERIFIED.
- **Date:** 2026-11-12
- **Refines:** [ADR-0039](0039-audio-manager.md) (audio-manager; its "not decided here: album art").
  Phase 6.1.

## Context

The owner asked for the picture of what the phone is playing on the Media
screen. Over Bluetooth that is AVRCP 1.6's cover art feature: the phone runs
a small OBEX server (BIP, the Basic Imaging Profile, "imaging responder") on
an L2CAP PSM it advertises in its AVRCP target record; while a BIP session
is open, each track's metadata carries an image handle, and the head unit
fetches the picture by that handle.

What BlueZ 5.86 (the image's version) gives, read on 2026-11-12 from its
source (`downloads/bluez-5.86.tar.xz` in the build VM) and the built
packages (`bluez5`, `bluez5-obex` 5.86-r0 RPMs):

| Fact | Source | Status |
|---|---|---|
| `MediaPlayer1.ObexPort` (uint16): "the player can get cover art using BIP over OBEX on this PSM port". **Experimental** | `doc/org.bluez.MediaPlayer.rst`; `profiles/audio/player.c` (`G_DBUS_PROPERTY_FLAG_EXPERIMENTAL`) | Verified |
| The track's `ImgHandle` (string, experimental): "available and valid only during the lifetime of an OBEX BIP connection to the ObexPort" | `doc/org.bluez.MediaPlayer.rst`; `profiles/audio/avrcp.c` (`AVRCP_MEDIA_ATTRIBUTE_IMG_HANDLE`) | Verified |
| bluetoothd reads the PSM from the phone's AVRCP target SDP record when it advertises cover art (`AVRCP_FEATURE_TG_COVERT_ART`, the OBEX entry of the additional protocol list) | `profiles/audio/avrcp.c` | Verified from source |
| Experimental interfaces need `bluetoothd --experimental` (`-E`) or `Experimental = true` in main.conf; the image's main.conf has everything commented out, its unit runs `/usr/libexec/bluetooth/bluetoothd` | `src/main.c`, `src/main.conf`; the RPM's `bluetooth.service` and `/etc/bluetooth/main.conf` | Verified |
| `org.bluez.obex.Client1.CreateSession(destination, {Target: "bip-avrcp", PSM: uint16})` | `doc/org.bluez.obex.Client.rst` | Verified |
| `org.bluez.obex.Image1` (experimental) on the session: `Properties(handle)`, `Get(file, handle, description)`, `GetThumbnail(file, handle)`; each returns a `Transfer1` whose `Status` ends `complete` or `error` | `doc/org.bluez.obex.Image.rst`, `doc/org.bluez.obex.Transfer.rst`; `obexd/client/bip.c` (the method table) | Verified |
| obexd creates the target file at the transfer's start, `O_WRONLY \| O_CREAT \| O_TRUNC`, mode **0600**, owned by obexd's user | `obexd/client/transfer.c` (`obc_transfer_get`, `transfer_open`) | Verified from source |
| obexd runs on the **session** bus unless started with `--system-bus`; the image ships it as a *user* unit (`/usr/lib/systemd/user/obex.service`) | `obexd/src/main.c`; the RPM | Verified |
| BlueZ's `obex.conf` lets only root own `org.bluez.obex` and anyone send to it | `obexd/src/obex.conf`; the RPM's `/usr/share/dbus-1/system.d/obex.conf` | Verified |
| obexd won't start without at least one server driver and one transport (`obex_server_init` returns `-EINVAL`): `--noplugin='*'` fails with "obex_server_init failed". The client, BIP included, isn't a plugin | `obexd/src/server.c`, `obexd/src/plugin.c`, `obexd/client/manager.c`; [BENCH] the bench Pi, 2026-11-13 | Verified |
| obexd's servers take connections only through a profile registered with bluetoothd (`ProfileManager1.RegisterProfile`, then `Profile1.NewConnection`); it opens no sockets of its own. A refused registration is logged and obexd goes on | `obexd/plugins/bluetooth.c` (`register_profile_reply`) | Verified from source |
| `bluez5-obex` is in the `agl-f250` image | the image manifest, 2026-11-12 | Verified |
| AVRCP 1.6's thumbnail is a small JPEG (200×200 in the specification) | Bluetooth AVRCP 1.6 specification, from memory | UNVERIFIED here: the size isn't relied on (pictures are scaled to fit) |
| Which phones offer cover art over AVRCP; whether the owner's iPhone does | — | UNVERIFIED: bench check 23 |
| The owner's Z Fold8 (Android 17) serves cover art: AVRCP 1.6, features 0x01d1, PSM 0x1001, JPEG thumbnails. Android allows **one cover art client per device** (`AvrcpCoverArtService`: a second gets `ObexRejectServer`, logged "RemoteDevice is invalid") | bench-log 2026-11-13, the phone's logcat and `dumpsys bluetooth_manager` | [BENCH] |
| BlueZ's `mpris-proxy` (the image enables it as a user unit for every user; it runs as agl-driver) has its own cover art client: once `ObexPort` is visible it starts a session obexd and opens `bip-avrcp` within 60 ms of AVRCP connecting, and asks for images with a descriptor this phone can't serve. It took the phone's one slot, so audio-manager was refused | `tools/mpris-proxy.c` (`bip-avrcp`, `CreateSession`, `ObexPort`, `Get`); [BENCH] logs on both sides, 2026-11-13 | Verified |

## Decision

1. **audio-manager fetches the picture** (CLAUDE.md rule 5: the dashboard
   never talks to Bluetooth). For the connected phone's player, if it has an
   `ObexPort`, it opens a `bip-avrcp` session through obexd; for each new
   `ImgHandle` it asks for the **thumbnail** (`GetThumbnail`: the one every
   cover art responder must have, and small), waits for the transfer (15 s at
   most), reads the file and checks it: a complete JPEG or PNG (BMP from the
   simulation), at most 1 MiB. The session is removed when the phone or its
   player goes, and opened again after a failure no sooner than 30 s later.
   A failed picture doesn't close the session unless obexd no longer knows it.
   `services/audio-manager/src/cover_art.rs`.
2. **Honest about which track a picture is for.** A picture is kept with the
   phone and the image handle it was fetched for, and shown only while the
   connected phone's current track has that handle. A session opened again
   forgets its pictures (handles are only valid for one session).
3. **The API:** `NowPlaying.cover_art_id` (empty: no picture; a new picture,
   a new id) and `cover_art_detail` (why there is none: "The phone doesn't
   offer cover art", "No picture for this track", a failure); `GetCoverArt(id)`
   returns the bytes and their type only while `id` is the current track's
   picture (`found = false` otherwise). Pictures don't ride on the
   once-a-second stream.
4. **The dashboard** fetches a picture when the id changes, drops the old one
   at once (never another track's picture while the new one loads), and shows
   a note symbol with the reason when there is none. The picture is square,
   left of the title, as big as the track area allows (at most 220 px; about
   170 px at 800×480 with the controls below).
5. **obexd on the system bus as user f250**, client only
   (`f250-obexd.service`: `--system-bus --nodetach --plugin=bluetooth,opp`:
   the transport and the one server obexd needs to start), started by
   audio-manager's unit. Same user, because obexd writes the picture 0600: it
   writes `/run/f250-obex/cover-art` (its own RuntimeDirectory) and
   audio-manager only reads it (`ProtectSystem=strict` leaves `/run`
   readable). `f250-obex.conf` lets f250 own `org.bluez.obex` and **denies f250
   `RegisterProfile`**, so the object push server is never registered with
   bluetoothd and a phone is offered nothing new (amended 2026-11-13 after
   `--noplugin='*'` failed on the bench Pi).
6. **bluetoothd with `--experimental`** (`bluetooth.service.d/50-f250.conf`
   replaces ExecStart; the package's main.conf is left alone). Stage 1
   restarts bluetoothd when the drop-in changes; the MX+ and the phone
   reconnect by themselves.
7. **mpris-proxy is masked for every user** (`/etc/systemd/user/mpris-proxy.service`
   → `/dev/null`, by Stage 1 and in the image), because a phone allows one
   cover art client and mpris-proxy would take it. It only mirrors the phone's
   player as MPRIS on the dashboard user's session bus, which nothing here uses
   (the dashboard asks audio-manager). Added 2026-11-13 on the bench.
8. **Off with `AUDIO_COVER_ART=0`**; the simulation has its own pictures (a
   made-up record per track, the third track none) and never starts obexd.

## Alternatives considered

- **obexd on the session bus** (the image's user unit): audio-manager is a
  system service with no session; it would need one of its own. Rejected.
- **obexd as root**: its files would be root's, 0600, unreadable by
  audio-manager. Rejected.
- **`Get` with the native picture** instead of the thumbnail: larger and
  optional for the phone; the thumbnail is enough at 200 px. Possible later.
- **Pictures in the watch stream**: tens of kilobytes once a second.
  Rejected for an id and a call.

## Consequences

- `--experimental` makes bluetoothd offer its other experimental D-Bus
  interfaces too. Nothing here uses them; it is one more thing to look at
  when BlueZ is upgraded.
- **UNVERIFIED:** whether `ImgHandle` appears for the track already playing
  when the session opens, or only from the next track: BlueZ reads a track's
  attributes when the phone reports a change, and the handle exists only
  while the session is open. If only from the next track, the first track
  after connecting shows the note. Bench check 23.
- The obexd unit's sandbox (`SystemCallFilter`, `RestrictAddressFamilies=AF_UNIX AF_BLUETOOTH`,
  no `PrivateNetwork`, because Bluetooth sockets work only in the host's
  network namespace) is UNVERIFIED on the Pi.
- Anything else on the Pi that opens a BIP session to the phone (another
  `mpris-proxy`, a desktop's media applet) takes the phone's one slot and
  audio-manager is refused; Media then says "Couldn't reach the phone's
  cover art: … Transport got disconnected".
- A phone without cover art (or bluetoothd without `--experimental`) shows
  the note and "The phone doesn't offer cover art"; nothing else changes.

## To verify on the Pi (bench check 23)

1. After `make deploy`: `systemctl status bluetooth f250-obexd`;
   `tr '\0' ' ' </proc/$(pidof bluetoothd)/cmdline` shows `--experimental`;
   `busctl --system status org.bluez.obex` shows obexd as user f250.
2. Play music on the phone: `busctl --system introspect org.bluez
   /org/bluez/hci0/dev_XX/player0` shows `ObexPort`; `journalctl -u
   f250-audio-manager` says "cover art: BIP session to … open". The Media
   screen shows the picture; Next shows the next track's, never the last
   one's. Note whether the first track had one.
3. `ls -l /run/f250-obex/cover-art`: owner f250, mode 0600.
   `systemd-analyze security f250-obexd`.
4. A track without art (a podcast, a file without a picture): the note with
   "No picture for this track". `systemctl restart f250-obexd` while
   playing: the next track's picture still arrives (the session is opened
   again within 30 s).
5. With `AUDIO_COVER_ART=0`: no picture, no session.
