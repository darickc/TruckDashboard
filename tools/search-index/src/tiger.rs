//! US Census Bureau address ranges: TIGER/Line ADDRFEAT shapefiles, one zip
//! per county (`tl_2026_20001_addrfeat.zip`), read without GDAL (ADR-0041).
//!
//! Each zip holds a shapefile: `.shp` (the lines, as polylines in NAD83
//! longitude and latitude) and `.dbf` (the attributes, one record per line,
//! in the same order). Of the attributes only these are read:
//!
//! | Field | What it is |
//! |---|---|
//! | `FULLNAME` | The street's name, abbreviated ("N Main St", "Co Rd 12") |
//! | `LFROMHN`, `LTOHN`, `RFROMHN`, `RTOHN` | The left and right sides' house numbers at the line's first and last point |
//! | `PARITYL`, `PARITYR` | `O` odd, `E` even, `B` both |
//! | `ZIPL`, `ZIPR` | Each side's ZIP code |
//!
//! Only numbers of plain digits are kept, as Nominatim's TIGER import does:
//! hyphenated numbers (Queens, NY: "10-09") and grid numbers (Wisconsin:
//! "S110W14498") are counted and left out. NAD83 and WGS 84 differ by about
//! a metre in the lower 48, less than the estimate's own error.

use std::io::Read;
use std::path::Path;

use geocode::ranges::{Edge, Parity, Side};

/// A shapefile's polylines as (lat, lon) points, in record order; None for
/// a null shape.
pub type Lines = Vec<Option<Vec<(f64, f64)>>>;

/// One line of an ADDRFEAT file: a street's piece between two crossings.
#[derive(Clone, Debug, PartialEq)]
pub struct TigerEdge {
    pub name: String,
    pub edge: Edge,
}

/// What a file held.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Read1 {
    /// Lines with a name and at least one side's range of plain numbers.
    pub kept: u64,
    /// Sides whose numbers aren't plain digits ("10-09", "S110W14498").
    pub odd_numbers: u64,
    /// Lines without a name, without ranges, or outside the box.
    pub dropped: u64,
}

/// The lines of one ADDRFEAT zip that have a name and a range, with a first
/// point inside `bbox` (west, south, east, north) when given.
pub fn read_zip(
    path: &Path,
    bbox: Option<(f64, f64, f64, f64)>,
) -> Result<(Vec<TigerEdge>, Read1), String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let at = |e: String| format!("{}: {e}", path.display());
    let files = unzip(&bytes).map_err(at)?;
    let find = |ext: &str| {
        files
            .iter()
            .find(|(n, _)| n.to_ascii_lowercase().ends_with(ext))
            .map(|(_, d)| d.as_slice())
            .ok_or_else(|| format!("{}: no {ext} in the zip", path.display()))
    };
    let lines = read_shp(find(".shp")?).map_err(at)?;
    let records = read_dbf(find(".dbf")?).map_err(at)?;
    if lines.len() != records.len() {
        return Err(format!(
            "{}: {} lines but {} records",
            path.display(),
            lines.len(),
            records.len()
        ));
    }
    Ok(edges(lines, &records, bbox))
}

