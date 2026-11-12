//! The speakers' filter-chain runner [SIM], against a fake `pipewire` (a
//! script that records its arguments and the configuration it was given,
//! then waits), a fake `pw-cli` and a fake `pw-metadata`: start, live fader
//! and crossover changes, a failed live change that falls back to a
//! restart, a crash that is restarted, and WirePlumber asked to relink after
//! every start.

#![allow(clippy::unwrap_used)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use audio_manager::dsp::{ChannelMap, Limits, Settings, Target};
use audio_manager::runner::{Dsp, DspState, PipewireConfig, PipewireDsp};

fn dir(test: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("f250-audio-dsp-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).expect("temp dir");
    d
}

fn script(path: &Path, body: &str) {
    std::fs::write(path, format!("#!/bin/sh\n{body}\n")).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// Fake pipewire: appends "start <crossover line>" to starts.log, writes its
/// pid, then sleeps until killed (or exits at once when `crash` exists).
/// Fake pw-cli and pw-metadata log their arguments.
fn fakes(d: &Path) -> (PathBuf, PathBuf, PathBuf) {
    let pw = d.join("pipewire");
    script(
        &pw,
        &format!(
            "[ \"$1\" = -c ] || exit 9\n\
             grep -o 'crossover [0-9]* Hz' \"$2\" >> {d}/starts.log\n\
             echo $$ > {d}/pid\n\
             [ -e {d}/crash ] && {{ rm {d}/crash; exit 3; }}\n\
             exec sleep 30",
            d = d.display()
        ),
    );
    let cli = d.join("pw-cli");
    script(
        &cli,
        &format!(
            "echo \"$@\" >> {d}/cli.log\n[ -e {d}/cli-fails ] && {{ echo 'Error: no such node' >&2; exit 1; }}\nexit 0",
            d = d.display()
        ),
    );
    let meta = d.join("pw-metadata");
    script(
        &meta,
        &format!("echo \"$@\" >> {d}/meta.log\nexit 0", d = d.display()),
    );
    (pw, cli, meta)
}

fn relinks(d: &Path) -> Vec<String> {
    std::fs::read_to_string(d.join("meta.log"))
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}

fn starts(d: &Path) -> Vec<String> {
    std::fs::read_to_string(d.join("starts.log"))
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect()
}

async fn wait(what: &str, mut f: impl FnMut() -> bool) {
    for _ in 0..200 {
        if f() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("timed out: {what}");
}

fn runner(d: &Path) -> Arc<PipewireDsp> {
    let (pipewire, pw_cli, pw_metadata) = fakes(d);
    PipewireDsp::new(PipewireConfig {
        pipewire,
        pw_cli,
        pw_metadata,
        conf: d.join("run/speakers.conf"),
        limits: Limits::default(),
        target: Target {
            dac_node: "dac".into(),
            map: ChannelMap::default(),
        },
        settle: Duration::from_millis(200),
        max_backoff: Duration::from_millis(400),
    })
}

#[tokio::test]
async fn start_live_change_and_restart() {
    let d = dir("live");
    let dsp = runner(&d);
    let state = dsp.state();
    dsp.start(Settings::default()).await;
    wait("applied", || *state.borrow() == DspState::Applied).await;
    // "Applied" comes after the settle time, not after the fake has logged
    // its start: under load the script can still be on its grep.
    wait("the fake pipewire's start logged", || {
        !starts(&d).is_empty()
    })
    .await;
    assert_eq!(starts(&d), ["crossover 80 Hz"]);
    let conf = std::fs::read_to_string(d.join("run/speakers.conf")).unwrap();
    assert!(conf.contains("filter.smart.target = { node.name = \"dac\" }"));
    // WirePlumber asked to relink the chain through it.
    assert_eq!(relinks(&d), ["-n filters 0 f250.speakers.started 1"]);

    // Fader: live, no restart.
    let r = dsp
        .apply(Settings {
            fader: 3,
            ..Settings::default()
        })
        .await
        .unwrap();
    assert_eq!(r, "Applied.");
    let cli = std::fs::read_to_string(d.join("cli.log")).unwrap();
    assert!(
        cli.starts_with("set-param f250.speakers Props { params = ["),
        "{cli}"
    );
    assert!(cli.contains("\"gain_fl:Gain 1\" 1.000000"));
    assert_eq!(starts(&d).len(), 1);

    // Crossover: live too, no restart (a restart bypasses the filter for a
    // moment), with the fader kept.
    let r = dsp
        .apply(Settings {
            fader: 3,
            crossover_hz: 100,
            ..Settings::default()
        })
        .await
        .unwrap();
    assert_eq!(r, "Applied.");
    let cli = std::fs::read_to_string(d.join("cli.log")).unwrap();
    let last = cli.lines().last().unwrap();
    assert!(last.contains("\"hp_fl1:Freq\" 100.000000"), "{last}");
    assert!(last.contains("\"lp_sub2:Freq\" 100.000000"), "{last}");
    assert!(last.contains("\"gain_fl:Gain 1\" 1.000000"), "{last}");
    assert_eq!(starts(&d).len(), 1);
    assert_eq!(relinks(&d).len(), 1);

    // A later restart (here a failed live change) starts with the live
    // crossover and asks for a relink again.
    std::fs::write(d.join("cli-fails"), "").unwrap();
    dsp.apply(Settings {
        fader: 2,
        crossover_hz: 100,
        ..Settings::default()
    })
    .await
    .unwrap();
    wait("restarted", || starts(&d).len() == 2).await;
    assert_eq!(starts(&d)[1], "crossover 100 Hz");
    wait("relinked again", || relinks(&d).len() == 2).await;
    assert_eq!(relinks(&d)[1], "-n filters 0 f250.speakers.started 2");
}

#[tokio::test]
async fn failed_live_change_falls_back_to_a_restart() {
    let d = dir("fallback");
    let dsp = runner(&d);
    let state = dsp.state();
    dsp.start(Settings::default()).await;
    wait("applied", || *state.borrow() == DspState::Applied).await;
    std::fs::write(d.join("cli-fails"), "").unwrap();
    let r = dsp
        .apply(Settings {
            sub_level_db: -5,
            ..Settings::default()
        })
        .await
        .unwrap();
    assert!(r.contains("restart"), "{r}");
    wait("restarted", || starts(&d).len() == 2).await;
}

#[tokio::test]
async fn a_crash_is_reported_and_restarted() {
    let d = dir("crash");
    std::fs::write(d.join("crash"), "").unwrap();
    let dsp = runner(&d);
    let mut state = dsp.state();
    dsp.start(Settings::default()).await;
    // The first child exits at once: not running, then started again.
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if matches!(&*state.borrow_and_update(), DspState::NotRunning(why) if why.contains("stopped")) {
                return;
            }
            state.changed().await.unwrap();
        }
    })
    .await
    .expect("NotRunning reported");
    wait("applied after the restart", || {
        *state.borrow() == DspState::Applied
    })
    .await;
    wait("the second start logged", || starts(&d).len() >= 2).await;
    assert_eq!(starts(&d).len(), 2);
    // The start that settled asked for a relink (under load the crashing
    // child can outlive the settle time too, and then it asked as well).
    let r = relinks(&d);
    assert!(!r.is_empty() && r.len() <= 2, "{r:?}");
    assert!(
        r.last()
            .unwrap()
            .starts_with("-n filters 0 f250.speakers.started ")
    );
}

