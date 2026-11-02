//! Telemetry recorder storage (PROJECT_PLAN 3.10).
//!
//! SQLite in WAL mode with `synchronous=NORMAL`, so a power cut loses at most
//! the last moments, not the file. Writes are batched per snapshot. Retention
//! is bounded by age and by row count, so the SD card or SSD can't fill up.
//! Raw adapter traffic is not stored here; the gateway keeps its own bounded
//! rotating traffic log (`--traffic-log`).

use std::path::Path;

use f250_proto::vehicle::v1 as pb;
use rusqlite::{Connection, params};

pub const SCHEMA_VERSION: i64 = 1;

#[derive(Debug, Clone, Copy)]
pub struct Retention {
    /// Rows older than this are deleted.
    pub max_age_days: u32,
    /// Hard cap on sample rows (oldest deleted first).
    pub max_sample_rows: u64,
}

impl Default for Retention {
    fn default() -> Self {
        // ~16 signals at 1 Hz ≈ 58 k rows/hour; 2 M rows ≈ 35 hours of driving.
        Retention {
            max_age_days: 30,
            max_sample_rows: 2_000_000,
        }
    }
}

pub struct Db {
    conn: Connection,
    /// Gateway session (increments when the gateway's monotonic clock goes
    /// backwards, i.e. it restarted), so event de-duplication stays correct.
    session: i64,
    last_mono: u64,
    last_event_mono: Option<u64>,
}