/// The lines and records as edges.
pub fn edges(
    lines: Lines,
    records: &Records,
    bbox: Option<(f64, f64, f64, f64)>,
) -> (Vec<TigerEdge>, Read1) {
    let mut out = Vec::new();
    let mut n = Read1::default();
    let field = |i: usize, name: &str| records.get(i, name).unwrap_or("");
    for (i, line) in lines.into_iter().enumerate() {
        let name = field(i, "FULLNAME");
        let Some(line) = line.filter(|l| l.len() >= 2) else {
            n.dropped += 1;
            continue;
        };
        if name.is_empty()
            || bbox.is_some_and(|(w, s, e, no)| {
                let (lat, lon) = line[0];
                !(s..=no).contains(&lat) || !(w..=e).contains(&lon)
            })
        {
            n.dropped += 1;
            continue;
        }
        let mut side = |from: &str, to: &str, parity: &str, zip: &str| -> Option<Side> {
            if from.is_empty() && to.is_empty() {
                return None;
            }
            match (plain(from), plain(to)) {
                (Some(from), Some(to)) => Some(Side {
                    from,
                    to,
                    parity: Parity::from_code(parity, from, to),
                    zip: zip5(zip),
                }),
                _ => {
                    n.odd_numbers += 1;
                    None
                }
            }
        };
        let left = side(
            field(i, "LFROMHN"),
            field(i, "LTOHN"),
            field(i, "PARITYL"),
            field(i, "ZIPL"),
        );
        let right = side(
            field(i, "RFROMHN"),
            field(i, "RTOHN"),
            field(i, "PARITYR"),
            field(i, "ZIPR"),
        );
        if left.is_none() && right.is_none() {
            n.dropped += 1;
            continue;
        }
        n.kept += 1;
        out.push(TigerEdge {
            name: name.to_string(),
            edge: Edge { line, left, right },
        });
    }
    (out, n)
}

/// A house number of plain digits, below a billion.
fn plain(s: &str) -> Option<u32> {
    (!s.is_empty() && s.len() <= 9 && s.bytes().all(|b| b.is_ascii_digit()))
        .then(|| s.parse().ok())
        .flatten()
}

fn zip5(s: &str) -> Option<u32> {
    (s.len() == 5 && s.bytes().all(|b| b.is_ascii_digit()))
        .then(|| s.parse().ok())
        .flatten()
}

fn u16_at(b: &[u8], i: usize) -> Result<usize, String> {
    b.get(i..i + 2)
        .map(|s| usize::from(u16::from_le_bytes([s[0], s[1]])))
        .ok_or_else(|| "cut short".to_string())
}

