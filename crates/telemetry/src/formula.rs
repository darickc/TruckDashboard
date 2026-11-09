//! The safe formula grammar of ADR-0006.
//!
//! ```text
//! expr    := term (('+' | '-') term)*
//! term    := unary (('*' | '/') unary)*
//! unary   := '-' unary | primary
//! primary := number | byte | signal | call | '(' expr ')'
//! number  := decimal (e.g. 0.03625) | hex (e.g. 0x7F)
//! byte    := 'A'..'Z'            payload byte after the stripped echo, 0–255
//! signal  := snake_case id       another signal's canonical value
//! call    := ('signed' | 'bit' | 'min' | 'max') '(' expr (',' expr)* ')'
//! ```
//!
//! There is no `eval`, no loops and no user functions. Input is bounded in
//! length and nesting depth, so an untrusted CSV can't exhaust the stack.
//! Evaluation never panics; it returns [`EvalError`] for division by zero, a
//! missing payload byte, an unknown reference, a function argument outside
//! its domain, or a non-finite result.
//!
//! [`from_torque`] translates Torque Pro equations into this grammar.

use std::collections::BTreeSet;
use std::fmt;

/// Longest formula accepted, in bytes.
pub const MAX_LEN: usize = 512;
/// Deepest nesting of parentheses, unary minus and calls.
pub const MAX_DEPTH: usize = 32;

/// A built-in function.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Function {
    /// `signed(x)`: an 8-bit value (0–255) read as two's complement
    /// (−128–127), as Torque's `signed(A)` does.
    Signed,
    /// `bit(x, n)`: bit `n` (0 = least significant) of the non-negative
    /// integer `x`, as 0 or 1.
    Bit,
    Min,
    Max,
}

impl Function {
    fn from_name(name: &str) -> Option<Self> {
        match name {
            "signed" => Some(Function::Signed),
            "bit" => Some(Function::Bit),
            "min" => Some(Function::Min),
            "max" => Some(Function::Max),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Function::Signed => "signed",
            Function::Bit => "bit",
            Function::Min => "min",
            Function::Max => "max",
        }
    }

    fn arity(self) -> usize {
        match self {
            Function::Signed => 1,
            Function::Bit | Function::Min | Function::Max => 2,
        }
    }
}

/// Names that can't be signal ids because they are functions.
pub const RESERVED_WORDS: [&str; 4] = ["signed", "bit", "min", "max"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
}

impl BinaryOp {
    pub fn symbol(self) -> char {
        match self {
            BinaryOp::Add => '+',
            BinaryOp::Sub => '-',
            BinaryOp::Mul => '*',
            BinaryOp::Div => '/',
        }
    }
}

/// Parsed expression tree.
#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Number(f64),
    /// Payload byte; 0 is `A`.
    Byte(u8),
    /// Another signal, by id.
    Signal(String),
    Neg(Box<Expr>),
    Binary(BinaryOp, Box<Expr>, Box<Expr>),
    Call(Function, Vec<Expr>),
}

/// A parsed, validated formula.
#[derive(Debug, Clone, PartialEq)]
pub struct Formula {
    source: String,
    expr: Expr,
}

/// Why a formula didn't parse.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ParseErrorKind {
    #[error("empty formula")]
    Empty,
    #[error("formula longer than {MAX_LEN} bytes")]
    TooLong,
    #[error("nested deeper than {MAX_DEPTH} levels")]
    TooDeep,
    #[error("unexpected character {0:?}")]
    UnexpectedChar(char),
    #[error("malformed number {0:?}")]
    BadNumber(String),
    #[error("{0:?} is neither a byte variable (single letter A–Z) nor a snake_case signal id")]
    BadIdentifier(String),
    #[error("unknown function {0:?} (only signed, bit, min, max; no user functions)")]
    UnknownFunction(String),
    #[error("{0:?} is a function and must be called")]
    FunctionNotCalled(String),
    #[error("{function}() takes {expected} argument(s), got {found}")]
    Arity {
        function: &'static str,
        expected: usize,
        found: usize,
    },
    #[error("expected {expected}, found {found}")]
    Expected {
        expected: &'static str,
        found: String,
    },
}

/// A parse error and the byte offset in the source where it was found.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("at position {position}: {kind}")]
pub struct ParseError {
    pub position: usize,
    pub kind: ParseErrorKind,
}

