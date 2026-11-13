//! Cover art from the connected phone (ADR-0042): AVRCP 1.6's cover art
//! feature, through obexd on the system bus.
//!
//! 1. The phone's player has an `ObexPort` (an L2CAP PSM; BlueZ exposes it
//!    only when bluetoothd runs with `--experimental`).
//! 2. `org.bluez.obex.Client1.CreateSession(address, {Target: "bip-avrcp",
//!    PSM: port})` opens an OBEX BIP session to the phone.
//! 3. While that session is open, the track's metadata carries an
//!    `ImgHandle`; `org.bluez.obex.Image1.GetThumbnail(file, handle)` asks
//!    obexd to fetch that picture's thumbnail into `file`, and returns an
//!    `org.bluez.obex.Transfer1` whose `Status` ends "complete" or "error".
//! 4. The file is read, checked (a JPEG, PNG or BMP, at most 1 MiB) and
//!    published; the session is removed when the phone or its player goes.
//!
//! From BlueZ 5.86: doc/org.bluez.MediaPlayer.rst (ObexPort, ImgHandle, both
//! experimental), doc/org.bluez.obex.{Client,Image,Transfer}.rst,
//! obexd/client/bip.c (the method table: Properties, Get, GetThumbnail) and
//! obexd/client/transfer.c (the target file is created, truncated, mode
//! 0600 when the transfer starts, owned by obexd's user). obexd runs as
//! audio-manager's user on the system bus (f250-obexd.service), so this
//! process can read what it wrote.
//!
//! Status: compiles and is linted on the Mac; UNVERIFIED against a real
//! obexd and phone until the bench (ADR-0042). Whether the owner's iPhone
//! offers cover art over AVRCP is UNVERIFIED.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::watch;
use tokio::time::Instant;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value as Z};
use zbus::{Connection, Proxy, proxy::CacheProperties};

use crate::model::{CoverArt, Picture, Snapshot, image_mime};

const OBEX: &str = "org.bluez.obex";
const CLIENT_PATH: &str = "/org/bluez/obex";
const CLIENT: &str = "org.bluez.obex.Client1";
const IMAGE: &str = "org.bluez.obex.Image1";
const TRANSFER: &str = "org.bluez.obex.Transfer1";

/// The largest picture accepted. A thumbnail is far smaller.
pub const MAX_BYTES: u64 = 1024 * 1024;
/// How long opening a session may take (the phone answers over Bluetooth).
const SESSION_WAIT: Duration = Duration::from_secs(15);
/// How long one picture may take.
const FETCH_WAIT: Duration = Duration::from_secs(15);
/// After a failed session, wait this long before trying again.
const RETRY_AFTER: Duration = Duration::from_secs(30);

pub const NO_COVER_ART: &str = "The phone doesn't offer cover art";
pub const NO_PICTURE: &str = "No picture for this track";

/// What the snapshot asks for: a session to the connected phone's cover
/// art server, and the picture of its current track.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Want {
    /// (address, PSM); None: no session (no phone, no player, or no
    /// cover art offered).
    pub session: Option<(String, u16)>,
    pub handle: Option<String>,
    /// Why nothing is asked for, for the screen.
    pub detail: &'static str,
}

/// What `s` asks for. Only the connected phone's player counts.
pub fn want(s: &Snapshot) -> Want {
    let none = |detail| Want {
        session: None,
        handle: None,
        detail,
    };
    let Some(p) = s
        .player
        .as_ref()
        .filter(|p| s.connected_phone().is_some_and(|c| c.address == p.address))
    else {
        return none("");
    };
    match p.obex_port {
        None => none(NO_COVER_ART),
        Some(port) => Want {
            session: Some((p.address.clone(), port)),
            handle: p.track.image_handle.clone(),
            detail: if p.track.image_handle.is_none() {
                NO_PICTURE
            } else {
                ""
            },
        },
    }
}

struct Session {
    address: String,
    psm: u16,
    path: OwnedObjectPath,
}

