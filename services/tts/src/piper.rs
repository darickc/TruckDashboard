//! Piper (OHF-Voice/piper1-gpl 1.8.0's libpiper, GPL-3.0), loaded at run
//! time with dlopen, so this crate builds and tests without it and the
//! service only needs it on the Pi.
//!
//! The C API (`libpiper/include/piper.h` at v1.8.0):
//!
//! - `piper_create(model, config, espeak_data)` loads a voice (about 1.4 s
//!   for a "medium" one on the Pi 5).
//! - `piper_synthesize_start(synth, text, NULL)` splits the text into
//!   sentences and clears anything left from the last text.
//! - `piper_synthesize_next(synth, &chunk)` synthesises one sentence: float
//!   samples valid until the next call, `PIPER_OK` (0) with more to come,
//!   `PIPER_DONE` (1) with the last one (`is_last`), negative on error.
//! - `piper_free(synth)`.
//!
//! libpiper needs libonnxruntime.so.1 and has no RUNPATH; loading that one
//! first, global, satisfies it without LD_LIBRARY_PATH.
//!
//! The only unsafe code in the crate besides one poll(2) (ADR-0048). Status:
//! [BENCH] 2026-11-15, Piper 1.8.0 built for aarch64 with onnxruntime 1.22.0.
#![allow(unsafe_code)]

use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::path::{Path, PathBuf};

use crate::server::{Engine, Speech};

const PIPER_OK: c_int = 0;
const PIPER_DONE: c_int = 1;

/// `piper_audio_chunk`, field for field.
#[repr(C)]
struct Chunk {
    samples: *const f32,
    num_samples: usize,
    sample_rate: c_int,
    is_last: bool,
    phonemes: *const u32,
    num_phonemes: usize,
    phoneme_ids: *const c_int,
    num_phoneme_ids: usize,
    alignments: *const c_int,
    num_alignments: usize,
}

impl Chunk {
    fn empty() -> Chunk {
        Chunk {
            samples: std::ptr::null(),
            num_samples: 0,
            sample_rate: 0,
            is_last: false,
            phonemes: std::ptr::null(),
            num_phonemes: 0,
            phoneme_ids: std::ptr::null(),
            num_phoneme_ids: 0,
            alignments: std::ptr::null(),
            num_alignments: 0,
        }
    }
}

type CreateFn = unsafe extern "C" fn(*const c_char, *const c_char, *const c_char) -> *mut c_void;
type FreeFn = unsafe extern "C" fn(*mut c_void);
type StartFn = unsafe extern "C" fn(*mut c_void, *const c_char, *const c_void) -> c_int;
type NextFn = unsafe extern "C" fn(*mut c_void, *mut Chunk) -> c_int;
type VersionFn = unsafe extern "C" fn() -> *const c_char;

/// Where Piper's install tree and a voice are.
#[derive(Debug, Clone)]
pub struct Paths {
    /// libpiper's CMake install prefix: lib/libpiper.so,
    /// lib/libonnxruntime.so.1, share/espeak-ng-data.
    pub prefix: PathBuf,
    /// The voice's .onnx; its config is beside it with ".json" added.
    pub voice: PathBuf,
}

impl Paths {
    pub fn libpiper(&self) -> PathBuf {
        self.prefix.join("lib/libpiper.so")
    }
    pub fn onnxruntime(&self) -> PathBuf {
        self.prefix.join("lib/libonnxruntime.so.1")
    }
    pub fn espeak_data(&self) -> PathBuf {
        self.prefix.join("share/espeak-ng-data")
    }
    pub fn voice_config(&self) -> PathBuf {
        let mut c = self.voice.as_os_str().to_owned();
        c.push(".json");
        PathBuf::from(c)
    }
    /// The files that must be there, missing ones first: what the start
    /// script and `serve` report instead of a dlopen error.
    pub fn missing(&self) -> Vec<PathBuf> {
        [
            self.libpiper(),
            self.onnxruntime(),
            self.espeak_data(),
            self.voice.clone(),
            self.voice_config(),
        ]
        .into_iter()
        .filter(|p| !p.exists())
        .collect()
    }
}

/// A loaded voice.
pub struct Piper {
    synth: *mut c_void,
    free: FreeFn,
    start: StartFn,
    next: NextFn,
    pub version: String,
}

fn cstr(p: &Path) -> Result<CString, String> {
    CString::new(p.as_os_str().as_encoded_bytes())
        .map_err(|_| format!("{}: a NUL in the path", p.display()))
}

fn dlerror() -> String {
    // SAFETY: dlerror returns NULL or a NUL-terminated string valid until the
    // next dl* call on this thread; it is copied at once.
    unsafe {
        let e = libc::dlerror();
        if e.is_null() {
            "unknown dlopen error".into()
        } else {
            CStr::from_ptr(e).to_string_lossy().into_owned()
        }
    }
}

fn open(path: &Path) -> Result<*mut c_void, String> {
    let c = cstr(path)?;
    // SAFETY: a valid C string; the handle is kept for the process's life
    // (never dlclose'd), so symbols from it stay valid.
    let h = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_GLOBAL) };
    if h.is_null() {
        return Err(format!("{}: {}", path.display(), dlerror()));
    }
    Ok(h)
}

