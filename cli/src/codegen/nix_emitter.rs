use std::collections::BTreeMap;

use pretty::{Arena, DocAllocator, DocBuilder};

use super::types::{K8sResourceType, K8sTypeSet, NixOption, NixType, Submodule};

const NIX_KEYWORDS: &[&str] = &[
    "assert", "else", "if", "in", "inherit", "let", "or", "rec", "then", "with",
];

#[derive(Debug, Clone)]
pub struct EmitterConfig {
    pub max_width: usize,
    pub indent_width: usize,
    pub include_descriptions: bool,
}

impl Default for EmitterConfig {
    fn default() -> Self {
        Self {
            max_width: 100,
            indent_width: 2,
            include_descriptions: true,
        }
    }
}

fn escape_nix_double_quoted(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("${", "\\${")
        .replace('\n', "\\n")
        .replace('\t', "\\t")
}

/// Upstream schema prose often ends a line with a space. Inside `''...''` that
/// survives verbatim, so the generated file carries invisible trailing
/// whitespace that every formatter and reviewer wants gone, and the file stops
/// being byte-stable against its own regeneration.
fn escape_nix_indented(s: &str) -> String {
    s.lines()
        .map(str::trim_end)
        .collect::<Vec<_>>()
        .join("\n")
        .replace("''", "''''")
        .replace("${", "''${")
}

fn quote_attr_name(name: &str) -> String {
    let needs_quoting = NIX_KEYWORDS.contains(&name)
        || name.contains('-')
        || name.contains('.')
        || name.contains('$')
        || name.contains('/')
        || name.contains(' ')
        || name.starts_with(|c: char| c.is_ascii_digit())
        || !name.chars().all(|c| c.is_alphanumeric() || c == '_');
    if needs_quoting {
        format!("\"{}\"", escape_nix_double_quoted(name))
    } else {
        name.to_string()
    }
}

pub struct NixEmitter<'a> {
    arena: &'a Arena<'a>,
    config: EmitterConfig,
}

impl<'a> NixEmitter<'a> {
    pub fn new(arena: &'a Arena<'a>, config: EmitterConfig) -> Self {
        Self { arena, config }
    }

    pub fn emit_k8s_types(&self, type_set: &K8sTypeSet) -> String {
        let doc = self.emit_k8s_types_doc(type_set);
        let mut output = String::new();
        doc.render_fmt(self.config.max_width, &mut output)
            .expect("writing to String cannot fail");
        output
    }

    fn emit_k8s_types_doc(&self, type_set: &K8sTypeSet) -> DocBuilder<'a, Arena<'a>> {
        let header = self.emit_header();
        let let_block = self.emit_let_block(type_set);
        let body = self.emit_k8s_body(type_set);

        header
            .append(self.arena.hardline())
            .append(self.arena.hardline())
            .append(let_block)
            .append(self.arena.hardline())
            .append(body)
    }

    /// No generated-file banner: the repo bans `#` comments in Nix, and the
    /// drift check in `nix/checks/` is what says these files are generated.
    fn emit_header(&self) -> DocBuilder<'a, Arena<'a>> {
        self.arena.text("{ lib }:")
    }

    /// `mkResource` and `mkTypedSubmodule` are imported rather than emitted.
    ///
    /// This file used to carry its own copies, which `index.nix` then shadowed
    /// with the hand-written ones for the CRD path only — so a change to the
    /// constructors took effect for CRD kinds and not for built-in ones. They
    /// are still re-exported because `reservedAttrs` expects to find them here.
    fn emit_let_block(&self, _type_set: &K8sTypeSet) -> DocBuilder<'a, Arena<'a>> {
        self.arena.text(
            r#"let
  inherit (lib) mkOption types;
  inherit (import ../../constructors.nix { inherit lib; }) mkTypedSubmodule mkResource;
in"#,
        )
    }