/// Follows `snap` and keeps `out` holding the connected phone's picture for
/// its current track, fetched by obexd into `file`. Runs until `snap`'s
/// sender is dropped.
pub async fn run(
    mut snap: watch::Receiver<Snapshot>,
    file: PathBuf,
    out: Arc<watch::Sender<CoverArt>>,
) {
    let mut conn: Option<Connection> = None;
    let mut session: Option<Session> = None;
    let mut retry_at: Option<Instant> = None;
    let mut next_id: u64 = 1;
    // The handle tried last, fetched or not: not fetched again until the
    // track's handle changes or the session is opened again.
    let mut tried: Option<(String, String)> = None;
    let publish = |art: CoverArt| {
        out.send_if_modified(|a| {
            if *a == art {
                false
            } else {
                if a.detail != art.detail && !art.detail.is_empty() {
                    eprintln!("[audio] cover art: {}", art.detail);
                }
                *a = art;
                true
            }
        });
    };
    loop {
        let w = want(&snap.borrow());

        // Close a session nobody wants any more.
        if let Some(s) = &session
            && w.session.as_ref() != Some(&(s.address.clone(), s.psm))
        {
            if let Some(c) = &conn {
                remove_session(c, &s.path).await;
            }
            session = None;
            tried = None;
            retry_at = None;
            publish(CoverArt::none(w.detail));
        }

        if let Some((address, psm)) = &w.session {
            if session.is_none() && retry_at.is_none_or(|t| Instant::now() >= t) {
                match open_session(&mut conn, address, *psm).await {
                    Ok(path) => {
                        eprintln!("[audio] cover art: BIP session to {address} open");
                        session = Some(Session {
                            address: address.clone(),
                            psm: *psm,
                            path,
                        });
                        retry_at = None;
                        tried = None;
                        // Handles are only valid for one session.
                        publish(CoverArt::none(w.detail));
                    }
                    Err(e) => {
                        retry_at = Some(Instant::now() + RETRY_AFTER);
                        publish(CoverArt::none(format!(
                            "Couldn't reach the phone's cover art: {e}"
                        )));
                    }
                }
            }
            if let (Some(s), Some(handle)) = (&session, &w.handle) {
                let key = (s.address.clone(), handle.clone());
                if tried.as_ref() != Some(&key) {
                    tried = Some(key);
                    let c = conn.clone();
                    let r = match c {
                        Some(c) => fetch(&c, &s.path, handle, &file).await,
                        None => Err(Failed {
                            why: "no D-Bus connection".into(),
                            session_gone: true,
                        }),
                    };
                    match r {
                        Ok((bytes, mime)) => {
                            publish(CoverArt {
                                picture: Some(Picture {
                                    address: s.address.clone(),
                                    handle: handle.clone(),
                                    id: next_id,
                                    bytes: Arc::new(bytes),
                                    mime,
                                }),
                                detail: String::new(),
                            });
                            next_id += 1;
                        }
                        Err(Failed { why, session_gone }) => {
                            // obexd restarted or the phone closed the
                            // session: open it again after the back-off (the
                            // handle is tried again then). Otherwise only
                            // this picture is missing.
                            if session_gone {
                                session = None;
                                tried = None;
                                retry_at = Some(Instant::now() + RETRY_AFTER);
                            }
                            publish(CoverArt::none(format!("Couldn't fetch the picture: {why}")));
                        }
                    }
                }
            } else if session.is_some() && w.handle.is_none() {
                let mut art = out.borrow().clone();
                art.detail = w.detail.to_string();
                publish(art);
            }
        } else if session.is_none() {
            publish(CoverArt::none(w.detail));
        }

        tokio::select! {
            r = snap.changed() => if r.is_err() { return; },
            () = tokio::time::sleep(Duration::from_secs(5)) => {}
        }
    }
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// obexd's error, shorter.
fn reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, msg, _) => {
            let name = name.as_str();
            if name == "org.freedesktop.DBus.Error.ServiceUnknown" {
                return "obexd isn't running".into();
            }
            let name = name.trim_start_matches("org.bluez.obex.Error.");
            match msg {
                Some(m) if !m.is_empty() => format!("{name}: {m}"),
                _ => name.to_string(),
            }
        }
        other => other.to_string(),
    }
}