fn u32_at(b: &[u8], i: usize) -> Result<u32, String> {
    b.get(i..i + 4)
        .map(|s| u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
        .ok_or_else(|| "cut short".to_string())
}

fn i32_at(b: &[u8], i: usize) -> Result<i32, String> {
    u32_at(b, i).map(|v| v as i32)
}

fn f64_at(b: &[u8], i: usize) -> Result<f64, String> {
    b.get(i..i + 8)
        .map(|s| {
            let mut a = [0u8; 8];
            a.copy_from_slice(s);
            f64::from_le_bytes(a)
        })
        .ok_or_else(|| "cut short".to_string())
}

/// The files of a zip archive, by name: stored or deflated, CRC-checked.
/// No ZIP64 (the Census's county files are a few MB).
pub fn unzip(b: &[u8]) -> Result<Vec<(String, Vec<u8>)>, String> {
    const EOCD: u32 = 0x0605_4b50;
    const CENTRAL: u32 = 0x0201_4b50;
    const LOCAL: u32 = 0x0403_4b50;
    let start = b.len().saturating_sub(22 + 65_535);
    let eocd = (start..b.len().saturating_sub(21))
        .rev()
        .find(|&i| u32_at(b, i) == Ok(EOCD))
        .ok_or("not a zip file")?;
    let entries = u16_at(b, eocd + 10)?;
    let mut p = u32_at(b, eocd + 16)? as usize;
    let mut out = Vec::with_capacity(entries);
    for _ in 0..entries {
        if u32_at(b, p)? != CENTRAL {
            return Err("bad central directory".into());
        }
        let method = u16_at(b, p + 10)?;
        let crc = u32_at(b, p + 16)?;
        let packed = u32_at(b, p + 20)? as usize;
        let size = u32_at(b, p + 24)? as usize;
        let (n, x, c) = (u16_at(b, p + 28)?, u16_at(b, p + 30)?, u16_at(b, p + 32)?);
        let local = u32_at(b, p + 42)? as usize;
        let name =
            String::from_utf8_lossy(b.get(p + 46..p + 46 + n).ok_or("cut short")?).into_owned();
        p += 46 + n + x + c;
        if u32_at(b, local)? != LOCAL {
            return Err(format!("{name}: bad local header"));
        }
        let data = local + 30 + u16_at(b, local + 26)? + u16_at(b, local + 28)?;
        let raw = b.get(data..data + packed).ok_or("cut short")?;
        let bytes = match method {
            0 => raw.to_vec(),
            8 => {
                let mut v = Vec::with_capacity(size);
                flate2::read::DeflateDecoder::new(raw)
                    .read_to_end(&mut v)
                    .map_err(|e| format!("{name}: {e}"))?;
                v
            }
            m => return Err(format!("{name}: compression method {m}")),
        };
        if bytes.len() != size || crc32fast::hash(&bytes) != crc {
            return Err(format!("{name}: damaged (size or CRC)"));
        }
        out.push((name, bytes));
    }
    Ok(out)
}

/// A shapefile's polylines as (lat, lon) points, in record order; None for
/// a null shape. Parts are joined in order.
pub fn read_shp(b: &[u8]) -> Result<Lines, String> {
    let be = |i: usize| -> Result<usize, String> {
        b.get(i..i + 4)
            .map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]]) as usize)
            .ok_or_else(|| "cut short".to_string())
    };
    if be(0)? != 9994 {
        return Err("not a shapefile".into());
    }
    let mut out = Vec::new();
    let mut p = 100;
    while p + 8 <= b.len() {
        let len = be(p + 4)? * 2;
        let c = p + 8;
        p = c + len;
        let shape = i32_at(b, c)?;
        match shape {
            0 => out.push(None),
            // PolyLine, and its Z and M forms (the same XY layout first).
            3 | 13 | 23 => {
                let parts = usize::try_from(i32_at(b, c + 36)?).map_err(|_| "bad part count")?;
                let points = usize::try_from(i32_at(b, c + 40)?).map_err(|_| "bad point count")?;
                let xy = c + 44 + 4 * parts;
                let mut line = Vec::with_capacity(points);
                for k in 0..points {
                    let x = f64_at(b, xy + 16 * k)?;
                    let y = f64_at(b, xy + 16 * k + 8)?;
                    line.push((y, x));
                }
                out.push(Some(line));
            }
            s => return Err(format!("shape type {s}, not a polyline")),
        }
    }
    Ok(out)
}

/// A dBASE table's records, as text.
pub struct Records {
    names: Vec<String>,
    rows: Vec<Vec<String>>,
}

impl Records {
    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    /// Record `i`'s field `name`, trimmed.
    pub fn get(&self, i: usize, name: &str) -> Option<&str> {
        let f = self.names.iter().position(|n| n == name)?;
        self.rows.get(i)?.get(f).map(String::as_str)
    }
}

/// A dBASE III table (UTF-8 text, as the `.cpg` says), deleted records
/// kept as empty rows so they stay in step with the shapes.
pub fn read_dbf(b: &[u8]) -> Result<Records, String> {
    let n = u32_at(b, 4)? as usize;
    let header = u16_at(b, 8)?;
    let size = u16_at(b, 10)?;
    let mut fields = Vec::new();
    let mut p = 32;
    while *b.get(p).ok_or("cut short")? != 0x0d {
        let d = b.get(p..p + 32).ok_or("cut short")?;
        let name = String::from_utf8_lossy(&d[..11])
            .trim_end_matches('\0')
            .to_string();
        fields.push((name, usize::from(d[16])));
        p += 32;
    }
    let mut rows = Vec::with_capacity(n);
    for r in 0..n {
        let rec = b
            .get(header + r * size..header + (r + 1) * size)
            .ok_or("cut short")?;
        if rec[0] == b'*' {
            rows.push(vec![String::new(); fields.len()]);
            continue;
        }
        let mut row = Vec::with_capacity(fields.len());
        let mut at = 1;
        for (_, len) in &fields {
            let v = rec.get(at..at + len).ok_or("record cut short")?;
            row.push(String::from_utf8_lossy(v).trim().to_string());
            at += len;
        }
        rows.push(row);
    }
    Ok(Records {
        names: fields.into_iter().map(|(n, _)| n).collect(),
        rows,
    })
}

