//! Architecture lints over the CLI's own source.
//!
//! These used to live in `nix/checks/cli-lints.nix` as awk and ripgrep: a
//! struct's fields came from `awk "/pub struct $s \{/{f=1;next} f&&/^\}/{exit}"`,
//! a function's body from a similar range match, and a match arm from a third.
//! Every one of those is a hand-rolled parser for a language that has a real
//! grammar, and each got the grammar slightly wrong — a nested brace, a `}` in
//! a string, an attribute between the pattern and the item, a field declared
//! with a different indent. When such an extractor stops matching it does not
//! fail; it returns nothing, and a lint over nothing passes.
//!
//! `syn` gives the same questions exact answers. These run under `cargo test`,
//! so the existing `cli` check covers them, and `syn` is a dev-dependency so
//! nothing reaches the shipped binary.

mod support;

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use syn::visit::Visit;

use support::*;

// ---------------------------------------------------------------- lints

/// `Command::new("kubectl")` reaches exactly one site.
///
/// It used to be two, and the difference was whether the subprocess got the
/// lab's merged CA bundle. Which callers had it was historical. Every kubectl
/// goes through `io::kubectl::command()`.
#[test]
fn kubectl_is_spawned_one_way() {
    assert_spawned_once("kubectl");
}

/// `Command::new("docker")` reaches exactly one site.
///
/// It used to be thirty, across six files, so what a docker subprocess
/// inherits was thirty decisions that were never made. `io::docker::command()`
/// adds nothing today, and that is the point: the next thing docker should or
/// should not inherit is decided once, there.
#[test]
fn docker_is_spawned_one_way() {
    assert_spawned_once("docker");
}

fn assert_spawned_once(program: &str) {
    let sources = Sources::load();
    let mut sites = Vec::new();

    for (path, file) in &sources.files {
        let mut visitor = NewCalls::default();
        visitor.visit_file(file);
        for (path_str, literal) in visitor.calls {
            if path_str.ends_with("Command::new") && literal == program {
                sites.push(sources.relative(path));
            }
        }
    }

    assert_eq!(
        sites.len(),
        1,
        "{program} is spawned {} different ways: {sites:?}\n\n\
         Every {program} goes through its io:: seam, which is the one site \
         this expects to find.",
        sites.len()
    );
}

/// `DOCKER_HOST` is set in exactly one place.
///
/// k3d, talosctl and docker all read it, and each had its own copy.
/// `io::docker::apply_host` is the one that stays.
#[test]
fn docker_host_is_set_in_one_place() {
    let sources = Sources::load();
    let mut sites = Vec::new();

    for (path, file) in &sources.files {
        for call in method_calls(file, "env") {
            if let Some(syn::Expr::Lit(lit)) = call.args.first()
                && let syn::Lit::Str(s) = &lit.lit
                && s.value() == "DOCKER_HOST"
            {
                sites.push(sources.relative(path));
            }
        }
    }

    assert_eq!(
        sites.len(),
        1,
        "DOCKER_HOST is set in {} places: {sites:?}",
        sites.len()
    );
}

/// A container is started one way, and that way applies its labels.
///
/// There were two ways, and only one of them could have carried labels. A
/// container without `catallaxy.io/lab` cannot be attributed to a lab, which
/// is what made an orphaned lab impossible to find or remove.
#[test]
fn every_container_carries_provenance() {
    let sources = Sources::load();
    let mut sites = Vec::new();

    for (path, file) in &sources.files {
        for call in method_calls(file, "args") {
            if let Some(first) = call.args.first() {
                let strings = array_strings(first);
                if strings.first().map(String::as_str) == Some("run")
                    && strings.get(1).map(String::as_str) == Some("-d")
                {
                    sites.push(sources.relative(path));
                }
            }
        }
    }

    assert_eq!(
        sites.len(),
        1,
        "a container is started {} different ways: {sites:?}\n\n\
         Every container goes through io::docker::RunContainer.",
        sites.len()
    );

    // The one site has to actually apply the labels. Asking whether the
    // enclosing function mentions `label_args` is the AST question; the text
    // version was a dot-matching regex with a 400-character window, which
    // would have gone quiet the moment the function grew.
    let docker = sources.file("io/docker.rs");
    let containing = fns_containing_run_detached(docker);

    assert_eq!(
        containing.len(),
        1,
        "expected exactly one fn in io/docker.rs to start a container, found {}",
        containing.len()
    );

    let (name, body_idents) = &containing[0];
    assert!(
        body_idents.contains("label_args"),
        "{name} starts a container without applying its labels.\n\n\
         catallaxy.io/lab is how `lab list` finds a running lab and how \
         `lab cleanup` removes one the flake no longer defines."
    );
}