fn sym(lib: *mut c_void, name: &CStr) -> Result<*mut c_void, String> {
    // SAFETY: `lib` is a live handle from dlopen and `name` a C string.
    let s = unsafe { libc::dlsym(lib, name.as_ptr()) };
    if s.is_null() {
        return Err(format!(
            "libpiper has no {}: {}",
            name.to_string_lossy(),
            dlerror()
        ));
    }
    Ok(s)
}

impl Piper {
    /// Loads libpiper and the voice.
    pub fn load(paths: &Paths) -> Result<Piper, String> {
        let missing = paths.missing();
        if !missing.is_empty() {
            let list: Vec<String> = missing.iter().map(|p| p.display().to_string()).collect();
            return Err(format!("missing {}", list.join(", ")));
        }
        open(&paths.onnxruntime())?;
        let lib = open(&paths.libpiper())?;
        // SAFETY: each symbol is the piper.h function of that name at
        // v1.8.0, cast to its declared C signature.
        let (create, free, start, next, version) = unsafe {
            (
                std::mem::transmute::<*mut c_void, CreateFn>(sym(lib, c"piper_create")?),
                std::mem::transmute::<*mut c_void, FreeFn>(sym(lib, c"piper_free")?),
                std::mem::transmute::<*mut c_void, StartFn>(sym(lib, c"piper_synthesize_start")?),
                std::mem::transmute::<*mut c_void, NextFn>(sym(lib, c"piper_synthesize_next")?),
                std::mem::transmute::<*mut c_void, VersionFn>(sym(lib, c"piper_version")?),
            )
        };
        let (model, config, espeak) = (
            cstr(&paths.voice)?,
            cstr(&paths.voice_config())?,
            cstr(&paths.espeak_data())?,
        );
        // SAFETY: three valid C strings; piper_version returns a static
        // string; piper_create returns NULL on failure, checked.
        let (synth, version) = unsafe {
            let v = version();
            let v = if v.is_null() {
                String::new()
            } else {
                CStr::from_ptr(v).to_string_lossy().into_owned()
            };
            (create(model.as_ptr(), config.as_ptr(), espeak.as_ptr()), v)
        };
        if synth.is_null() {
            return Err(format!("piper_create failed for {}", paths.voice.display()));
        }
        Ok(Piper {
            synth,
            free,
            start,
            next,
            version,
        })
    }
}

impl Engine for Piper {
    fn synthesize(
        &mut self,
        text: &str,
        keep_going: &mut dyn FnMut() -> bool,
    ) -> Result<Speech, String> {
        let text = CString::new(text).map_err(|_| "a NUL in the text".to_string())?;
        // SAFETY: a live synthesizer and a C string; NULL options means
        // Piper's defaults for the voice.
        let r = unsafe { (self.start)(self.synth, text.as_ptr(), std::ptr::null()) };
        if r < PIPER_OK {
            return Err(format!("piper_synthesize_start: {r}"));
        }
        let mut speech = Speech {
            sample_rate: 22050,
            samples: Vec::new(),
        };
        loop {
            let mut chunk = Chunk::empty();
            // SAFETY: a live synthesizer and a chunk it fills; its samples
            // stay valid until the next call, and are copied before then.
            let r = unsafe { (self.next)(self.synth, &mut chunk) };
            if r < PIPER_OK {
                return Err(format!("piper_synthesize_next: {r}"));
            }
            if chunk.sample_rate > 0 {
                speech.sample_rate = chunk.sample_rate as u32;
            }
            if !chunk.samples.is_null() && chunk.num_samples > 0 {
                // SAFETY: Piper says `num_samples` floats at `samples`.
                let s = unsafe { std::slice::from_raw_parts(chunk.samples, chunk.num_samples) };
                speech.samples.extend_from_slice(s);
            }
            if r == PIPER_DONE || chunk.is_last || !keep_going() {
                // A stop part-way is safe: the next start clears Piper's queue.
                return Ok(speech);
            }
        }
    }
}

impl Drop for Piper {
    fn drop(&mut self) {
        // SAFETY: the synthesizer from piper_create, freed once.
        unsafe { (self.free)(self.synth) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_follow_libpipers_install_tree() {
        let p = Paths {
            prefix: "/opt/f250/piper".into(),
            voice: "/opt/f250/piper/voices/en_US-ljspeech-medium.onnx".into(),
        };
        assert_eq!(p.libpiper(), Path::new("/opt/f250/piper/lib/libpiper.so"));
        assert_eq!(
            p.onnxruntime(),
            Path::new("/opt/f250/piper/lib/libonnxruntime.so.1")
        );
        assert_eq!(
            p.espeak_data(),
            Path::new("/opt/f250/piper/share/espeak-ng-data")
        );
        assert_eq!(
            p.voice_config(),
            Path::new("/opt/f250/piper/voices/en_US-ljspeech-medium.onnx.json")
        );
    }

    #[test]
    fn missing_files_are_named_and_load_refuses_without_dlopen() {
        let p = Paths {
            prefix: "/nonexistent/piper".into(),
            voice: "/nonexistent/voice.onnx".into(),
        };
        assert_eq!(p.missing().len(), 5);
        let err = Piper::load(&p).err().unwrap_or_default();
        assert!(
            err.starts_with("missing /nonexistent/piper/lib/libpiper.so"),
            "{err}"
        );
        assert!(err.contains("/nonexistent/voice.onnx.json"), "{err}");
    }
}
