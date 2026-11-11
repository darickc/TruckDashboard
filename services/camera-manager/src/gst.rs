//! In-process GStreamer (gstreamer-rs), ADR-0027 decision 2: one capture
//! per camera, its picture split by a `tee` into
//!
//! ```text
//! v4l2src ! capsfilter (the camera's caps) ! tee
//!   tee. ! queue (leaky) ! [h264parse] ! splitmuxsink (matroskamux)      recording, always
//!   tee. ! queue (leaky) ! DECODER ! videoconvert ! identity ! SINK      display, while shown
//! ```
//!
//! - The recording branch keeps what the camera sends (decision 3), in
//!   segments named by the loop ([`RecordSpec::next_segment`]) through
//!   `splitmuxsink`'s `format-location` signal. Its `fragment-opened` and
//!   `fragment-closed` messages become [`Event::SegmentOpened`] and
//!   [`Event::SegmentClosed`].
//! - `matroskamux` closes a cluster at least every second, where the
//!   property exists (`max-cluster-duration`: on 1.26 it does, default
//!   65.5 s; on the Pi's 1.28 UNVERIFIED, so it is set by name, from a
//!   string, and a missing one is logged).
//! - The display branch is added and removed while the recording runs. It
//!   is unlinked from the `tee` at an idle moment (an IDLE pad probe) and
//!   set to NULL, which closes its window.
//! - Both queues are leaky: a slow drive drops recorded frames rather than
//!   freezing the picture, and a slow display never holds up the recording.
//! - Frames are counted by pad probes, not by parsing output.
//! - A stop sends end-of-stream first, so `splitmuxsink` finishes the
//!   segment being written, and waits up to [`EOS_WAIT`] for it.
//!
//! Status: `[SIM]` with real pipelines from `videotestsrc` in Linux
//! (`make linux-test`, tests/gst.rs); `[BENCH]` 2026-11-10 on the Pi's
//! GStreamer 1.28.5 with two USB webcams (bench-log).

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, mpsc as std_mpsc};
use std::time::Duration;

/// For tests that read segments back (a dev-dependency can't be optional).
pub use gstreamer;
use gstreamer as gst;
use gstreamer::prelude::*;
use tokio::sync::mpsc;

use crate::media::{
    Branch, Capture, CaptureSpec, Encoding, Event, Media, StopFuture, encoding, recordable,
    split_caps,
};
use crate::pipeline::FRAME_ELEMENT;

/// How long a stop waits for the recording's end-of-stream before cutting
/// it off. Inside main's stop grace and the unit's TimeoutStopSec.
pub const EOS_WAIT: Duration = Duration::from_secs(3);

/// How long removing the display branch waits for the `tee` to be idle.
const IDLE_WAIT: Duration = Duration::from_secs(1);

/// Captures in this process.
pub struct GstMedia {
    /// A pipeline description used in place of the camera
    /// (`videotestsrc is-live=true ! ... ! jpegenc`), for tests and
    /// development. `None`: `v4l2src device=...`.
    source: Option<String>,
}

impl GstMedia {
    /// Initialises GStreamer.
    pub fn new() -> Result<GstMedia, String> {
        gst::init().map_err(|e| e.to_string())?;
        Ok(GstMedia { source: None })
    }

    /// Every camera is this description instead (tests, development).
    pub fn with_source(description: &str) -> Result<GstMedia, String> {
        let mut m = Self::new()?;
        m.source = Some(description.to_string());
        Ok(m)
    }
}

impl Media for GstMedia {
    fn can_record(&self) -> Result<(), String> {
        for f in ["splitmuxsink", "matroskamux"] {
            if gst::ElementFactory::find(f).is_none() {
                return Err(format!(
                    "GStreamer has no {f} (gst-plugins-good's multifile and matroska plugins)"
                ));
            }
        }
        Ok(())
    }

    fn start(
        &mut self,
        spec: CaptureSpec,
        events: mpsc::Sender<Event>,
    ) -> Result<Box<dyn Capture>, String> {
        GstCapture::start(self.source.as_deref(), spec, events)
            .map(|c| Box::new(c) as Box<dyn Capture>)
    }
}