fn fns_containing_run_detached(file: &syn::File) -> Vec<(String, IdentCounts)> {
    struct Finder {
        found: Vec<(String, IdentCounts)>,
    }

    impl Visit<'_> for Finder {
        fn visit_item_fn(&mut self, item: &syn::ItemFn) {
            let mut calls = MethodCalls {
                name: "args",
                found: Vec::new(),
            };
            calls.visit_item_fn(item);

            let starts_container = calls.found.iter().any(|call| {
                call.args.first().is_some_and(|first| {
                    let strings = array_strings(first);
                    strings.first().map(String::as_str) == Some("run")
                        && strings.get(1).map(String::as_str) == Some("-d")
                })
            });

            if starts_container {
                self.found
                    .push((item.sig.ident.to_string(), idents_of(item)));
            }

            syn::visit::visit_item_fn(self, item);
        }
    }

    let mut finder = Finder { found: Vec::new() };
    finder.visit_file(file);
    finder.found
}

/// Nothing in the tree carries a lint suppression.
///
/// A suppression hides the warning from `cargo clippy -- -D warnings` too, so
/// the clippy check cannot see what it covers.
#[test]
fn there_are_no_lint_suppressions() {
    struct Suppressions {
        found: Vec<String>,
    }

    impl Visit<'_> for Suppressions {
        fn visit_attribute(&mut self, attr: &syn::Attribute) {
            if attr.path().is_ident("allow") || attr.path().is_ident("expect") {
                self.found.push(path_string(attr.path()));
            }
            syn::visit::visit_attribute(self, attr);
        }
    }

    let sources = Sources::load();
    let mut sites = Vec::new();

    for (path, file) in &sources.files {
        let mut visitor = Suppressions { found: Vec::new() };
        visitor.visit_file(file);
        for kind in visitor.found {
            sites.push(format!("{}: #[{kind}]", sources.relative(path)));
        }
    }

    assert!(
        sites.is_empty(),
        "the cli carries lint suppressions:\n{}\n\n\
         Fix the code the lint points at.",
        sites.join("\n")
    );
}

/// The orphan path never evaluates a flake.
///
/// `lab cleanup` exists for the case the flake cannot answer: the lab was
/// deleted from it, renamed, built from another checkout, or the flake no
/// longer evaluates. Reaching for it here would fail in exactly the situation
/// the command is for.
#[test]
fn cleanup_never_reaches_for_a_flake() {
    let sources = Sources::load();
    let guarded = [
        "commands/lab/cleanup.rs",
        "domain/inventory.rs",
        "io/host_inventory.rs",
    ];

    for relative in guarded {
        let idents = idents_of(sources.file(relative));
        for forbidden in ["get_lab_spec", "get_lab_config", "nix"] {
            assert!(
                !idents.contains(forbidden),
                "{relative} reaches for `{forbidden}`, so the orphan path \
                 evaluates a flake."
            );
        }
    }
}