/// Why a formula could not be evaluated.
#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum EvalError {
    #[error("division by zero")]
    DivisionByZero,
    #[error("payload byte {variable} is missing (payload has {available} byte(s))")]
    MissingByte { variable: char, available: usize },
    #[error("signal {0:?} has no current value")]
    UnknownReference(String),
    #[error("{function}() argument {value} is outside its domain ({domain})")]
    Domain {
        function: &'static str,
        value: f64,
        domain: &'static str,
    },
    #[error("result is not a finite number")]
    NonFinite,
}

impl Formula {
    /// Parses `source`. Errors carry the byte position.
    pub fn parse(source: &str) -> Result<Formula, ParseError> {
        if source.len() > MAX_LEN {
            return Err(ParseError {
                position: MAX_LEN,
                kind: ParseErrorKind::TooLong,
            });
        }
        let tokens = lex(source)?;
        let mut parser = Parser {
            tokens: &tokens,
            pos: 0,
            depth: 0,
            end: source.len(),
        };
        if tokens.is_empty() {
            return Err(ParseError {
                position: 0,
                kind: ParseErrorKind::Empty,
            });
        }
        let expr = parser.expr()?;
        if let Some(tok) = parser.peek() {
            return Err(ParseError {
                position: tok.position,
                kind: ParseErrorKind::Expected {
                    expected: "an operator or end of formula",
                    found: tok.kind.describe(),
                },
            });
        }
        Ok(Formula {
            source: source.to_owned(),
            expr,
        })
    }

    /// The text this formula was parsed from.
    pub fn source(&self) -> &str {
        &self.source
    }

    pub fn expr(&self) -> &Expr {
        &self.expr
    }

    /// Payload bytes the formula needs: highest byte variable index + 1
    /// (`B` → 2), or 0 when it uses none.
    pub fn bytes_required(&self) -> usize {
        fn walk(e: &Expr) -> usize {
            match e {
                Expr::Byte(i) => usize::from(*i) + 1,
                Expr::Number(_) | Expr::Signal(_) => 0,
                Expr::Neg(x) => walk(x),
                Expr::Binary(_, a, b) => walk(a).max(walk(b)),
                Expr::Call(_, args) => args.iter().map(walk).max().unwrap_or(0),
            }
        }
        walk(&self.expr)
    }

    /// Ids of the other signals the formula refers to.
    pub fn references(&self) -> BTreeSet<String> {
        fn walk(e: &Expr, out: &mut BTreeSet<String>) {
            match e {
                Expr::Signal(id) => {
                    out.insert(id.clone());
                }
                Expr::Number(_) | Expr::Byte(_) => {}
                Expr::Neg(x) => walk(x, out),
                Expr::Binary(_, a, b) => {
                    walk(a, out);
                    walk(b, out);
                }
                Expr::Call(_, args) => args.iter().for_each(|a| walk(a, out)),
            }
        }
        let mut out = BTreeSet::new();
        walk(&self.expr, &mut out);
        out
    }

    /// Evaluates against `payload` (the bytes after the positive-response
    /// echo). `signal` returns the current canonical value of a referenced
    /// signal, or `None` when it has none.
    pub fn eval(
        &self,
        payload: &[u8],
        signal: &dyn Fn(&str) -> Option<f64>,
    ) -> Result<f64, EvalError> {
        let v = eval(&self.expr, payload, signal)?;
        if v.is_finite() {
            Ok(v)
        } else {
            Err(EvalError::NonFinite)
        }
    }

    /// [`Formula::eval`] for formulas without signal references.
    pub fn eval_payload(&self, payload: &[u8]) -> Result<f64, EvalError> {
        self.eval(payload, &|_| None)
    }
}

impl fmt::Display for Formula {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.source)
    }
}

