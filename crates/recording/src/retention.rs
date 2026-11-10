//! Which recordings to delete (ADR-0027 decision 7). Pure: the store scans
//! the drive, this decides, the store deletes.
//!
//! Rules, applied in this order; a segment goes for the first one that
//! catches it, and whichever limit bites first wins:
//!
//! 1. **Age**, only when the clock is trusted *now*. A wrong clock must not
//!    delete a week of video (a clock that jumped forward) or keep it forever
//!    by mistake (one that jumped back). Segments carry a wall time only if
//!    the clock was trusted when they were recorded; the others are ordered
//!    by run and sequence, so a trusted segment that is too old takes every
//!    segment recorded before it with it.
//! 2. **Count** per camera (`max_segments`, off by default).
//! 3. **Size**: unprotected video of every camera together.
//! 4. **Free space** on the drive.
//!
//! Never deleted: a segment being written, and a protected (saved) clip.
//! If only those are left and the drive is still below its free-space
//! minimum, the plan says so: recording must stop rather than fill the
//! drive, and the dashboard says why.

use std::collections::{HashMap, HashSet};

use crate::segment::SegmentName;
use crate::settings::Settings;

/// A segment on the drive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    pub name: SegmentName,
    pub bytes: u64,
    /// A saved clip (in `protected/`): never deleted by retention.
    pub protected: bool,
}

/// The drive's free space now, from the caller (statvfs).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Drive {
    pub free_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    Age,
    Count,
    Size,
    FreeSpace,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Problem {
    /// Below the free-space minimum with nothing left to delete: recording
    /// must stop.
    DriveFull {
        free_bytes: u64,
        min_free_bytes: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Plan {
    /// Oldest first.
    pub delete: Vec<(SegmentName, Reason)>,
    /// Unprotected video left after the deletions, writing segments included.
    pub recording_bytes_after: u64,
    pub free_bytes_after: u64,
    pub problem: Option<Problem>,
}

/// Decides what to delete. `now` is UTC seconds, `Some` only while the
/// clock is trusted. `writing` are the segments being recorded now.
pub fn plan(
    segments: &[Segment],
    writing: &[SegmentName],
    drive: Drive,
    now: Option<u64>,
    s: &Settings,
) -> Plan {
    let writing: HashSet<&SegmentName> = writing.iter().collect();
    let mut recordings: Vec<&Segment> = segments.iter().filter(|g| !g.protected).collect();
    recordings.sort_by(|a, b| a.name.order(&b.name));
    // Deletable: not being written, oldest first.
    let deletable: Vec<&Segment> = recordings
        .iter()
        .copied()
        .filter(|g| !writing.contains(&g.name))
        .collect();

    let mut chosen: Vec<Option<Reason>> = vec![None; deletable.len()];

    // 1. Age.
    if let (Some(now), true) = (now, s.max_age_days > 0) {
        let cutoff = now.saturating_sub(u64::from(s.max_age_days) * 86_400);
        // The newest trusted segment older than the cutoff; it and every
        // segment recorded before it go. A wall time in the future (the
        // clock was wrong then) is never "old".
        if let Some(last) = deletable
            .iter()
            .rposition(|g| g.name.wall.is_some_and(|t| t < cutoff))
        {
            for c in chosen.iter_mut().take(last + 1) {
                *c = Some(Reason::Age);
            }
        }
    }

    // 2. Count per camera, writing segments included in the count.
    if s.max_segments > 0 {
        let mut per_camera: HashMap<&str, usize> = HashMap::new();
        for g in &recordings {
            *per_camera.entry(g.name.camera.as_str()).or_default() += 1;
        }
        let mut deleted: HashMap<&str, usize> = HashMap::new();
        for (i, g) in deletable.iter().enumerate() {
            if chosen[i].is_some() {
                *deleted.entry(g.name.camera.as_str()).or_default() += 1;
            }
        }
        for (i, g) in deletable.iter().enumerate() {
            let cam = g.name.camera.as_str();
            let left = per_camera[cam] - deleted.get(cam).copied().unwrap_or(0);
            if chosen[i].is_none() && left > s.max_segments as usize {
                chosen[i] = Some(Reason::Count);
                *deleted.entry(cam).or_default() += 1;
            }
        }
    }

    let freed = |chosen: &[Option<Reason>]| -> u64 {
        deletable
            .iter()
            .zip(chosen)
            .filter(|(_, c)| c.is_some())
            .map(|(g, _)| g.bytes)
            .sum()
    };
    let total: u64 = recordings.iter().map(|g| g.bytes).sum();

    // 3. Size.
    let mut kept = total - freed(&chosen);
    for (i, g) in deletable.iter().enumerate() {
        if kept <= s.max_bytes {
            break;
        }
        if chosen[i].is_none() {
            chosen[i] = Some(Reason::Size);
            kept -= g.bytes;
        }
    }

    // 4. Free space.
    let mut free = drive.free_bytes + freed(&chosen);
    for (i, g) in deletable.iter().enumerate() {
        if free >= s.min_free_bytes {
            break;
        }
        if chosen[i].is_none() {
            chosen[i] = Some(Reason::FreeSpace);
            free += g.bytes;
        }
    }

    let problem = (free < s.min_free_bytes).then_some(Problem::DriveFull {
        free_bytes: free,
        min_free_bytes: s.min_free_bytes,
    });
    let delete: Vec<(SegmentName, Reason)> = deletable
        .iter()
        .zip(&chosen)
        .filter_map(|(g, c)| c.map(|r| (g.name.clone(), r)))
        .collect();
    Plan {
        recording_bytes_after: total - freed(&chosen),
        free_bytes_after: free,
        delete,
        problem,
    }
}