    fn emit_k8s_body(&self, type_set: &K8sTypeSet) -> DocBuilder<'a, Arena<'a>> {
        let mut grouped: BTreeMap<String, BTreeMap<String, Vec<&K8sResourceType>>> =
            BTreeMap::new();

        for resource in type_set.resources.values() {
            let group = if resource.group.is_empty() || resource.group == "core" {
                "core".to_string()
            } else {
                resource.group.replace(['.', '-'], "_")
            };

            grouped
                .entry(group)
                .or_default()
                .entry(resource.version.clone())
                .or_default()
                .push(resource);
        }

        let mut parts = Vec::new();

        parts.push(self.arena.text("{"));
        parts.push(self.arena.hardline());
        parts.push(
            self.arena
                .text(format!("  version = \"{}\";", type_set.version)),
        );
        parts.push(self.arena.hardline());
        parts.push(self.arena.hardline());
        parts.push(self.arena.text("  inherit mkTypedSubmodule mkResource;"));
        parts.push(self.arena.hardline());
        parts.push(self.arena.hardline());

        for (group, versions) in &grouped {
            parts.push(self.arena.text(format!("  {group} = {{")));
            parts.push(self.arena.hardline());

            for (version, resources) in versions {
                parts.push(self.arena.text(format!("    {version} = {{")));
                parts.push(self.arena.hardline());

                for resource in resources {
                    let resource_doc = self.emit_resource(resource);
                    parts.push(self.arena.text("      "));
                    parts.push(resource_doc);
                    parts.push(self.arena.hardline());
                }

                parts.push(self.arena.text("    };"));
                parts.push(self.arena.hardline());
            }

            parts.push(self.arena.text("  };"));
            parts.push(self.arena.hardline());
            parts.push(self.arena.hardline());
        }

        parts.push(self.arena.text("}"));

        self.arena.concat(parts)
    }

    fn emit_resource(&self, resource: &K8sResourceType) -> DocBuilder<'a, Arena<'a>> {
        let spec_type = match &resource.spec {
            Some(ty) => self.emit_type(ty),
            None => self.arena.text("types.attrs"),
        };

        let mut parts = Vec::new();

        parts.push(
            self.arena
                .text(format!("{} = mkResource {{", resource.kind)),
        );
        parts.push(self.arena.hardline());
        parts.push(self.arena.text(format!(
            "        apiVersion = \"{}\";",
            resource.api_version
        )));
        parts.push(self.arena.hardline());
        parts.push(
            self.arena
                .text(format!("        kind = \"{}\";", resource.kind)),
        );
        parts.push(self.arena.hardline());
        parts.push(self.arena.text("        specType = "));
        parts.push(spec_type);
        parts.push(self.arena.text(";"));
        parts.push(self.arena.hardline());

        if !resource.top_level.is_empty() {
            parts.push(self.arena.text("        topLevel = {"));
            parts.push(self.arena.hardline());
            for (name, option) in &resource.top_level {
                parts.push(self.arena.text("          "));
                parts.push(self.emit_option(name, option));
                parts.push(self.arena.hardline());
            }
            parts.push(self.arena.text("        };"));
            parts.push(self.arena.hardline());
        }

        parts.push(self.arena.text("      };"));

        self.arena.concat(parts)
    }

    pub fn emit_type(&self, ty: &NixType) -> DocBuilder<'a, Arena<'a>> {
        match ty {
            NixType::Str => self.arena.text("types.str"),
            NixType::Int => self.arena.text("types.int"),
            NixType::Float => self.arena.text("types.float"),
            NixType::Bool => self.arena.text("types.bool"),
            NixType::Anything => self.arena.text("types.anything"),
            NixType::Attrs => self.arena.text("types.attrs"),
            NixType::Raw => self.arena.text("types.raw"),
            NixType::Package => self.arena.text("types.package"),
            NixType::Path => self.arena.text("types.path"),

            NixType::NullOr(inner) => {
                let inner_doc = self.emit_type(inner);
                self.arena
                    .text("(types.nullOr ")
                    .append(inner_doc)
                    .append(self.arena.text(")"))
            }

            NixType::ListOf(inner) => {
                let inner_doc = self.emit_type(inner);
                self.arena
                    .text("(types.listOf ")
                    .append(inner_doc)
                    .append(self.arena.text(")"))
            }

            NixType::AttrsOf(inner) => {
                let inner_doc = self.emit_type(inner);
                self.arena
                    .text("(types.attrsOf ")
                    .append(inner_doc)
                    .append(self.arena.text(")"))
            }

            NixType::Enum(values) => {
                let values_str = values
                    .iter()
                    .map(|v| format!("\"{}\"", escape_nix_double_quoted(v)))
                    .collect::<Vec<_>>()
                    .join(" ");
                self.arena.text(format!("(types.enum [ {values_str} ])"))
            }

            NixType::Either(a, b) => {
                let a_doc = self.emit_type(a);
                let b_doc = self.emit_type(b);
                self.arena
                    .text("(types.either ")
                    .append(a_doc)
                    .append(self.arena.text(" "))
                    .append(b_doc)
                    .append(self.arena.text(")"))
            }

            NixType::OneOf(types) => {
                let types_docs: Vec<_> = types.iter().map(|t| self.emit_type(t)).collect();
                let types_list = self.arena.intersperse(types_docs, self.arena.text(" "));
                self.arena
                    .text("(types.oneOf [ ")
                    .append(types_list)
                    .append(self.arena.text(" ])"))
            }

            NixType::Submodule(submodule) => self.emit_submodule(submodule),

            NixType::Ref(_) => self.arena.text("types.attrs"),
        }
    }

