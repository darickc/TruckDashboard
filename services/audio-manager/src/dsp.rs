//! The speakers' DSP (ADR-0014 decision 5, ADR-0039 decision 6): a PipeWire
//! filter-chain in front of the HiFiBerry DAC8x. Stereo in; out to the DAC's
//! channels: front L/R and rear L/R high-passed, the sub (L+R)/2 low-passed
//! on both legs of its jack, the spare jack silent. Fader, balance and sub
//! level are gains, and so is the master volume (ADR-0043), on every output;
//! the crossover is a 4th-order Linkwitz-Riley (two
//! Butterworth biquads, Q 0.7071, on each side).
//!
//! Every number in [`Limits::default`] and [`Settings::default`] is an
//! example (CLAUDE.md rule 10). Which DAC channel comes out of which jack is
//! UNVERIFIED (found on the bench with a test tone, wiring/audio.md), so the
//! channel map is configuration too.
//!
//! The filter-chain's builtin plugins, their ports and controls (`copy`,
//! `mixer` "Gain 1".., `bq_highpass`/`bq_lowpass` "Freq"/"Q") and the
//! `filter.smart` properties are from PipeWire 1.6.8's
//! src/modules/module-filter-chain.c and WirePlumber 0.5.14's
//! docs/rst/policies/smart_filters.rst, read on 2026-11-12.

use std::fmt::Write as _;

/// The driver's settings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    /// -steps (rear only) ..= +steps (front only).
    pub fader: i32,
    /// -steps (left only) ..= +steps (right only).
    pub balance: i32,
    /// dB, relative to the sub's reference level.
    pub sub_level_db: i32,
    /// Hz.
    pub crossover_hz: u32,
}

impl Default for Settings {
    /// Example defaults: centred, the sub at its reference, 80 Hz.
    fn default() -> Settings {
        Settings {
            fader: 0,
            balance: 0,
            sub_level_db: 0,
            crossover_hz: 80,
        }
    }
}

/// What the filter-chain runs with: the speaker settings and the volume's
/// gain (ADR-0043).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Mix {
    pub settings: Settings,
    /// 0..=1 ([`crate::volume::gain`]).
    pub master: f32,
}

/// What the driver may set. Examples, not recommendations.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Limits {
    pub steps: i32,
    pub step_db: f32,
    pub sub_min_db: i32,
    pub sub_max_db: i32,
    pub crossover_min_hz: u32,
    pub crossover_max_hz: u32,
    pub crossover_step_hz: u32,
}

impl Default for Limits {
    fn default() -> Limits {
        Limits {
            steps: 10,
            step_db: 2.0,
            sub_min_db: -20,
            sub_max_db: 6,
            crossover_min_hz: 50,
            crossover_max_hz: 120,
            crossover_step_hz: 10,
        }
    }
}

impl Limits {
    /// The limits themselves make sense: a crossover that keeps bass off the
    /// door speakers and full range off the subs (no 0 Hz high-pass, no
    /// low-pass up into the midrange), and a sub that can't be boosted
    /// without bound.
    pub fn check(&self) -> Result<(), String> {
        if !(1..=30).contains(&self.steps) {
            return Err(format!(
                "fader/balance steps must be 1..=30, not {}",
                self.steps
            ));
        }
        if !(self.step_db > 0.0 && self.step_db <= 10.0) {
            return Err(format!("step_db must be >0 and <=10, not {}", self.step_db));
        }
        if self.sub_min_db > self.sub_max_db || self.sub_max_db > 12 || self.sub_min_db < -60 {
            return Err(format!(
                "sub level limits must be within -60..=12 dB, min <= max (got {}..{})",
                self.sub_min_db, self.sub_max_db
            ));
        }
        if self.crossover_min_hz < 30
            || self.crossover_max_hz > 250
            || self.crossover_min_hz > self.crossover_max_hz
        {
            return Err(format!(
                "crossover limits must be within 30..=250 Hz, min <= max (got {}..{})",
                self.crossover_min_hz, self.crossover_max_hz
            ));
        }
        if self.crossover_step_hz == 0 {
            return Err("crossover step must be > 0".into());
        }
        Ok(())
    }

