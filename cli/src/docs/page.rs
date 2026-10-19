//! One reference page, as data, and the markdown for it.
//!
//! Every generated page in `docs/generated/` has the same shape — a title, some
//! paragraphs, and sections that hold a table or more paragraphs or both — and
//! until now each generator wrote its own markdown. `nix/docs/floes.nix` had
//! `esc`, `table` and `section`; `nix/docs/signatures.nix` had the same three
//! copied; [`super::options`] had a third implementation in Rust. Three sets of
//! escaping rules and three answers to "what does an empty section look like".
//!
//! Nix evaluates and emits this; the markdown happens here. A generator says
//! what the page *is* and never what it looks like, which is also what lets one
//! check apply to all of them — an anchor collision is a property of a page, not
//! of whichever language rendered it.

use serde::Deserialize;

/// A table, rendered GitHub-flavoured. Dropped entirely when it has no rows:
/// a header over nothing reads as "there are none of these", which is what the
/// absence of the section says more clearly.
#[derive(Debug, Clone, Deserialize)]
pub struct Table {
    pub columns: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

impl Table {
    fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    /// `|` ends a cell and a newline ends the row, so neither can appear in
    /// one. The newline becomes a space rather than `<br>`: these are
    /// descriptions written as prose and wrapped, so the break is an artifact
    /// of the source and not something the author meant.
    fn escape(cell: &str) -> String {
        cell.replace('|', "\\|").replace('\n', " ")
    }

    fn lines(&self) -> Vec<String> {
        if self.is_empty() {
            return Vec::new();
        }
        let mut out = vec![
            format!("| {} |", self.columns.join(" | ")),
            format!(
                "| {} |",
                self.columns
                    .iter()
                    .map(|_| "---")
                    .collect::<Vec<_>>()
                    .join(" | ")
            ),
        ];
        for row in &self.rows {
            let cells: Vec<String> = row.iter().map(|c| Self::escape(c)).collect();
            out.push(format!("| {} |", cells.join(" | ")));
        }
        out
    }
}

/// A `###` entry inside a section: one option, or one provision with its
/// fields.
#[derive(Debug, Clone, Deserialize)]
pub struct Block {
    pub heading: String,

    /// An HTML anchor, when the heading is something a reader links to. Checked
    /// for collisions across the page.
    #[serde(default)]
    pub anchor: Option<String>,

    #[serde(default)]
    pub lead: Vec<String>,

    #[serde(default)]
    pub table: Option<Table>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Section {
    pub heading: String,

    #[serde(default)]
    pub lead: Vec<String>,

    #[serde(default)]
    pub table: Option<Table>,

    #[serde(default)]
    pub blocks: Vec<Block>,
}

impl Section {
    /// A section with nothing in it is left out rather than rendered empty.
    /// Every generator already wanted this and each implemented it; "a floe
    /// that collects nothing has no Collects heading" is the rule, not a
    /// special case.
    fn is_empty(&self) -> bool {
        self.lead.is_empty()
            && self.blocks.is_empty()
            && self.table.as_ref().is_none_or(Table::is_empty)
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct Page {
    /// Relative to the output directory, so a generator decides its own family:
    /// `floes/lab-dns.md`, `signatures/DNS_ZONE.md`.
    pub path: String,

    pub title: String,

    /// Paragraphs under the title. A paragraph may hold newlines — it is prose
    /// that was wrapped at the source — and each is followed by a blank line.
    #[serde(default)]
    pub lead: Vec<String>,

    #[serde(default)]
    pub sections: Vec<Section>,
}

fn paragraphs(into: &mut Vec<String>, paras: &[String]) {
    for para in paras {
        for line in para.lines() {
            into.push(line.to_string());
        }
        into.push(String::new());
    }
}

/// Every anchor the page declares, in order, so a caller can refuse a
/// duplicate. Two `### `name`` entries resolving to one anchor means one of the
/// two is unreachable, and a reference whose links go to the wrong row is worse
/// than one with no links.
pub fn anchors(page: &Page) -> Vec<String> {
    page.sections
        .iter()
        .flat_map(|s| s.blocks.iter())
        .filter_map(|b| b.anchor.clone())
        .collect()
}

pub fn render(page: &Page) -> String {
    let mut lines = vec![format!("# {}", page.title), String::new()];
    paragraphs(&mut lines, &page.lead);

    for section in &page.sections {
        if section.is_empty() {
            continue;
        }

        lines.push(format!("## {}", section.heading));
        lines.push(String::new());
        paragraphs(&mut lines, &section.lead);

        if let Some(table) = &section.table {
            lines.extend(table.lines());
            if !table.is_empty() {
                lines.push(String::new());
            }
        }

        for block in &section.blocks {
            match &block.anchor {
                Some(anchor) => lines.push(format!("### {} {{#{anchor}}}", block.heading)),
                None => lines.push(format!("### {}", block.heading)),
            }
            lines.push(String::new());
            paragraphs(&mut lines, &block.lead);
            if let Some(table) = &block.table {
                lines.extend(table.lines());
                if !table.is_empty() {
                    lines.push(String::new());
                }
            }
        }
    }

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(rows: Vec<Vec<&str>>) -> Table {
        Table {
            columns: vec!["a".into(), "b".into()],
            rows: rows
                .into_iter()
                .map(|r| r.into_iter().map(String::from).collect())
                .collect(),
        }
    }

    fn section(heading: &str, table: Option<Table>) -> Section {
        Section {
            heading: heading.into(),
            lead: vec![],
            table,
            blocks: vec![],
        }
    }

    #[test]
    fn a_section_with_an_empty_table_is_left_out() {
        let page = Page {
            path: "x.md".into(),
            title: "t".into(),
            lead: vec![],
            sections: vec![
                section("Gone", Some(table(vec![]))),
                section("Kept", Some(table(vec![vec!["1", "2"]]))),
            ],
        };
        let out = render(&page);
        assert!(!out.contains("## Gone"), "{out}");
        assert!(out.contains("## Kept"));
    }

    #[test]
    fn a_pipe_in_a_cell_is_escaped_and_a_newline_becomes_a_space() {
        let page = Page {
            path: "x.md".into(),
            title: "t".into(),
            lead: vec![],
            sections: vec![section("S", Some(table(vec![vec!["a|b", "one\ntwo"]])))],
        };
        assert!(render(&page).contains("| a\\|b | one two |"));
    }

    #[test]
    fn a_lead_paragraph_keeps_its_line_breaks_and_gains_a_blank_after() {
        let page = Page {
            path: "x.md".into(),
            title: "t".into(),
            lead: vec!["one\ntwo".into()],
            sections: vec![],
        };
        assert_eq!(render(&page), "# t\n\none\ntwo\n");
    }

    #[test]
    fn anchors_are_collected_in_order_for_the_collision_check() {
        let page = Page {
            path: "x.md".into(),
            title: "t".into(),
            lead: vec![],
            sections: vec![Section {
                heading: "S".into(),
                lead: vec![],
                table: None,
                blocks: vec![
                    Block {
                        heading: "`a`".into(),
                        anchor: Some("a".into()),
                        lead: vec!["d".into()],
                        table: None,
                    },
                    Block {
                        heading: "`b`".into(),
                        anchor: None,
                        lead: vec!["d".into()],
                        table: None,
                    },
                ],
            }],
        };
        assert_eq!(anchors(&page), vec!["a".to_string()]);
        assert!(render(&page).contains("### `a` {#a}"));
        assert!(render(&page).contains("### `b`\n"));
    }
}