    fn emit_submodule(&self, submodule: &Submodule) -> DocBuilder<'a, Arena<'a>> {
        let mut parts = vec![
            self.arena.text("(mkTypedSubmodule {"),
            self.arena.hardline(),
            self.arena.text("  options = {"),
            self.arena.hardline(),
        ];

        for (name, option) in &submodule.options {
            let option_doc = self.emit_option(name, option);
            parts.push(self.arena.text("    "));
            parts.push(option_doc);
            parts.push(self.arena.hardline());
        }

        parts.push(self.arena.text("  };"));

        if let Some(freeform) = &submodule.freeform_type {
            parts.push(self.arena.hardline());
            parts.push(self.arena.text("  freeformType = "));
            parts.push(self.emit_type(freeform));
            parts.push(self.arena.text(";"));
        }

        parts.push(self.arena.hardline());
        parts.push(self.arena.text("})"));

        self.arena.concat(parts)
    }

    /// A required collection drops `emptyValue`.
    ///
    /// The generator says a field is required by emitting it with no default,
    /// which the module system enforces for scalars and not for collections:
    /// nixpkgs gives `listOf` and `attrsOf` an `emptyValue`, so a required list
    /// that nobody wrote reads as `[ ]` instead of failing. Required-ness then
    /// held for `spec.replicas` and not for `spec.sources`, which is harder to
    /// reason about than either extreme.
    fn requires_a_value(option: &NixOption) -> bool {
        option.default.is_none() && matches!(option.ty, NixType::ListOf(_) | NixType::AttrsOf(_))
    }

    fn emit_option(&self, name: &str, option: &NixOption) -> DocBuilder<'a, Arena<'a>> {
        let mut parts = Vec::new();

        let safe_name = quote_attr_name(name);
        parts.push(self.arena.text(format!("{safe_name} = mkOption {{")));
        parts.push(self.arena.hardline());
        parts.push(self.arena.text("      type = "));
        if Self::requires_a_value(option) {
            parts.push(self.arena.text("("));
            parts.push(self.emit_type(&option.ty));
            parts.push(self.arena.text(" // { emptyValue = { }; })"));
        } else {
            parts.push(self.emit_type(&option.ty));
        }
        parts.push(self.arena.text(";"));

        if let Some(default) = &option.default {
            parts.push(self.arena.hardline());
            parts.push(self.arena.text(format!("      default = {default};")));
        }

        if self.config.include_descriptions
            && let Some(desc) = &option.description
        {
            parts.push(self.arena.hardline());
            if desc.contains('\n') {
                let escaped = escape_nix_indented(desc);
                parts.push(self.arena.text(format!(
                    "      description = ''\n        {}\n      '';",
                    escaped.replace('\n', "\n        ")
                )));
            } else {
                let escaped = escape_nix_double_quoted(desc);
                parts.push(
                    self.arena
                        .text(format!("      description = \"{escaped}\";")),
                );
            }
        }

        parts.push(self.arena.hardline());
        parts.push(self.arena.text("    };"));

        self.arena.concat(parts)
    }

    pub fn emit_crd_types(&self, resources: &[K8sResourceType]) -> String {
        let doc = self.emit_crd_types_doc(resources);
        let mut output = String::new();
        doc.render_fmt(self.config.max_width, &mut output)
            .expect("writing to String cannot fail");
        output
    }