    /// `s` is allowed.
    pub fn validate(&self, s: &Settings) -> Result<(), String> {
        if s.fader.abs() > self.steps {
            return Err(format!("Fader {} is outside ±{}.", s.fader, self.steps));
        }
        if s.balance.abs() > self.steps {
            return Err(format!("Balance {} is outside ±{}.", s.balance, self.steps));
        }
        if s.sub_level_db < self.sub_min_db || s.sub_level_db > self.sub_max_db {
            return Err(format!(
                "Sub level {} dB is outside {}..{} dB.",
                s.sub_level_db, self.sub_min_db, self.sub_max_db
            ));
        }
        if s.crossover_hz < self.crossover_min_hz || s.crossover_hz > self.crossover_max_hz {
            return Err(format!(
                "Crossover {} Hz is outside {}..{} Hz.",
                s.crossover_hz, self.crossover_min_hz, self.crossover_max_hz
            ));
        }
        Ok(())
    }
}

/// Which DAC channel feeds which amplifier input. Indexes into `positions`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChannelMap {
    /// The DAC sink's channel positions, in its order (PipeWire names:
    /// FL FR RL RR FC LFE SL SR, or AUX0..). UNVERIFIED for the DAC8x.
    pub positions: Vec<String>,
    pub front: [usize; 2],
    pub rear: [usize; 2],
    /// Both legs of the sub's jack carry the same mono signal.
    pub sub: [usize; 2],
}

impl Default for ChannelMap {
    /// An example: jack 1 front, jack 2 rear, jack 3 sub, jack 4 spare, on
    /// the eight channels in PipeWire's 7.1 order. UNVERIFIED (the bench's
    /// test-tone check decides).
    fn default() -> ChannelMap {
        ChannelMap {
            positions: ["FL", "FR", "RL", "RR", "FC", "LFE", "SL", "SR"]
                .map(String::from)
                .to_vec(),
            front: [0, 1],
            rear: [2, 3],
            sub: [4, 5],
        }
    }
}

const KNOWN_POSITIONS: [&str; 14] = [
    "FL", "FR", "FC", "LFE", "SL", "SR", "FLC", "FRC", "RC", "RL", "RR", "TC", "MONO", "AUX",
];

fn position_ok(p: &str) -> bool {
    if let Some(n) = p.strip_prefix("AUX") {
        return n.parse::<u8>().is_ok_and(|n| n < 64);
    }
    KNOWN_POSITIONS.contains(&p) && p != "AUX"
}

impl ChannelMap {
    /// Parses "FL,FR,..." and "0,1".
    pub fn parse(
        positions: &str,
        front: &str,
        rear: &str,
        sub: &str,
    ) -> Result<ChannelMap, String> {
        let pair = |what: &str, s: &str| -> Result<[usize; 2], String> {
            let v: Vec<usize> = s
                .split(',')
                .map(|x| x.trim().parse::<usize>())
                .collect::<Result<_, _>>()
                .map_err(|_| format!("{what}: want two channel numbers like 0,1, got {s:?}"))?;
            <[usize; 2]>::try_from(v)
                .map_err(|_| format!("{what}: want two channel numbers like 0,1, got {s:?}"))
        };
        let m = ChannelMap {
            positions: positions
                .split(',')
                .map(|p| p.trim().to_ascii_uppercase())
                .filter(|p| !p.is_empty())
                .collect(),
            front: pair("front", front)?,
            rear: pair("rear", rear)?,
            sub: pair("sub", sub)?,
        };
        m.check()?;
        Ok(m)
    }

