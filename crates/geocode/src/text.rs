//! Words, as both the index and the search see them.
//!
//! A name is lowercased, Latin accents are dropped ("Cañon" → "canon"),
//! apostrophes vanish ("O'Neil" → "oneil") and anything else that isn't a
//! letter or a digit splits words. OpenStreetMap spells US street names out
//! ("North Main Street") while people type "n main st", so the index also
//! holds each word's other form from [`SYNONYMS`]: the search needs no
//! rewriting of its own and the table lives in one place.

/// Each pair is one word's long and short form. A word may be in more than
/// one pair ("st": street and saint).
pub const SYNONYMS: &[(&str, &str)] = &[
    ("street", "st"),
    ("saint", "st"),
    ("avenue", "ave"),
    ("avenue", "av"),
    ("road", "rd"),
    ("drive", "dr"),
    ("boulevard", "blvd"),
    ("lane", "ln"),
    ("court", "ct"),
    ("place", "pl"),
    ("circle", "cir"),
    ("terrace", "ter"),
    ("parkway", "pkwy"),
    ("highway", "hwy"),
    ("expressway", "expy"),
    ("freeway", "fwy"),
    ("trail", "trl"),
    ("square", "sq"),
    ("center", "ctr"),
    ("junction", "jct"),
    ("heights", "hts"),
    ("crossing", "xing"),
    ("point", "pt"),
    ("route", "rte"),
    ("mount", "mt"),
    ("fort", "ft"),
    ("north", "n"),
    ("south", "s"),
    ("east", "e"),
    ("west", "w"),
    ("northeast", "ne"),
    ("northwest", "nw"),
    ("southeast", "se"),
    ("southwest", "sw"),
    ("first", "1st"),
    ("second", "2nd"),
    ("third", "3rd"),
    ("fourth", "4th"),
    ("fifth", "5th"),
    ("sixth", "6th"),
    ("seventh", "7th"),
    ("eighth", "8th"),
    ("ninth", "9th"),
    ("tenth", "10th"),
];

/// The words of `text`, in order.
pub fn words(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut word = String::new();
    for c in text.chars() {
        if c == '\'' || c == '\u{2019}' {
            continue; // O'Neil, Casey’s
        }
        let mut pushed = false;
        for l in c.to_lowercase() {
            let l = fold(l);
            if l.is_alphanumeric() {
                word.push(l);
                pushed = true;
            }
        }
        if !pushed && !word.is_empty() {
            out.push(std::mem::take(&mut word));
        }
    }
    if !word.is_empty() {
        out.push(word);
    }
    out
}

/// The other forms of `word` (none for most words).
pub fn synonyms(word: &str) -> impl Iterator<Item = &'static str> + '_ {
    SYNONYMS.iter().filter_map(move |&(long, short)| {
        if long == word {
            Some(short)
        } else if short == word {
            Some(long)
        } else {
            None
        }
    })
}

/// The words of `text` followed by their other forms, each once: what the
/// index holds for it.
pub fn index_terms(text: &str) -> Vec<String> {
    let base = words(text);
    let mut out = base.clone();
    for w in &base {
        for s in synonyms(w) {
            if !out.iter().any(|o| o == s) {
                out.push(s.to_string());
            }
        }
    }
    out
}

/// A house number's searchable form: its first word, if that starts with a
/// digit ("123", "123a"; "123 1/2" → "123"). None for "Unit B" or "".
pub fn house_number(text: &str) -> Option<String> {
    let first = words(text).into_iter().next()?;
    first
        .chars()
        .next()
        .filter(char::is_ascii_digit)
        .map(|_| first)
}

/// Whether a query word looks like a house number: digits, optionally a
/// letter or two after them ("123", "12b"), but not an ordinal ("3rd").
pub fn looks_like_house_number(word: &str) -> bool {
    let digits = word.chars().take_while(char::is_ascii_digit).count();
    let rest = &word[digits..];
    digits > 0
        && rest.len() <= 2
        && rest.chars().all(|c| c.is_ascii_lowercase())
        && !matches!(rest, "st" | "nd" | "rd" | "th")
}

/// Latin letters with accents, as their base letter. Other scripts are kept.
fn fold(c: char) -> char {
    match c {
        'à'..='å' | 'ā' | 'ă' | 'ą' => 'a',
        'ç' | 'ć' | 'ĉ' | 'ċ' | 'č' => 'c',
        'ď' | 'đ' => 'd',
        'è'..='ë' | 'ē' | 'ĕ' | 'ė' | 'ę' | 'ě' => 'e',
        'ĝ' | 'ğ' | 'ġ' | 'ģ' => 'g',
        'ĥ' | 'ħ' => 'h',
        'ì'..='ï' | 'ĩ' | 'ī' | 'ĭ' | 'į' | 'ı' => 'i',
        'ĵ' => 'j',
        'ķ' => 'k',
        'ĺ' | 'ļ' | 'ľ' | 'ŀ' | 'ł' => 'l',
        'ñ' | 'ń' | 'ņ' | 'ň' => 'n',
        'ò'..='ö' | 'ø' | 'ō' | 'ŏ' | 'ő' => 'o',
        'ŕ' | 'ŗ' | 'ř' => 'r',
        'ś' | 'ŝ' | 'ş' | 'š' => 's',
        'ţ' | 'ť' | 'ŧ' => 't',
        'ù'..='ü' | 'ũ' | 'ū' | 'ŭ' | 'ů' | 'ű' | 'ų' => 'u',
        'ŵ' => 'w',
        'ý' | 'ÿ' | 'ŷ' => 'y',
        'ź' | 'ż' | 'ž' => 'z',
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_split_lowercase_and_fold() {
        assert_eq!(words("North Main Street"), ["north", "main", "street"]);
        assert_eq!(words("O'Neil  Ave."), ["oneil", "ave"]);
        assert_eq!(
            words("Casey’s General Store"),
            ["caseys", "general", "store"]
        );
        assert_eq!(words("Cañon City"), ["canon", "city"]);
        assert_eq!(words("K-9 / US-36"), ["k", "9", "us", "36"]);
        assert_eq!(words("  "), Vec::<String>::new());
        assert_eq!(words("Ærø"), ["æro"]);
        assert_eq!(words("Αθήνα"), ["αθήνα"]); // other scripts: kept
    }

    #[test]
    fn index_terms_add_the_other_forms_once() {
        assert_eq!(
            index_terms("North Main Street"),
            ["north", "main", "street", "n", "st"]
        );
        assert_eq!(
            index_terms("N Main St"),
            ["n", "main", "st", "north", "street", "saint"]
        );
        assert_eq!(
            index_terms("W 3rd Ave"),
            ["w", "3rd", "ave", "west", "third", "avenue"]
        );
        assert_eq!(index_terms("Street Street"), ["street", "street", "st"]);
    }

    #[test]
    fn house_numbers() {
        assert_eq!(house_number("123").as_deref(), Some("123"));
        assert_eq!(house_number("123A").as_deref(), Some("123a"));
        assert_eq!(house_number("123 1/2").as_deref(), Some("123"));
        assert_eq!(house_number("Unit B"), None);
        assert_eq!(house_number(""), None);
        assert!(looks_like_house_number("123"));
        assert!(looks_like_house_number("12b"));
        assert!(!looks_like_house_number("3rd"));
        assert!(!looks_like_house_number("1st"));
        assert!(!looks_like_house_number("us"));
        assert!(!looks_like_house_number("12abc"));
    }
}
