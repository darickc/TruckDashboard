//! The Torque Pro custom-PID export (`exportedPIDs.csv`). **Untrusted
//! input**: every field is text until the importer has checked it.
//!
//! ```text
//! "Name", "ShortName", "ModeAndPID", "Equation", "Min Value", "Max Value", "Units", "Header", ...
//! "[FORD]Engine Oil Temp","EOT","0x221310","(((A*256)+B)/100)-40",0,300,"°C","Auto","","",1,0
//! ```

/// One row, as text, with its line number (1-based).
#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub line: usize,
    pub name: String,
    pub short_name: String,
    pub mode_and_pid: String,
    pub equation: String,
    pub min: String,
    pub max: String,
    pub units: String,
    pub header: String,
}

/// Splits one CSV line. Quoted fields may hold commas and `""` escapes;
/// unquoted fields are trimmed; spaces after a comma are skipped.
pub fn fields(line: &str) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    let mut chars = line.chars().peekable();
    loop {
        while chars.peek() == Some(&' ') {
            chars.next();
        }
        let mut field = String::new();
        if chars.peek() == Some(&'"') {
            chars.next();
            let mut closed = false;
            while let Some(c) = chars.next() {
                if c == '"' {
                    if chars.peek() == Some(&'"') {
                        chars.next();
                        field.push('"');
                    } else {
                        closed = true;
                        break;
                    }
                } else {
                    field.push(c);
                }
            }
            if !closed {
                return Err("a quoted field is not closed".into());
            }
            while chars.peek().is_some_and(|c| *c == ' ') {
                chars.next();
            }
            if chars.peek().is_some_and(|c| *c != ',') {
                return Err("text after a quoted field".into());
            }
        } else {
            while let Some(c) = chars.peek().copied() {
                if c == ',' {
                    break;
                }
                field.push(c);
                chars.next();
            }
            field = field.trim().to_owned();
        }
        out.push(field);
        if chars.next().is_none() {
            return Ok(out);
        }
    }
}

/// The columns the importer reads.
const COLUMNS: [&str; 8] = [
    "Name",
    "ShortName",
    "ModeAndPID",
    "Equation",
    "Min Value",
    "Max Value",
    "Units",
    "Header",
];

/// The export as read.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Export {
    pub rows: Vec<Row>,
    /// Lines that couldn't be read (line number, why); the rest still are.
    pub bad: Vec<(usize, String)>,
}

/// Reads the whole export.
pub fn read(text: &str) -> Result<Export, String> {
    let mut lines = text
        .lines()
        .enumerate()
        .map(|(i, l)| (i + 1, l.trim_start_matches('\u{feff}')))
        .filter(|(_, l)| !l.trim().is_empty());
    let (_, head) = lines.next().ok_or("the file is empty")?;
    let head = fields(head).map_err(|e| format!("header: {e}"))?;
    let mut col = [0usize; COLUMNS.len()];
    for (slot, name) in col.iter_mut().zip(COLUMNS) {
        *slot = head
            .iter()
            .position(|h| h == name)
            .ok_or_else(|| format!("no {name:?} column (is this a Torque export?)"))?;
    }
    let mut rows = Vec::new();
    let mut bad = Vec::new();
    for (n, line) in lines {
        match fields(line) {
            Ok(f) if f.len() == head.len() => {
                let g = |i: usize| f[col[i]].clone();
                rows.push(Row {
                    line: n,
                    name: g(0),
                    short_name: g(1),
                    mode_and_pid: g(2),
                    equation: g(3),
                    min: g(4),
                    max: g(5),
                    units: g(6),
                    header: g(7),
                });
            }
            Ok(f) => bad.push((
                n,
                format!("{} fields, the header has {}", f.len(), head.len()),
            )),
            Err(e) => bad.push((n, e)),
        }
    }
    Ok(Export { rows, bad })
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn splits_quoted_and_bare_fields() {
        assert_eq!(
            fields(r#""a, b", "c""d",3, 4.5 ,"""#).unwrap(),
            ["a, b", "c\"d", "3", "4.5", ""]
        );
        assert!(fields(r#""open"#).is_err());
        assert!(fields(r#""a"b,c"#).is_err());
    }

    #[test]
    fn reads_rows_by_column_name_and_reports_bad_lines() {
        let text = "\u{feff}\"Name\", \"ShortName\", \"ModeAndPID\", \"Equation\", \"Min Value\", \"Max Value\", \"Units\", \"Header\", \"x\"\n\
                    \"[FORD]Engine Oil Temp\",\"EOT\",\"0x221310\",\"(((A*256)+B)/100)-40\",0,300,\"°C\",\"Auto\",1\n\
                    \n\
                    \"short\",\"row\"\n";
        let Export { rows, bad } = read(text).unwrap();
        assert_eq!(rows.len(), 1);
        let r = &rows[0];
        assert_eq!((r.line, r.name.as_str()), (2, "[FORD]Engine Oil Temp"));
        assert_eq!(r.mode_and_pid, "0x221310");
        assert_eq!((r.min.as_str(), r.max.as_str()), ("0", "300"));
        assert_eq!((r.units.as_str(), r.header.as_str()), ("°C", "Auto"));
        assert_eq!(bad, [(4, "2 fields, the header has 9".to_string())]);
        assert!(read("").is_err());
        assert!(read("\"Name\"\n").unwrap_err().contains("ShortName"));
    }
}