    /// Every channel is a real position, and front, rear and sub are six
    /// different channels: a sub channel can never also carry full range.
    pub fn check(&self) -> Result<(), String> {
        if self.positions.is_empty() || self.positions.len() > 16 {
            return Err(format!(
                "{} DAC channels: want 1..=16",
                self.positions.len()
            ));
        }
        for p in &self.positions {
            if !position_ok(p) {
                return Err(format!("{p:?} isn't a PipeWire channel position"));
            }
        }
        let mut seen = std::collections::BTreeSet::new();
        for p in &self.positions {
            if !seen.insert(p) {
                return Err(format!("channel position {p} is listed twice"));
            }
        }
        let used = [self.front, self.rear, self.sub].concat();
        for &i in &used {
            if i >= self.positions.len() {
                return Err(format!(
                    "channel {i} doesn't exist: the DAC has {}",
                    self.positions.len()
                ));
            }
        }
        let distinct: std::collections::BTreeSet<_> = used.iter().collect();
        if distinct.len() != used.len() {
            return Err("front, rear and sub must use six different DAC channels".into());
        }
        Ok(())
    }
}

/// Linear gains from the settings.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Gains {
    pub front_left: f32,
    pub front_right: f32,
    pub rear_left: f32,
    pub rear_right: f32,
    /// Each of L and R into the sub's (L+R)/2 mix.
    pub sub_each: f32,
}

fn db(x: f32) -> f32 {
    10f32.powf(x / 20.0)
}

/// The gain of the side a fader or balance moves away from: `step_db` per
/// step, silent at the last step.
fn away(steps: i32, limits: &Limits) -> f32 {
    let n = steps.abs();
    if n == 0 {
        1.0
    } else if n >= limits.steps {
        0.0
    } else {
        db(-(n as f32) * limits.step_db)
    }
}

/// `master` is the volume's gain (0..=1, [`crate::volume::gain`]): every
/// output is multiplied by it, so it never boosts.
pub fn gains(limits: &Limits, s: &Settings, master: f32) -> Gains {
    let m = master.clamp(0.0, 1.0);
    let (front, rear) = match s.fader {
        f if f > 0 => (1.0, away(f, limits)),
        f if f < 0 => (away(f, limits), 1.0),
        _ => (1.0, 1.0),
    };
    let (left, right) = match s.balance {
        b if b > 0 => (away(b, limits), 1.0),
        b if b < 0 => (1.0, away(b, limits)),
        _ => (1.0, 1.0),
    };
    Gains {
        front_left: m * front * left,
        front_right: m * front * right,
        rear_left: m * rear * left,
        rear_right: m * rear * right,
        sub_each: m * 0.5 * db(s.sub_level_db as f32),
    }
}

/// What the filter-chain needs besides the settings.
#[derive(Debug, Clone, PartialEq)]
pub struct Target {
    /// The DAC's PipeWire node name; empty: WirePlumber's default sink.
    /// The DAC8x's node name is UNVERIFIED.
    pub dac_node: String,
    pub map: ChannelMap,
}

/// The name of the filter-chain's sink node, for `pw-cli set-param`.
pub const NODE_NAME: &str = "f250.speakers";
/// Butterworth Q: two in a row make a Linkwitz-Riley 4th-order crossover.
pub const BUTTERWORTH_Q: f32 = std::f32::consts::FRAC_1_SQRT_2;

/// The control values that change without restarting the chain, as
/// `node:port` → value: fader, balance, sub level and volume, and the crossover (every
/// biquad's "Freq"; the Q stays Butterworth). A restart unlinks the chain
/// for a moment, and full range reaches the doors then (bench-log
/// 2026-11-12), so nothing the driver changes restarts it.
pub fn live_controls(limits: &Limits, s: &Settings, master: f32) -> Vec<(String, f32)> {
    let g = gains(limits, s, master);
    let f = s.crossover_hz as f32;
    let mut c: Vec<(String, f32)> = vec![
        ("gain_fl:Gain 1".into(), g.front_left),
        ("gain_fr:Gain 1".into(), g.front_right),
        ("gain_rl:Gain 1".into(), g.rear_left),
        ("gain_rr:Gain 1".into(), g.rear_right),
        ("sub_mix:Gain 1".into(), g.sub_each),
        ("sub_mix:Gain 2".into(), g.sub_each),
    ];
    for side in ["fl", "fr", "rl", "rr"] {
        for stage in 1..=2 {
            c.push((format!("hp_{side}{stage}:Freq"), f));
        }
    }
    for stage in 1..=2 {
        c.push((format!("lp_sub{stage}:Freq"), f));
    }
    c
}