/// The lab CA is applied only from the process seam.
///
/// `io::process::{run_capture,run_streaming,run_interactive,run_output,run_status}`
/// apply the CA and honour `--verbose`. A call to `trust::apply` anywhere else
/// is a subprocess that went around them, and the next one like it will forget.
#[test]
fn trust_goes_through_the_process_seam() {
    struct TrustApply {
        found: bool,
    }

    impl Visit<'_> for TrustApply {
        fn visit_path(&mut self, path: &syn::Path) {
            let text = path_string(path);
            if text == "trust::apply" || text.ends_with("::trust::apply") {
                self.found = true;
            }
            syn::visit::visit_path(self, path);
        }
    }

    let sources = Sources::load();
    let mut sites = Vec::new();

    for (path, file) in &sources.files {
        let relative = sources.relative(path);
        if relative.ends_with("process.rs") {
            continue;
        }
        let mut visitor = TrustApply { found: false };
        visitor.visit_file(file);
        if visitor.found {
            sites.push(relative);
        }
    }

    assert!(
        sites.is_empty(),
        "the lab CA is applied outside io/process.rs: {sites:?}"
    );
}

/// No `serde_json::Value` crosses a public boundary outside `io/`.
///
/// `contributing.md`: "Parse `nix eval` JSON into a typed struct at the seam;
/// downstream code takes `LabSpec`, not `serde_json::Value`. A
/// `.pointer("/foo/bar")` chain means a type is missing at the edge."
///
/// `io/` is where JSON arrives and where the types are made, so it is exempt.
/// Everywhere else a `Value` in a signature is a type that was not written.
/// The baseline shrinks only.
#[test]
fn no_untyped_json_crosses_a_public_boundary() {
    let sources = Sources::load();
    let allowed = untyped_json_baseline();

    let mut found = Vec::new();
    for (path, file) in &sources.files {
        let relative = sources.relative(path);
        if relative.starts_with("io/") || relative.contains("/io/") {
            continue;
        }
        for name in pub_fns_taking_json(file) {
            found.push(format!("{relative}: {name}"));
        }
    }

    let new: Vec<&String> = found
        .iter()
        .filter(|f| !allowed.contains(f.as_str()))
        .collect();
    let stale: Vec<&&str> = allowed
        .iter()
        .filter(|b| !found.iter().any(|f| f == *b))
        .collect();

    assert!(
        new.is_empty(),
        "these public functions outside io/ take or return serde_json::Value:\n  {}\n\n\
         Parse it into a type at the seam in io/ and hand that down.",
        new.iter()
            .map(|s| s.as_str())
            .collect::<Vec<_>>()
            .join("\n  ")
    );

    assert!(
        stale.is_empty(),
        "these baseline entries no longer fire, so the baseline is stale:\n  {}\n\nDelete them.",
        stale.iter().map(|s| **s).collect::<Vec<_>>().join("\n  ")
    );
}

/// What still hands untyped JSON around outside `io/`. Shrinks only.
fn untyped_json_baseline() -> BTreeSet<&'static str> {
    [
        // JSON Schema *is* the subject of the generator, so a Value here is
        // the input, not a missing type.
        "codegen/convert.rs: convert",
        "codegen/convert.rs: new",
        // Golden-file rendering canonicalises whatever JSON it is handed,
        // which is the job.
        "commands/lab/golden.rs: canonicalize",
        "commands/lab/golden.rs: render_value",
        // The constructors that *make* the types: a Value goes in and a type
        // comes out, which is the seam doing its work.
        "domain/cluster.rs: from_value",
        "domain/lab.rs: from_value",
        "domain/secrets.rs: from_lab_config",
        // --- Debt below. Each is a type that was never written, and each
        // --- decodes a reply at the point of use rather than at the edge.
        "domain/crossplane.rs: of",
        "images/actual.rs: images_in_pods",
        "images/mod.rs: publish_one",
        "images/mod.rs: tags_from_body",
        "topology/extract.rs: health_of",
    ]
    .into_iter()
    .collect()
}

