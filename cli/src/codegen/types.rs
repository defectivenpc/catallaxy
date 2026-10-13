use std::collections::BTreeMap;

#[derive(Debug, Clone)]
pub enum NixType {
    Str,
    Int,
    Float,
    Bool,
    NullOr(Box<NixType>),
    ListOf(Box<NixType>),
    AttrsOf(Box<NixType>),
    Enum(Vec<String>),
    Either(Box<NixType>, Box<NixType>),
    OneOf(Vec<NixType>),
    Submodule(Submodule),
    Ref(String),
    Anything,
    Attrs,
    Raw,
    Package,
    Path,
}

impl NixType {
    pub fn nullable(self) -> Self {
        match self {
            NixType::NullOr(_) => self,
            other => NixType::NullOr(Box::new(other)),
        }
    }

    pub fn list(inner: NixType) -> Self {
        NixType::ListOf(Box::new(inner))
    }
}

#[derive(Debug, Clone)]
pub struct Submodule {
    pub options: BTreeMap<String, NixOption>,
    pub freeform_type: Option<Box<NixType>>,
    pub description: Option<String>,
}

impl Submodule {
    pub fn new() -> Self {
        Self {
            options: BTreeMap::new(),
            freeform_type: None,
            description: None,
        }
    }
}

impl Default for Submodule {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone)]
pub struct NixOption {
    pub ty: NixType,
    pub default: Option<String>,
    pub description: Option<String>,
    pub example: Option<String>,
    pub visible: bool,
    pub internal: bool,
    pub read_only: bool,
}

impl NixOption {
    pub fn new(ty: NixType) -> Self {
        Self {
            ty,
            default: None,
            description: None,
            example: None,
            visible: true,
            internal: false,
            read_only: false,
        }
    }

    pub fn internal(mut self) -> Self {
        self.internal = true;
        self.visible = false;
        self
    }
}

#[derive(Debug, Clone)]
pub struct K8sResourceType {
    pub group: String,
    pub version: String,
    pub kind: String,
    pub api_version: String,
    pub spec: Option<NixType>,
    pub status: Option<NixType>,

    /// The object's other authorable top-level fields: `Role.rules`,
    /// `Secret.type`, `RoleBinding.roleRef`. Converting `spec` alone left the
    /// whole top level freeform, so a misspelled `metadataa` was a new key
    /// rather than an error — the class we close inside `spec`, one level up.
    ///
    /// `status` is deliberately absent. It is the controller's, a floe writes
    /// desired state, and leaving it undeclared is what makes writing one a
    /// refusal rather than a silently discarded field.
    pub top_level: BTreeMap<String, NixOption>,

    pub description: Option<String>,
    pub namespaced: bool,
}

/// Top-level keys a resource's generated type does not take from the schema:
/// three the constructor declares itself, and `status`.
pub const NOT_TOP_LEVEL: &[&str] = &["apiVersion", "kind", "metadata", "spec", "status"];

impl K8sResourceType {
    pub fn new(group: String, version: String, kind: String) -> Self {
        let api_version = if group.is_empty() || group == "core" {
            version.clone()
        } else {
            format!("{group}/{version}")
        };

        Self {
            group,
            version,
            kind,
            api_version,
            spec: None,
            status: None,
            top_level: BTreeMap::new(),
            description: None,
            namespaced: true,
        }
    }
}

#[derive(Debug, Clone)]
pub struct K8sTypeSet {
    pub version: String,
    pub resources: BTreeMap<String, K8sResourceType>,
    pub definitions: BTreeMap<String, NixType>,
}

impl K8sTypeSet {
    pub fn new(version: impl Into<String>) -> Self {
        Self {
            version: version.into(),
            resources: BTreeMap::new(),
            definitions: BTreeMap::new(),
        }
    }

    pub fn add_resource(&mut self, resource: K8sResourceType) {
        let key = format!("{}/{}/{}", resource.group, resource.version, resource.kind);
        self.resources.insert(key, resource);
    }

    pub fn add_definition(&mut self, name: impl Into<String>, ty: NixType) {
        self.definitions.insert(name.into(), ty);
    }
}

#[derive(Debug, Clone)]
pub struct GeneratorOptions {
    /// Make *every* object schema freeform, not only the ones declaring
    /// `x-kubernetes-preserve-unknown-fields`.
    ///
    /// Off by default. A freeform schema cannot tell a misspelling from a
    /// field it has not described, so `configMapp` becomes a new key rather
    /// than an error and reaches the apiserver, which prunes it silently under
    /// a structural schema. Kubernetes already marks the schemas that are
    /// genuinely open, and `convert` honours that marking either way.
    pub freeform_type: bool,
    pub include_descriptions: bool,
    pub exclude_groups: Vec<String>,
}

impl Default for GeneratorOptions {
    fn default() -> Self {
        Self {
            freeform_type: false,
            include_descriptions: true,
            exclude_groups: vec!["internal.apiserver.k8s.io".to_string()],
        }
    }
}