/// The display branch while it is linked.
struct Display {
    bin: gst::Bin,
    tee_pad: gst::Pad,
}

struct GstCapture {
    generation: u64,
    pipeline: gst::Pipeline,
    tee: gst::Element,
    /// The display branch's description, to add it again.
    display_desc: String,
    display: Option<Display>,
    recording: bool,
    events: mpsc::Sender<Event>,
    eos: Arc<Mutex<Option<std_mpsc::Sender<()>>>>,
    bus_stop: Arc<AtomicBool>,
    bus_thread: Option<std::thread::JoinHandle<()>>,
}

fn element(factory: &str) -> Result<gst::Element, String> {
    gst::ElementFactory::make(factory)
        .build()
        .map_err(|_| format!("GStreamer has no {factory}"))
}

impl GstCapture {
    fn start(
        source: Option<&str>,
        spec: CaptureSpec,
        events: mpsc::Sender<Event>,
    ) -> Result<GstCapture, String> {
        let generation = spec.generation;
        let (camera_caps, decode) = split_caps(&spec.caps);
        let caps: gst::Caps = camera_caps
            .parse()
            .map_err(|_| format!("bad caps: {camera_caps}"))?;
        let pipeline = gst::Pipeline::new();

        let src: gst::Element = match source {
            Some(desc) => gst::parse::bin_from_description(desc, true)
                .map_err(|e| format!("source {desc:?}: {e}"))?
                .upcast(),
            None => gst::ElementFactory::make("v4l2src")
                .property("device", &spec.device)
                .build()
                .map_err(|_| "GStreamer has no v4l2src".to_string())?,
        };
        let filter = gst::ElementFactory::make("capsfilter")
            .property("caps", &caps)
            .build()
            .map_err(|_| "GStreamer has no capsfilter".to_string())?;
        let tee = gst::ElementFactory::make("tee")
            .property("allow-not-linked", true)
            .build()
            .map_err(|_| "GStreamer has no tee".to_string())?;
        pipeline
            .add_many([&src, &filter, &tee])
            .map_err(|e| e.to_string())?;
        gst::Element::link_many([&src, &filter, &tee]).map_err(|e| e.to_string())?;

        let recording = spec.record.is_some();
        if let Some(rec) = &spec.record {
            let enc = recordable(&spec.caps)?;
            let queue = gst::ElementFactory::make("queue")
                .property("max-size-buffers", 0u32)
                .property("max-size-bytes", 0u32)
                .property("max-size-time", 2_000_000_000u64)
                .property_from_str("leaky", "downstream")
                .build()
                .map_err(|_| "GStreamer has no queue".to_string())?;
            let mux = element("matroskamux")?;
            let cluster_ns = rec.cluster.as_nanos().to_string();
            if mux.find_property("max-cluster-duration").is_some() {
                mux.set_property_from_str("max-cluster-duration", &cluster_ns);
            } else {
                eprintln!(
                    "[camera] matroskamux has no max-cluster-duration: clusters are the muxer's default"
                );
            }
            let split = gst::ElementFactory::make("splitmuxsink")
                .property("max-size-time", rec.segment.as_nanos() as u64)
                .property("muxer", &mux)
                .build()
                .map_err(|_| "GStreamer has no splitmuxsink".to_string())?;
            let next = rec.next_segment.clone();
            split.connect("format-location", false, move |_| {
                Some(next().to_string_lossy().into_owned().to_value())
            });
            let mut chain: Vec<gst::Element> = vec![queue.clone()];
            if enc == Encoding::H264 {
                chain.push(element("h264parse")?);
            }
            chain.push(split);
            pipeline.add_many(&chain).map_err(|e| e.to_string())?;
            gst::Element::link_many(&chain).map_err(|e| e.to_string())?;
            let tee_pad = tee
                .request_pad_simple("src_%u")
                .ok_or("the tee gave no pad")?;
            let q_sink = queue.static_pad("sink").ok_or("queue has no sink")?;
            tee_pad.link(&q_sink).map_err(|e| format!("{e:?}"))?;
            // Count what leaves the queue toward the muxer.
            let q_src = queue.static_pad("src").ok_or("queue has no src")?;
            count_frames(&q_src, &events, generation, Branch::Record);
        }
        debug_assert!(encoding(camera_caps) != Encoding::Other || !recording);

        let display_desc = format!(
            "queue leaky=downstream max-size-buffers=2 ! {}videoconvert ! identity name={FRAME_ELEMENT} ! {}",
            if decode.is_empty() {
                String::new()
            } else {
                format!("{decode} ! ")
            },
            spec.sink
        );

        let eos: Arc<Mutex<Option<std_mpsc::Sender<()>>>> = Arc::default();
        let bus_stop = Arc::new(AtomicBool::new(false));
        let bus = pipeline.bus().ok_or("the pipeline has no bus")?;
        let bus_thread = {
            let events = events.clone();
            let eos = eos.clone();
            let stop = bus_stop.clone();
            std::thread::Builder::new()
                .name(format!("gst-bus-{generation}"))
                .spawn(move || watch_bus(&bus, generation, &events, &eos, &stop))
                .map_err(|e| e.to_string())?
        };

        let mut cap = GstCapture {
            generation,
            pipeline,
            tee,
            display_desc,
            display: None,
            recording,
            events,
            eos,
            bus_stop,
            bus_thread: Some(bus_thread),
        };
        if spec.display {
            cap.add_display()?;
        }
        if let Err(e) = cap.pipeline.set_state(gst::State::Playing) {
            cap.teardown();
            return Err(format!("the pipeline wouldn't play: {e}"));
        }
        Ok(cap)
    }