fn pub_fns_taking_json(file: &syn::File) -> Vec<String> {
    struct Finder {
        found: Vec<String>,
    }

    impl Visit<'_> for Finder {
        fn visit_item_fn(&mut self, item: &syn::ItemFn) {
            if matches!(item.vis, syn::Visibility::Public(_))
                && signature_mentions(&item.sig, "Value")
            {
                self.found.push(item.sig.ident.to_string());
            }
            syn::visit::visit_item_fn(self, item);
        }

        fn visit_impl_item_fn(&mut self, item: &syn::ImplItemFn) {
            if matches!(item.vis, syn::Visibility::Public(_))
                && signature_mentions(&item.sig, "Value")
            {
                self.found.push(item.sig.ident.to_string());
            }
            syn::visit::visit_impl_item_fn(self, item);
        }
    }

    let mut finder = Finder { found: Vec::new() };
    finder.visit_file(file);
    finder.found
}

/// No file grows past the size limit.
///
/// `docs/book/src/contributing.md` states it as a one-way ratchet — "a file
/// reduced below the limit may not grow back past it" — and the pull-request
/// checklist repeats it, but until now nothing checked it, and `io/ssa/mod.rs`
/// had drifted to 1024 lines.
///
/// The cap is on the file, not the module: a file you cannot describe in one
/// sentence is the thing being ruled out, and splitting one is always
/// available.
#[test]
fn no_file_is_over_the_size_cap() {
    const CAP: usize = 1000;

    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut over = Vec::new();

    for dir in ["src", "tests"] {
        for entry in walkdir::WalkDir::new(root.join(dir))
            .sort_by_file_name()
            .into_iter()
            .filter_map(Result::ok)
        {
            let path = entry.path();
            if path.extension().is_none_or(|e| e != "rs") {
                continue;
            }
            let lines = std::fs::read_to_string(path)
                .unwrap_or_else(|e| panic!("reading {}: {e}", path.display()))
                .lines()
                .count();
            if lines > CAP {
                over.push(format!(
                    "{}: {lines} lines",
                    path.strip_prefix(root).unwrap_or(path).display()
                ));
            }
        }
    }

    assert!(
        over.is_empty(),
        "these files are over the {CAP}-line cap:\n{}\n\n\
         Split along the seams the file already has. If you cannot say what \
         the file is for in one sentence, that is the actual finding.",
        over.join("\n")
    );
}

/// Anything that builds a `--context` argument resolves the name first.
///
/// kubectl reads an empty `--context` as unset and falls back to the
/// kubeconfig's current-context, so an unresolved lab context runs against
/// whatever cluster the operator is pointed at rather than failing.
/// `lab status` once reported such a lab as reachable because an unrelated
/// live cluster answered.
#[test]
fn kube_contexts_are_checked_before_use() {
    let sources = Sources::load();

    // The two seams that are allowed to spell it: one resolves the name, the
    // other is the single place kubectl is built.
    let seams = ["io/kube_context.rs", "io/kubectl/run.rs"];

    // The module, not the file, is the unit that owns the guard. A module
    // resolves the context once at its entry point and passes a `&str` down;
    // splitting that module into several files moves the `--context` usage
    // away from the `require_named` call without changing anything. Scoping
    // to the file made `io/ssa/mod.rs` fail purely for being split up.
    //
    // The real fix is a resolved-context newtype that only
    // `io::kube_context::require_named` can mint, which would make this check
    // unnecessary. Until then this is the honest approximation.
    let guarded_modules: BTreeMap<String, bool> =
        sources
            .files
            .iter()
            .fold(BTreeMap::new(), |mut acc, (path, file)| {
                let module = module_of(&sources.relative(path));
                let guarded = idents_of(file).contains("require_named");
                *acc.entry(module).or_insert(false) |= guarded;
                acc
            });

    let mut unguarded = Vec::new();

    for (path, file) in &sources.files {
        let relative = sources.relative(path);
        if seams.contains(&relative.as_str()) {
            continue;
        }
        if !string_literals(file).iter().any(|s| s == "--context") {
            continue;
        }
        if !guarded_modules
            .get(&module_of(&relative))
            .copied()
            .unwrap_or(false)
        {
            unguarded.push(relative);
        }
    }

    assert!(
        unguarded.is_empty(),
        "these modules build a --context argument and never resolve one: {unguarded:?}\n\n\
         Build the command through io::kubectl::run's contextual(), or pass the \
         name through io::kube_context::require_named()."
    );

    // A resolved-or-nothing lookup collapsed to a default is the same bug by
    // another route: an empty context is not "no context in particular", it is
    // the operator's current one.
    let mut erased = Vec::new();
    for (path, file) in &sources.files {
        if kube_context_is_defaulted(file) {
            erased.push(sources.relative(path));
        }
    }

    assert!(
        erased.is_empty(),
        "a kube context lookup was collapsed to an empty string: {erased:?}\n\n\
         Handle the error instead."
    );
}

