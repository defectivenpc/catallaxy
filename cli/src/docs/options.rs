use std::collections::{BTreeMap, HashMap};

use serde::Deserialize;

use crate::docs::page;

/// Every option on the page is one field of one step, so the page's own
/// prefix is what gets stripped off each display name.
const STEP_ENTRY_PREFIX: &str = "steps.<name>.";

#[derive(Debug, Clone, Deserialize)]
pub struct OptionDoc {
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default, rename = "type")]
    pub type_name: Option<String>,
    #[serde(default)]
    pub default: Option<Literal>,
    #[serde(default)]
    pub example: Option<Literal>,
    #[serde(default)]
    pub declarations: Vec<Declaration>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum Literal {
    Rendered { text: String },
    Scalar(serde_json::Value),
}

impl Literal {
    pub fn text(&self) -> String {
        match self {
            Literal::Rendered { text } => text.clone(),
            Literal::Scalar(serde_json::Value::String(s)) => s.clone(),
            Literal::Scalar(v) => v.to_string(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum Declaration {
    Linked { name: String, url: String },
    Plain(String),
}

pub fn escape_placeholders(text: &str) -> String {
    text.split('`')
        .enumerate()
        .map(|(i, part)| {
            if i % 2 == 0 {
                part.replace('<', "&lt;").replace('>', "&gt;")
            } else {
                part.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join("`")
}

/// A default or an example. Long or multi-line goes in a fenced block, because
/// a forty-line `values` attrset inside backticks is one unreadable line.
fn block_or_inline(label: &str, text: &str) -> String {
    if text.len() > 80 || text.contains('\n') {
        format!("**{label}:**\n```nix\n{text}\n```")
    } else {
        format!("**{label}:** `{text}`")
    }
}

pub fn anchor(display_name: &str) -> String {
    display_name
        .to_lowercase()
        .split(['.', ' '])
        .map(|seg| {
            seg.trim_matches(|c| c == '<' || c == '>' || c == '*')
                .to_string()
        })
        .filter(|seg| !seg.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

fn group_of(display_name: &str) -> &str {
    match display_name.split_once('.') {
        Some((head, _)) => head,
        None => "",
    }
}

/// One option, as a `###` entry. Its paragraphs are what the module system
/// knows about it: the description, the type, a default worth printing, and
/// where it is declared.
pub fn option_block(name: &str, opt: &OptionDoc) -> page::Block {
    let mut lead: Vec<String> = Vec::new();

    if let Some(d) = opt.description.as_ref().filter(|d| !d.trim().is_empty()) {
        lead.push(escape_placeholders(d.trim()));
    }

    if let Some(t) = opt.type_name.as_ref().filter(|t| !t.is_empty()) {
        lead.push(format!("**Type:** `{t}`"));
    }

    if let Some(default) = &opt.default {
        let text = default.text();

        if !text.is_empty() && text != "null" {
            lead.push(block_or_inline("Default", &text));
        }
    }

    if let Some(example) = &opt.example {
        let text = example.text();
        if !text.is_empty() {
            lead.push(block_or_inline("Example", &text));
        }
    }

    let links: Vec<String> = opt
        .declarations
        .iter()
        .map(|d| match d {
            Declaration::Linked { name, url } => format!("[{name}]({url})"),
            Declaration::Plain(s) => s.clone(),
        })
        .collect();
    if !links.is_empty() {
        lead.push(format!("**Declared in:** {}", links.join(", ")));
    }

    lead.push("---".to_string());

    page::Block {
        heading: format!("`{name}`"),
        anchor: Some(anchor(name)),
        lead,
        table: None,
    }
}

/// The map at the top of the page: every option, its type, and a default short
/// enough to read in a cell.
fn index_table(displayed: &[(String, &OptionDoc)]) -> page::Table {
    page::Table {
        columns: vec!["Option".into(), "Type".into(), "Default".into()],
        rows: displayed
            .iter()
            .map(|(display, opt)| {
                let ty = opt.type_name.clone().unwrap_or_default();
                let default = opt
                    .default
                    .as_ref()
                    .map(|d| d.text())
                    .filter(|t| !t.is_empty() && !t.contains('\n') && t.len() <= 40)
                    .map(|t| format!("`{t}`"))
                    .unwrap_or_default();
                vec![
                    format!("[`{display}`](#{})", anchor(display)),
                    format!("`{ty}`"),
                    default,
                ]
            })
            .collect(),
    }
}

/// One option page, as data.
///
/// Grouped by the first component of the option path, which is how a reader
/// navigates it: `verify.endpoints.enable` sits under `verify` beside
/// everything else about verification, and an option with no dot is top level.
pub fn build_page(
    path: &str,
    title: &str,
    description: &str,
    options: &BTreeMap<String, OptionDoc>,
    prefix_to_strip: &str,
) -> Result<page::Page, String> {
    let mut displayed: Vec<(String, &OptionDoc)> = options
        .iter()
        .map(|(name, opt)| {
            (
                name.strip_prefix(prefix_to_strip)
                    .unwrap_or(name)
                    .to_string(),
                opt,
            )
        })
        .collect();

    displayed.sort_by(|(a, _), (b, _)| group_of(a).cmp(group_of(b)).then_with(|| a.cmp(b)));

    let mut seen: HashMap<String, String> = HashMap::new();
    for (display, _) in &displayed {
        let a = anchor(display);
        if let Some(previous) = seen.insert(a.clone(), display.clone()) {
            return Err(format!(
                "anchor `#{a}` is claimed by both `{previous}` and `{display}` on page \"{title}\""
            ));
        }
    }

    let mut sections = vec![page::Section {
        heading: "Every option".into(),
        lead: vec![],
        table: Some(index_table(&displayed)),
        blocks: vec![],
    }];

    for (display, opt) in &displayed {
        let group = group_of(display);
        let heading = if group.is_empty() {
            "Top level".to_string()
        } else {
            format!("`{group}`")
        };

        if sections.last().is_none_or(|s| s.heading != heading) {
            sections.push(page::Section {
                heading,
                lead: vec![],
                table: None,
                blocks: vec![],
            });
        }

        sections
            .last_mut()
            .expect("a section was just pushed")
            .blocks
            .push(option_block(display, opt));
    }

    Ok(page::Page {
        path: path.into(),
        title: title.into(),
        lead: if description.is_empty() {
            vec![]
        } else {
            vec![description.into()]
        },
        sections,
    })
}

#[derive(Debug)]
pub enum RenderError {
    Unrouted(Vec<String>),
    AnchorCollision(String),
}

#[derive(Debug)]
pub struct Rendered {
    pub pages: Vec<page::Page>,
    pub option_count: usize,
    pub undescribed: Vec<String>,
}

pub fn is_undescribed(opt: &OptionDoc) -> bool {
    opt.description
        .as_ref()
        .is_none_or(|d| d.trim().is_empty() || d.trim() == "This option has no description.")
}

/// The step schema, and nothing else. A lab is a floe, so what a lab writes
/// is rendered from floe declarations by `nix/docs/floes.nix`; what is left
/// here is a *floe author's* document — the fields a floe writes into each
/// entry of its `LAB_STEPS` contribution.
///
/// An option that is not one of those fields is an error rather than a page
/// nobody asked for: it means the module this is generated from grew
/// something, and a reference silently dropping it is how a field goes
/// undocumented.
pub fn render_all(all: BTreeMap<String, OptionDoc>) -> Result<Rendered, RenderError> {
    let mut steps = BTreeMap::new();
    let mut unrouted = Vec::new();
    let mut undescribed = Vec::new();

    for (name, opt) in all {
        if name == "_module.args" || name == "steps" {
            continue;
        }
        if is_undescribed(&opt) {
            undescribed.push(name.clone());
        }
        if name.starts_with(STEP_ENTRY_PREFIX) {
            steps.insert(name, opt);
        } else {
            unrouted.push(name);
        }
    }

    if !unrouted.is_empty() {
        unrouted.sort();
        return Err(RenderError::Unrouted(unrouted));
    }

    let option_count = steps.len();
    undescribed.sort();

    let page = build_page(
        "options/steps.md",
        "Plan Step Schema",
        "What a floe writes into each entry of its `LAB_STEPS` \
         contribution. What a given `kind` accepts in `params` is in \
         [Plan Step Kinds](../step-kinds.md).",
        &steps,
        STEP_ENTRY_PREFIX,
    )
    .map_err(RenderError::AnchorCollision)?;

    Ok(Rendered {
        pages: vec![page],
        option_count,
        undescribed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opt(description: &str) -> OptionDoc {
        OptionDoc {
            description: Some(description.to_string()),
            type_name: Some("bool".into()),
            default: None,
            example: None,
            declarations: vec![],
        }
    }

    #[test]
    fn placeholders_are_escaped_only_outside_code_spans() {
        assert_eq!(
            escape_placeholders("set `floes.<n>.x` on <name> here"),
            "set `floes.<n>.x` on &lt;name&gt; here"
        );
    }

    #[test]
    fn long_defaults_become_code_blocks() {
        let inline = block_or_inline("Default", "true");
        assert_eq!(inline, "**Default:** `true`");
        let block = block_or_inline("Default", &"x".repeat(81));
        assert!(block.starts_with("**Default:**\n```nix\n"));
    }

    #[test]
    fn a_multiline_default_becomes_a_code_block_even_when_short() {
        assert!(block_or_inline("Example", "a\nb").contains("```nix"));
    }

    #[test]
    fn unrouted_options_are_an_error_not_a_silent_drop() {
        let mut all = BTreeMap::new();
        all.insert("nixpkgs.config".to_string(), opt("stray"));
        match render_all(all).unwrap_err() {
            RenderError::Unrouted(names) => assert_eq!(names, vec!["nixpkgs.config".to_string()]),
            other => panic!("expected Unrouted, got {other:?}"),
        }
    }

    #[test]
    fn a_step_is_its_own_schema_and_the_parent_is_not() {
        let all = BTreeMap::from([
            ("steps".to_string(), opt("where the three producers merge")),
            (
                "steps.<name>.kind".to_string(),
                opt("which of the step kinds this is"),
            ),
        ]);
        let rendered = render_all(all).expect("a step field is the whole page");
        assert_eq!(
            rendered.option_count, 1,
            "the parent is the merge point, not a field a floe writes"
        );
        assert_eq!(rendered.pages[0].path, "options/steps.md");
    }

    #[test]
    fn anchors_strip_placeholder_punctuation() {
        assert_eq!(anchor("helmCharts.<name>.values"), "helmcharts-name-values");
        assert_eq!(anchor("assertions.*.message"), "assertions-message");
        assert_eq!(anchor("awaitRollout"), "awaitrollout");
    }

    #[test]
    fn an_option_heading_carries_its_anchor() {
        let block = option_block("awaitRollout", &opt("wait for it"));
        assert_eq!(block.heading, "`awaitRollout`");
        assert_eq!(block.anchor.as_deref(), Some("awaitrollout"));
    }

    #[test]
    fn colliding_anchors_are_an_error_not_a_silent_shadow() {
        let mut options = BTreeMap::new();
        options.insert("a.<name>.x".to_string(), opt("one"));
        options.insert("a.name.x".to_string(), opt("two"));
        let err = build_page("p.md", "T", "", &options, "").unwrap_err();
        assert!(err.contains("a-name-x"), "{err}");
        assert!(
            err.contains("a.<name>.x") && err.contains("a.name.x"),
            "{err}"
        );
    }

    #[test]
    fn a_page_leads_with_an_index_table_then_groups() {
        let mut options = BTreeMap::new();
        options.insert("dns.zone".to_string(), opt("the zone"));
        options.insert("dns.enable".to_string(), opt("on"));
        options.insert("name".to_string(), opt("lab name"));
        let body = page::render(&build_page("p.md", "T", "", &options, "").unwrap());

        assert!(body.contains("| Option | Type | Default |"));
        assert!(body.contains("| [`dns.zone`](#dns-zone) |"));
        assert!(body.contains("## Top level"));
        assert!(body.contains("## `dns`"));
        assert!(
            body.find("## Top level") < body.find("## `dns`"),
            "groups must be contiguous and sorted"
        );
    }

    #[test]
    fn undescribed_options_are_collected() {
        let mut all = BTreeMap::new();
        all.insert("steps.<name>.described".to_string(), opt("has one"));
        all.insert("steps.<name>.bare".to_string(), opt(""));
        let rendered = render_all(all).unwrap();
        assert_eq!(rendered.undescribed, vec!["steps.<name>.bare".to_string()]);
    }

    #[test]
    fn module_args_is_dropped_without_being_unrouted() {
        let mut all = BTreeMap::new();
        all.insert("_module.args".to_string(), opt("internal"));
        all.insert("steps.<name>.kind".to_string(), opt("the kind"));
        let rendered = render_all(all).expect("routes cleanly");
        assert_eq!(rendered.option_count, 1);
    }

    #[test]
    fn option_names_are_shown_with_their_page_prefix_stripped() {
        let mut all = BTreeMap::new();
        all.insert("steps.<name>.policy.onFailure".to_string(), opt("d"));
        let rendered = render_all(all).expect("routes cleanly");
        assert!(page::render(&rendered.pages[0]).contains("`policy.onFailure`"));
    }
}