impl Db {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        Self::init(Connection::open(path)?)
    }

    pub fn in_memory() -> rusqlite::Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> rusqlite::Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS samples (
                 wall_ms INTEGER NOT NULL, session INTEGER NOT NULL, mono_ms INTEGER NOT NULL,
                 signal_id TEXT NOT NULL, validity TEXT NOT NULL,
                 value REAL, last_good_value REAL, last_good_raw REAL, age_ms INTEGER,
                 rejected_value REAL, nrc INTEGER, responder TEXT, latency_ms INTEGER,
                 successes INTEGER, failures INTEGER, poll_state TEXT);
             CREATE INDEX IF NOT EXISTS samples_time ON samples (wall_ms);
             CREATE INDEX IF NOT EXISTS samples_signal_time ON samples (signal_id, wall_ms);
             CREATE TABLE IF NOT EXISTS link (
                 wall_ms INTEGER NOT NULL, session INTEGER NOT NULL, mono_ms INTEGER NOT NULL,
                 state TEXT NOT NULL, machine_state TEXT, transport TEXT, simulated INTEGER,
                 transmit_enabled INTEGER, requests_per_second REAL, adapter_voltage REAL,
                 scenario TEXT, detail TEXT);
             CREATE INDEX IF NOT EXISTS link_time ON link (wall_ms);
             CREATE TABLE IF NOT EXISTS events (
                 wall_ms INTEGER NOT NULL, session INTEGER NOT NULL, mono_ms INTEGER NOT NULL,
                 severity TEXT NOT NULL, message TEXT NOT NULL);
             CREATE INDEX IF NOT EXISTS events_time ON events (wall_ms);",
        )?;
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?1)",
            params![SCHEMA_VERSION.to_string()],
        )?;
        let session: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(session), 0) + 1 FROM samples",
                [],
                |r| r.get(0),
            )
            .unwrap_or(1);
        Ok(Db {
            conn,
            session,
            last_mono: 0,
            last_event_mono: None,
        })
    }

    pub fn session(&self) -> i64 {
        self.session
    }

    fn track_session(&mut self, mono_ms: u64) {
        if mono_ms < self.last_mono {
            self.session += 1;
            self.last_event_mono = None;
        }
        self.last_mono = mono_ms;
    }

    /// Writes one snapshot (all signals + link) in one transaction.
    pub fn record_snapshot(&mut self, wall_ms: i64, snap: &pb::Snapshot) -> rusqlite::Result<()> {
        self.track_session(snap.mono_ms);
        let session = self.session;
        let tx = self.conn.transaction()?;
        {
            let mut ins = tx.prepare_cached(
                "INSERT INTO samples (wall_ms, session, mono_ms, signal_id, validity, value,
                     last_good_value, last_good_raw, age_ms, rejected_value, nrc, responder,
                     latency_ms, successes, failures, poll_state)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)",
            )?;
            for s in &snap.samples {
                ins.execute(params![
                    wall_ms,
                    session,
                    snap.mono_ms as i64,
                    s.signal_id,
                    validity_name(s.validity),
                    s.value,
                    s.last_good_value,
                    s.last_good_raw,
                    s.last_good_age_ms.map(|a| a as i64),
                    s.rejected_value,
                    (s.last_nrc != 0).then_some(s.last_nrc),
                    (!s.last_responder.is_empty()).then_some(&s.last_responder),
                    (s.last_latency_ms != 0).then_some(s.last_latency_ms),
                    s.successes as i64,
                    s.failures as i64,
                    s.poll_state,
                ])?;
            }
            if let Some(l) = &snap.link {
                tx.execute(
                    "INSERT INTO link (wall_ms, session, mono_ms, state, machine_state, transport,
                         simulated, transmit_enabled, requests_per_second, adapter_voltage, scenario, detail)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
                    params![
                        wall_ms,
                        session,
                        snap.mono_ms as i64,
                        link_state_name(l.state),
                        l.machine_state,
                        l.transport,
                        l.simulated,
                        l.transmit_enabled,
                        l.requests_per_second,
                        l.adapter_voltage,
                        (!l.scenario.is_empty()).then_some(&l.scenario),
                        (!l.detail.is_empty()).then_some(&l.detail),
                    ],
                )?;
            }
        }
        tx.commit()
    }

    /// Stores events not seen before (the gateway returns its whole recent
    /// history each time). Returns how many were new.
    pub fn record_events(&mut self, events: &pb::ListEventsResponse) -> rusqlite::Result<usize> {
        let mut new: Vec<&pb::Event> = events
            .events
            .iter()
            .filter(|e| self.last_event_mono.is_none_or(|m| e.mono_ms > m))
            .collect();
        new.sort_by_key(|e| e.mono_ms);
        let session = self.session;
        let tx = self.conn.transaction()?;
        for e in &new {
            tx.execute(
                "INSERT INTO events (wall_ms, session, mono_ms, severity, message) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![e.wall_ms, session, e.mono_ms as i64, severity_name(e.severity), e.message],
            )?;
        }
        tx.commit()?;
        if let Some(last) = new.last() {
            self.last_event_mono = Some(last.mono_ms);
        }
        Ok(new.len())
    }

    /// Applies the retention limits. Returns sample rows deleted.
    pub fn prune(&mut self, now_wall_ms: i64, r: Retention) -> rusqlite::Result<usize> {
        let cutoff = now_wall_ms - i64::from(r.max_age_days) * 86_400_000;
        let mut deleted = self
            .conn
            .execute("DELETE FROM samples WHERE wall_ms < ?1", params![cutoff])?;
        self.conn
            .execute("DELETE FROM link WHERE wall_ms < ?1", params![cutoff])?;
        self.conn
            .execute("DELETE FROM events WHERE wall_ms < ?1", params![cutoff])?;
        let rows: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM samples", [], |x| x.get(0))?;
        let excess = rows - r.max_sample_rows as i64;
        if excess > 0 {
            deleted += self.conn.execute(
                "DELETE FROM samples WHERE rowid IN (SELECT rowid FROM samples ORDER BY wall_ms LIMIT ?1)",
                params![excess],
            )?;
        }
        Ok(deleted)
    }

    pub fn sample_rows(&self) -> rusqlite::Result<i64> {
        self.conn
            .query_row("SELECT COUNT(*) FROM samples", [], |x| x.get(0))
    }

    /// CSV of samples, optionally limited to signals and a time window.
    pub fn export_samples_csv(
        &self,
        out: &mut dyn std::io::Write,
        signals: &[String],
        from_wall_ms: Option<i64>,
        to_wall_ms: Option<i64>,
    ) -> Result<usize, Box<dyn std::error::Error>> {
        writeln!(
            out,
            "wall_ms,session,mono_ms,signal_id,validity,value,last_good_value,last_good_raw,age_ms,rejected_value,nrc,responder,latency_ms,successes,failures,poll_state"
        )?;
        let mut stmt = self.conn.prepare(
            "SELECT wall_ms, session, mono_ms, signal_id, validity, value, last_good_value,
                    last_good_raw, age_ms, rejected_value, nrc, responder, latency_ms,
                    successes, failures, poll_state
             FROM samples WHERE wall_ms >= ?1 AND wall_ms <= ?2 ORDER BY wall_ms, signal_id",
        )?;
        let mut rows = stmt.query(params![
            from_wall_ms.unwrap_or(i64::MIN),
            to_wall_ms.unwrap_or(i64::MAX)
        ])?;
        let mut n = 0;
        while let Some(r) = rows.next()? {
            let signal: String = r.get(3)?;
            if !signals.is_empty() && !signals.contains(&signal) {
                continue;
            }
            let opt_f = |i: usize| -> rusqlite::Result<String> {
                Ok(r.get::<_, Option<f64>>(i)?
                    .map(|v| v.to_string())
                    .unwrap_or_default())
            };
            let opt_i = |i: usize| -> rusqlite::Result<String> {
                Ok(r.get::<_, Option<i64>>(i)?
                    .map(|v| v.to_string())
                    .unwrap_or_default())
            };
            writeln!(
                out,
                "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}",
                r.get::<_, i64>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, i64>(2)?,
                csv(&signal),
                csv(&r.get::<_, String>(4)?),
                opt_f(5)?,
                opt_f(6)?,
                opt_f(7)?,
                opt_i(8)?,
                opt_f(9)?,
                opt_i(10)?,
                csv(&r.get::<_, Option<String>>(11)?.unwrap_or_default()),
                opt_i(12)?,
                r.get::<_, i64>(13)?,
                r.get::<_, i64>(14)?,
                csv(&r.get::<_, Option<String>>(15)?.unwrap_or_default()),
            )?;
            n += 1;
        }
        Ok(n)
    }

    pub fn export_events_csv(
        &self,
        out: &mut dyn std::io::Write,
    ) -> Result<usize, Box<dyn std::error::Error>> {
        writeln!(out, "wall_ms,session,mono_ms,severity,message")?;
        let mut stmt = self.conn.prepare(
            "SELECT wall_ms, session, mono_ms, severity, message FROM events ORDER BY wall_ms, mono_ms, rowid",
        )?;
        let mut rows = stmt.query([])?;
        let mut n = 0;
        while let Some(r) = rows.next()? {
            writeln!(
                out,
                "{},{},{},{},{}",
                r.get::<_, i64>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, i64>(2)?,
                csv(&r.get::<_, String>(3)?),
                csv(&r.get::<_, String>(4)?)
            )?;
            n += 1;
        }
        Ok(n)
    }
}