/// The module a file belongs to: its directory, or the file itself at the top
/// level. `io/ssa/prune.rs` and `io/ssa/mod.rs` are one module; `commands/x.rs`
/// and `commands/y.rs` are not.
fn module_of(relative: &str) -> String {
    match relative.rsplit_once('/') {
        Some((dir, _)) => dir.to_string(),
        None => relative.to_string(),
    }
}

fn string_literals(file: &syn::File) -> Vec<String> {
    struct Literals {
        found: Vec<String>,
    }

    impl Visit<'_> for Literals {
        fn visit_lit_str(&mut self, lit: &syn::LitStr) {
            self.found.push(lit.value());
        }
    }

    let mut visitor = Literals { found: Vec::new() };
    visitor.visit_file(file);
    visitor.found
}

/// `something.kube_context(..).unwrap_or_default()` or `.unwrap_or("")`.
fn kube_context_is_defaulted(file: &syn::File) -> bool {
    struct Defaulted {
        found: bool,
    }

    impl Visit<'_> for Defaulted {
        fn visit_expr_method_call(&mut self, call: &syn::ExprMethodCall) {
            let collapses = call.method == "unwrap_or_default"
                || (call.method == "unwrap_or"
                    && call.args.first().is_some_and(|arg| match arg {
                        syn::Expr::Lit(lit) => match &lit.lit {
                            syn::Lit::Str(s) => s.value().is_empty(),
                            _ => false,
                        },
                        _ => false,
                    }));

            if collapses && receiver_mentions_kube_context(&call.receiver) {
                self.found = true;
            }

            syn::visit::visit_expr_method_call(self, call);
        }
    }

    let mut visitor = Defaulted { found: false };
    visitor.visit_file(file);
    visitor.found
}

fn receiver_mentions_kube_context(expr: &syn::Expr) -> bool {
    match expr {
        syn::Expr::MethodCall(call) => call.method == "kube_context",
        syn::Expr::Call(call) => match &*call.func {
            syn::Expr::Path(p) => path_string(&p.path).ends_with("kube_context"),
            _ => false,
        },
        syn::Expr::Field(field) => match &field.member {
            syn::Member::Named(name) => name == "kube_context",
            syn::Member::Unnamed(_) => false,
        },
        _ => false,
    }
}

/// Every field an operator can declare reaches the shape drift compares.
///
/// `lab up` refuses a cluster whose declaration no longer matches the shape it
/// was built from, and the comparison is over `ClusterShape`. A field missing
/// from it is one an operator can change and have silently ignored, which is
/// what this exists to stop coming back: drift used to compare two fields of
/// twelve.
#[test]
fn cluster_drift_sees_every_declared_field() {
    let sources = Sources::load();
    let declared = sources.file("domain/cluster.rs");
    let shape = idents_of(sources.file("domain/cluster_shape.rs"));

    // A different k3d cluster name is a different cluster, so `cluster_exists`
    // never matches one and there is nothing to drift.
    let exempt = ["cluster_name"];

    let mut missing = Vec::new();
    for name in ["K3dConfig", "ClusterNetwork", "KubernetesSpec"] {
        for field in struct_fields(declared, name) {
            if exempt.contains(&field.as_str()) {
                continue;
            }
            if !shape.contains(&field) {
                missing.push(format!("{name}.{field}"));
            }
        }
    }

    assert!(
        missing.is_empty(),
        "these declared cluster fields are not in the recorded shape: {missing:?}\n\n\
         Add each to ClusterShape::of and compare_shapes, or if it genuinely \
         cannot drift, exempt it here with a reason."
    );
}