fn eval(e: &Expr, payload: &[u8], signal: &dyn Fn(&str) -> Option<f64>) -> Result<f64, EvalError> {
    Ok(match e {
        Expr::Number(n) => *n,
        Expr::Byte(i) => match payload.get(usize::from(*i)) {
            Some(b) => f64::from(*b),
            None => {
                return Err(EvalError::MissingByte {
                    variable: char::from(b'A' + *i),
                    available: payload.len(),
                });
            }
        },
        Expr::Signal(id) => signal(id).ok_or_else(|| EvalError::UnknownReference(id.clone()))?,
        Expr::Neg(x) => -eval(x, payload, signal)?,
        Expr::Binary(op, a, b) => {
            let a = eval(a, payload, signal)?;
            let b = eval(b, payload, signal)?;
            match op {
                BinaryOp::Add => a + b,
                BinaryOp::Sub => a - b,
                BinaryOp::Mul => a * b,
                BinaryOp::Div => {
                    if b == 0.0 {
                        return Err(EvalError::DivisionByZero);
                    }
                    a / b
                }
            }
        }
        Expr::Call(f, args) => {
            let mut values = [0.0_f64; 2];
            for (slot, arg) in values.iter_mut().zip(args) {
                *slot = eval(arg, payload, signal)?;
            }
            let [x, y] = values;
            match f {
                Function::Signed => {
                    if !(0.0..=255.0).contains(&x) || x.fract() != 0.0 {
                        return Err(EvalError::Domain {
                            function: "signed",
                            value: x,
                            domain: "an integer 0–255",
                        });
                    }
                    if x >= 128.0 { x - 256.0 } else { x }
                }
                Function::Bit => {
                    // Exact integers only: f64 represents every integer up to 2^53.
                    const LIMIT: f64 = 9_007_199_254_740_992.0;
                    if !(0.0..=LIMIT).contains(&x) || x.fract() != 0.0 {
                        return Err(EvalError::Domain {
                            function: "bit",
                            value: x,
                            domain: "an integer 0–2^53",
                        });
                    }
                    if !(0.0..=53.0).contains(&y) || y.fract() != 0.0 {
                        return Err(EvalError::Domain {
                            function: "bit",
                            value: y,
                            domain: "a bit index 0–53",
                        });
                    }
                    // Both checked above: exact, in range, non-negative.
                    let (x, n) = (x as u64, y as u32);
                    ((x >> n) & 1) as f64
                }
                Function::Min => x.min(y),
                Function::Max => x.max(y),
            }
        }
    })
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
enum TokenKind {
    Number(f64),
    Ident(String),
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
    Comma,
}

impl TokenKind {
    fn describe(&self) -> String {
        match self {
            TokenKind::Number(n) => format!("number {n}"),
            TokenKind::Ident(s) => format!("{s:?}"),
            TokenKind::Plus => "'+'".into(),
            TokenKind::Minus => "'-'".into(),
            TokenKind::Star => "'*'".into(),
            TokenKind::Slash => "'/'".into(),
            TokenKind::LParen => "'('".into(),
            TokenKind::RParen => "')'".into(),
            TokenKind::Comma => "','".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
struct Token {
    kind: TokenKind,
    position: usize,
}

fn lex(src: &str) -> Result<Vec<Token>, ParseError> {
    let bytes = src.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        let start = i;
        let simple = match c {
            b' ' | b'\t' => {
                i += 1;
                continue;
            }
            b'+' => Some(TokenKind::Plus),
            b'-' => Some(TokenKind::Minus),
            b'*' => Some(TokenKind::Star),
            b'/' => Some(TokenKind::Slash),
            b'(' => Some(TokenKind::LParen),
            b')' => Some(TokenKind::RParen),
            b',' => Some(TokenKind::Comma),
            _ => None,
        };
        if let Some(kind) = simple {
            out.push(Token {
                kind,
                position: start,
            });
            i += 1;
            continue;
        }
        if c.is_ascii_digit() || c == b'.' {
            let is_hex = c == b'0' && matches!(bytes.get(i + 1), Some(b'x' | b'X'));
            if is_hex {
                i += 2;
                while i < bytes.len() && bytes[i].is_ascii_alphanumeric() {
                    i += 1;
                }
                let text = &src[start..i];
                let value = u64::from_str_radix(&text[2..], 16)
                    .ok()
                    .filter(|_| text.len() > 2 && text.len() <= 2 + 13)
                    .ok_or_else(|| ParseError {
                        position: start,
                        kind: ParseErrorKind::BadNumber(text.to_owned()),
                    })?;
                // At most 13 hex digits (< 2^52), so the conversion is exact.
                out.push(Token {
                    kind: TokenKind::Number(value as f64),
                    position: start,
                });
            } else {
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'.') {
                    i += 1;
                }
                let text = &src[start..i];
                let well_formed = text.bytes().all(|b| b.is_ascii_digit() || b == b'.')
                    && text.bytes().filter(|&b| b == b'.').count() <= 1
                    && text.bytes().any(|b| b.is_ascii_digit());
                let value = text
                    .parse::<f64>()
                    .ok()
                    .filter(|v| well_formed && v.is_finite())
                    .ok_or_else(|| ParseError {
                        position: start,
                        kind: ParseErrorKind::BadNumber(text.to_owned()),
                    })?;
                out.push(Token {
                    kind: TokenKind::Number(value),
                    position: start,
                });
            }
            continue;
        }
        if c.is_ascii_alphabetic() || c == b'_' {
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                i += 1;
            }
            out.push(Token {
                kind: TokenKind::Ident(src[start..i].to_owned()),
                position: start,
            });
            continue;
        }
        let ch = src[start..].chars().next().unwrap_or('\u{FFFD}');
        return Err(ParseError {
            position: start,
            kind: ParseErrorKind::UnexpectedChar(ch),
        });
    }
    Ok(out)
}

/// Whether `s` is a valid snake_case signal id: a lowercase letter, then
/// lowercase letters, digits and single underscores, not ending in `_`.
pub fn is_snake_case_id(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b[0].is_ascii_lowercase()
        && b.iter()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_')
        && !s.ends_with('_')
        && !s.contains("__")
}

// ---------------------------------------------------------------------------
// Parser (recursive descent, depth-limited)
// ---------------------------------------------------------------------------

struct Parser<'a> {
    tokens: &'a [Token],
    pos: usize,
    depth: usize,
    end: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos)
    }

    fn here(&self) -> usize {
        self.peek().map_or(self.end, |t| t.position)
    }

    fn found(&self) -> String {
        self.peek()
            .map_or_else(|| "end of formula".to_owned(), |t| t.kind.describe())
    }

    fn eat(&mut self, kind: &TokenKind) -> bool {
        if self.peek().is_some_and(|t| &t.kind == kind) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn expect(&mut self, kind: &TokenKind, expected: &'static str) -> Result<(), ParseError> {
        if self.eat(kind) {
            Ok(())
        } else {
            Err(ParseError {
                position: self.here(),
                kind: ParseErrorKind::Expected {
                    expected,
                    found: self.found(),
                },
            })
        }
    }

    fn enter(&mut self) -> Result<(), ParseError> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            return Err(ParseError {
                position: self.here(),
                kind: ParseErrorKind::TooDeep,
            });
        }
        Ok(())
    }

    fn expr(&mut self) -> Result<Expr, ParseError> {
        let mut lhs = self.term()?;
        loop {
            let op = if self.eat(&TokenKind::Plus) {
                BinaryOp::Add
            } else if self.eat(&TokenKind::Minus) {
                BinaryOp::Sub
            } else {
                return Ok(lhs);
            };
            let rhs = self.term()?;
            lhs = Expr::Binary(op, Box::new(lhs), Box::new(rhs));
        }
    }

    fn term(&mut self) -> Result<Expr, ParseError> {
        let mut lhs = self.unary()?;
        loop {
            let op = if self.eat(&TokenKind::Star) {
                BinaryOp::Mul
            } else if self.eat(&TokenKind::Slash) {
                BinaryOp::Div
            } else {
                return Ok(lhs);
            };
            let rhs = self.unary()?;
            lhs = Expr::Binary(op, Box::new(lhs), Box::new(rhs));
        }
    }

    fn unary(&mut self) -> Result<Expr, ParseError> {
        if self.eat(&TokenKind::Minus) {
            self.enter()?;
            let inner = self.unary()?;
            self.depth -= 1;
            return Ok(Expr::Neg(Box::new(inner)));
        }
        self.primary()
    }

    fn primary(&mut self) -> Result<Expr, ParseError> {
        let Some(tok) = self.peek().cloned() else {
            return Err(ParseError {
                position: self.end,
                kind: ParseErrorKind::Expected {
                    expected: "a number, byte, signal, call or '('",
                    found: "end of formula".into(),
                },
            });
        };
        match tok.kind {
            TokenKind::Number(n) => {
                self.pos += 1;
                Ok(Expr::Number(n))
            }
            TokenKind::LParen => {
                self.pos += 1;
                self.enter()?;
                let inner = self.expr()?;
                self.expect(&TokenKind::RParen, "')'")?;
                self.depth -= 1;
                Ok(inner)
            }
            TokenKind::Ident(name) => {
                self.pos += 1;
                self.identifier(name, tok.position)
            }
            other => Err(ParseError {
                position: tok.position,
                kind: ParseErrorKind::Expected {
                    expected: "a number, byte, signal, call or '('",
                    found: other.describe(),
                },
            }),
        }
    }

    fn identifier(&mut self, name: String, position: usize) -> Result<Expr, ParseError> {
        let called = self.peek().is_some_and(|t| t.kind == TokenKind::LParen);
        if called {
            let Some(function) = Function::from_name(&name) else {
                return Err(ParseError {
                    position,
                    kind: ParseErrorKind::UnknownFunction(name),
                });
            };
            self.pos += 1; // '('
            self.enter()?;
            let mut args = Vec::new();
            if !self.eat(&TokenKind::RParen) {
                loop {
                    args.push(self.expr()?);
                    if self.eat(&TokenKind::Comma) {
                        continue;
                    }
                    self.expect(&TokenKind::RParen, "',' or ')'")?;
                    break;
                }
            }
            self.depth -= 1;
            if args.len() != function.arity() {
                return Err(ParseError {
                    position,
                    kind: ParseErrorKind::Arity {
                        function: function.name(),
                        expected: function.arity(),
                        found: args.len(),
                    },
                });
            }
            return Ok(Expr::Call(function, args));
        }
        if name.len() == 1 && name.as_bytes()[0].is_ascii_uppercase() {
            return Ok(Expr::Byte(name.as_bytes()[0] - b'A'));
        }
        if Function::from_name(&name).is_some() {
            return Err(ParseError {
                position,
                kind: ParseErrorKind::FunctionNotCalled(name),
            });
        }
        if is_snake_case_id(&name) {
            return Ok(Expr::Signal(name));
        }
        Err(ParseError {
            position,
            kind: ParseErrorKind::BadIdentifier(name),
        })
    }
}