async fn open_session(
    conn: &mut Option<Connection>,
    address: &str,
    psm: u16,
) -> Result<OwnedObjectPath, String> {
    if conn.is_none() {
        *conn = Some(
            Connection::system()
                .await
                .map_err(|e| format!("no system D-Bus ({e})"))?,
        );
    }
    let c = conn.as_ref().ok_or("no system D-Bus")?;
    let client = Proxy::new(c, OBEX, CLIENT_PATH, CLIENT)
        .await
        .map_err(err)?;
    let mut args: std::collections::HashMap<&str, Z<'_>> = std::collections::HashMap::new();
    args.insert("Target", Z::from("bip-avrcp"));
    args.insert("PSM", Z::from(psm));
    let r = tokio::time::timeout(
        SESSION_WAIT,
        client.call::<_, _, OwnedObjectPath>("CreateSession", &(address, args)),
    )
    .await
    .map_err(|_| format!("no answer in {} s", SESSION_WAIT.as_secs()))?;
    r.map_err(|e| reason(&e))
}

async fn remove_session(conn: &Connection, path: &OwnedObjectPath) {
    let Ok(client) = Proxy::new(conn, OBEX, CLIENT_PATH, CLIENT).await else {
        return;
    };
    if let Err(e) = client.call_method("RemoveSession", &(path,)).await {
        eprintln!("[audio] cover art: removing the session: {}", reason(&e));
    }
}

/// Why a picture wasn't fetched, and whether the session itself is gone.
struct Failed {
    why: String,
    session_gone: bool,
}

impl From<String> for Failed {
    fn from(why: String) -> Failed {
        Failed {
            why,
            session_gone: false,
        }
    }
}

impl From<&str> for Failed {
    fn from(why: &str) -> Failed {
        Failed::from(why.to_string())
    }
}

/// The session object (or obexd itself) is gone.
fn gone(e: &zbus::Error) -> bool {
    matches!(e, zbus::Error::MethodError(name, _, _) if matches!(
        name.as_str(),
        "org.freedesktop.DBus.Error.UnknownObject"
            | "org.freedesktop.DBus.Error.UnknownMethod"
            | "org.freedesktop.DBus.Error.UnknownInterface"
            | "org.freedesktop.DBus.Error.ServiceUnknown"
            | "org.freedesktop.DBus.Error.NoReply"
    ))
}