/// Every provisioner that creates a cluster also converges an existing one.
///
/// The field walk above cannot see a provisioner that is never compared at
/// all, which is how Talos went without a drift check while its
/// `cluster_create` read controlPlanes and workers from the declaration.
#[test]
fn every_provisioner_converges_what_it_finds() {
    let sources = Sources::load();
    let provisioning = find_fn(
        sources.file("provision/mod.rs"),
        "provision_cluster_with_registry",
    );

    for kind in ["K3d", "Talos"] {
        let arm = provisioner_arm(provisioning, kind)
            .unwrap_or_else(|| panic!("no ProvisionerKind::{kind} arm in provisioning"));

        let idents = idents_of(&arm);
        assert!(
            idents.contains("converge_existing_cluster") || idents.contains("provision_k3d"),
            "ProvisionerKind::{kind} provisions a cluster without ever comparing \
             it to what the lab declares.\n\n\
             An existing cluster that short-circuits on 'already running' reports \
             a green run for a declaration it ignored."
        );
    }
}

/// The body of the `ProvisionerKind::<kind>` arm, as an expression.
///
/// The shell version took this with `awk "/ProvisionerKind::$1 =>/{f=1} f{print} f&&/^        \}\$/{exit}"`
/// — a range match that ended at a closing brace *at one specific indent*, so
/// reindenting the function silently emptied the lint.
fn provisioner_arm(item: &syn::ItemFn, kind: &str) -> Option<syn::Expr> {
    struct ArmFinder<'a> {
        kind: &'a str,
        found: Option<syn::Expr>,
    }

    impl<'a> Visit<'_> for ArmFinder<'a> {
        fn visit_expr_match(&mut self, node: &syn::ExprMatch) {
            for arm in &node.arms {
                if pattern_names_variant(&arm.pat, "ProvisionerKind", self.kind) {
                    self.found = Some((*arm.body).clone());
                }
            }
            syn::visit::visit_expr_match(self, node);
        }
    }

    let mut finder = ArmFinder { kind, found: None };
    finder.visit_item_fn(item);
    finder.found
}

fn pattern_names_variant(pat: &syn::Pat, enum_name: &str, variant: &str) -> bool {
    let path = match pat {
        syn::Pat::Path(p) => &p.path,
        syn::Pat::TupleStruct(p) => &p.path,
        syn::Pat::Struct(p) => &p.path,
        syn::Pat::Or(or) => {
            return or
                .cases
                .iter()
                .any(|case| pattern_names_variant(case, enum_name, variant));
        }
        _ => return false,
    };

    let segments: Vec<String> = path.segments.iter().map(|s| s.ident.to_string()).collect();
    let names_variant = segments.last().is_some_and(|last| last == variant);
    let names_enum = segments
        .iter()
        .rev()
        .nth(1)
        .is_some_and(|prev| prev == enum_name);

    names_variant && names_enum
}

/// Awaiting a wave waits for workloads and then runs the probe.
///
/// It used to branch on whether a bundle declared a probe, and the branch
/// meant a bundle with a probe never waited for its own Deployments. A probe
/// answers a narrower question than the rollout: cert-manager's checks an
/// Issuer, not the webhook serving it, so the next wave started against pods
/// that were still coming up.
#[test]
fn a_ready_probe_never_replaces_the_rollout_wait() {
    let sources = Sources::load();
    let body = find_fn(sources.file("io/ssa/mod.rs"), "await_wave_bundles");
    let idents = idents_of(body);

    for call in ["wait_workloads_ready", "run_ready_probe"] {
        assert!(
            idents.contains(call),
            "await_wave_bundles no longer calls {call}."
        );
    }

    assert!(
        !matches_on_ready_probe(body),
        "awaiting a bundle branches on whether it declares a probe.\n\n\
         Wait for the workloads, then run the probe. A bundle with no workloads \
         makes the wait a no-op, so nothing is paid for it."
    );
}

