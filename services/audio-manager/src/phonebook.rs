//! The connected phone's contacts and recent calls (ADR-0045 phase 2), read
//! over PBAP through obexd, so the Phone screen can call a contact or call
//! back. Kept in memory only: obexd writes each list into a file under
//! `/run` (tmpfs), which is read and removed at once.
//!
//! BlueZ 5.86 (doc/org.bluez.obex.PhonebookAccess.rst, obexd/client/pbap.c):
//! `Client1.CreateSession(address, {Target: "pbap"})`, then on the session
//! `PhonebookAccess1.Select("int", "pb" | "cch")` and `PullAll(file,
//! filters)`, which returns a `Transfer1` whose `Status` ends "complete" or
//! "error"; the filter's field names (`VERSION`, `FN`, `N`, `TEL`,
//! `X-IRMC-CALL-DATETIME`) are obexd's own list. A phone that hasn't allowed
//! contact sharing answers `Forbidden`.
//!
//! The vCard parsing is pure and tested on hand-written cards (2.1 and 3.0:
//! folded lines, quoted-printable, TYPE parameters, call times). Which
//! fields the owner's phones send, and whether they ask before sharing, is
//! UNVERIFIED until the bench.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::watch;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value as Z};
use zbus::{Connection, Proxy, proxy::CacheProperties};

use crate::objects::clean_text;