/// "US Census Bureau TIGER/Line 2026", from a file named `tl_2026_…`.
pub fn source_of(path: &Path) -> String {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    match name.strip_prefix("tl_").and_then(|r| r.get(..4)) {
        Some(y) if y.bytes().all(|b| b.is_ascii_digit()) => {
            format!("US Census Bureau TIGER/Line {y}")
        }
        _ => "US Census Bureau TIGER/Line".to_string(),
    }
}

/// Made-up ADDRFEAT files for tests (here and in `tests/build.rs`): a zip of
/// a shapefile and a dBASE table, built in memory.
#[doc(hidden)]
pub mod fixture {

    /// A dBASE table with these character fields and rows.
    pub fn dbf(fields: &[(&str, u8)], rows: &[Vec<&str>]) -> Vec<u8> {
        let size: usize = 1 + fields.iter().map(|f| usize::from(f.1)).sum::<usize>();
        let header = 32 + 32 * fields.len() + 1;
        let mut b = vec![0u8; 32];
        b[0] = 3;
        b[4..8].copy_from_slice(&(rows.len() as u32).to_le_bytes());
        b[8..10].copy_from_slice(&(header as u16).to_le_bytes());
        b[10..12].copy_from_slice(&(size as u16).to_le_bytes());
        for (name, len) in fields {
            let mut d = [0u8; 32];
            d[..name.len()].copy_from_slice(name.as_bytes());
            d[11] = b'C';
            d[16] = *len;
            b.extend_from_slice(&d);
        }
        b.push(0x0d);
        for row in rows {
            b.push(b' ');
            for ((_, len), v) in fields.iter().zip(row) {
                let mut cell = v.as_bytes().to_vec();
                cell.resize(usize::from(*len), b' ');
                b.extend_from_slice(&cell);
            }
        }
        b.push(0x1a);
        b
    }

    /// A shapefile of these polylines ((lat, lon) points; None: null).
    pub fn shp(lines: &[Option<Vec<(f64, f64)>>]) -> Vec<u8> {
        let mut recs = Vec::new();
        for (i, l) in lines.iter().enumerate() {
            let mut c = Vec::new();
            match l {
                None => c.extend_from_slice(&0i32.to_le_bytes()),
                Some(pts) => {
                    c.extend_from_slice(&3i32.to_le_bytes());
                    c.extend_from_slice(&[0u8; 32]);
                    c.extend_from_slice(&1i32.to_le_bytes());
                    c.extend_from_slice(&(pts.len() as i32).to_le_bytes());
                    c.extend_from_slice(&0i32.to_le_bytes());
                    for (lat, lon) in pts {
                        c.extend_from_slice(&lon.to_le_bytes());
                        c.extend_from_slice(&lat.to_le_bytes());
                    }
                }
            }
            recs.extend_from_slice(&(i as u32 + 1).to_be_bytes());
            recs.extend_from_slice(&((c.len() / 2) as u32).to_be_bytes());
            recs.extend_from_slice(&c);
        }
        let mut b = vec![0u8; 100];
        b[0..4].copy_from_slice(&9994u32.to_be_bytes());
        b[24..28].copy_from_slice(&(((100 + recs.len()) / 2) as u32).to_be_bytes());
        b[28..32].copy_from_slice(&1000u32.to_le_bytes());
        b[32..36].copy_from_slice(&3u32.to_le_bytes());
        b.extend_from_slice(&recs);
        b
    }

