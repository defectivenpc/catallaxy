//! Comparing rendered output against a committed baseline.
//!
//! `lab plan` and `lab plan-manifests` both render something derived from a
//! Nix evaluation, canonicalise it, scrub the store hashes out of it and diff
//! it against a checked-in file. All four steps were written twice, and only
//! `plan.rs` had tests for them, so the copy that ran under
//! `plan-manifests` was the untested one.

use std::io::Write;
use std::path::Path;

use anyhow::{Context, Result};
use console::style;
use serde_json::Value;

/// One value, flattened to the single line a baseline holds.
///
/// A scalar goes in bare unless it carries whitespace or the punctuation the
/// `key=value` rendering uses; anything compound goes in as canonical JSON.
#[must_use]
pub fn render_value(v: &Value) -> String {
    match v {
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => {
            let needs_quote = s
                .chars()
                .any(|c| c.is_whitespace() || c == '=' || c == '"' || c == '\\');
            if needs_quote {
                serde_json::to_string(s).unwrap_or_else(|_| format!("{s:?}"))
            } else {
                s.clone()
            }
        }
        Value::Array(_) | Value::Object(_) => serde_json::to_string(&canonicalize(v))
            .unwrap_or_else(|_| "<unserializable>".to_string()),
    }
}

/// The same value with every object's keys in sorted order.
///
/// Nix attribute sets have no order, so two evaluations can serialise the same
/// data differently. A baseline diff would then report a change nobody made.
#[must_use]
pub fn canonicalize(v: &Value) -> Value {
    match v {
        Value::Object(m) => {
            let mut keys: Vec<&String> = m.keys().collect();
            keys.sort();
            let mut sorted = serde_json::Map::with_capacity(m.len());
            for k in keys {
                sorted.insert(k.clone(), canonicalize(&m[k]));
            }
            Value::Object(sorted)
        }
        Value::Array(a) => Value::Array(a.iter().map(canonicalize).collect()),
        _ => v.clone(),
    }
}

/// Replace every store hash with `HASH`.
///
/// The hash changes whenever anything upstream of the derivation does, so a
/// baseline that kept them would need refreshing on every unrelated change and
/// would stop meaning anything.
#[must_use]
pub fn normalize_store_paths(s: &str) -> String {
    const PREFIX: &str = "/nix/store/";
    const HASH_LEN: usize = 32;

    let mut result = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(idx) = rest.find(PREFIX) {
        result.push_str(&rest[..idx]);
        result.push_str(PREFIX);
        let after = &rest[idx + PREFIX.len()..];
        let bytes = after.as_bytes();
        if bytes.len() > HASH_LEN
            && bytes[HASH_LEN] == b'-'
            && bytes[..HASH_LEN]
                .iter()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        {
            result.push_str("HASH");
            rest = &after[HASH_LEN..];
        } else {
            rest = after;
        }
    }
    result.push_str(rest);
    result
}

/// Whether `actual` matches the baseline, printing a unified diff when not.
///
/// `subject` names what is being compared, for the two messages an operator
/// reads — "plan", "manifest waves".
///
/// # Errors
///
/// If the baseline cannot be read, or the temp file the diff reads from
/// cannot be created or written. A `diff` that fails to run is reported and
/// treated as a mismatch, because the comparison did not happen.
pub fn run_diff(actual: &str, baseline_path: &Path, subject: &str) -> Result<bool> {
    let baseline = crate::io::fs::read_to_string(baseline_path)
        .with_context(|| format!("reading baseline {}", baseline_path.display()))?;

    if actual == baseline {
        eprintln!(
            "{subject} matches baseline {}",
            style(baseline_path.display()).dim()
        );
        return Ok(true);
    }

    let mut tmp = crate::io::fs::secure_tempfile("cata-plan-", ".txt")
        .context("creating temp file for diff")?;
    tmp.write_all(actual.as_bytes())
        .with_context(|| format!("writing actual {subject} to temp file"))?;
    tmp.flush()
        .context("flushing the temp file the diff is read from")?;

    if let Err(e) = crate::io::diff::unified(baseline_path, tmp.path()) {
        eprintln!(
            "{}: `diff -u` failed ({e}); {subject} differs from baseline",
            style("error").red()
        );
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn normalize_store_paths_collapses_hash() {
        let input = "/nix/store/abcdef0123456789abcdef0123456789-foo/bin/foo";
        assert_eq!(normalize_store_paths(input), "/nix/store/HASH-foo/bin/foo");
    }

    #[test]
    fn normalize_store_paths_leaves_non_matching_alone() {
        let input = "/nix/store/short-foo /nix/store/UPPERCASE00000000000000000000000-x";
        assert_eq!(normalize_store_paths(input), input);
    }

    #[test]
    fn normalize_store_paths_multiple_occurrences() {
        let input = "a /nix/store/00000000000000000000000000000000-x b /nix/store/11111111111111111111111111111111-y c";
        assert_eq!(
            normalize_store_paths(input),
            "a /nix/store/HASH-x b /nix/store/HASH-y c"
        );
    }

    /// A path that is exactly the prefix plus a hash, with nothing after it,
    /// is not a store path and must be left alone.
    #[test]
    fn normalize_store_paths_needs_something_after_the_hash() {
        let input = "/nix/store/00000000000000000000000000000000";
        assert_eq!(normalize_store_paths(input), input);
    }

    #[test]
    fn canonicalize_sorts_keys_at_every_depth() {
        let v = json!({ "b": 1, "a": { "d": 2, "c": 3 } });
        assert_eq!(
            serde_json::to_string(&canonicalize(&v)).unwrap(),
            r#"{"a":{"c":3,"d":2},"b":1}"#
        );
    }

    #[test]
    fn a_plain_scalar_is_rendered_bare() {
        assert_eq!(render_value(&json!("k3d-mgmt")), "k3d-mgmt");
    }

    /// Whitespace or `=` would make the `key=value` line ambiguous.
    #[test]
    fn a_scalar_needing_quotes_gets_them() {
        assert_eq!(render_value(&json!("two words")), "\"two words\"");
        assert_eq!(render_value(&json!("a=b")), "\"a=b\"");
    }

    #[test]
    fn a_compound_value_is_rendered_canonically() {
        assert_eq!(render_value(&json!({ "b": 1, "a": 2 })), r#"{"a":2,"b":1}"#);
    }
}