#[tokio::test]
async fn no_pw_metadata_still_runs_the_filter() {
    let d = dir("nometa");
    let (pipewire, pw_cli, _) = fakes(&d);
    let dsp = PipewireDsp::new(PipewireConfig {
        pipewire,
        pw_cli,
        pw_metadata: d.join("no-such-pw-metadata"),
        conf: d.join("run/speakers.conf"),
        limits: Limits::default(),
        target: Target {
            dac_node: String::new(),
            map: ChannelMap::default(),
        },
        settle: Duration::from_millis(100),
        max_backoff: Duration::from_millis(200),
    });
    let state = dsp.state();
    dsp.start(Settings::default()).await;
    wait("applied", || *state.borrow() == DspState::Applied).await;
}

#[tokio::test]
async fn no_pipewire_binary_is_not_running_with_a_reason() {
    let d = dir("missing");
    let dsp = PipewireDsp::new(PipewireConfig {
        pipewire: d.join("no-such-pipewire"),
        pw_cli: d.join("no-such-pw-cli"),
        pw_metadata: d.join("no-such-pw-metadata"),
        conf: d.join("speakers.conf"),
        limits: Limits::default(),
        target: Target {
            dac_node: String::new(),
            map: ChannelMap::default(),
        },
        settle: Duration::from_millis(100),
        max_backoff: Duration::from_millis(200),
    });
    let state = dsp.state();
    dsp.start(Settings::default()).await;
    wait(
        "not running",
        || matches!(&*state.borrow(), DspState::NotRunning(why) if why.contains("can't start")),
    )
    .await;
}