    /// A zip of these files, the first stored and the rest deflated.
    pub fn zip(files: &[(&str, &[u8])]) -> Vec<u8> {
        use std::io::Write;
        let mut b = Vec::new();
        let mut central = Vec::new();
        for (k, (name, data)) in files.iter().enumerate() {
            let (method, packed) = if k == 0 {
                (0u16, data.to_vec())
            } else {
                let mut e =
                    flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::default());
                // Writing to a Vec doesn't fail.
                let _ = e.write_all(data);
                (8u16, e.finish().unwrap_or_default())
            };
            let crc = crc32fast::hash(data);
            let offset = b.len() as u32;
            b.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
            b.extend_from_slice(&[20, 0, 0, 0]);
            b.extend_from_slice(&method.to_le_bytes());
            b.extend_from_slice(&[0; 4]);
            b.extend_from_slice(&crc.to_le_bytes());
            b.extend_from_slice(&(packed.len() as u32).to_le_bytes());
            b.extend_from_slice(&(data.len() as u32).to_le_bytes());
            b.extend_from_slice(&(name.len() as u16).to_le_bytes());
            b.extend_from_slice(&0u16.to_le_bytes());
            b.extend_from_slice(name.as_bytes());
            b.extend_from_slice(&packed);
            central.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
            central.extend_from_slice(&[20, 0, 20, 0, 0, 0]);
            central.extend_from_slice(&method.to_le_bytes());
            central.extend_from_slice(&[0; 4]);
            central.extend_from_slice(&crc.to_le_bytes());
            central.extend_from_slice(&(packed.len() as u32).to_le_bytes());
            central.extend_from_slice(&(data.len() as u32).to_le_bytes());
            central.extend_from_slice(&(name.len() as u16).to_le_bytes());
            central.extend_from_slice(&[0; 12]);
            central.extend_from_slice(&offset.to_le_bytes());
            central.extend_from_slice(name.as_bytes());
        }
        let cd = b.len() as u32;
        b.extend_from_slice(&central);
        b.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
        b.extend_from_slice(&[0; 4]);
        b.extend_from_slice(&(files.len() as u16).to_le_bytes());
        b.extend_from_slice(&(files.len() as u16).to_le_bytes());
        b.extend_from_slice(&(central.len() as u32).to_le_bytes());
        b.extend_from_slice(&cd.to_le_bytes());
        b.extend_from_slice(&0u16.to_le_bytes());
        b
    }

    pub const FIELDS: &[(&str, u8)] = &[
        ("TLID", 10),
        ("FULLNAME", 100),
        ("LFROMHN", 12),
        ("LTOHN", 12),
        ("RFROMHN", 12),
        ("RTOHN", 12),
        ("ZIPL", 5),
        ("ZIPR", 5),
        ("PARITYL", 1),
        ("PARITYR", 1),
    ];

    /// An ADDRFEAT-like zip of these rows (FIELDS order after TLID) and lines.
    pub fn addrfeat(rows: &[Vec<&str>], lines: &[Option<Vec<(f64, f64)>>]) -> Vec<u8> {
        let rows: Vec<Vec<&str>> = rows
            .iter()
            .enumerate()
            .map(|(i, r)| {
                let mut v = vec![if i % 2 == 0 { "1" } else { "2" }];
                v.extend(r.iter().copied());
                v
            })
            .collect();
        zip(&[
            ("tl_2099_99001_addrfeat.cpg", b"UTF-8"),
            ("tl_2099_99001_addrfeat.dbf", &dbf(FIELDS, &rows)),
            ("tl_2099_99001_addrfeat.shp", &shp(lines)),
        ])
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    //! Made-up files: streets that don't exist, in the Gulf of Mexico.
    use super::fixture::*;
    use super::*;

    #[test]
    fn reads_a_county_file() {
        let dir = std::env::temp_dir().join(format!("f250-tiger-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("tl_2099_99001_addrfeat.zip");
        let line = vec![(26.0, -90.0), (26.0, -89.99)];
        std::fs::write(
            &path,
            addrfeat(
                &[
                    // Both sides.
                    vec![
                        "Imaginary Rd",
                        "101",
                        "199",
                        "100",
                        "198",
                        "99001",
                        "99001",
                        "O",
                        "E",
                    ],
                    // Reversed, one side, no parity code.
                    vec!["Imaginary Rd", "", "", "298", "200", "", "99002", "", ""],
                    // Hyphenated and grid numbers: left out.
                    vec![
                        "Dream St", "10-01", "10-99", "S1W1", "S1W99", "99001", "99001", "O", "E",
                    ],
                    // No name; no ranges.
                    vec!["", "1", "9", "", "", "99001", "", "O", ""],
                    vec!["Nowhere Ln", "", "", "", "", "", "", "", ""],
                    // Outside the box.
                    vec!["Far Rd", "1", "9", "", "", "", "", "O", ""],
                ],
                &[
                    Some(line.clone()),
                    Some(line.clone()),
                    Some(line.clone()),
                    Some(line.clone()),
                    Some(line.clone()),
                    Some(vec![(40.0, -100.0), (40.0, -100.1)]),
                ],
            ),
        )
        .unwrap();
        let (edges, n) = read_zip(&path, Some((-95.0, 20.0, -85.0, 30.0))).unwrap();
        assert_eq!(
            n,
            Read1 {
                kept: 2,
                odd_numbers: 2,
                dropped: 4
            }
        );
        assert_eq!(edges[0].name, "Imaginary Rd");
        assert_eq!(edges[0].edge.line, line);
        let l = edges[0].edge.left.clone().unwrap();
        assert_eq!(
            (l.from, l.to, l.parity, l.zip),
            (101, 199, Parity::Odd, Some(99001))
        );
        let r = edges[1].edge.right.clone().unwrap();
        assert_eq!(
            (r.from, r.to, r.parity, r.zip),
            (298, 200, Parity::Even, Some(99002))
        );
        assert_eq!(edges[1].edge.left, None);
        // Without the box, Far Rd too.
        assert_eq!(read_zip(&path, None).unwrap().1.kept, 3);
        assert_eq!(source_of(&path), "US Census Bureau TIGER/Line 2099");

        // Damaged: one byte changed in the deflated table, or cut short.
        let good = std::fs::read(&path).unwrap();
        let name = b"addrfeat.dbf";
        let k = good.windows(name.len()).position(|w| w == name).unwrap() + name.len() + 8;
        let mut bad = good.clone();
        bad[k] ^= 0x55;
        std::fs::write(&path, &bad).unwrap();
        let err = read_zip(&path, None).unwrap_err();
        assert!(err.contains("tl_2099_99001_addrfeat"), "{err}");
        std::fs::write(&path, &good[..good.len() - 30]).unwrap();
        assert!(read_zip(&path, None).unwrap_err().contains("not a zip"));
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn null_shapes_and_deleted_records_stay_in_step() {
        let lines = read_shp(&shp(&[None, Some(vec![(1.0, 2.0), (1.5, 2.5)])])).unwrap();
        assert_eq!(lines, vec![None, Some(vec![(1.0, 2.0), (1.5, 2.5)])]);
        let mut d = dbf(&[("A", 3)], &[vec!["x"], vec!["yz"]]);
        let header = 32 + 32 + 1;
        d[header] = b'*';
        let r = read_dbf(&d).unwrap();
        assert_eq!(r.len(), 2);
        assert_eq!(r.get(0, "A"), Some(""));
        assert_eq!(r.get(1, "A"), Some("yz"));
        assert_eq!(r.get(1, "B"), None);
        assert!(read_shp(b"not a shapefile at all, but long enough to have a header").is_err());
        assert!(unzip(b"PK nonsense").is_err());
    }

    #[test]
    fn numbers_and_zips() {
        assert_eq!(plain("4400"), Some(4400));
        assert_eq!(plain("0"), Some(0));
        assert_eq!(plain("10-09"), None);
        assert_eq!(plain("S110W14498"), None);
        assert_eq!(plain(""), None);
        assert_eq!(plain("1234567890"), None);
        assert_eq!(zip5("00501"), Some(501));
        assert_eq!(zip5("9900"), None);
    }
}