    fn emit_crd_types_doc(&self, resources: &[K8sResourceType]) -> DocBuilder<'a, Arena<'a>> {
        let mut parts = Vec::new();

        parts.push(self.arena.text(
            r#"{ lib, k8sTypes }:

let
  inherit (lib) mkOption types;
  inherit (k8sTypes) mkTypedSubmodule mkResource;
in
{"#,
        ));
        parts.push(self.arena.hardline());

        for resource in resources {
            parts.push(self.arena.text("  "));
            parts.push(self.emit_resource(resource));
            parts.push(self.arena.hardline());
            parts.push(self.arena.hardline());
        }

        parts.push(self.arena.text("}"));

        self.arena.concat(parts)
    }

    /// The entry point for the generated tree: `forVersion` to pick a
    /// Kubernetes release, and three ways to look a kind up in it.
    ///
    /// `crd_names` are API groups, one per emitted `crds/<group>.nix`, and the
    /// group is also the attribute name — so the index key, the filename and
    /// the `apiVersion` a floe writes are one string with no mapping between
    /// them.
    ///
    /// Of the three lookups, `coreKinds` answers "is this kind built in" and
    /// `typesByKind` takes every CRD group at once. `typesByKindForGroups`
    /// takes the Kubernetes API plus named groups only: built-in kinds are
    /// global because every cluster runs an apiserver, but a CRD kind exists
    /// only where something installed its CRD, so passing the groups one
    /// cluster establishes is what keeps another cluster's kinds out of scope.
    /// It skips groups it has no types for and leaves refusing them to the
    /// caller, which is the only side that can name the bundle at fault.
    pub fn emit_index(&self, k8s_versions: &[String], crd_names: &[String]) -> String {
        let mut output = String::new();

        output.push_str(
            r#"{ lib }:

let
  k8sVersions = {
"#,
        );

        for version in k8s_versions {
            let safe_version = version.replace(['.', '-'], "_");
            output.push_str(&format!(
                "    \"{safe_version}\" = import ./k8s/{safe_version}.nix {{ inherit lib; }};\n"
            ));
        }

        output.push_str(
            r#"  };

  constructors = import ../constructors.nix { inherit lib; };

  loadCrds =
    versioned:
    let
      k8sTypes = versioned // constructors;
    in
    {
"#,
        );

        for group in crd_names {
            output.push_str(&format!(
                "    \"{group}\" = import ./crds/{group}.nix {{ inherit lib k8sTypes; }};\n"
            ));
        }

        output.push_str(Self::INDEX_LOOKUPS);

        output
    }

    /// The part of `index.nix` that does not depend on what was generated:
    /// picking a release, and the three ways to look a kind up in it. Separate
    /// from `emit_index` because only the lists above it vary.
    const INDEX_LOOKUPS: &'static str = r#"  };

  reservedAttrs = [ "version" "mkTypedSubmodule" "mkResource" "crds" ];

  forVersion = version:
    let
      safeVersion = builtins.replaceStrings ["."] ["_"] version;
      k8sTypes = k8sVersions.${safeVersion} or (throw "Unknown K8s version: ${version}");
    in
    k8sTypes // {
      crds = loadCrds k8sTypes;
    };

  flattenTypes = versionedTypes:
    let
      inherit (builtins) isAttrs attrNames foldl' elem;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      flattenGroup = group:
        let apiVersions = builtins.sort (a: b: a < b) (attrNames group);
        in foldl' (acc: av: acc // group.${av}) {} apiVersions;
      k8sFlat = foldl' (acc: gn: acc // flattenGroup groups.${gn}) {} (attrNames groups);
      crdFlat =
        if versionedTypes ? crds then
          foldl' (acc: cn: acc // versionedTypes.crds.${cn}) {} (attrNames versionedTypes.crds)
        else {};
    in
    k8sFlat // crdFlat;

  typesByKind = versionedTypes:
    let
      inherit (builtins) isAttrs attrNames foldl' elem;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addKinds = acc: kinds:
        foldl' (a: k: a // { ${k} = (a.${k} or []) ++ [ kinds.${k} ]; }) acc (attrNames kinds);
      addGroup = acc: group: foldl' (a: av: addKinds a group.${av}) acc (attrNames group);
      k8sByKind = foldl' (acc: gn: addGroup acc groups.${gn}) {} (attrNames groups);
    in
    if versionedTypes ? crds then
      foldl' (acc: cn: addKinds acc versionedTypes.crds.${cn}) k8sByKind
        (attrNames versionedTypes.crds)
    else k8sByKind;

  crdGroups = versionedTypes:
    if versionedTypes ? crds then builtins.attrNames versionedTypes.crds else [];

  typesByKindForGroups = versionedTypes: groups:
    let
      inherit (builtins) isAttrs attrNames foldl' elem filter;
      inherit (lib) filterAttrs;
      k8sGroups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addKinds = acc: kinds:
        foldl' (a: k: a // { ${k} = (a.${k} or []) ++ [ kinds.${k} ]; }) acc (attrNames kinds);
      addGroup = acc: group: foldl' (a: av: addKinds a group.${av}) acc (attrNames group);
      k8sByKind = foldl' (acc: gn: addGroup acc k8sGroups.${gn}) {} (attrNames k8sGroups);
      known = filter (g: (versionedTypes.crds or {}) ? ${g}) groups;
    in
    foldl' (acc: g: addKinds acc versionedTypes.crds.${g}) k8sByKind known;

  coreKinds = versionedTypes:
    let
      inherit (builtins) isAttrs attrNames foldl' elem;
      inherit (lib) filterAttrs;
      groups = filterAttrs (n: v: isAttrs v && !(elem n reservedAttrs)) versionedTypes;
      addGroup = acc: group:
        foldl' (a: av: a // lib.genAttrs (attrNames group.${av}) (_: true)) acc (attrNames group);
    in
    foldl' (acc: gn: addGroup acc groups.${gn}) {} (attrNames groups);

  apiVersionOfType = type: (type.getSubOptions [ ]).apiVersion.default or null;

  apiVersionsForKind = byKind: kind:
    map apiVersionOfType (byKind.${kind} or []);

  resolveResourceType = byKind: apiVersion: kind:
    let
      matching = builtins.filter (t: apiVersionOfType t == apiVersion) (byKind.${kind} or []);
    in
    if matching == [] then null else builtins.head matching;

in {
  inherit k8sVersions loadCrds forVersion flattenTypes;
  inherit typesByKind apiVersionsForKind resolveResourceType coreKinds;
  inherit crdGroups typesByKindForGroups;

  default = forVersion "1.31";
}
"#;
}

pub fn emit_k8s_types(type_set: &K8sTypeSet, config: EmitterConfig) -> String {
    let arena = Arena::new();
    let emitter = NixEmitter::new(&arena, config);
    emitter.emit_k8s_types(type_set)
}

pub fn emit_crd_types(resources: &[K8sResourceType], config: EmitterConfig) -> String {
    let arena = Arena::new();
    let emitter = NixEmitter::new(&arena, config);
    emitter.emit_crd_types(resources)
}

pub fn emit_index(k8s_versions: &[String], crd_names: &[String], _config: EmitterConfig) -> String {
    let arena = Arena::new();
    let emitter = NixEmitter::new(&arena, EmitterConfig::default());
    emitter.emit_index(k8s_versions, crd_names)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emit_simple_type() {
        let arena = Arena::new();
        let emitter = NixEmitter::new(&arena, EmitterConfig::default());

        let doc = emitter.emit_type(&NixType::Str);
        let mut output = String::new();
        doc.render_fmt(80, &mut output).unwrap();

        assert_eq!(output, "types.str");
    }

    #[test]
    fn test_emit_list_type() {
        let arena = Arena::new();
        let emitter = NixEmitter::new(&arena, EmitterConfig::default());

        let doc = emitter.emit_type(&NixType::ListOf(Box::new(NixType::Str)));
        let mut output = String::new();
        doc.render_fmt(80, &mut output).unwrap();

        assert_eq!(output, "(types.listOf types.str)");
    }

    #[test]
    fn test_quote_nix_keywords() {
        assert_eq!(quote_attr_name("inherit"), "\"inherit\"");
        assert_eq!(quote_attr_name("if"), "\"if\"");
        assert_eq!(quote_attr_name("name"), "name");
        assert_eq!(quote_attr_name("my-field"), "\"my-field\"");
    }

    #[test]
    fn test_escape_nix_indented() {
        assert_eq!(escape_nix_indented("hello"), "hello");
        assert_eq!(escape_nix_indented("it''s"), "it''''s");
        assert_eq!(escape_nix_indented("${foo}"), "''${foo}");
        assert_eq!(escape_nix_indented("a \nb\t\nc"), "a\nb\nc");
    }

    #[test]
    fn test_ref_falls_back_to_attrs() {
        let arena = Arena::new();
        let emitter = NixEmitter::new(&arena, EmitterConfig::default());

        let doc = emitter.emit_type(&NixType::Ref("some.definition".to_string()));
        let mut output = String::new();
        doc.render_fmt(80, &mut output).unwrap();

        assert_eq!(output, "types.attrs");
    }

    fn a_resource() -> K8sResourceType {
        let mut r = K8sResourceType::new(
            "postgresql.cnpg.io".to_string(),
            "v1".to_string(),
            "Cluster".to_string(),
        );
        r.description = Some("A PostgreSQL cluster managed by CloudNativePG.".to_string());
        r
    }

    #[test]
    fn generated_k8s_types_carry_no_nix_comment() {
        let mut set = K8sTypeSet::new("1.31");
        set.add_resource(a_resource());
        let out = emit_k8s_types(&set, EmitterConfig::default());
        assert!(!out.contains('#'), "{out}");
    }

    #[test]
    fn generated_crd_types_carry_no_nix_comment() {
        let out = emit_crd_types(&[a_resource()], EmitterConfig::default());
        assert!(!out.contains('#'), "{out}");
    }

    #[test]
    fn the_generated_index_carries_no_nix_comment() {
        let out = emit_index(
            &["1.31".to_string()],
            &["cnpg".to_string()],
            EmitterConfig::default(),
        );
        assert!(!out.contains('#'), "{out}");
    }

    #[test]
    fn the_generated_index_loads_crds_through_constructors() {
        let out = emit_index(
            &["1.31".to_string()],
            &["postgresql.cnpg.io".to_string()],
            EmitterConfig::default(),
        );
        assert!(
            out.contains("import ../constructors.nix { inherit lib; }"),
            "{out}"
        );
        assert!(out.contains("versioned // constructors"), "{out}");
        assert!(
            out.contains(
                "\"postgresql.cnpg.io\" = import ./crds/postgresql.cnpg.io.nix \
                 { inherit lib k8sTypes; };"
            ),
            "{out}"
        );
    }

    #[test]
    fn a_required_collection_is_emitted_without_an_empty_value() {
        let arena = Arena::new();
        let e = NixEmitter::new(&arena, EmitterConfig::default());

        let required_list = NixOption::new(NixType::ListOf(Box::new(NixType::Str)));
        let out = e.emit_option("verbs", &required_list);
        let mut s = String::new();
        out.render_fmt(100, &mut s).unwrap();
        assert!(s.contains("emptyValue = { }"), "{s}");

        let mut optional_list = NixOption::new(NixType::ListOf(Box::new(NixType::Str)));
        optional_list.default = Some("null".to_string());
        let out = e.emit_option("verbs", &optional_list);
        let mut s = String::new();
        out.render_fmt(100, &mut s).unwrap();
        assert!(!s.contains("emptyValue"), "{s}");

        let required_scalar = NixOption::new(NixType::Str);
        let out = e.emit_option("name", &required_scalar);
        let mut s = String::new();
        out.render_fmt(100, &mut s).unwrap();
        assert!(!s.contains("emptyValue"), "{s}");
    }

    #[test]
    fn a_crd_group_is_keyed_by_its_api_group_verbatim() {
        let out = emit_index(
            &["1.31".to_string()],
            &["gateway.networking.k8s.io".to_string()],
            EmitterConfig::default(),
        );
        assert!(out.contains("\"gateway.networking.k8s.io\""), "{out}");
        assert!(!out.contains("gateway_networking_k8s_io"), "{out}");
    }

    #[test]
    fn the_index_offers_group_scoped_resolution() {
        let out = emit_index(&["1.31".to_string()], &[], EmitterConfig::default());
        assert!(
            out.contains("typesByKindForGroups = versionedTypes: groups:"),
            "{out}"
        );
        assert!(
            out.contains("inherit crdGroups typesByKindForGroups;"),
            "{out}"
        );
    }
}
