//! `search-index`: navigation's offline search index (ADR-0038).
//!
//!   search-index build --pbf kansas-261111.osm.pbf --region Kansas --out build/search/search.sqlite
//!   search-index build --pbf ... --tiger-list counties.txt --tiger-bbox=-124.85,24.4,-66.88,49.38 ...
//!   search-index info build/search/search.sqlite
//!   search-index query build/search/search.sqlite "120 n main st" --near 38.5,-97.5

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Instant;

use clap::{Parser, Subcommand};
use geocode::search::{Index, Match};
use search_index::builder::{self, Options};

#[derive(Parser)]
#[command(about = "Navigation's offline search index from OpenStreetMap extracts (ADR-0038)")]
struct Args {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Build an index from one or more .osm.pbf extracts.
    Build {
        #[arg(long, required = true, value_name = "FILE")]
        pbf: Vec<PathBuf>,
        #[arg(long, value_name = "FILE")]
        out: PathBuf,
        /// What it covers, shown on the screen (repeatable): "Kansas".
        #[arg(long, value_name = "NAME")]
        region: Vec<String>,
        /// The OSM data's date (YYYY-MM-DD); else the extract's own.
        #[arg(long, value_name = "DATE")]
        data_date: Option<String>,
        /// State boundaries, GeoJSON lines from `osmium export`: each result
        /// then names its state.
        #[arg(long, value_name = "FILE")]
        states: Option<PathBuf>,
        /// A US Census TIGER/Line ADDRFEAT county zip (repeatable): its
        /// address ranges place house numbers OSM lacks (ADR-0041).
        #[arg(long, value_name = "ZIP")]
        tiger: Vec<PathBuf>,
        /// A file listing ADDRFEAT zips, one path per line.
        #[arg(long, value_name = "FILE")]
        tiger_list: Option<PathBuf>,
        /// Keep only ranges starting in this box: W,S,E,N.
        #[arg(long, value_name = "W,S,E,N", allow_hyphen_values = true)]
        tiger_bbox: Option<String>,
    },
    /// What an index covers.
    Info { file: PathBuf },
    /// Search an index, as navigation does.
    Query {
        file: PathBuf,
        text: String,
        /// Rank from here: LAT,LON.
        #[arg(long, value_name = "LAT,LON", allow_hyphen_values = true)]
        near: Option<String>,
        #[arg(long, default_value_t = 8)]
        limit: usize,
        /// Search this many times and print each time: the first is cold.
        #[arg(long, default_value_t = 1)]
        repeat: u32,
    },
}

fn main() -> ExitCode {
    match run(Args::parse().cmd) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("search-index: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run(cmd: Cmd) -> Result<(), String> {
    match cmd {
        Cmd::Build {
            pbf,
            out,
            region,
            data_date,
            states,
            mut tiger,
            tiger_list,
            tiger_bbox,
        } => {
            let start = Instant::now();
            if let Some(list) = tiger_list {
                let text = std::fs::read_to_string(&list)
                    .map_err(|e| format!("{}: {e}", list.display()))?;
                tiger.extend(
                    text.lines()
                        .map(str::trim)
                        .filter(|l| !l.is_empty())
                        .map(PathBuf::from),
                );
            }
            let tiger_bbox = tiger_bbox
                .map(|b| {
                    let v: Vec<f64> = b
                        .split(',')
                        .map(|x| x.trim().parse::<f64>())
                        .collect::<Result<_, _>>()
                        .map_err(|e| format!("--tiger-bbox {b}: {e}"))?;
                    match v[..] {
                        [w, s, e, n] if w < e && s < n => Ok((w, s, e, n)),
                        _ => Err(format!("--tiger-bbox {b}: give W,S,E,N")),
                    }
                })
                .transpose()?;
            let s = builder::build(&Options {
                pbfs: pbf,
                out: out.clone(),
                regions: region,
                data_date,
                states,
                tiger,
                tiger_bbox,
                verbose: true,
            })?;
            let size = std::fs::metadata(&out).map(|m| m.len()).unwrap_or(0);
            let c = s.counts;
            println!(
                "{}: {} addresses, {} streets, {} towns, {} named places, {} ZIP codes; {:.0} MB; OSM data {}; {:.0} s{}",
                out.display(),
                c.addresses,
                c.streets,
                c.localities,
                c.pois,
                c.postcodes,
                size as f64 / 1e6,
                s.data_date.as_deref().unwrap_or("of unknown date"),
                start.elapsed().as_secs_f64(),
                if s.missing_nodes > 0 {
                    format!(
                        " ({} ways cut at the extract's edge left out)",
                        s.missing_nodes
                    )
                } else {
                    String::new()
                }
            );
            if c.range_streets > 0 {
                println!(
                    "US Census address ranges: {} sides on {} streets ({} pieces of street read; {} sides of hyphenated or grid numbers and {} pieces without a name or range left out)",
                    c.ranges, c.range_streets, s.tiger.kept, s.tiger.odd_numbers, s.tiger.dropped
                );
            }
            Ok(())
        }
        Cmd::Info { file } => {
            let ix = Index::open(&file)?;
            let i = &ix.info;
            println!("regions:   {}", i.regions.join(", "));
            println!("data date: {}", i.data_date.as_deref().unwrap_or("unknown"));
            println!("built:     {}", i.built_at);
            println!(
                "rows:      {} addresses, {} streets, {} towns, {} named places, {} ZIP codes",
                i.counts.addresses,
                i.counts.streets,
                i.counts.localities,
                i.counts.pois,
                i.counts.postcodes
            );
            if let Some(src) = &i.ranges_source {
                println!(
                    "ranges:    {} address-range sides on {} streets ({src})",
                    i.counts.ranges, i.counts.range_streets
                );
            }
            Ok(())
        }
        Cmd::Query {
            file,
            text,
            near,
            limit,
            repeat,
        } => {
            let ix = Index::open(&file)?;
            let near = near
                .map(|n| {
                    let (a, b) = n.split_once(',').ok_or("--near LAT,LON")?;
                    Ok::<_, String>((
                        a.trim().parse::<f64>().map_err(|e| e.to_string())?,
                        b.trim().parse::<f64>().map_err(|e| e.to_string())?,
                    ))
                })
                .transpose()?;
            let mut hits = Vec::new();
            let mut times = Vec::new();
            for _ in 0..repeat.max(1) {
                let start = Instant::now();
                hits = ix.search(&text, near, limit).map_err(|e| e.to_string())?;
                times.push(format!("{:.1}", start.elapsed().as_secs_f64() * 1000.0));
            }
            let ms = times.join(", ");
            for h in &hits {
                let what = match h.kind {
                    Match::Address => "address",
                    Match::Street if h.house_number_missing => "street (no such number)",
                    Match::Street => "street",
                    Match::Locality => "town",
                    Match::Place => "place",
                    Match::Estimated => "estimated (US Census)",
                };
                println!(
                    "{:7.2}  {:<24} {} | {}{}{}",
                    h.score,
                    what,
                    h.title,
                    h.subtitle,
                    h.distance_m
                        .map(|d| format!("  {:.1} km", d / 1000.0))
                        .unwrap_or_default(),
                    if h.unmatched.is_empty() {
                        String::new()
                    } else {
                        format!("  (not matched: {})", h.unmatched.join(" "))
                    }
                );
            }
            println!("{} results in {ms} ms", hits.len());
            Ok(())
        }
    }
}
