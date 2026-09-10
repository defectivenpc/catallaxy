//! Every `cata` command in a book code block parses.

use std::path::{Path, PathBuf};

use cata::commands::cli::Cli;
use clap::CommandFactory;

/// The book's markdown. `CATALLAXY_BOOK_SRC` under Nix, where the crate is
/// built from a filtered copy of `cli/` alone.
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

/// Fenced-block `cata …` lines, as argv. Prose is skipped: reconstructing a
/// command from a sentence means guessing where it ends.
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
        let line = line.strip_prefix("$ ").unwrap_or(line);
        if !line.starts_with("cata ") || line.ends_with('\\') {
            continue;
        }
        let line = match line.split_once(" # ") {
            Some((cmd, _)) => cmd.trim(),
            None => line,
        };
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
        "no `cata` commands found under {}",
        src.display()
    );

    assert!(
        failures.is_empty(),
        "the book prints {} command(s) `cata` does not accept:\n{}\n\n\
         `cata-build` is a different binary.",
        failures.len(),
        failures.join("\n")
    );
}
