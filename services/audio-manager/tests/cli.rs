//! The binary starts with its defaults: every argument's default parses
//! (an empty PathBuf default once kept it from starting at all, which no
//! library test saw). `--print-dsp-config` exits after printing.

#![allow(clippy::unwrap_used)]

use std::process::Command;

const BIN: &str = env!("CARGO_BIN_EXE_audio-manager");

#[test]
fn defaults_parse_and_the_dsp_config_prints() {
    for extra in [
        &[][..],
        &["--simulate"][..],
        &["--voice-command", "say"][..],
        &["--call-mic", "usb-mic"][..],
        &["--simulate", "--sim-call-every-s", "30"][..],
    ] {
        let out = Command::new(BIN)
            .args(extra)
            .arg("--print-dsp-config")
            .output()
            .unwrap();
        assert!(
            out.status.success(),
            "{extra:?}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        let conf = String::from_utf8(out.stdout).unwrap();
        assert!(conf.contains("libpipewire-module-filter-chain"));
        assert!(conf.contains("\"Freq\" = 80.0"));
    }
}

#[test]
fn bad_configuration_refuses_to_start() {
    for bad in [
        &["--sub", "1,5"][..],
        &["--crossover-hz", "1000"][..],
        &["--dac-positions", "FL,FL,RL,RR,FC,LFE"][..],
    ] {
        let out = Command::new(BIN)
            .args(bad)
            .arg("--print-dsp-config")
            .output()
            .unwrap();
        assert!(!out.status.success(), "{bad:?} started");
    }
}