/// The longest name or number kept.
const MAX_TEXT: usize = 64;
/// At most this many contacts (a phone may have thousands; the screen
/// scrolls them).
pub const MAX_CONTACTS: usize = 5000;
/// Numbers kept per contact.
const MAX_NUMBERS: usize = 8;
/// Recent calls asked for and kept.
pub const MAX_RECENT: u16 = 100;
/// The largest list file read.
const MAX_FILE: u64 = 16 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Number {
    pub number: String,
    /// "Mobile", "Home", "Work", "Other"; empty: not given.
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Contact {
    pub name: String,
    pub numbers: Vec<Number>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecentKind {
    Received,
    Dialed,
    Missed,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recent {
    pub name: String,
    pub number: String,
    pub kind: RecentKind,
    /// "YYYY-MM-DDTHH:MM:SS", the phone's local time; empty: not given.
    pub time: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BookState {
    /// No phone connected.
    None,
    Loading,
    Ready,
    /// Why the phone didn't share them.
    Failed(String),
    /// Not configured: why.
    Off(String),
}

/// What is known of the connected phone's lists, replaced as a whole.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Book {
    pub state: BookState,
    /// The phone they are from (upper case); None without a phone.
    pub address: Option<String>,
    pub contacts: Arc<Vec<Contact>>,
    pub recent: Arc<Vec<Recent>>,
    /// Changes whenever the lists do.
    pub version: u64,
}

impl Book {
    pub fn off(why: impl Into<String>) -> Book {
        Book {
            state: BookState::Off(why.into()),
            address: None,
            contacts: Arc::default(),
            recent: Arc::default(),
            version: 0,
        }
    }

    fn none() -> Book {
        Book {
            state: BookState::None,
            ..Book::off("")
        }
    }
}

// ---------------------------------------------------------------------------
// vCard parsing (pure)

/// One property line: its name (upper case), parameters (upper case, as
/// given: `TYPE=CELL`, `CELL`, `ENCODING=QUOTED-PRINTABLE`), and value
/// (decoded).
#[derive(Debug, Clone, PartialEq, Eq)]
struct Prop {
    name: String,
    params: Vec<String>,
    value: String,
}

impl Prop {
    /// Every type the parameters give: bare (2.1) and TYPE= lists (3.0).
    fn types(&self) -> Vec<String> {
        let mut out = Vec::new();
        for p in &self.params {
            let v = p.strip_prefix("TYPE=").unwrap_or(p);
            if v.contains('=') {
                continue;
            }
            for t in v.split(',') {
                let t = t.trim().trim_matches('"');
                if !t.is_empty() {
                    out.push(t.to_string());
                }
            }
        }
        out
    }
}

/// Unfolds `text` into logical lines: a line starting with a space or tab
/// continues the one before (RFC 2425), and a quoted-printable line ending
/// with `=` continues on the next (vCard 2.1's soft line break).
fn logical_lines(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut qp_open = false;
    for raw in text.split('\n') {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if qp_open && let Some(last) = out.last_mut() {
            last.pop(); // the '='
            last.push_str(line);
            qp_open = is_qp(last) && last.ends_with('=');
            continue;
        }
        if (line.starts_with(' ') || line.starts_with('\t')) && !out.is_empty() {
            if let Some(last) = out.last_mut() {
                last.push_str(&line[1..]);
            }
        } else if !line.is_empty() {
            out.push(line.to_string());
        }
        if let Some(last) = out.last() {
            qp_open = is_qp(last) && last.ends_with('=');
        }
    }
    out
}

fn is_qp(line: &str) -> bool {
    line.split_once(':')
        .is_some_and(|(head, _)| head.to_ascii_uppercase().contains("QUOTED-PRINTABLE"))
}

/// `=XX` bytes decoded, as UTF-8 (the charset phones use; others are read
/// lossily).
fn decode_qp(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'='
            && let (Some(h), Some(l)) = (
                b.get(i + 1).and_then(|c| (*c as char).to_digit(16)),
                b.get(i + 2).and_then(|c| (*c as char).to_digit(16)),
            )
        {
            out.push(u8::try_from(h * 16 + l).unwrap_or(b'?'));
            i += 3;
            continue;
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// vCard 3.0's escapes: `\,` `\;` `\\` and `\n`.
fn unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('n' | 'N') => out.push(' '),
                Some(o) => out.push(o),
                None => {}
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn parse_prop(line: &str) -> Option<Prop> {
    let (head, value) = line.split_once(':')?;
    let mut parts = head.split(';');
    let name = parts.next()?;
    // A group prefix ("item1.TEL") names nothing we need.
    let name = name.rsplit('.').next()?.trim().to_ascii_uppercase();
    let params: Vec<String> = parts.map(|p| p.trim().to_ascii_uppercase()).collect();
    let value = if params.iter().any(|p| p.contains("QUOTED-PRINTABLE")) {
        decode_qp(value)
    } else {
        value.to_string()
    };
    Some(Prop {
        name,
        params,
        value,
    })
}

/// The cards in `text`: each one's properties, in order.
fn cards(text: &str) -> Vec<Vec<Prop>> {
    let mut out = Vec::new();
    let mut cur: Option<Vec<Prop>> = None;
    for line in logical_lines(text) {
        let Some(p) = parse_prop(&line) else { continue };
        match (
            p.name.as_str(),
            p.value.trim().to_ascii_uppercase().as_str(),
        ) {
            ("BEGIN", "VCARD") => cur = Some(Vec::new()),
            ("END", "VCARD") => {
                if let Some(c) = cur.take() {
                    out.push(c);
                }
            }
            _ => {
                if let Some(c) = cur.as_mut() {
                    c.push(p);
                }
            }
        }
    }
    out
}

/// FN, else N's given and family names, else empty.
fn name_of(card: &[Prop]) -> String {
    if let Some(f) = card.iter().find(|p| p.name == "FN") {
        let n = clean_text(&unescape(&f.value), MAX_TEXT);
        if !n.is_empty() {
            return n;
        }
    }
    if let Some(n) = card.iter().find(|p| p.name == "N") {
        // Family;Given;Additional;Prefix;Suffix
        let parts: Vec<String> = n.value.split(';').map(unescape).collect();
        let given = parts.get(1).map_or("", |s| s.trim());
        let family = parts.first().map_or("", |s| s.trim());
        let joined = format!("{given} {family}");
        return clean_text(&joined, MAX_TEXT);
    }
    String::new()
}

/// A TEL's number, without a `tel:` prefix; empty if it has no digit.
fn number_of(p: &Prop) -> String {
    let v = p.value.trim();
    let v = v.strip_prefix("tel:").unwrap_or(v);
    let n = clean_text(&unescape(v), MAX_TEXT);
    if n.chars().any(|c| c.is_ascii_digit()) {
        n
    } else {
        String::new()
    }
}

fn label_of(types: &[String]) -> &'static str {
    let has = |t: &str| types.iter().any(|x| x == t);
    if has("CELL") || has("MOBILE") || has("IPHONE") {
        "Mobile"
    } else if has("WORK") {
        "Work"
    } else if has("HOME") {
        "Home"
    } else if types.iter().any(|t| t != "VOICE" && t != "PREF") {
        "Other"
    } else {
        ""
    }
}

/// The digits (and a leading +) of a number, to tell two spellings of one
/// number apart from two numbers.
fn digits(n: &str) -> String {
    n.chars()
        .filter(|c| c.is_ascii_digit() || *c == '+' || *c == '*' || *c == '#')
        .collect()
}

/// The contacts in a phonebook listing (`pb`): those with a number, by
/// name (no name last), each number once. Fax numbers are left out (they
/// can't be called).
pub fn contacts(text: &str) -> Vec<Contact> {
    let mut out: Vec<Contact> = cards(text)
        .into_iter()
        .filter_map(|card| {
            let mut numbers: Vec<Number> = Vec::new();
            for p in card.iter().filter(|p| p.name == "TEL") {
                let types = p.types();
                if types.iter().any(|t| t == "FAX") {
                    continue;
                }
                let number = number_of(p);
                if number.is_empty() || numbers.iter().any(|n| digits(&n.number) == digits(&number))
                {
                    continue;
                }
                numbers.push(Number {
                    number,
                    label: label_of(&types).to_string(),
                });
                if numbers.len() == MAX_NUMBERS {
                    break;
                }
            }
            (!numbers.is_empty()).then(|| Contact {
                name: name_of(&card),
                numbers,
            })
        })
        .take(MAX_CONTACTS)
        .collect();
    out.sort_by(|a, b| {
        (a.name.is_empty(), a.name.to_lowercase()).cmp(&(b.name.is_empty(), b.name.to_lowercase()))
    });
    out
}

/// `20261114T153000` (or with a trailing Z) as `2026-11-14T15:30:00`; empty
/// if it isn't one.
fn call_time(v: &str) -> String {
    let v = v.trim().trim_end_matches('Z');
    let ok = v.len() == 15
        && v.as_bytes()[8] == b'T'
        && v.chars()
            .enumerate()
            .all(|(i, c)| i == 8 || c.is_ascii_digit());
    if !ok {
        return String::new();
    }
    format!(
        "{}-{}-{}T{}:{}:{}",
        &v[0..4],
        &v[4..6],
        &v[6..8],
        &v[9..11],
        &v[11..13],
        &v[13..15]
    )
}

/// The calls in a call-history listing (`cch`): newest first where the
/// phone gives times (in the order given otherwise), at most
/// [`MAX_RECENT`].
pub fn recent(text: &str) -> Vec<Recent> {
    let mut out: Vec<Recent> = cards(text)
        .into_iter()
        .map(|card| {
            let when = card.iter().find(|p| p.name == "X-IRMC-CALL-DATETIME");
            let kind = when.map_or(RecentKind::Unknown, |p| {
                let types = p.types();
                let has = |t: &str| types.iter().any(|x| x == t);
                if has("MISSED") {
                    RecentKind::Missed
                } else if has("RECEIVED") {
                    RecentKind::Received
                } else if has("DIALED") {
                    RecentKind::Dialed
                } else {
                    RecentKind::Unknown
                }
            });
            Recent {
                name: name_of(&card),
                number: card
                    .iter()
                    .filter(|p| p.name == "TEL")
                    .map(number_of)
                    .find(|n| !n.is_empty())
                    .unwrap_or_default(),
                kind,
                time: when.map(|p| call_time(&p.value)).unwrap_or_default(),
            }
        })
        .collect();
    // Stable: equal or missing times keep the phone's order.
    out.sort_by(|a, b| match (a.time.is_empty(), b.time.is_empty()) {
        (false, false) => b.time.cmp(&a.time),
        _ => std::cmp::Ordering::Equal,
    });
    out.truncate(usize::from(MAX_RECENT));
    out
}

/// The contact a number belongs to, for a call whose phone gives no name
/// (many give none for a call out). Digits only; the same number, or one
/// ending with the other when the shorter has at least 7 digits (a country
/// code or trunk prefix on one side only).
pub fn name_for(contacts: &[Contact], number: &str) -> Option<String> {
    let want: String = number.chars().filter(char::is_ascii_digit).collect();
    if want.is_empty() {
        return None;
    }
    let same = |n: &str| {
        let have: String = n.chars().filter(char::is_ascii_digit).collect();
        if have == want {
            return true;
        }
        let (short, long) = if have.len() < want.len() {
            (&have, &want)
        } else {
            (&want, &have)
        };
        short.len() >= 7 && long.ends_with(short.as_str())
    };
    contacts
        .iter()
        .find(|c| !c.name.is_empty() && c.numbers.iter().any(|n| same(&n.number)))
        .map(|c| c.name.clone())
}

/// What the dashboard may dial: digits with an optional leading `+`, and
/// `*` and `#`; spaces, dashes, dots, slashes and brackets are dropped.
/// PipeWire accepts `[0-9+*#,ABCD]{1,80}` (README-Telephony.md); this is
/// stricter.
pub fn dial_number(s: &str) -> Result<String, String> {
    let mut out = String::new();
    for (i, c) in s.trim().chars().enumerate() {
        match c {
            '0'..='9' | '*' | '#' => out.push(c),
            '+' if i == 0 => out.push(c),
            ' ' | '-' | '.' | '/' | '(' | ')' => {}
            _ => return Err(format!("\"{c}\" can't be dialled.")),
        }
    }
    if !out.chars().any(|c| c.is_ascii_digit()) {
        return Err("Enter a number to call.".into());
    }
    if out.len() > 80 {
        return Err("That number is too long.".into());
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Keeping the connected phone's lists

/// Reads a phone's lists.
#[tonic::async_trait]
pub trait Reader: Send + Sync + 'static {
    async fn read(&self, address: &str) -> Result<(Vec<Contact>, Vec<Recent>), String>;
}

/// The connected phone's lists.
pub trait Phonebook: Send + Sync {
    fn book(&self) -> watch::Receiver<Book>;
    /// Reads `address`'s lists (again), or clears them (None). The latest
    /// request wins: one still being read is dropped.
    fn load(&self, address: Option<String>);
}

/// Not configured: the screen says why.
pub struct NoPhonebook(watch::Sender<Book>);

impl NoPhonebook {
    pub fn new(why: impl Into<String>) -> NoPhonebook {
        NoPhonebook(watch::Sender::new(Book::off(why)))
    }
}

impl Phonebook for NoPhonebook {
    fn book(&self) -> watch::Receiver<Book> {
        self.0.subscribe()
    }
    fn load(&self, _: Option<String>) {}
}

/// Follows load requests with a [`Reader`].
pub struct Lists {
    want: watch::Sender<(Option<String>, u64)>,
    out: watch::Sender<Book>,
}

impl Lists {
    pub fn start(reader: impl Reader) -> Arc<Lists> {
        let l = Arc::new(Lists {
            want: watch::Sender::new((None, 0)),
            out: watch::Sender::new(Book::none()),
        });
        tokio::spawn(run(Arc::new(reader), l.want.subscribe(), l.out.clone()));
        l
    }
}

impl Phonebook for Lists {
    fn book(&self) -> watch::Receiver<Book> {
        self.out.subscribe()
    }

    fn load(&self, address: Option<String>) {
        self.want.send_modify(|(a, n)| {
            *a = address.map(|s| s.to_ascii_uppercase());
            *n += 1;
        });
    }
}

async fn run(
    reader: Arc<dyn Reader>,
    mut want: watch::Receiver<(Option<String>, u64)>,
    out: watch::Sender<Book>,
) {
    let mut version: u64 = 0;
    loop {
        let (address, _) = want.borrow_and_update().clone();
        let mut book = out.borrow().clone();
        match address {
            None => {
                if book.address.is_some() || book.state != BookState::None {
                    version += 1;
                    out.send_replace(Book {
                        version,
                        ..Book::none()
                    });
                }
            }
            Some(a) => {
                // The same phone's lists stay shown while they are read again.
                if book.address.as_deref() != Some(a.as_str()) {
                    book.contacts = Arc::default();
                    book.recent = Arc::default();
                    version += 1;
                }
                book.address = Some(a.clone());
                book.state = BookState::Loading;
                book.version = version;
                out.send_replace(book.clone());
                let r = tokio::select! {
                    r = reader.read(&a) => Some(r),
                    c = want.changed() => {
                        if c.is_err() { return; }
                        None
                    }
                };
                match r {
                    // A newer request: read that one.
                    None => continue,
                    Some(Ok((contacts, recent))) => {
                        eprintln!(
                            "[audio] phonebook: {} contacts, {} recent calls",
                            contacts.len(),
                            recent.len()
                        );
                        version += 1;
                        out.send_replace(Book {
                            state: BookState::Ready,
                            address: Some(a),
                            contacts: Arc::new(contacts),
                            recent: Arc::new(recent),
                            version,
                        });
                    }
                    Some(Err(why)) => {
                        eprintln!("[audio] phonebook: {why}");
                        book.state = BookState::Failed(why);
                        out.send_replace(book);
                    }
                }
            }
        }
        if want.changed().await.is_err() {
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// The simulated phone's lists

/// Made-up contacts and calls, after a moment, for the Mac and the tests.
pub struct SimReader {
    pub delay: Duration,
}

pub const SIM_CONTACTS: &str = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Alex Rivera\r\nTEL;TYPE=CELL:+1 555 010 1001\r\nTEL;TYPE=WORK:+1 555 010 2001\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Blake Chen\r\nTEL;TYPE=CELL:555-010-1002\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Casey Morgan\r\nTEL;TYPE=HOME:555-010-1003\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Dana Brooks\r\nTEL;TYPE=CELL:555-010-1004\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ellis Parts & Service\r\nTEL;TYPE=WORK:555-010-1005\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Frankie Diaz\r\nTEL;TYPE=CELL:555-010-1006\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Gray's Towing\r\nTEL;TYPE=WORK:555-010-1007\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Harper Lee\r\nTEL;TYPE=CELL:555-010-1008\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jordan Kim\r\nTEL;TYPE=CELL:555-010-1009\r\nTEL;TYPE=HOME:555-010-2009\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Morgan Feed & Supply\r\nTEL;TYPE=WORK:555-010-1010\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Quinn Taylor\r\nTEL;TYPE=CELL:555-010-1011\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Riley Novak\r\nTEL;TYPE=CELL:555-010-1012\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Sam Ortiz\r\nTEL;TYPE=CELL:555-010-1013\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Taylor Diesel Repair\r\nTEL;TYPE=WORK:555-010-1014\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Whitney Hale\r\nTEL;TYPE=CELL:555-010-1015\r\nEND:VCARD\r\n";

pub const SIM_RECENT: &str = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Blake Chen\r\nTEL:555-010-1002\r\nX-IRMC-CALL-DATETIME;TYPE=MISSED:20261114T081500\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:\r\nTEL:555-010-9999\r\nX-IRMC-CALL-DATETIME;TYPE=RECEIVED:20261113T171000\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Taylor Diesel Repair\r\nTEL:555-010-1014\r\nX-IRMC-CALL-DATETIME;TYPE=DIALED:20261113T093000\r\nEND:VCARD\r\n\
BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Alex Rivera\r\nTEL:+15550101001\r\nX-IRMC-CALL-DATETIME;TYPE=RECEIVED:20261112T184500\r\nEND:VCARD\r\n";

#[tonic::async_trait]
impl Reader for SimReader {
    async fn read(&self, _: &str) -> Result<(Vec<Contact>, Vec<Recent>), String> {
        tokio::time::sleep(self.delay).await;
        Ok((contacts(SIM_CONTACTS), recent(SIM_RECENT)))
    }
}

// ---------------------------------------------------------------------------
// obexd

const OBEX: &str = "org.bluez.obex";
const CLIENT_PATH: &str = "/org/bluez/obex";
const CLIENT: &str = "org.bluez.obex.Client1";
const PBAP: &str = "org.bluez.obex.PhonebookAccess1";
const TRANSFER: &str = "org.bluez.obex.Transfer1";
/// Opening the session (the phone may ask its user first).
const SESSION_WAIT: Duration = Duration::from_secs(30);
/// One list.
const PULL_WAIT: Duration = Duration::from_secs(60);

/// Reads over PBAP through obexd into `file` (under /run: memory only).
pub struct ObexReader {
    pub file: PathBuf,
}

fn reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(name, msg, _) => {
            let name = name.as_str();
            if name == "org.freedesktop.DBus.Error.ServiceUnknown" {
                return "obexd isn't running".into();
            }
            if name.ends_with(".Forbidden") {
                return "the phone didn't allow it: allow contact sharing for this head unit in the \
                        phone's Bluetooth settings"
                    .into();
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

impl ObexReader {
    async fn pull(
        &self,
        conn: &Connection,
        session: &OwnedObjectPath,
        list: &str,
        fields: &[&str],
        max: Option<u16>,
    ) -> Result<String, String> {
        let pb = Proxy::new(conn, OBEX, session.as_str(), PBAP)
            .await
            .map_err(|e| e.to_string())?;
        pb.call_method("Select", &("int", list))
            .await
            .map_err(|e| reason(&e))?;
        let target = self
            .file
            .to_str()
            .ok_or("the phonebook file's path isn't UTF-8")?;
        let mut filters: std::collections::HashMap<&str, Z<'_>> = std::collections::HashMap::new();
        filters.insert("Format", Z::from("vcard30"));
        filters.insert("Fields", Z::from(fields.to_vec()));
        if let Some(m) = max {
            filters.insert("MaxCount", Z::from(m));
        }
        let (transfer, _): (
            OwnedObjectPath,
            std::collections::HashMap<String, OwnedValue>,
        ) = pb
            .call("PullAll", &(target, filters))
            .await
            .map_err(|e| reason(&e))?;
        let t = zbus::proxy::Builder::<Proxy<'_>>::new(conn)
            .destination(OBEX)
            .map_err(|e| e.to_string())?
            .path(transfer)
            .map_err(|e| e.to_string())?
            .interface(TRANSFER)
            .map_err(|e| e.to_string())?
            .cache_properties(CacheProperties::No)
            .build()
            .await
            .map_err(|e| e.to_string())?;
        let until = tokio::time::Instant::now() + PULL_WAIT;
        loop {
            match t.get_property::<String>("Status").await {
                Ok(s) if s == "complete" => break,
                Ok(s) if s == "error" => return Err(format!("reading {list} failed")),
                Ok(_) => {}
                // obexd removes a finished transfer's object.
                Err(_) => break,
            }
            if tokio::time::Instant::now() >= until {
                let _ = t.call_method("Cancel", &()).await;
                return Err(format!("{list}: no answer in {} s", PULL_WAIT.as_secs()));
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
        let text = self.take_file().await?;
        Ok(text)
    }

    /// The file's text, removed at once (it holds the owner's contacts).
    async fn take_file(&self) -> Result<String, String> {
        let len = tokio::fs::metadata(&self.file)
            .await
            .map_err(|e| format!("{}: {e}", self.file.display()))?
            .len();
        let r = if len > MAX_FILE {
            Err(format!("the list is too big ({len} bytes)"))
        } else {
            tokio::fs::read(&self.file)
                .await
                .map(|b| String::from_utf8_lossy(&b).into_owned())
                .map_err(|e| format!("{}: {e}", self.file.display()))
        };
        let _ = tokio::fs::remove_file(&self.file).await;
        r
    }
}

#[tonic::async_trait]
impl Reader for ObexReader {
    async fn read(&self, address: &str) -> Result<(Vec<Contact>, Vec<Recent>), String> {
        let conn = Connection::system()
            .await
            .map_err(|e| format!("no system D-Bus ({e})"))?;
        let client = Proxy::new(&conn, OBEX, CLIENT_PATH, CLIENT)
            .await
            .map_err(|e| e.to_string())?;
        let mut args: std::collections::HashMap<&str, Z<'_>> = std::collections::HashMap::new();
        args.insert("Target", Z::from("pbap"));
        let session: OwnedObjectPath =
            tokio::time::timeout(SESSION_WAIT, client.call("CreateSession", &(address, args)))
                .await
                .map_err(|_| format!("the phone didn't answer in {} s", SESSION_WAIT.as_secs()))?
                .map_err(|e| reason(&e))?;
        let r = async {
            let pb = self
                .pull(&conn, &session, "pb", &["VERSION", "FN", "N", "TEL"], None)
                .await?;
            let contacts = contacts(&pb);
            // A phone without call history over PBAP still has contacts.
            let recent = match self
                .pull(
                    &conn,
                    &session,
                    "cch",
                    &["VERSION", "FN", "N", "TEL", "X-IRMC-CALL-DATETIME"],
                    Some(MAX_RECENT),
                )
                .await
            {
                Ok(t) => recent(&t),
                Err(e) => {
                    eprintln!("[audio] phonebook: recent calls: {e}");
                    Vec::new()
                }
            };
            Ok((contacts, recent))
        }
        .await;
        if let Err(e) = client.call_method("RemoveSession", &(&session,)).await {
            eprintln!("[audio] phonebook: removing the session: {}", reason(&e));
        }
        let _ = tokio::fs::remove_file(&self.file).await;
        r
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn a_v30_card() {
        let c = contacts(
            "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ana\\, Mechanic\r\nN:Mechanic;Ana;;;\r\n\
             TEL;TYPE=CELL,VOICE:+1 (555) 010-0001\r\nTEL;TYPE=WORK:555 010 0002\r\n\
             TEL;TYPE=FAX:555 010 0003\r\nEND:VCARD\r\n",
        );
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].name, "Ana, Mechanic");
        assert_eq!(
            c[0].numbers,
            vec![
                Number {
                    number: "+1 (555) 010-0001".into(),
                    label: "Mobile".into()
                },
                Number {
                    number: "555 010 0002".into(),
                    label: "Work".into()
                },
            ],
            "the fax is left out"
        );
    }

    #[test]
    fn a_v21_card_with_quoted_printable_and_folding() {
        // José, quoted-printable UTF-8 over a soft line break; a folded TEL.
        let c = contacts(
            "BEGIN:VCARD\nVERSION:2.1\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Garc=C3=ADa;Jos=\n=C3=A9;;;\n\
             TEL;CELL;PREF:555\n 0100\nTEL;HOME:5550100\nEND:VCARD\n",
        );
        assert_eq!(c[0].name, "José García", "N's given then family name");
        assert_eq!(c[0].numbers.len(), 1, "the same number twice is kept once");
        assert_eq!(c[0].numbers[0].number, "5550100");
        assert_eq!(c[0].numbers[0].label, "Mobile");
    }

    #[test]
    fn contacts_without_numbers_go_and_the_rest_sort_by_name() {
        let c = contacts(
            "BEGIN:VCARD\nFN:zed\nTEL:1\nEND:VCARD\nBEGIN:VCARD\nFN:No Number\nEND:VCARD\n\
             BEGIN:VCARD\nTEL:2\nEND:VCARD\nBEGIN:VCARD\nFN:Amy\nTEL;X-CUSTOM:3\nEND:VCARD\n\
             BEGIN:VCARD\nFN:Bad\nTEL:none\nEND:VCARD\n",
        );
        let names: Vec<&str> = c.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names, vec!["Amy", "zed", ""], "no name last");
        assert_eq!(c[0].numbers[0].label, "Other");
        assert_eq!(c[1].numbers[0].label, "");
    }

    #[test]
    fn a_tel_uri_and_a_group_prefix() {
        let c = contacts("BEGIN:VCARD\nitem1.TEL;TYPE=cell:tel:+15550100\nFN:X\nEND:VCARD\n");
        assert_eq!(c[0].numbers[0].number, "+15550100");
        assert_eq!(c[0].numbers[0].label, "Mobile");
    }

    #[test]
    fn recent_calls_newest_first() {
        let r = recent(SIM_RECENT);
        assert_eq!(r.len(), 4);
        assert_eq!(r[0].kind, RecentKind::Missed);
        assert_eq!(r[0].time, "2026-11-14T08:15:00");
        assert_eq!(r[1].name, "", "an empty FN");
        assert_eq!(r[1].number, "555-010-9999");
        assert_eq!(r[2].kind, RecentKind::Dialed);
        assert_eq!(r[3].kind, RecentKind::Received);
        // 2.1's bare parameter, a Z, and no time at all.
        let r = recent(
            "BEGIN:VCARD\nTEL:1\nX-IRMC-CALL-DATETIME;DIALED:20260101T000000Z\nEND:VCARD\n\
             BEGIN:VCARD\nTEL:2\nEND:VCARD\nBEGIN:VCARD\nTEL:3\nX-IRMC-CALL-DATETIME;MISSED:bad\nEND:VCARD\n",
        );
        assert_eq!(r[0].kind, RecentKind::Dialed);
        assert_eq!(r[0].time, "2026-01-01T00:00:00");
        assert_eq!(r[1].kind, RecentKind::Unknown);
        assert_eq!(r[2].kind, RecentKind::Missed);
        assert_eq!(r[2].time, "");
    }

    #[test]
    fn the_sim_contacts_parse() {
        let c = contacts(SIM_CONTACTS);
        assert_eq!(c.len(), 15);
        assert_eq!(c[0].name, "Alex Rivera");
        assert_eq!(c[0].numbers.len(), 2);
    }

    #[test]
    fn a_number_finds_its_contact() {
        let c = contacts(SIM_CONTACTS);
        assert_eq!(name_for(&c, "5550101002").as_deref(), Some("Blake Chen"));
        assert_eq!(
            name_for(&c, "+15550101002").as_deref(),
            Some("Blake Chen"),
            "a country code on one side"
        );
        assert_eq!(
            name_for(&c, "+1 555 010 2001").as_deref(),
            Some("Alex Rivera")
        );
        assert_eq!(name_for(&c, "5550109999"), None);
        assert_eq!(
            name_for(&c, "0101002"),
            Some("Blake Chen".into()),
            "7 digits"
        );
        assert_eq!(name_for(&c, "101002"), None, "too short to match a part");
        assert_eq!(name_for(&c, ""), None);
    }

    #[test]
    fn numbers_to_dial() {
        assert_eq!(dial_number(" +1 (555) 010-0100 ").unwrap(), "+15550100100");
        assert_eq!(dial_number("*67#").unwrap(), "*67#");
        assert!(dial_number("").is_err());
        assert!(dial_number("+").is_err());
        assert!(dial_number("1+2").is_err(), "+ only first");
        assert!(dial_number("555-CALL").is_err());
        assert!(dial_number(&"1".repeat(81)).is_err());
    }

    struct Fake {
        delay: Duration,
        fail: bool,
    }

    #[tonic::async_trait]
    impl Reader for Fake {
        async fn read(&self, a: &str) -> Result<(Vec<Contact>, Vec<Recent>), String> {
            tokio::time::sleep(self.delay).await;
            if self.fail {
                return Err("Forbidden".into());
            }
            Ok((
                vec![Contact {
                    name: a.into(),
                    numbers: vec![],
                }],
                vec![],
            ))
        }
    }

    async fn settle(rx: &mut watch::Receiver<Book>, want: BookState) -> Book {
        loop {
            let b = rx.borrow_and_update().clone();
            if b.state == want {
                return b;
            }
            rx.changed().await.unwrap();
        }
    }

    #[tokio::test(start_paused = true)]
    async fn loads_the_connected_phone_and_the_latest_wins() {
        let l = Lists::start(Fake {
            delay: Duration::from_secs(1),
            fail: false,
        });
        let mut rx = l.book();
        assert_eq!(rx.borrow().state, BookState::None);
        l.load(Some("aa".into()));
        let b = settle(&mut rx, BookState::Loading).await;
        assert_eq!(b.address.as_deref(), Some("AA"));
        // Another phone before the first answers: only its lists.
        l.load(Some("bb".into()));
        let b = settle(&mut rx, BookState::Ready).await;
        assert_eq!(b.contacts[0].name, "BB");
        let v = b.version;
        // Read again: still shown while loading.
        l.load(Some("bb".into()));
        let b = settle(&mut rx, BookState::Loading).await;
        assert_eq!(b.contacts.len(), 1);
        let b = settle(&mut rx, BookState::Ready).await;
        assert!(b.version > v);
        // No phone: nothing.
        l.load(None);
        let b = settle(&mut rx, BookState::None).await;
        assert!(b.contacts.is_empty());
        assert!(b.address.is_none());
    }

    #[tokio::test(start_paused = true)]
    async fn a_refusal_is_said() {
        let l = Lists::start(Fake {
            delay: Duration::from_millis(10),
            fail: true,
        });
        let mut rx = l.book();
        l.load(Some("aa".into()));
        let b = settle(&mut rx, BookState::Failed("Forbidden".into())).await;
        assert!(b.contacts.is_empty());
    }

    #[tokio::test]
    async fn the_file_is_removed_after_reading() {
        let file = std::env::temp_dir().join(format!("f250-pb-{}", std::process::id()));
        std::fs::write(&file, SIM_CONTACTS).unwrap();
        let r = ObexReader { file: file.clone() };
        assert!(r.take_file().await.unwrap().contains("Alex Rivera"));
        assert!(!file.exists());
    }
}
