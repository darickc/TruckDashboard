//! The media page's cover (owner, 2026-11-23): the phone's picture, made
//! ready for the dial here so the dial only scales it up and draws it.
//!
//! audio-manager's GetCoverArt gives the picture as the phone sent it (a
//! JPEG from a phone, BMP from the simulated one). This crops it square from
//! the middle, scales it to [`SIDE`] x [`SIDE`], darkens it — its opacity
//! over black, [`opacity`], less for a bright cover, so the page's white
//! text stays readable — and turns it into RGB565, high byte first (the
//! dial's panel order). The dial doubles it to its 360 x 360 screen.
//!
//! On the serial port (firmware/knob-display/lib/KnobCore/src/Art.h):
//!
//!   A1 begin <id> <w> <h> <len> <crc32>*CS
//!   A1 data <id> <offset> <base64>*CS      CHUNK bytes each, in order
//!   A1 none*CS
//!
//! The id is the CRC-32 of the pixels, so a repeat of the same picture is
//! recognised by the dial whatever audio-manager called it.

use image::imageops::FilterType;

use crate::frame::with_checksum;

/// The picture's side on the wire; the dial scales it to 360.
pub const SIDE: u32 = 180;
/// Bytes per data line: 200 base64 characters, so a line stays under the
/// dial's 255.
pub const CHUNK: usize = 150;

/// A cover ready for the dial.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Art {
    pub id: u32,
    pub w: u16,
    pub h: u16,
    /// RGB565, high byte first, darkened.
    pub pixels: Vec<u8>,
    pub crc: u32,
}

/// How much of the cover shows over black, from its mean brightness (0..1,
/// Rec. 601 luma): 40 % for a dark cover, down to 30 % for a bright one, so
/// the text over it reads the same (the canvas's two media boards, owner
/// 2026-11-23). A look, not a vehicle threshold.
pub fn opacity(mean_luma: f32) -> f32 {
    const DARK: (f32, f32) = (0.35, 0.40);
    const BRIGHT: (f32, f32) = (0.65, 0.30);
    if mean_luma <= DARK.0 {
        DARK.1
    } else if mean_luma >= BRIGHT.0 {
        BRIGHT.1
    } else {
        let t = (mean_luma - DARK.0) / (BRIGHT.0 - DARK.0);
        DARK.1 + t * (BRIGHT.1 - DARK.1)
    }
}

/// Decodes `bytes` (JPEG, PNG or BMP) and makes it ready for the dial.
pub fn prepare(bytes: &[u8]) -> Result<Art, String> {
    let img = image::load_from_memory(bytes).map_err(|e| format!("cover: {e}"))?;
    let rgb = img
        .resize_to_fill(SIDE, SIDE, FilterType::Triangle)
        .to_rgb8();
    let n = (rgb.width() * rgb.height()) as f32;
    let mean = rgb
        .pixels()
        .map(|p| 0.299 * p[0] as f32 + 0.587 * p[1] as f32 + 0.114 * p[2] as f32)
        .sum::<f32>()
        / n
        / 255.0;
    let opa = opacity(mean);
    let mut pixels = Vec::with_capacity((SIDE * SIDE * 2) as usize);
    for p in rgb.pixels() {
        let v = rgb565([p[0], p[1], p[2]], opa);
        pixels.extend_from_slice(&v.to_be_bytes());
    }
    let crc = crc32(&pixels);
    Ok(Art {
        id: if crc == 0 { 1 } else { crc },
        w: rgb.width() as u16,
        h: rgb.height() as u16,
        pixels,
        crc,
    })
}

/// One pixel darkened by `opa` (0..1) and packed as RGB565.
pub fn rgb565(c: [u8; 3], opa: f32) -> u16 {
    let dim = |v: u8, max: u32| -> u16 {
        let x = (v as f32 * opa / 255.0 * max as f32).round() as u32;
        x.min(max) as u16
    };
    (dim(c[0], 31) << 11) | (dim(c[1], 63) << 5) | dim(c[2], 31)
}

/// The lines that send `art`: its begin, then its data in order.
pub fn lines(art: &Art) -> Vec<String> {
    let mut out = Vec::with_capacity(1 + art.pixels.len().div_ceil(CHUNK));
    out.push(with_checksum(&format!(
        "A1 begin {:08x} {} {} {} {:08x}",
        art.id,
        art.w,
        art.h,
        art.pixels.len(),
        art.crc
    )));
    for (i, chunk) in art.pixels.chunks(CHUNK).enumerate() {
        out.push(with_checksum(&format!(
            "A1 data {:08x} {} {}",
            art.id,
            i * CHUNK,
            base64(chunk)
        )));
    }
    out
}

/// No cover for this track.
pub fn none_line() -> String {
    with_checksum("A1 none")
}

