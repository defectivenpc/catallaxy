//! Shared AST machinery for the architecture lints.
//!
//! Split out of `architecture.rs` when that file crossed the 1000-line cap
//! the lints themselves enforce.

#![allow(dead_code)]

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use syn::visit::Visit;

// ---------------------------------------------------------------- loading

pub fn src_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("src")
}

/// Every `.rs` file under `cli/src`, parsed once.
pub struct Sources {
    pub files: Vec<(PathBuf, syn::File)>,
}

impl Sources {
    pub fn load() -> Self {
        let root = src_root();
        let mut files = Vec::new();

        for entry in walkdir::WalkDir::new(&root)
            .sort_by_file_name()
            .into_iter()
            .filter_map(Result::ok)
        {
            let path = entry.path();
            if path.extension().is_none_or(|e| e != "rs") {
                continue;
            }
            let text = std::fs::read_to_string(path)
                .unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
            let parsed = syn::parse_file(&text)
                .unwrap_or_else(|e| panic!("parsing {}: {e}", path.display()));
            files.push((path.to_path_buf(), parsed));
        }

        assert!(
            files.len() > 50,
            "only found {} source files under {}; the walk is wrong, and a lint \
             over no files passes for the wrong reason",
            files.len(),
            root.display()
        );

        Self { files }
    }

    pub fn relative(&self, path: &Path) -> String {
        path.strip_prefix(src_root())
            .unwrap_or(path)
            .display()
            .to_string()
    }

    pub fn file(&self, relative: &str) -> &syn::File {
        let want = src_root().join(relative);
        &self
            .files
            .iter()
            .find(|(p, _)| *p == want)
            .unwrap_or_else(|| panic!("{relative} is not in cli/src; did it move?"))
            .1
    }
}

// ---------------------------------------------------------------- visitors

/// Every identifier in whatever it is shown, counted.
#[derive(Default)]
pub struct IdentCounts {
    counts: BTreeMap<String, usize>,
}

impl IdentCounts {
    pub fn get(&self, name: &str) -> usize {
        self.counts.get(name).copied().unwrap_or(0)
    }

    pub fn contains(&self, name: &str) -> bool {
        self.get(name) > 0
    }
}

impl Visit<'_> for IdentCounts {
    fn visit_ident(&mut self, ident: &proc_macro2::Ident) {
        *self.counts.entry(ident.to_string()).or_insert(0) += 1;
    }
}

pub fn idents_of<T>(node: &T) -> IdentCounts
where
    for<'a> IdentCounts: Visit<'a>,
    T: for<'a> VisitableWith<'a>,
{
    let mut counts = IdentCounts::default();
    node.accept(&mut counts);
    counts
}

/// Lets `idents_of` take any syn node without a macro.
pub trait VisitableWith<'a> {
    fn accept(&'a self, visitor: &mut IdentCounts);
}

impl<'a> VisitableWith<'a> for syn::File {
    fn accept(&'a self, visitor: &mut IdentCounts) {
        visitor.visit_file(self);
    }
}

impl<'a> VisitableWith<'a> for syn::ItemFn {
    fn accept(&'a self, visitor: &mut IdentCounts) {
        visitor.visit_item_fn(self);
    }
}

impl<'a> VisitableWith<'a> for syn::Expr {
    fn accept(&'a self, visitor: &mut IdentCounts) {
        visitor.visit_expr(self);
    }
}

// ---------------------------------------------------------------- helpers

/// The named free function, wherever it sits in the file's module tree.
pub fn find_fn<'a>(file: &'a syn::File, name: &str) -> &'a syn::ItemFn {
    pub fn search<'a>(items: &'a [syn::Item], name: &str) -> Option<&'a syn::ItemFn> {
        for item in items {
            match item {
                syn::Item::Fn(f) if f.sig.ident == name => return Some(f),
                syn::Item::Mod(m) => {
                    if let Some((_, inner)) = &m.content
                        && let Some(found) = search(inner, name)
                    {
                        return Some(found);
                    }
                }
                _ => {}
            }
        }
        None
    }

    search(&file.items, name).unwrap_or_else(|| panic!("no fn {name} in that file; did it move?"))
}

