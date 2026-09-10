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
    pub description: Option<String>,
    pub namespaced: bool,
}

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
    pub freeform_type: bool,
    pub include_descriptions: bool,
    pub exclude_groups: Vec<String>,
}

impl Default for GeneratorOptions {
    fn default() -> Self {
        Self {
            freeform_type: true,
            include_descriptions: true,
            exclude_groups: vec!["internal.apiserver.k8s.io".to_string()],
        }
    }
}