/// Standard base64 with '=' padding.
pub fn base64(data: &[u8]) -> String {
    const ABC: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for c in data.chunks(3) {
        let b = [c[0], *c.get(1).unwrap_or(&0), *c.get(2).unwrap_or(&0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for k in 0..4 {
            if k <= c.len() {
                out.push(ABC[((n >> (18 - 6 * k)) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

/// CRC-32 (IEEE 802.3, reflected), as zlib's crc32() and the dial's.
pub fn crc32(data: &[u8]) -> u32 {
    let mut c = 0xFFFF_FFFFu32;
    for &b in data {
        c ^= u32::from(b);
        for _ in 0..8 {
            c = (c >> 1) ^ (0xEDB8_8320 & 0u32.wrapping_sub(c & 1));
        }
    }
    !c
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;
    use crate::frame::checksum;

    /// A plain 24-bit BMP of `w` x `h` in one colour.
    fn bmp(w: u32, h: u32, c: [u8; 3]) -> Vec<u8> {
        let row = (w * 3).div_ceil(4) * 4;
        let size = 54 + row * h;
        let mut v = Vec::new();
        v.extend_from_slice(b"BM");
        v.extend_from_slice(&size.to_le_bytes());
        v.extend_from_slice(&[0; 4]);
        v.extend_from_slice(&54u32.to_le_bytes());
        v.extend_from_slice(&40u32.to_le_bytes());
        v.extend_from_slice(&w.to_le_bytes());
        v.extend_from_slice(&h.to_le_bytes());
        v.extend_from_slice(&1u16.to_le_bytes());
        v.extend_from_slice(&24u16.to_le_bytes());
        v.extend_from_slice(&[0; 24]);
        for _ in 0..h {
            for _ in 0..w {
                v.extend_from_slice(&[c[2], c[1], c[0]]);
            }
            v.extend(std::iter::repeat_n(0, (row - w * 3) as usize));
        }
        v
    }

    #[test]
    fn base64_and_crc32_known_vectors() {
        assert_eq!(base64(b"Man"), "TWFu");
        assert_eq!(base64(b"Ma"), "TWE=");
        assert_eq!(base64(b"M"), "TQ==");
        assert_eq!(base64(&[0xFF, 0xFE, 0xFD]), "//79");
        assert_eq!(base64(b""), "");
        assert_eq!(crc32(b"123456789"), 0xCBF4_3926);
        assert_eq!(crc32(b""), 0);
    }

    #[test]
    fn opacity_less_for_bright_covers() {
        assert_eq!(opacity(0.0), 0.40);
        assert_eq!(opacity(0.35), 0.40);
        assert!((opacity(0.5) - 0.35).abs() < 1e-6);
        assert_eq!(opacity(0.65), 0.30);
        assert_eq!(opacity(1.0), 0.30);
    }

    #[test]
    fn pixels_darkened_and_packed_high_byte_first() {
        assert_eq!(rgb565([255, 255, 255], 1.0), 0xFFFF);
        assert_eq!(rgb565([0, 0, 0], 0.4), 0);
        // White at 40 %: 12/31, 25/63, 12/31.
        assert_eq!(rgb565([255, 255, 255], 0.4), (12 << 11) | (25 << 5) | 12);
        assert_eq!(rgb565([255, 0, 0], 1.0), 0xF800);
    }

    #[test]
    fn a_cover_is_cropped_scaled_and_darkened() {
        // A wide red picture: square, 180 x 180, red at 40 % (dark: luma 0.3).
        let art = prepare(&bmp(400, 200, [255, 0, 0])).unwrap();
        assert_eq!((art.w, art.h), (180, 180));
        assert_eq!(art.pixels.len(), 180 * 180 * 2);
        let first = u16::from_be_bytes([art.pixels[0], art.pixels[1]]);
        assert_eq!(first, rgb565([255, 0, 0], 0.40));
        assert_eq!(art.crc, crc32(&art.pixels));
        assert_eq!(art.id, art.crc);
        // A white one is bright: 30 %.
        let white = prepare(&bmp(10, 10, [255, 255, 255])).unwrap();
        let p = u16::from_be_bytes([white.pixels[0], white.pixels[1]]);
        assert_eq!(p, rgb565([255, 255, 255], 0.30));
        // The same picture gets the same id; another gets another.
        assert_eq!(prepare(&bmp(400, 200, [255, 0, 0])).unwrap().id, art.id);
        assert_ne!(white.id, art.id);
        assert!(prepare(b"not a picture").is_err());
    }

    #[test]
    fn lines_carry_every_byte_in_order_under_the_dials_limit() {
        let art = prepare(&bmp(200, 200, [10, 120, 200])).unwrap();
        let lines = lines(&art);
        assert_eq!(lines.len(), 1 + (180 * 180 * 2usize).div_ceil(CHUNK));
        assert_eq!(
            lines[0],
            with_checksum(&format!(
                "A1 begin {:08x} 180 180 64800 {:08x}",
                art.id, art.crc
            ))
        );
        let mut got = Vec::new();
        for (i, l) in lines[1..].iter().enumerate() {
            assert!(l.len() <= 255, "line {i} is {} long", l.len());
            let (body, cs) = l.rsplit_once('*').unwrap();
            assert_eq!(u8::from_str_radix(cs, 16).unwrap(), checksum(body));
            let f: Vec<_> = body.split(' ').collect();
            assert_eq!(f[..3], ["A1", "data", &format!("{:08x}", art.id)]);
            assert_eq!(f[3].parse::<usize>().unwrap(), got.len());
            got.extend(decode(f[4]));
        }
        assert_eq!(got, art.pixels);
        assert_eq!(none_line(), with_checksum("A1 none"));
    }

    fn decode(s: &str) -> Vec<u8> {
        const ABC: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = Vec::new();
        for q in s.as_bytes().chunks(4) {
            let v: Vec<u32> = q
                .iter()
                .map(|&c| ABC.find(c as char).unwrap_or(0) as u32)
                .collect();
            let n = (v[0] << 18) | (v[1] << 12) | (v[2] << 6) | v[3];
            let pad = q.iter().filter(|&&c| c == b'=').count();
            out.extend(&[(n >> 16) as u8, (n >> 8) as u8, n as u8][..3 - pad]);
        }
        out
    }
}