/// RFC 4180 quoting when needed.
fn csv(s: &str) -> String {
    if s.contains([',', '"', '\n', '\r']) {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

fn validity_name(v: i32) -> &'static str {
    match pb::Validity::try_from(v).unwrap_or(pb::Validity::Unspecified) {
        pb::Validity::Valid => "VALID",
        pb::Validity::Stale => "STALE",
        pb::Validity::NoData => "NO_DATA",
        pb::Validity::OutOfRange => "OUT_OF_RANGE",
        pb::Validity::DecodeError => "DECODE_ERROR",
        pb::Validity::Unsupported => "UNSUPPORTED",
        pb::Validity::Disabled => "DISABLED",
        pb::Validity::Unspecified => "UNSPECIFIED",
    }
}

fn link_state_name(v: i32) -> &'static str {
    match pb::LinkState::try_from(v).unwrap_or(pb::LinkState::Unspecified) {
        pb::LinkState::Connecting => "CONNECTING",
        pb::LinkState::Up => "UP",
        pb::LinkState::Degraded => "DEGRADED",
        pb::LinkState::Down => "DOWN",
        pb::LinkState::Unspecified => "UNSPECIFIED",
    }
}

fn severity_name(v: i32) -> &'static str {
    match pb::EventSeverity::try_from(v).unwrap_or(pb::EventSeverity::Unspecified) {
        pb::EventSeverity::Critical => "CRITICAL",
        pb::EventSeverity::Advisory => "ADVISORY",
        pb::EventSeverity::Info => "INFO",
        pb::EventSeverity::Unspecified => "UNSPECIFIED",
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;

    fn snap(mono: u64, value: Option<f64>) -> pb::Snapshot {
        pb::Snapshot {
            mono_ms: mono,
            samples: vec![
                pb::Sample {
                    signal_id: "eot".into(),
                    validity: if value.is_some() {
                        pb::Validity::Valid
                    } else {
                        pb::Validity::Stale
                    } as i32,
                    value,
                    last_good_value: Some(92.0),
                    last_good_age_ms: Some(400),
                    successes: 5,
                    poll_state: "ACTIVE".into(),
                    last_responder: "7E8".into(),
                    ..Default::default()
                },
                pb::Sample {
                    signal_id: "rpm".into(),
                    validity: pb::Validity::Valid as i32,
                    value: Some(700.0),
                    ..Default::default()
                },
            ],
            link: Some(pb::LinkStatus {
                state: pb::LinkState::Up as i32,
                machine_state: "POLLING".into(),
                transport: "obdlink".into(),
                adapter_voltage: Some(12.6),
                ..Default::default()
            }),
            alerts: vec![],
        }
    }

    #[test]
    fn records_samples_and_link_and_exports_csv() {
        let mut db = Db::in_memory().unwrap();
        db.record_snapshot(1_000, &snap(100, Some(92.0))).unwrap();
        db.record_snapshot(2_000, &snap(1100, None)).unwrap();
        assert_eq!(db.sample_rows().unwrap(), 4);
        let mut out = Vec::new();
        let n = db
            .export_samples_csv(&mut out, &["eot".into()], None, None)
            .unwrap();
        assert_eq!(n, 2);
        let text = String::from_utf8(out).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert!(lines[0].starts_with("wall_ms,session"));
        assert!(lines[1].contains(",eot,VALID,92,92,"), "{}", lines[1]);
        assert!(
            lines[2].contains(",eot,STALE,,92,"),
            "stale row keeps no current value: {}",
            lines[2]
        );
    }

    #[test]
    fn events_are_deduplicated_and_sessions_follow_gateway_restarts() {
        let mut db = Db::in_memory().unwrap();
        let ev = |mono: u64, m: &str| pb::Event {
            mono_ms: mono,
            wall_ms: mono as i64,
            severity: 1,
            message: m.into(),
        };
        let batch = pb::ListEventsResponse {
            events: vec![ev(20, "b"), ev(10, "a")],
            dropped: 0,
        };
        assert_eq!(db.record_events(&batch).unwrap(), 2);
        assert_eq!(db.record_events(&batch).unwrap(), 0, "already stored");
        let s1 = db.session();
        db.record_snapshot(1, &snap(5000, Some(1.0))).unwrap();
        db.record_snapshot(2, &snap(10, Some(1.0))).unwrap(); // gateway restarted
        assert_eq!(db.session(), s1 + 1);
        assert_eq!(
            db.record_events(&pb::ListEventsResponse {
                events: vec![ev(5, "after restart")],
                dropped: 0
            })
            .unwrap(),
            1
        );
        let mut out = Vec::new();
        assert_eq!(db.export_events_csv(&mut out).unwrap(), 3);
    }

    #[test]
    fn retention_by_age_and_row_cap() {
        let mut db = Db::in_memory().unwrap();
        let day = 86_400_000;
        db.record_snapshot(0, &snap(1, Some(1.0))).unwrap();
        db.record_snapshot(40 * day, &snap(2, Some(1.0))).unwrap();
        let deleted = db
            .prune(
                40 * day,
                Retention {
                    max_age_days: 30,
                    max_sample_rows: 1_000,
                },
            )
            .unwrap();
        assert_eq!(deleted, 2, "the 40-day-old snapshot's two rows");
        for i in 0..10 {
            db.record_snapshot(40 * day + i, &snap(3 + i as u64, Some(1.0)))
                .unwrap();
        }
        db.prune(
            40 * day + 100,
            Retention {
                max_age_days: 30,
                max_sample_rows: 5,
            },
        )
        .unwrap();
        assert_eq!(db.sample_rows().unwrap(), 5);
    }

    #[test]
    fn csv_quoting() {
        assert_eq!(csv("plain"), "plain");
        assert_eq!(csv("a,b"), "\"a,b\"");
        assert_eq!(csv("say \"hi\""), "\"say \"\"hi\"\"\"");
    }

    #[test]
    fn survives_reopen_on_disk() {
        let path =
            std::env::temp_dir().join(format!("f250-recorder-{}.sqlite", std::process::id()));
        let _ = std::fs::remove_file(&path);
        {
            let mut db = Db::open(&path).unwrap();
            db.record_snapshot(1, &snap(1, Some(1.0))).unwrap();
        }
        let db = Db::open(&path).unwrap();
        assert_eq!(db.sample_rows().unwrap(), 2);
        assert_eq!(db.session(), 2, "a new recorder run is a new session");
        let _ = std::fs::remove_file(&path);
    }
}