    fn add_display(&mut self) -> Result<(), String> {
        if self.display.is_some() {
            return Ok(());
        }
        let bin = gst::parse::bin_from_description(&self.display_desc, true)
            .map_err(|e| format!("display {:?}: {e}", self.display_desc))?;
        if let Some(id) = bin.by_name(FRAME_ELEMENT)
            && let Some(pad) = id.static_pad("src")
        {
            count_frames(&pad, &self.events, self.generation, Branch::Display);
        }
        self.pipeline.add(&bin).map_err(|e| e.to_string())?;
        let tee_pad = self
            .tee
            .request_pad_simple("src_%u")
            .ok_or("the tee gave no pad")?;
        let sink = bin
            .static_pad("sink")
            .ok_or("the display has no sink pad")?;
        if let Err(e) = tee_pad.link(&sink) {
            self.tee.release_request_pad(&tee_pad);
            let _ = self.pipeline.remove(&bin);
            return Err(format!("display link: {e:?}"));
        }
        if let Err(e) = bin.sync_state_with_parent() {
            let d = Display { bin, tee_pad };
            self.drop_display(d);
            return Err(format!("display start: {e}"));
        }
        self.display = Some(Display { bin, tee_pad });
        Ok(())
    }

    fn remove_display(&mut self) {
        if let Some(d) = self.display.take() {
            self.drop_display(d);
        }
    }

    /// Unlinks at an idle moment, then NULL (the window closes) and out.
    fn drop_display(&self, d: Display) {
        let (tx, rx) = std_mpsc::channel();
        if let Some(sink) = d.bin.static_pad("sink") {
            let tx = Mutex::new(Some(tx));
            d.tee_pad.add_probe(gst::PadProbeType::IDLE, move |pad, _| {
                let _ = pad.unlink(&sink);
                if let Ok(mut t) = tx.lock()
                    && let Some(t) = t.take()
                {
                    let _ = t.send(());
                }
                gst::PadProbeReturn::Remove
            });
            if rx.recv_timeout(IDLE_WAIT).is_err() {
                eprintln!("[camera] display branch: the tee wasn't idle; removing it anyway");
            }
        }
        let _ = d.bin.set_state(gst::State::Null);
        let _ = self.pipeline.remove(&d.bin);
        self.tee.release_request_pad(&d.tee_pad);
    }

