//! The speakers' filter-chain runner [SIM], against a fake `pipewire` (a
//! script that records its arguments and the configuration it was given,
//! then waits) and a fake `pw-cli`: start, a live fader change, a crossover
//! change that restarts it, a failed live change that falls back to a
//! restart, and a crash that is restarted.

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
fn fakes(d: &Path) -> (PathBuf, PathBuf) {
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
    (pw, cli)
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
    let (pipewire, pw_cli) = fakes(d);
    PipewireDsp::new(PipewireConfig {
        pipewire,
        pw_cli,
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
    assert_eq!(starts(&d), ["crossover 80 Hz"]);
    let conf = std::fs::read_to_string(d.join("run/speakers.conf")).unwrap();
    assert!(conf.contains("filter.smart.target = { node.name = \"dac\" }"));

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

    // Crossover: a restart, with the fader kept.
    let r = dsp
        .apply(Settings {
            fader: 3,
            crossover_hz: 100,
            ..Settings::default()
        })
        .await
        .unwrap();
    assert!(r.contains("restart"), "{r}");
    wait("restarted", || starts(&d).len() == 2).await;
    assert_eq!(starts(&d)[1], "crossover 100 Hz");
    wait("applied", || *state.borrow() == DspState::Applied).await;
    let conf = std::fs::read_to_string(d.join("run/speakers.conf")).unwrap();
    assert!(conf.contains("fader 3"));
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
    assert_eq!(starts(&d).len(), 2);
}

#[tokio::test]
async fn no_pipewire_binary_is_not_running_with_a_reason() {
    let d = dir("missing");
    let dsp = PipewireDsp::new(PipewireConfig {
        pipewire: d.join("no-such-pipewire"),
        pw_cli: d.join("no-such-pw-cli"),
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