fn matches_on_ready_probe(item: &syn::ItemFn) -> bool {
    struct ProbeMatch {
        found: bool,
    }

    impl Visit<'_> for ProbeMatch {
        fn visit_expr_match(&mut self, node: &syn::ExprMatch) {
            if let syn::Expr::Field(field) = strip_reference(&node.expr)
                && let syn::Member::Named(name) = &field.member
                && name == "ready_probe"
            {
                self.found = true;
            }
            syn::visit::visit_expr_match(self, node);
        }
    }

    let mut visitor = ProbeMatch { found: false };
    visitor.visit_item_fn(item);
    visitor.found
}

fn strip_reference(expr: &syn::Expr) -> &syn::Expr {
    match expr {
        syn::Expr::Reference(r) => strip_reference(&r.expr),
        other => other,
    }
}

/// The CLI reads every field it parses out of the lab config.
///
/// Nix computes and documents these, so an operator who sets the option gets a
/// green run and none of the behaviour if nothing reads it.
#[test]
fn cli_parses_nothing_it_ignores() {
    let sources = Sources::load();

    // Every identifier in the tree, counted once.
    let mut everywhere = IdentCounts::default();
    for (_, file) in &sources.files {
        everywhere.visit_file(file);
    }

    let mut orphaned = Vec::new();

    for relative in ["domain/cluster.rs", "domain/lab.rs"] {
        for (owner, field, flattened) in declared_fields(sources.file(relative)) {
            // A serde(flatten) catch-all exists to round-trip unknown keys, so
            // it has no reader by design.
            if flattened {
                continue;
            }

            let declarations = declaration_count(&sources, &field);
            if everywhere.get(&field) <= declarations {
                orphaned.push(format!("{relative}: {owner}.{field}"));
            }
        }
    }

    assert!(
        orphaned.is_empty(),
        "the CLI parses fields out of the lab config and then never reads them:\n{}\n\n\
         Either consume the field or stop emitting it from the module that \
         produces it.",
        orphaned.join("\n")
    );
}

/// (struct name, field name, whether it is the serde(flatten) catch-all).
fn declared_fields(file: &syn::File) -> Vec<(String, String, bool)> {
    struct Structs {
        found: Vec<(String, String, bool)>,
    }

    impl Visit<'_> for Structs {
        fn visit_item_struct(&mut self, item: &syn::ItemStruct) {
            if let syn::Fields::Named(named) = &item.fields {
                for field in &named.named {
                    if let Some(ident) = &field.ident {
                        let flattened = field.attrs.iter().any(is_serde_flatten);
                        self.found
                            .push((item.ident.to_string(), ident.to_string(), flattened));
                    }
                }
            }
            syn::visit::visit_item_struct(self, item);
        }
    }

    let mut visitor = Structs { found: Vec::new() };
    visitor.visit_file(file);
    visitor.found
}

/// How many times this name appears as a struct field declaration anywhere.
///
/// A field that appears only where it is declared is one nothing reads. The
/// shell version approximated a declaration as the text `^    pub name:`,
/// which counted a four-space indent as "top level struct" and missed any
/// field written otherwise.
fn declaration_count(sources: &Sources, field: &str) -> usize {
    struct Declarations<'a> {
        field: &'a str,
        count: usize,
    }

    impl<'a> Visit<'_> for Declarations<'a> {
        fn visit_field(&mut self, node: &syn::Field) {
            if node.ident.as_ref().is_some_and(|i| i == self.field) {
                self.count += 1;
            }
            syn::visit::visit_field(self, node);
        }
    }

    let mut total = 0;
    for (_, file) in &sources.files {
        let mut visitor = Declarations { field, count: 0 };
        visitor.visit_file(file);
        total += visitor.count;
    }
    total
}
