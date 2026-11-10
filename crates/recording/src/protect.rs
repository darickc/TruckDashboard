//! Saved clips (ADR-0027 decision 8). Pure: what to protect; the store moves
//! the files into `protected/`, where retention never looks.
//!
//! A segment being written is never moved. "Save clip" protects the
//! finished segments before it now, and asks the caller to protect the
//! segment being written and the ones after it as each one finishes,
//! checking the cap again each time with the real size.

use crate::retention::Segment;
use crate::segment::SegmentName;
use crate::settings::Settings;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipPlan {
    /// Finished segments to protect now, oldest first.
    pub protect_now: Vec<SegmentName>,
    /// Per camera: protect this many more segments as they finish (the one
    /// being written, then the ones after it).
    pub protect_next: Vec<(String, u32)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipError {
    /// Nothing is being recorded, so there is nothing to save.
    NotRecording,
    /// The saved clips would pass `RECORD_PROTECTED_MAX_GB`. The save is
    /// refused rather than deleting an older saved clip.
    CapFull { need_bytes: u64, free_bytes: u64 },
}

/// Whether `bytes` more fit under the saved-clip cap.
pub fn fits(protected_bytes: u64, bytes: u64, s: &Settings) -> bool {
    protected_bytes.saturating_add(bytes) <= s.protected_max_bytes
}

/// "Save clip": the `clip_before_s` before the segment being written, that
/// segment, and `clip_after_s` after it, for every camera recording now.
///
/// The cap check counts the finished segments plus an estimate for the ones
/// still to come (the camera's average finished segment, or nothing if it
/// has none yet); each later segment is checked again with [`fits`].
pub fn save_clip(
    segments: &[Segment],
    writing: &[SegmentName],
    protected_bytes: u64,
    s: &Settings,
) -> Result<ClipPlan, ClipError> {
    if writing.is_empty() {
        return Err(ClipError::NotRecording);
    }
    let before = s.segments_for(s.clip_before_s) as usize;
    let after = s.segments_for(s.clip_after_s);
    let mut protect_now: Vec<&Segment> = Vec::new();
    let mut protect_next = Vec::new();
    let mut estimate = 0u64;
    for current in writing {
        let mut finished: Vec<&Segment> = segments
            .iter()
            .filter(|g| {
                !g.protected && g.name.camera == current.camera && g.name.order(current).is_lt()
            })
            .collect();
        finished.sort_by(|a, b| a.name.order(&b.name));
        let average = if finished.is_empty() {
            0
        } else {
            finished.iter().map(|g| g.bytes).sum::<u64>() / finished.len() as u64
        };
        let from = finished.len().saturating_sub(before);
        protect_now.extend(&finished[from..]);
        // The segment being written, then `after` more.
        protect_next.push((current.camera.clone(), after + 1));
        estimate += average * u64::from(after + 1);
    }
    protect_now.sort_by(|a, b| a.name.order(&b.name));
    let need = protect_now.iter().map(|g| g.bytes).sum::<u64>() + estimate;
    if !fits(protected_bytes, need, s) {
        return Err(ClipError::CapFull {
            need_bytes: need,
            free_bytes: s.protected_max_bytes.saturating_sub(protected_bytes),
        });
    }
    Ok(ClipPlan {
        protect_now: protect_now.into_iter().map(|g| g.name.clone()).collect(),
        protect_next,
    })
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UncleanPlan {
    /// Protected, newest first.
    pub protect: Vec<SegmentName>,
    /// Wanted, but the saved-clip cap was full: they stay unprotected and
    /// the dashboard says so.
    pub skipped: Vec<SegmentName>,
}

/// After an unclean stop (no clean-stop marker): the last
/// `unclean_protect_min` minutes of the previous run, per camera, newest
/// first as far as the cap allows. The newest segment was cut short, so one
/// more segment than the minutes need is taken. Off when the setting is 0.
pub fn after_unclean_stop(
    segments: &[Segment],
    previous_boot: u32,
    protected_bytes: u64,
    s: &Settings,
) -> UncleanPlan {
    if s.unclean_protect_min == 0 {
        return UncleanPlan::default();
    }
    let per_camera = s.segments_for(s.unclean_protect_min * 60) as usize + 1;
    let mut last_run: Vec<&Segment> = segments
        .iter()
        .filter(|g| !g.protected && g.name.boot == previous_boot)
        .collect();
    // Newest first, so the minutes closest to the stop win the cap.
    last_run.sort_by(|a, b| b.name.order(&a.name));
    let mut taken: std::collections::HashMap<&str, usize> = Default::default();
    let mut used = protected_bytes;
    let mut plan = UncleanPlan::default();
    for g in last_run {
        let n = taken.entry(g.name.camera.as_str()).or_default();
        if *n >= per_camera {
            continue;
        }
        *n += 1;
        if fits(used, g.bytes, s) {
            used += g.bytes;
            plan.protect.push(g.name.clone());
        } else {
            plan.skipped.push(g.name.clone());
        }
    }
    plan
}