/// Asks obexd for `handle`'s thumbnail into `file`, waits for the transfer
/// and reads it.
async fn fetch(
    conn: &Connection,
    session: &OwnedObjectPath,
    handle: &str,
    file: &std::path::Path,
) -> Result<(Vec<u8>, &'static str), Failed> {
    let image = Proxy::new(conn, OBEX, session.as_str(), IMAGE)
        .await
        .map_err(err)?;
    let target = file
        .to_str()
        .ok_or("the cover art file's path isn't UTF-8")?;
    let (transfer, _props): (
        OwnedObjectPath,
        std::collections::HashMap<String, OwnedValue>,
    ) = image
        .call("GetThumbnail", &(target, handle))
        .await
        .map_err(|e| Failed {
            why: reason(&e),
            session_gone: gone(&e),
        })?;
    // obexd created and truncated `file` before answering: whatever is in it
    // from here on is this picture.
    let t = zbus::proxy::Builder::<Proxy<'_>>::new(conn)
        .destination(OBEX)
        .map_err(err)?
        .path(transfer)
        .map_err(err)?
        .interface(TRANSFER)
        .map_err(err)?
        .cache_properties(CacheProperties::No)
        .build()
        .await
        .map_err(err)?;
    let until = Instant::now() + FETCH_WAIT;
    loop {
        match t.get_property::<String>("Status").await {
            Ok(s) if s == "complete" => break,
            Ok(s) if s == "error" => return Err("the transfer failed".into()),
            Ok(_) => {}
            // obexd removes a finished transfer's object: check the file.
            Err(_) => break,
        }
        if Instant::now() >= until {
            let _ = t.call_method("Cancel", &()).await;
            return Err(format!("no picture in {} s", FETCH_WAIT.as_secs()).into());
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    Ok(read_picture(file).await?)
}

/// The picture in `file`: refused if it is too big, empty, or not a
/// complete JPEG, PNG or BMP.
pub async fn read_picture(file: &std::path::Path) -> Result<(Vec<u8>, &'static str), String> {
    let len = tokio::fs::metadata(file)
        .await
        .map_err(|e| format!("{}: {e}", file.display()))?
        .len();
    if len > MAX_BYTES {
        return Err(format!("the picture is too big ({len} bytes)"));
    }
    let bytes = tokio::fs::read(file)
        .await
        .map_err(|e| format!("{}: {e}", file.display()))?;
    check_picture(bytes)
}

/// A complete picture of a known type, or why not.
pub fn check_picture(bytes: Vec<u8>) -> Result<(Vec<u8>, &'static str), String> {
    if bytes.len() as u64 > MAX_BYTES {
        return Err(format!("the picture is too big ({} bytes)", bytes.len()));
    }
    let mime = image_mime(&bytes).ok_or("not a JPEG, PNG or BMP")?;
    let complete = match mime {
        "image/jpeg" => bytes.ends_with(&[0xFF, 0xD9]),
        "image/png" => bytes.len() >= 12 && &bytes[bytes.len() - 8..bytes.len() - 4] == b"IEND",
        _ => true,
    };
    if !complete {
        return Err("the picture is incomplete".into());
    }
    Ok((bytes, mime))
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use crate::model::{Adapter, Phone, PlayState, Player, Track};

    fn snap(connected: bool, port: Option<u16>, handle: Option<&str>) -> Snapshot {
        Snapshot {
            adapter: Adapter::Ready {
                discoverable: false,
                pairable: false,
            },
            phones: vec![Phone {
                address: "AA".into(),
                name: "Phone".into(),
                connected,
                paired: true,
            }],
            player: Some(Player {
                path: "/p".into(),
                address: "AA".into(),
                name: String::new(),
                obex_port: port,
                state: PlayState::Playing,
                track: Track {
                    image_handle: handle.map(str::to_string),
                    ..Track::default()
                },
                position_ms: None,
                read_at: Instant::now(),
            }),
            streaming: true,
        }
    }

    #[test]
    fn what_is_wanted() {
        let w = want(&snap(true, Some(0x1005), Some("1000001")));
        assert_eq!(w.session, Some(("AA".into(), 0x1005)));
        assert_eq!(w.handle.as_deref(), Some("1000001"));
        assert_eq!(w.detail, "");

        let w = want(&snap(true, Some(0x1005), None));
        assert_eq!(
            w.session,
            Some(("AA".into(), 0x1005)),
            "the session stays open between pictures"
        );
        assert_eq!(w.handle, None);
        assert_eq!(w.detail, NO_PICTURE);

        let w = want(&snap(true, None, Some("1000001")));
        assert_eq!(w.session, None, "no ObexPort: nothing to connect to");
        assert_eq!(w.detail, NO_COVER_ART);

        let w = want(&snap(false, Some(0x1005), Some("1")));
        assert_eq!(w.session, None, "never a phone that isn't connected");
        assert_eq!(w.detail, "");

        let w = want(&Snapshot::unavailable("off"));
        assert_eq!(w.session, None);
    }

    #[test]
    fn only_complete_pictures_of_known_types() {
        let jpeg = vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9];
        assert_eq!(check_picture(jpeg.clone()).unwrap().1, "image/jpeg");
        assert!(check_picture(jpeg[..6].to_vec()).is_err(), "cut short");
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
        png.extend_from_slice(&[0, 0, 0, 0]);
        png.extend_from_slice(b"IEND");
        png.extend_from_slice(&[0xAE, 0x42, 0x60, 0x82]);
        assert_eq!(check_picture(png.clone()).unwrap().1, "image/png");
        assert!(check_picture(png[..12].to_vec()).is_err());
        assert!(check_picture(b"GIF89a....".to_vec()).is_err());
        assert!(check_picture(Vec::new()).is_err());
        let mut big = vec![0xFF, 0xD8, 0xFF];
        big.resize(usize::try_from(MAX_BYTES).unwrap() + 1, 0);
        assert!(check_picture(big).unwrap_err().contains("too big"));
    }

    #[tokio::test]
    async fn reads_the_file_obexd_wrote() {
        let dir = std::env::temp_dir().join(format!("f250-cover-art-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let f = dir.join("thumb");
        std::fs::write(&f, [0xFF, 0xD8, 0xFF, 0xD9]).unwrap();
        assert_eq!(read_picture(&f).await.unwrap().1, "image/jpeg");
        assert!(read_picture(&dir.join("missing")).await.is_err());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