    fn teardown(&mut self) {
        let _ = self.pipeline.set_state(gst::State::Null);
        self.bus_stop.store(true, Ordering::Release);
        if let Some(t) = self.bus_thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for GstCapture {
    fn drop(&mut self) {
        self.teardown();
    }
}

impl Capture for GstCapture {
    fn generation(&self) -> u64 {
        self.generation
    }

    fn set_display(&mut self, on: bool) -> Result<(), String> {
        if on {
            self.add_display()
        } else {
            self.remove_display();
            Ok(())
        }
    }

    fn stop(mut self: Box<Self>) -> StopFuture {
        Box::pin(async move {
            tokio::task::spawn_blocking(move || {
                // The window first: it never outlives the stop.
                self.remove_display();
                let mut clean = true;
                if self.recording {
                    let (tx, rx) = std_mpsc::channel();
                    if let Ok(mut e) = self.eos.lock() {
                        *e = Some(tx);
                    }
                    self.pipeline.send_event(gst::event::Eos::new());
                    clean = rx.recv_timeout(EOS_WAIT).is_ok();
                    if !clean {
                        eprintln!(
                            "[camera] the recording didn't finish within {} s: cut off",
                            EOS_WAIT.as_secs()
                        );
                    }
                }
                self.teardown();
                clean
            })
            .await
            .unwrap_or(false)
        })
    }
}

/// Reports each buffer through `pad` as a frame of `branch`. Never blocks
/// the streaming thread: a full channel drops the report.
fn count_frames(pad: &gst::Pad, events: &mpsc::Sender<Event>, generation: u64, branch: Branch) {
    let events = events.clone();
    pad.add_probe(gst::PadProbeType::BUFFER, move |_, _| {
        let _ = events.try_send(Event::Frame { generation, branch });
        gst::PadProbeReturn::Ok
    });
}

fn watch_bus(
    bus: &gst::Bus,
    generation: u64,
    events: &mpsc::Sender<Event>,
    eos: &Mutex<Option<std_mpsc::Sender<()>>>,
    stop: &AtomicBool,
) {
    let mut ended = false;
    while !stop.load(Ordering::Acquire) {
        let Some(msg) = bus.timed_pop(gst::ClockTime::from_mseconds(100)) else {
            continue;
        };
        match msg.view() {
            gst::MessageView::Element(e) => {
                let Some(s) = e.structure() else { continue };
                let location = || s.get::<String>("location").ok().map(PathBuf::from);
                let ev = match s.name().as_str() {
                    "splitmuxsink-fragment-opened" => {
                        location().map(|path| Event::SegmentOpened { generation, path })
                    }
                    "splitmuxsink-fragment-closed" => {
                        location().map(|path| Event::SegmentClosed { generation, path })
                    }
                    _ => None,
                };
                if let Some(ev) = ev {
                    let _ = events.blocking_send(ev);
                }
            }
            gst::MessageView::Eos(_) => {
                if let Ok(mut e) = eos.lock()
                    && let Some(tx) = e.take()
                {
                    let _ = tx.send(());
                    continue;
                }
                if !ended {
                    ended = true;
                    let _ = events.blocking_send(Event::Ended {
                        generation,
                        detail: "the camera's stream ended".into(),
                    });
                }
            }
            gst::MessageView::Error(e) => {
                let src = e
                    .src()
                    .map(|s| s.name().to_string())
                    .unwrap_or_else(|| "pipeline".into());
                let detail = format!("{src}: {}", e.error());
                eprintln!(
                    "[camera] gst: {detail}{}",
                    e.debug().map(|d| format!(" ({d})")).unwrap_or_default()
                );
                if !ended {
                    ended = true;
                    let _ = events.blocking_send(Event::Ended { generation, detail });
                }
            }
            gst::MessageView::Warning(w) => {
                eprintln!("[camera] gst warning: {}", w.error());
            }
            _ => {}
        }
    }
}
