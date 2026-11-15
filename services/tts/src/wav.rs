//! A mono 16-bit PCM WAV from float samples, which pw-play (libsndfile)
//! plays as it plays Flite's.

/// The bytes of a mono 16-bit PCM WAV. Samples outside -1..1 are clipped.
pub fn mono_i16(sample_rate: u32, samples: &[f32]) -> Vec<u8> {
    let data_len = u32::try_from(samples.len() * 2).unwrap_or(u32::MAX - 36) & !1;
    let n = (data_len / 2) as usize;
    let mut out = Vec::with_capacity(44 + n * 2);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data_len).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes()); // fmt chunk size
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&(sample_rate * 2).to_le_bytes()); // bytes a second
    out.extend_from_slice(&2u16.to_le_bytes()); // block align
    out.extend_from_slice(&16u16.to_le_bytes()); // bits a sample
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data_len.to_le_bytes());
    for &s in &samples[..n] {
        let v = if s.is_nan() { 0.0 } else { s.clamp(-1.0, 1.0) };
        out.extend_from_slice(&((v * 32767.0).round() as i16).to_le_bytes());
    }
    out
}

/// Whether `bytes` starts like a WAV this module writes (RIFF, WAVE, PCM)
/// with at least one sample: what the client checks before keeping it.
pub fn looks_valid(bytes: &[u8]) -> bool {
    bytes.len() > 44
        && &bytes[0..4] == b"RIFF"
        && &bytes[8..12] == b"WAVE"
        && &bytes[12..16] == b"fmt "
        && &bytes[36..40] == b"data"
}

#[cfg(test)]
mod tests {
    use super::*;

    fn u32_at(b: &[u8], i: usize) -> u32 {
        u32::from_le_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]])
    }

    #[test]
    fn header_says_mono_16_bit_at_the_rate_with_the_right_lengths() {
        let w = mono_i16(22050, &[0.0, 0.5, -0.5]);
        assert_eq!(w.len(), 44 + 6);
        assert_eq!(&w[0..4], b"RIFF");
        assert_eq!(u32_at(&w, 4), 36 + 6);
        assert_eq!(&w[8..16], b"WAVEfmt ");
        assert_eq!(u32_at(&w, 16), 16);
        assert_eq!(u16::from_le_bytes([w[20], w[21]]), 1, "PCM");
        assert_eq!(u16::from_le_bytes([w[22], w[23]]), 1, "mono");
        assert_eq!(u32_at(&w, 24), 22050);
        assert_eq!(u32_at(&w, 28), 44100);
        assert_eq!(u16::from_le_bytes([w[34], w[35]]), 16);
        assert_eq!(&w[36..40], b"data");
        assert_eq!(u32_at(&w, 40), 6);
        assert!(looks_valid(&w));
    }

    #[test]
    fn samples_are_scaled_and_clipped() {
        let w = mono_i16(16000, &[1.0, -1.0, 2.0, -3.0, f32::NAN, 0.5]);
        let s: Vec<i16> = w[44..]
            .chunks(2)
            .map(|c| i16::from_le_bytes([c[0], c[1]]))
            .collect();
        assert_eq!(s, vec![32767, -32767, 32767, -32767, 0, 16384]);
    }

    #[test]
    fn empty_or_foreign_bytes_are_not_valid() {
        assert!(!looks_valid(&mono_i16(22050, &[])));
        assert!(!looks_valid(b""));
        let mut w = mono_i16(22050, &[0.1; 10]);
        w[8] = b'X';
        assert!(!looks_valid(&w));
    }
}