/// The named struct's field names, in declaration order.
pub fn struct_fields(file: &syn::File, name: &str) -> Vec<String> {
    pub fn search<'a>(items: &'a [syn::Item], name: &str) -> Option<&'a syn::ItemStruct> {
        for item in items {
            match item {
                syn::Item::Struct(s) if s.ident == name => return Some(s),
                syn::Item::Mod(m) => {
                    if let Some((_, inner)) = &m.content
                        && let Some(found) = search(inner, name)
                    {
                        return Some(found);
                    }
                }
                _ => {}
            }
        }
        None
    }

    let found =
        search(&file.items, name).unwrap_or_else(|| panic!("no struct {name}; did it move?"));

    let fields = named_fields(&found.fields);
    assert!(
        !fields.is_empty(),
        "struct {name} has no named fields, so any lint over them is vacuous"
    );
    fields
}

pub fn named_fields(fields: &syn::Fields) -> Vec<String> {
    match fields {
        syn::Fields::Named(named) => named
            .named
            .iter()
            .filter_map(|f| f.ident.as_ref().map(ToString::to_string))
            .collect(),
        _ => Vec::new(),
    }
}

/// Whether an attribute is `#[serde(flatten)]`.
pub fn is_serde_flatten(attr: &syn::Attribute) -> bool {
    if !attr.path().is_ident("serde") {
        return false;
    }
    let mut flatten = false;
    let _ = attr.parse_nested_meta(|meta| {
        if meta.path.is_ident("flatten") {
            flatten = true;
        }
        Ok(())
    });
    flatten
}

/// A path written as `a::b::c`, joined, so a lint can compare whole paths
/// rather than looking for a substring in the file's text.
pub fn path_string(path: &syn::Path) -> String {
    path.segments
        .iter()
        .map(|s| s.ident.to_string())
        .collect::<Vec<_>>()
        .join("::")
}

/// Every call of the form `Type::new("literal")`, as (path, literal).
#[derive(Default)]
pub struct NewCalls {
    pub calls: Vec<(String, String)>,
}

impl Visit<'_> for NewCalls {
    fn visit_expr_call(&mut self, call: &syn::ExprCall) {
        if let syn::Expr::Path(func) = &*call.func {
            let path = path_string(&func.path);
            if let Some(syn::Expr::Lit(lit)) = call.args.first()
                && let syn::Lit::Str(s) = &lit.lit
            {
                self.calls.push((path, s.value()));
            }
        }
        syn::visit::visit_expr_call(self, call);
    }
}

/// Every method call by name, with its receiver and first argument available
/// for inspection.
pub struct MethodCalls<'a> {
    pub name: &'a str,
    pub found: Vec<syn::ExprMethodCall>,
}

impl<'a> Visit<'_> for MethodCalls<'a> {
    fn visit_expr_method_call(&mut self, call: &syn::ExprMethodCall) {
        if call.method == self.name {
            self.found.push(call.clone());
        }
        syn::visit::visit_expr_method_call(self, call);
    }
}

pub fn method_calls(file: &syn::File, name: &str) -> Vec<syn::ExprMethodCall> {
    let mut visitor = MethodCalls {
        name,
        found: Vec::new(),
    };
    visitor.visit_file(file);
    visitor.found
}

/// The string literals in an array expression, if it is one.
pub fn array_strings(expr: &syn::Expr) -> Vec<String> {
    let syn::Expr::Array(array) = expr else {
        return Vec::new();
    };
    array
        .elems
        .iter()
        .filter_map(|e| match e {
            syn::Expr::Lit(lit) => match &lit.lit {
                syn::Lit::Str(s) => Some(s.value()),
                _ => None,
            },
            _ => None,
        })
        .collect()
}

/// A function signature rendered back to tokens, for asking whether a type
/// appears anywhere in it — argument, return, or nested in a generic.
pub fn signature_mentions(sig: &syn::Signature, ty: &str) -> bool {
    struct Types {
        found: bool,
        want: String,
    }

    impl Visit<'_> for Types {
        fn visit_path(&mut self, path: &syn::Path) {
            if path
                .segments
                .last()
                .is_some_and(|s| s.ident == self.want.as_str())
            {
                self.found = true;
            }
            syn::visit::visit_path(self, path);
        }
    }

    let mut visitor = Types {
        found: false,
        want: ty.to_string(),
    };
    for input in &sig.inputs {
        visitor.visit_fn_arg(input);
    }
    visitor.visit_return_type(&sig.output);
    visitor.found
}