// ---------------------------------------------------------------------------
// Torque Pro import
// ---------------------------------------------------------------------------

/// A Torque equation translated into this grammar.
#[derive(Debug, Clone, PartialEq)]
pub struct TorqueTranslation {
    pub formula: Formula,
    /// Things a reviewer must check before trusting the translation.
    pub caveats: Vec<String>,
}

/// Why a Torque equation could not be translated.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("cannot translate Torque equation at position {position}: {reason}")]
pub struct TorqueReject {
    pub position: usize,
    pub reason: String,
}

/// Translates a Torque Pro equation into the ADR-0006 grammar.
///
/// Handled: numbers, `A`–`Z`, `+ - * /`, parentheses, `signed(x)` in any
/// letter case, and `BARO()`, which becomes a reference to the `baro`
/// signal. Everything else (Torque's `{A:n}` bit syntax, `VAL{…}`, other
/// functions, `^`, comparisons, two-letter byte variables beyond `Z`) is
/// rejected with a reason rather than guessed at.
///
/// A translation is only syntactic. The result is still an
/// `IMPORTED_UNVERIFIED` formula.
pub fn from_torque(equation: &str) -> Result<TorqueTranslation, TorqueReject> {
    let reject = |position: usize, reason: String| TorqueReject { position, reason };
    let bytes = equation.as_bytes();
    let mut out = String::with_capacity(equation.len());
    let mut caveats = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        match c {
            b' ' | b'\t' | b'+' | b'-' | b'*' | b'/' | b'(' | b')' | b',' | b'.' => {
                out.push(char::from(c));
                i += 1;
            }
            b'0'..=b'9' => {
                out.push(char::from(c));
                i += 1;
            }
            b'{' => {
                return Err(reject(
                    i,
                    "Torque bit syntax {X:n} is not translated (its bit numbering is \
                     unconfirmed); hand-write it with bit(x, n)"
                        .into(),
                ));
            }
            b'^' | b'<' | b'>' | b'=' | b'&' | b'|' | b'%' | b'!' | b'?' | b':' => {
                return Err(reject(
                    i,
                    format!("operator {:?} is not in the grammar", char::from(c)),
                ));
            }
            _ if c.is_ascii_alphabetic() || c == b'_' => {
                let start = i;
                while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_') {
                    i += 1;
                }
                let word = &equation[start..i];
                let next_non_space = equation[i..].trim_start();
                let called = next_non_space.starts_with('(');
                if word.len() == 1 && word.as_bytes()[0].is_ascii_uppercase() {
                    out.push_str(word);
                } else if word.eq_ignore_ascii_case("signed") && called {
                    out.push_str("signed");
                } else if word.eq_ignore_ascii_case("baro") && called {
                    let after = next_non_space[1..].trim_start();
                    if !after.starts_with(')') {
                        return Err(reject(start, "BARO() takes no arguments".into()));
                    }
                    // Skip "(" … ")".
                    let consumed = equation.len() - after.len() + 1;
                    i = consumed;
                    out.push_str("baro");
                    caveats.push(
                        "BARO() became a reference to signal `baro`, which resolves in its \
                         canonical unit (kPa); check that the rest of the formula uses the \
                         same unit before trusting it"
                            .into(),
                    );
                } else if word.len() == 2 && word.bytes().all(|b| b.is_ascii_uppercase()) {
                    return Err(reject(
                        start,
                        format!("byte variable {word} is beyond Z; the grammar has A–Z only"),
                    ));
                } else if word.eq_ignore_ascii_case("val") {
                    return Err(reject(
                        start,
                        "VAL{…} refers to another Torque PID by name; map it to a registry \
                         signal id by hand"
                            .into(),
                    ));
                } else if called {
                    return Err(reject(
                        start,
                        format!("Torque function {word}() has no equivalent in the grammar"),
                    ));
                } else {
                    return Err(reject(start, format!("unknown identifier {word:?}")));
                }
            }
            _ => {
                let ch = equation[i..].chars().next().unwrap_or('\u{FFFD}');
                return Err(reject(i, format!("unexpected character {ch:?}")));
            }
        }
    }
    let formula = Formula::parse(&out).map_err(|e| TorqueReject {
        position: e.position,
        reason: format!("translated formula {out:?} does not parse: {}", e.kind),
    })?;
    Ok(TorqueTranslation { formula, caveats })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Formula {
        Formula::parse(s).expect(s)
    }

    fn eval(s: &str, payload: &[u8]) -> f64 {
        parse(s).eval_payload(payload).expect(s)
    }

    fn parse_err(s: &str) -> ParseError {
        match Formula::parse(s) {
            Ok(f) => panic!("{s:?} parsed as {:?}", f.expr()),
            Err(e) => e,
        }
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3", &[]), 7.0);
        assert_eq!(eval("(1 + 2) * 3", &[]), 9.0);
        assert_eq!(eval("10 - 4 - 3", &[]), 3.0);
        assert_eq!(eval("100 / 10 / 5", &[]), 2.0);
        assert_eq!(eval("A*100/128", &[64]), 50.0);
        assert_eq!(eval("2 * -3", &[]), -6.0);
        assert_eq!(eval("-A + 1", &[5]), -4.0);
        assert_eq!(eval("--A", &[5]), 5.0);
        assert_eq!(eval("-(A - 1)", &[5]), -4.0);
    }

    #[test]
    fn numbers_decimal_and_hex() {
        assert_eq!(eval("0x7F", &[]), 127.0);
        assert_eq!(eval("0XFF + 1", &[]), 256.0);
        assert_eq!(eval("0.03625 * 1000", &[]), 36.25);
        assert_eq!(eval(".5", &[]), 0.5);
        assert_eq!(eval("13.53", &[]), 13.53);
    }

    #[test]
    fn byte_variables_are_unsigned_payload_bytes() {
        assert_eq!(eval("A", &[0xFF]), 255.0);
        assert_eq!(eval("B", &[0, 0x80]), 128.0);
        assert_eq!(eval("Z", &[7; 26]), 7.0);
    }

    #[test]
    fn sae_vectors() {
        // Engine RPM captures from VERIFICATION_LOG.md 2026-08-09.
        assert_eq!(eval("((A*256)+B)/4", &[0x0A, 0xC4]), 689.0);
        assert_eq!(eval("((A*256)+B)/4", &[0x0A, 0xC2]), 688.5);
        assert_eq!(eval("((A*256)+B)/4", &[0x0A, 0xC3]), 688.75);
        // ECT A-40.
        assert_eq!(eval("A-40", &[0]), -40.0);
        assert_eq!(eval("A-40", &[130]), 90.0);
    }

    #[test]
    fn trans_temp_verified_capture() {
        // 7E9 62 16 74 04 13 → 1043 / 8 = 130.375 °F (VERIFICATION_LOG.md).
        assert_eq!(eval("((A*256)+B)/8", &[0x04, 0x13]), 130.375);
    }

    #[test]
    fn signed_is_8_bit_twos_complement() {
        assert_eq!(eval("signed(A)", &[0x00]), 0.0);
        assert_eq!(eval("signed(A)", &[0x7F]), 127.0);
        assert_eq!(eval("signed(A)", &[0x80]), -128.0);
        assert_eq!(eval("signed(A)", &[0xFF]), -1.0);
        // The Torque transmission-temp row (0x221E1C).
        let f = "(((signed(A)*256)+B)*(9/8)+320)/10";
        assert_eq!(
            eval(f, &[0xFF, 0x00]),
            ((-256.0) * 9.0 / 8.0 + 320.0) / 10.0
        );
        assert!(matches!(
            parse("signed(A*2)").eval_payload(&[200]),
            Err(EvalError::Domain {
                function: "signed",
                ..
            })
        ));
        assert!(matches!(
            parse("signed(A/2)").eval_payload(&[3]),
            Err(EvalError::Domain { .. })
        ));
    }

    #[test]
    fn bit_min_max() {
        assert_eq!(eval("bit(A, 0)", &[0b101]), 1.0);
        assert_eq!(eval("bit(A, 1)", &[0b101]), 0.0);
        assert_eq!(eval("bit(A, 7)", &[0x80]), 1.0);
        assert_eq!(eval("bit((A*256)+B, 8)", &[0x01, 0x00]), 1.0);
        assert_eq!(eval("min(A, B)", &[3, 9]), 3.0);
        assert_eq!(eval("max(A, B)", &[3, 9]), 9.0);
        assert_eq!(eval("max(min(A, 10), 5)", &[200]), 10.0);
        assert!(matches!(
            parse("bit(A, 54)").eval_payload(&[1]),
            Err(EvalError::Domain { .. })
        ));
        assert!(matches!(
            parse("bit(-A, 0)").eval_payload(&[1]),
            Err(EvalError::Domain { .. })
        ));
    }

    #[test]
    fn signal_references() {
        let f = parse("eot - ect");
        assert_eq!(
            f.references().into_iter().collect::<Vec<_>>(),
            ["ect", "eot"]
        );
        assert_eq!(f.bytes_required(), 0);
        let v = f
            .eval(&[], &|id| match id {
                "eot" => Some(100.0),
                "ect" => Some(90.0),
                _ => None,
            })
            .expect("both present");
        assert_eq!(v, 10.0);
        assert_eq!(
            f.eval(&[], &|id| (id == "eot").then_some(1.0)),
            Err(EvalError::UnknownReference("ect".into()))
        );
    }

    #[test]
    fn bytes_required_is_highest_variable_plus_one() {
        assert_eq!(parse("1+2").bytes_required(), 0);
        assert_eq!(parse("A").bytes_required(), 1);
        assert_eq!(parse("((A*256)+B)/8").bytes_required(), 2);
        assert_eq!(parse("D").bytes_required(), 4);
        assert_eq!(parse("bit(C, 1) + min(A, 0)").bytes_required(), 3);
    }

    #[test]
    fn eval_errors() {
        assert_eq!(
            parse("A / B").eval_payload(&[1, 0]),
            Err(EvalError::DivisionByZero)
        );
        assert_eq!(
            parse("A / (B - B)").eval_payload(&[1, 3]),
            Err(EvalError::DivisionByZero)
        );
        assert_eq!(
            parse("((A*256)+B)/8").eval_payload(&[4]),
            Err(EvalError::MissingByte {
                variable: 'B',
                available: 1
            })
        );
        assert_eq!(
            parse("baro").eval_payload(&[]),
            Err(EvalError::UnknownReference("baro".into()))
        );
    }

    #[test]
    fn parse_errors_carry_positions() {
        let e = parse_err("A + ");
        assert_eq!(e.position, 4);
        let e = parse_err("A $ B");
        assert_eq!(
            e,
            ParseError {
                position: 2,
                kind: ParseErrorKind::UnexpectedChar('$')
            }
        );
        let e = parse_err("(A + B");
        assert_eq!(e.position, 6);
        let e = parse_err("A B");
        assert_eq!(e.position, 2);
        let e = parse_err("pow(A, 2)");
        assert_eq!(e.kind, ParseErrorKind::UnknownFunction("pow".into()));
        assert_eq!(e.position, 0);
        let e = parse_err("1 + Baro");
        assert_eq!(e.kind, ParseErrorKind::BadIdentifier("Baro".into()));
        assert_eq!(e.position, 4);
        assert_eq!(
            parse_err("AB").kind,
            ParseErrorKind::BadIdentifier("AB".into())
        );
        assert_eq!(
            parse_err("min + 1").kind,
            ParseErrorKind::FunctionNotCalled("min".into())
        );
        assert!(matches!(
            parse_err("signed(A, B)").kind,
            ParseErrorKind::Arity { .. }
        ));
        assert!(matches!(
            parse_err("max(A)").kind,
            ParseErrorKind::Arity { .. }
        ));
        assert_eq!(parse_err("").kind, ParseErrorKind::Empty);
        assert_eq!(parse_err("   ").kind, ParseErrorKind::Empty);
        assert!(matches!(
            parse_err("1.2.3").kind,
            ParseErrorKind::BadNumber(_)
        ));
        assert!(matches!(parse_err("0x").kind, ParseErrorKind::BadNumber(_)));
        assert!(matches!(
            parse_err("0xZZ").kind,
            ParseErrorKind::BadNumber(_)
        ));
        assert!(matches!(
            parse_err("1e5").kind,
            ParseErrorKind::BadNumber(_)
        ));
        assert!(matches!(
            parse_err("+A").kind,
            ParseErrorKind::Expected { .. }
        ));
        assert!(matches!(
            parse_err("A ^ 2").kind,
            ParseErrorKind::UnexpectedChar('^')
        ));
        assert!(matches!(
            parse_err("A;B").kind,
            ParseErrorKind::UnexpectedChar(';')
        ));
        assert!(matches!(
            parse_err("é").kind,
            ParseErrorKind::UnexpectedChar('é')
        ));
    }

    #[test]
    fn hostile_input_is_bounded() {
        let deep = format!("{}A{}", "(".repeat(100), ")".repeat(100));
        assert_eq!(parse_err(&deep).kind, ParseErrorKind::TooDeep);
        let negs = format!("{}A", "-".repeat(100));
        assert_eq!(parse_err(&negs).kind, ParseErrorKind::TooDeep);
        let long = "A+".repeat(300) + "A";
        assert_eq!(parse_err(&long).kind, ParseErrorKind::TooLong);
        // Just inside the limits parses.
        let ok = format!("{}A{}", "(".repeat(MAX_DEPTH), ")".repeat(MAX_DEPTH));
        assert_eq!(parse(&ok).bytes_required(), 1);
    }

    #[test]
    fn overflow_is_an_error_not_infinity() {
        let big = "9".repeat(200);
        // 10^200 * 10^200 overflows f64.
        let f = parse(&format!("{big} * {big}"));
        assert_eq!(f.eval_payload(&[]), Err(EvalError::NonFinite));
    }

    #[test]
    fn snake_case_ids() {
        for ok in ["baro", "eot_ect_delta", "map2", "a"] {
            assert!(is_snake_case_id(ok), "{ok}");
        }
        for bad in ["", "Baro", "_x", "x_", "a__b", "2x", "a-b", "A"] {
            assert!(!is_snake_case_id(bad), "{bad}");
        }
    }

    #[test]
    fn torque_translation() {
        let t = from_torque("(((A*256)+B)*0.03625)-BARO()").expect("boost row");
        assert_eq!(t.formula.source(), "(((A*256)+B)*0.03625)-baro");
        assert_eq!(
            t.formula.references().into_iter().collect::<Vec<_>>(),
            ["baro"]
        );
        assert_eq!(t.caveats.len(), 1);

        let t = from_torque("(((Signed(A)*256)+B)*(9/8)+320)/10").expect("signed");
        assert_eq!(t.formula.source(), "(((signed(A)*256)+B)*(9/8)+320)/10");
        assert!(t.caveats.is_empty());

        let t = from_torque("BARO ( )").expect("spaced call");
        assert_eq!(t.formula.source(), "baro");
    }

    #[test]
    fn torque_rejections_have_reasons() {
        let cases = [
            ("{A:7}", "bit syntax"),
            ("A^2", "operator"),
            ("A>B", "operator"),
            ("VAL{Engine RPM}", "VAL"),
            ("LOOKUP(A:0=Off:1=On)", "LOOKUP"),
            ("INT(A/2)", "INT"),
            ("AA*256+AB", "beyond Z"),
            ("foo", "unknown identifier"),
            ("BARO(A)", "no arguments"),
            ("A+", "does not parse"),
            ("A°", "unexpected character"),
        ];
        for (eq, why) in cases {
            match from_torque(eq) {
                Ok(t) => panic!("{eq:?} translated to {:?}", t.formula.source()),
                Err(e) => assert!(e.reason.contains(why), "{eq:?}: {}", e.reason),
            }
        }
    }
}
