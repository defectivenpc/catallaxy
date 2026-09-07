//! Every `cata` command the book prints is a command `cata` accepts.
//!
//! The book is where a reader goes before they know enough to tell a working
//! command from a plausible one, so an invented flag costs them more there
//! than anywhere else. When this was first run it found `cata generate`,
//! documented as a live command on the CLI reference page for as long as the
//! subcommand had lived on `cata-build`.
//!
//! The idiom is borrowed from `cli.rs`'s
//! `every_command_the_secrets_error_suggests_actually_parses`, which holds an
//! error message's suggestions to the same standard. Documentation deserves
//! it at least as much: an error message is read once, a book page for years.
//!
//! What this does *not* check is whether a command does what the surrounding
//! prose says. Nothing mechanical can. It checks the cheaper half — that the
//! reader who copies the line gets past argument parsing — and that half was
//! where the defects were.

use std::path::{Path, PathBuf};

use cata::commands::cli::Cli;
use clap::CommandFactory;

/// Where the book's markdown is.
///
/// Two callers, and they see different trees. Under `cargo test` in a
/// checkout it is `../docs/book/src`. Under Nix the crate is built from a
/// filtered copy of `cli/` alone, so there is no `../docs` at all and
/// `pkgs/cli.nix` passes the path in — the alternative being to widen the
/// derivation's source to the repo root and rebuild the CLI whenever
/// anything anywhere changes.
///
/// Neither branch falls back to skipping. A test that quietly passes when it
/// cannot find its input is worse than one that fails.
fn book_src() -> PathBuf {
    match std::env::var_os("CATALLAXY_BOOK_SRC") {
        Some(p) => PathBuf::from(p),
        None => Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("cli/ has a parent")
            .join("docs/book/src"),
    }
}

fn markdown_under(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).expect("book source is readable") {
            let path = entry.expect("readable entry").path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md") {
                out.push(path);
            }
        }
    }
    out.sort();
    out
}

/// A `cata …` invocation, as argv.
///
/// Only lines *inside a fenced code block* count. Prose says things like
/// "`cata lab up` runs it" mid-sentence, and reconstructing argv from a
/// sentence means guessing where the command stops — which is the kind of
/// hand-rolled parsing `architecture.rs` opens by arguing against. A reader
/// copies from code blocks; those are what must be right.
fn commands_in(text: &str) -> Vec<Vec<String>> {
    let mut out = Vec::new();
    let mut in_fence = false;
    for line in text.lines() {
        if line.trim_start().starts_with("```") {
            in_fence = !in_fence;
            continue;
        }
        if !in_fence {
            continue;
        }
        let line = line.trim();
        // `$ cata …` and `cata …` both appear; a trailing `# comment` is
        // prose, and a line continuation means the command is incomplete
        // here, so skip rather than guess.
        let line = line.strip_prefix("$ ").unwrap_or(line);
        if !line.starts_with("cata ") || line.ends_with('\\') {
            continue;
        }
        let line = match line.split_once(" # ") {
            Some((cmd, _)) => cmd.trim(),
            None => line,
        };
        // A placeholder is the author saying "your value here". Feeding it
        // through is fine — clap type-checks few of these — but a shell
        // construct is not something argv can represent.
        if line.contains('|') || line.contains('$') || line.contains('`') {
            continue;
        }
        out.push(line.split_whitespace().map(str::to_string).collect());
    }
    out
}

#[test]
fn every_cata_command_in_the_book_parses() {
    let src = book_src();
    assert!(src.is_dir(), "book source not found at {}", src.display());

    let mut failures = Vec::new();
    let mut checked = 0usize;

    for page in markdown_under(&src) {
        let text = std::fs::read_to_string(&page).expect("page is readable");
        for argv in commands_in(&text) {
            checked += 1;
            if Cli::command().try_get_matches_from(&argv).is_err() {
                let rel = page.strip_prefix(&src).unwrap_or(&page);
                failures.push(format!("  {}: {}", rel.display(), argv.join(" ")));
            }
        }
    }

    assert!(
        checked > 0,
        "no `cata` commands found under {} — this test would pass over an \
         empty set, which is the failure mode it exists to prevent",
        src.display()
    );

    assert!(
        failures.is_empty(),
        "the book prints {} command(s) `cata` does not accept:\n{}\n\n\
         A reader copies these. Either the command was renamed — fix the page \
         — or it belongs to `cata-build`, which is a different binary.",
        failures.len(),
        failures.join("\n")
    );
}