/// `pw-cli set-param <node> Props <this>`: PipeWire 1.6.8's filter-graph
/// reads `params` as name/value pairs (spa/plugins/filter-graph,
/// `parse_params`). Not documented for filter-chain itself: UNVERIFIED on
/// the Pi.
pub fn props_json(limits: &Limits, s: &Settings, master: f32) -> String {
    let mut out = String::from("{ params = [");
    for (k, v) in live_controls(limits, s, master) {
        let _ = write!(out, " \"{k}\" {v:.6}");
    }
    out.push_str(" ] }");
    out
}

fn quote(s: &str) -> String {
    // PipeWire's SPA-JSON strings: no quotes or backslashes in our names.
    format!(
        "\"{}\"",
        s.chars()
            .filter(|c| *c != '"' && *c != '\\' && !c.is_control())
            .collect::<String>()
    )
}

/// The whole PipeWire configuration for `pipewire -c <file>`: a client
/// process running only the filter-chain (as PipeWire's own
/// filter-chain.conf does), so audio-manager can restart it on its own.
pub fn render(limits: &Limits, s: &Settings, master: f32, target: &Target) -> String {
    let g = gains(limits, s, master);
    let f = s.crossover_hz as f32;
    let q = BUTTERWORTH_Q;
    let mut nodes = String::new();
    let mut node = |name: &str, label: &str, control: String| {
        let _ = writeln!(
            nodes,
            "                    {{ type = builtin name = {name} label = {label}{} }}",
            if control.is_empty() {
                String::new()
            } else {
                format!(" control = {{ {control} }}")
            }
        );
    };
    node("in_l", "copy", String::new());
    node("in_r", "copy", String::new());
    for (side, gain) in [
        ("fl", g.front_left),
        ("fr", g.front_right),
        ("rl", g.rear_left),
        ("rr", g.rear_right),
    ] {
        for stage in 1..=2 {
            node(
                &format!("hp_{side}{stage}"),
                "bq_highpass",
                format!("\"Freq\" = {f:.1} \"Q\" = {q:.4}"),
            );
        }
        node(
            &format!("gain_{side}"),
            "mixer",
            format!("\"Gain 1\" = {gain:.6}"),
        );
    }
    node(
        "sub_mix",
        "mixer",
        format!(
            "\"Gain 1\" = {:.6} \"Gain 2\" = {:.6}",
            g.sub_each, g.sub_each
        ),
    );
    for stage in 1..=2 {
        node(
            &format!("lp_sub{stage}"),
            "bq_lowpass",
            format!("\"Freq\" = {f:.1} \"Q\" = {q:.4}"),
        );
    }
    node("sub_a", "copy", String::new());
    node("sub_b", "copy", String::new());

    let mut links = String::new();
    let mut link = |o: &str, i: &str| {
        let _ = writeln!(
            links,
            "                    {{ output = \"{o}\" input = \"{i}\" }}"
        );
    };
    for (side, from) in [
        ("fl", "in_l"),
        ("rl", "in_l"),
        ("fr", "in_r"),
        ("rr", "in_r"),
    ] {
        link(&format!("{from}:Out"), &format!("hp_{side}1:In"));
        link(&format!("hp_{side}1:Out"), &format!("hp_{side}2:In"));
        link(&format!("hp_{side}2:Out"), &format!("gain_{side}:In 1"));
    }
    link("in_l:Out", "sub_mix:In 1");
    link("in_r:Out", "sub_mix:In 2");
    link("sub_mix:Out", "lp_sub1:In");
    link("lp_sub1:Out", "lp_sub2:In");
    link("lp_sub2:Out", "sub_a:In");
    link("lp_sub2:Out", "sub_b:In");

    // One graph output per DAC channel, in its order; the spare jack's are
    // "null" (silent).
    let map = &target.map;
    let outputs: Vec<String> = (0..map.positions.len())
        .map(|i| {
            let port = if i == map.front[0] {
                "gain_fl:Out"
            } else if i == map.front[1] {
                "gain_fr:Out"
            } else if i == map.rear[0] {
                "gain_rl:Out"
            } else if i == map.rear[1] {
                "gain_rr:Out"
            } else if i == map.sub[0] {
                "sub_a:Out"
            } else if i == map.sub[1] {
                "sub_b:Out"
            } else {
                "null"
            };
            if port == "null" {
                port.to_string()
            } else {
                quote(port)
            }
        })
        .collect();
    let target_line = if target.dac_node.is_empty() {
        "                # No DAC named: WirePlumber's default sink.\n".to_string()
    } else {
        format!(
            "                filter.smart.target = {{ node.name = {} }}\n",
            quote(&target.dac_node)
        )
    };

    format!(
        "# Generated by audio-manager (ADR-0039) from its settings: do not edit.
# Example values (CLAUDE.md rule 10): crossover {xo} Hz, fader {fader}, balance {balance},
# sub {sub} dB. Fader/balance {step} dB a step, the last step silent. Volume gain {master:.6}.
context.properties = {{
    log.level = 0
}}
context.spa-libs = {{
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}}
context.modules = [
    {{ name = libpipewire-module-rt args = {{ }} flags = [ ifexists nofail ] }}
    {{ name = libpipewire-module-protocol-native }}
    {{ name = libpipewire-module-client-node }}
    {{ name = libpipewire-module-adapter }}
    {{ name = libpipewire-module-filter-chain
        args = {{
            node.description = \"F-250 speakers\"
            media.name       = \"F-250 speakers\"
            filter.graph = {{
                nodes = [
{nodes}                ]
                links = [
{links}                ]
                inputs  = [ \"in_l:In\" \"in_r:In\" ]
                outputs = [ {outputs} ]
            }}
            capture.props = {{
                node.name      = \"{name}\"
                media.class    = Audio/Sink
                audio.position = [ FL FR ]
                # A WirePlumber smart filter in front of the DAC, after AGL's
                # equalizer (if present), so everything played reaches it.
                filter.smart = true
                filter.smart.name = \"{name}\"
                filter.smart.after = [ \"agl.filter.equalizer-sink\" ]
{target_line}            }}
            playback.props = {{
                node.name         = \"{name}.out\"
                audio.position    = [ {positions} ]
                stream.dont-remix = true
                node.passive      = true
                media.role        = \"DSP\"
            }}
        }}
    }}
]
",
        xo = s.crossover_hz,
        fader = s.fader,
        balance = s.balance,
        sub = s.sub_level_db,
        step = limits.step_db,
        master = master.clamp(0.0, 1.0),
        outputs = outputs.join(" "),
        name = NODE_NAME,
        positions = map.positions.join(" "),
    )
}

/// The settings file: a small JSON object. A damaged or out-of-limits file
/// gives the defaults (and says why).
pub fn parse_settings(
    text: &str,
    limits: &Limits,
    defaults: &Settings,
) -> Result<Settings, String> {
    let v: serde_json::Value = serde_json::from_str(text).map_err(|e| format!("not JSON: {e}"))?;
    let int = |k: &str, d: i64| -> Result<i64, String> {
        match v.get(k) {
            None => Ok(d),
            Some(x) => x
                .as_i64()
                .ok_or_else(|| format!("{k} isn't a whole number")),
        }
    };
    let conv = |k: &str, x: i64| i32::try_from(x).map_err(|_| format!("{k} is out of range"));
    let s = Settings {
        fader: conv("fader", int("fader", defaults.fader.into())?)?,
        balance: conv("balance", int("balance", defaults.balance.into())?)?,
        sub_level_db: conv(
            "sub_level_db",
            int("sub_level_db", defaults.sub_level_db.into())?,
        )?,
        crossover_hz: u32::try_from(int("crossover_hz", defaults.crossover_hz.into())?)
            .map_err(|_| "crossover_hz is out of range".to_string())?,
    };
    limits.validate(&s)?;
    Ok(s)
}

pub fn settings_json(s: &Settings) -> String {
    serde_json::json!({
        "fader": s.fader,
        "balance": s.balance,
        "sub_level_db": s.sub_level_db,
        "crossover_hz": s.crossover_hz,
    })
    .to_string()
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    fn target() -> Target {
        Target {
            dac_node: "alsa_output.platform-dac8x".into(),
            map: ChannelMap::default(),
        }
    }

    fn close(a: f32, b: f32) -> bool {
        (a - b).abs() < 1e-4
    }

    #[test]
    fn the_example_limits_and_defaults_are_consistent() {
        let l = Limits::default();
        l.check().unwrap();
        l.validate(&Settings::default()).unwrap();
        ChannelMap::default().check().unwrap();
    }

    #[test]
    fn values_outside_the_limits_are_refused() {
        let l = Limits::default();
        let ok = Settings::default();
        for bad in [
            Settings { fader: 11, ..ok },
            Settings { fader: -11, ..ok },
            Settings { balance: 11, ..ok },
            Settings {
                sub_level_db: 7,
                ..ok
            },
            Settings {
                sub_level_db: -21,
                ..ok
            },
            Settings {
                crossover_hz: 49,
                ..ok
            },
            Settings {
                crossover_hz: 121,
                ..ok
            },
            Settings {
                crossover_hz: 0,
                ..ok
            },
        ] {
            assert!(l.validate(&bad).is_err(), "{bad:?}");
        }
        assert!(
            l.validate(&Settings {
                fader: -10,
                sub_level_db: 6,
                crossover_hz: 120,
                ..ok
            })
            .is_ok()
        );
    }

    #[test]
    fn unsafe_limits_are_refused() {
        let ok = Limits::default();
        for bad in [
            // A 0 Hz high-pass (full range to the doors) or a low-pass in the
            // midrange (full range to the subs).
            Limits {
                crossover_min_hz: 0,
                ..ok
            },
            Limits {
                crossover_max_hz: 2000,
                ..ok
            },
            Limits {
                crossover_min_hz: 100,
                crossover_max_hz: 90,
                ..ok
            },
            Limits {
                sub_max_db: 30,
                ..ok
            },
            Limits {
                sub_min_db: 1,
                sub_max_db: 0,
                ..ok
            },
            Limits { steps: 0, ..ok },
            Limits { step_db: 0.0, ..ok },
            Limits {
                crossover_step_hz: 0,
                ..ok
            },
        ] {
            assert!(bad.check().is_err(), "{bad:?}");
        }
    }

    #[test]
    fn fader_and_balance_gains() {
        let l = Limits::default();
        let g = gains(&l, &Settings::default(), 1.0);
        assert_eq!(
            (g.front_left, g.front_right, g.rear_left, g.rear_right),
            (1.0, 1.0, 1.0, 1.0)
        );
        assert!(close(g.sub_each, 0.5));
        // Towards the front: the rear down 2 dB a step.
        let g = gains(
            &l,
            &Settings {
                fader: 3,
                ..Settings::default()
            },
            1.0,
        );
        assert_eq!(g.front_left, 1.0);
        assert!(close(g.rear_left, db(-6.0)));
        // The last step mutes the far pair.
        let g = gains(
            &l,
            &Settings {
                fader: -10,
                ..Settings::default()
            },
            1.0,
        );
        assert_eq!((g.front_left, g.front_right), (0.0, 0.0));
        assert_eq!(g.rear_right, 1.0);
        // Balance right: the left side down.
        let g = gains(
            &l,
            &Settings {
                balance: 2,
                fader: 1,
                ..Settings::default()
            },
            1.0,
        );
        assert!(close(g.front_left, db(-4.0)));
        assert_eq!(g.front_right, 1.0);
        assert!(close(g.rear_left, db(-6.0)));
        // Sub +6 dB.
        let g = gains(
            &l,
            &Settings {
                sub_level_db: 6,
                ..Settings::default()
            },
            1.0,
        );
        assert!(close(g.sub_each, 0.5 * db(6.0)));
    }

    #[test]
    fn channel_map_checks() {
        assert!(ChannelMap::parse("FL,FR,RL,RR,FC,LFE,SL,SR", "0,1", "2,3", "4,5").is_ok());
        assert!(
            ChannelMap::parse(
                "AUX0,AUX1,AUX2,AUX3,AUX4,AUX5,AUX6,AUX7",
                "0,1",
                "2,3",
                "6,7"
            )
            .is_ok()
        );
        // The sub sharing a speaker channel would send it full range.
        assert!(ChannelMap::parse("FL,FR,RL,RR,FC,LFE,SL,SR", "0,1", "2,3", "1,5").is_err());
        assert!(ChannelMap::parse("FL,FR,RL,RR,FC,LFE,SL,SR", "0,1", "2,3", "4,8").is_err());
        assert!(ChannelMap::parse("FL,FR,XX", "0,1", "2,3", "4,5").is_err());
        assert!(ChannelMap::parse("FL,FL,RL,RR,FC,LFE", "0,1", "2,3", "4,5").is_err());
        assert!(ChannelMap::parse("FL,FR,RL,RR,FC,LFE", "0", "2,3", "4,5").is_err());
        assert!(ChannelMap::parse("AUX64,FR,RL,RR,FC,LFE", "0,1", "2,3", "4,5").is_err());
    }

    #[test]
    fn rendered_graph_high_passes_the_speakers_and_low_passes_the_sub() {
        let l = Limits::default();
        let s = Settings {
            crossover_hz: 90,
            ..Settings::default()
        };
        let c = render(&l, &s, 1.0, &target());
        // Two Butterworth stages each side, at the crossover.
        assert_eq!(
            c.matches("label = bq_highpass control = { \"Freq\" = 90.0 \"Q\" = 0.7071 }")
                .count(),
            8
        );
        assert_eq!(
            c.matches("label = bq_lowpass control = { \"Freq\" = 90.0 \"Q\" = 0.7071 }")
                .count(),
            2
        );
        // Each speaker output comes through its high-pass; the sub's only
        // through the low-pass.
        for side in ["fl", "fr", "rl", "rr"] {
            assert!(c.contains(&format!(
                "{{ output = \"hp_{side}2:Out\" input = \"gain_{side}:In 1\" }}"
            )));
        }
        assert!(c.contains("{ output = \"lp_sub2:Out\" input = \"sub_a:In\" }"));
        assert!(c.contains("{ output = \"lp_sub2:Out\" input = \"sub_b:In\" }"));
        assert_eq!(
            c.matches("input = \"sub_a:In\"").count(),
            1,
            "nothing else feeds the sub"
        );
        assert_eq!(c.matches("input = \"sub_b:In\"").count(), 1);
        // Outputs in the DAC's channel order, spare jack silent.
        assert!(c.contains(
            "outputs = [ \"gain_fl:Out\" \"gain_fr:Out\" \"gain_rl:Out\" \"gain_rr:Out\" \"sub_a:Out\" \"sub_b:Out\" null null ]"
        ));
        assert!(c.contains("audio.position    = [ FL FR RL RR FC LFE SL SR ]"));
        assert!(c.contains("filter.smart.target = { node.name = \"alsa_output.platform-dac8x\" }"));
        assert!(c.contains("node.name      = \"f250.speakers\""));
        assert!(c.contains("Example values"));
    }

    #[test]
    fn rendered_map_follows_the_configuration() {
        let t = Target {
            dac_node: String::new(),
            map: ChannelMap::parse(
                "AUX0,AUX1,AUX2,AUX3,AUX4,AUX5,AUX6,AUX7",
                "6,7",
                "0,1",
                "2,3",
            )
            .unwrap(),
        };
        let c = render(&Limits::default(), &Settings::default(), 1.0, &t);
        assert!(c.contains(
            "outputs = [ \"gain_rl:Out\" \"gain_rr:Out\" \"sub_a:Out\" \"sub_b:Out\" null null \"gain_fl:Out\" \"gain_fr:Out\" ]"
        ));
        assert!(!c.contains("filter.smart.target ="));
        assert!(c.contains("No DAC named"));
    }

    #[test]
    fn rendered_brackets_balance() {
        let c = render(&Limits::default(), &Settings::default(), 1.0, &target());
        let no_comments: String = c
            .lines()
            .filter(|l| !l.trim_start().starts_with('#'))
            .collect::<Vec<_>>()
            .join("\n");
        for (o, cl) in [('{', '}'), ('[', ']')] {
            assert_eq!(
                no_comments.matches(o).count(),
                no_comments.matches(cl).count(),
                "{o}{cl}"
            );
        }
    }

    #[test]
    fn live_params_carry_the_gains() {
        let l = Limits::default();
        let j = props_json(
            &l,
            &Settings {
                fader: 10,
                ..Settings::default()
            },
            1.0,
        );
        assert!(j.starts_with("{ params = ["));
        assert!(j.contains("\"gain_rl:Gain 1\" 0.000000"));
        assert!(j.contains("\"gain_fl:Gain 1\" 1.000000"));
        assert!(j.contains("\"sub_mix:Gain 2\" 0.500000"));
    }

    #[test]
    fn live_params_carry_the_crossover_to_every_biquad() {
        let l = Limits::default();
        let j = props_json(
            &l,
            &Settings {
                crossover_hz: 100,
                ..Settings::default()
            },
            1.0,
        );
        for side in ["fl", "fr", "rl", "rr"] {
            for stage in 1..=2 {
                assert!(
                    j.contains(&format!("\"hp_{side}{stage}:Freq\" 100.000000")),
                    "{j}"
                );
            }
        }
        assert!(j.contains("\"lp_sub1:Freq\" 100.000000"));
        assert!(j.contains("\"lp_sub2:Freq\" 100.000000"));
        // The same node and port names the rendered graph has.
        let c = render(&l, &Settings::default(), 1.0, &target());
        for (k, _) in live_controls(&l, &Settings::default(), 1.0) {
            let node = k.split(':').next().unwrap();
            assert!(c.contains(&format!("name = {node} ")), "{node}");
        }
    }

    #[test]
    fn settings_file_round_trip_and_damage() {
        let l = Limits::default();
        let d = Settings::default();
        let s = Settings {
            fader: -3,
            balance: 1,
            sub_level_db: -4,
            crossover_hz: 100,
        };
        assert_eq!(parse_settings(&settings_json(&s), &l, &d).unwrap(), s);
        assert_eq!(
            parse_settings("{}", &l, &d).unwrap(),
            d,
            "missing keys: defaults"
        );
        assert!(parse_settings("not json", &l, &d).is_err());
        assert!(
            parse_settings("{\"fader\": 99}", &l, &d).is_err(),
            "outside the limits"
        );
        assert!(parse_settings("{\"fader\": \"x\"}", &l, &d).is_err());
        assert!(parse_settings("{\"crossover_hz\": -5}", &l, &d).is_err());
    }

    #[test]
    fn the_volume_scales_every_output() {
        let l = Limits::default();
        let s = Settings {
            fader: 3,
            sub_level_db: 6,
            ..Settings::default()
        };
        let full = gains(&l, &s, 1.0);
        let half = gains(&l, &s, 0.5);
        for (a, b) in [
            (full.front_left, half.front_left),
            (full.front_right, half.front_right),
            (full.rear_left, half.rear_left),
            (full.rear_right, half.rear_right),
            (full.sub_each, half.sub_each),
        ] {
            assert!(close(b, a * 0.5), "{a} {b}");
        }
        assert_eq!(gains(&l, &s, 0.0).sub_each, 0.0, "silent");
        assert_eq!(gains(&l, &s, 3.0), full, "never a boost");
        let j = props_json(&l, &Settings::default(), 0.25);
        assert!(j.contains("\"gain_fl:Gain 1\" 0.250000"), "{j}");
        assert!(j.contains("\"sub_mix:Gain 1\" 0.125000"), "{j}");
        let c = render(&l, &Settings::default(), 0.25, &target());
        assert!(c.contains("\"Gain 1\" = 0.250000"));
        assert!(c.contains("Volume gain 0.250000"));
    }
}
