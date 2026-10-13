use std::path::PathBuf;

use anyhow::{Context as _, Result};

#[derive(Debug, Clone)]
pub struct FlakeRef {
    pub uri: String,
    pub fragment: Option<String>,
}

impl FlakeRef {
    pub fn parse(input: &str) -> Result<Self> {
        let (uri_part, fragment) = match input.split_once('#') {
            Some((uri, frag)) => (uri, Some(frag.to_string())),
            None => (input, None),
        };

        let uri = if Self::is_remote(uri_part) {
            uri_part.to_string()
        } else {
            let path = PathBuf::from(uri_part)
                .canonicalize()
                .with_context(|| format!("Failed to resolve flake path: {uri_part}"))?;
            path.display().to_string()
        };

        Ok(Self { uri, fragment })
    }

    /// Where a file written beside this flake would go, or None when there is
    /// nowhere sensible.
    ///
    /// `path:/abs/dir` is a local directory that `is_remote` calls remote,
    /// because the two questions differ: that one decides whether to
    /// canonicalise, this one decides whether a write has a destination.
    pub fn local_dir(&self) -> Option<PathBuf> {
        if let Some(rest) = self.uri.strip_prefix("path:") {
            return Some(PathBuf::from(rest));
        }
        if Self::is_remote(&self.uri) {
            return None;
        }
        Some(PathBuf::from(&self.uri))
    }

    fn is_remote(uri: &str) -> bool {
        uri.contains("://")
            || uri.starts_with("github:")
            || uri.starts_with("git+")
            || uri.starts_with("gitlab:")
            || uri.starts_with("sourcehut:")
            || uri.starts_with("path:")
    }
}

/// The macOS VM the operator runs docker in.
///
/// It describes the operator's machine and not any cluster, so it is `cata`'s
/// own configuration rather than a field on a cluster document — where it sat
/// until the document became what a cluster *is*. Environment-driven, because
/// the one person it concerns is the one running the command.
#[derive(Clone, Debug)]
pub struct Colima {
    pub enable: bool,
    pub profile: String,
    pub cpu: u64,
    pub memory: u64,
    pub disk: u64,
}

impl Default for Colima {
    fn default() -> Self {
        Self {
            enable: crate::io::colima::is_macos(),
            profile: "catallaxy".to_string(),
            cpu: 4,
            memory: 8,
            disk: 60,
        }
    }
}

impl Colima {
    /// `CATA_COLIMA_{DISABLE,PROFILE,CPU,MEMORY,DISK}`, each falling back to
    /// the default above.
    pub fn from_env() -> Self {
        let d = Self::default();
        let setting = crate::io::colima::env_setting;
        let num =
            |k: &str, fallback: u64| setting(k).and_then(|v| v.parse().ok()).unwrap_or(fallback);
        Self {
            enable: d.enable && setting("CATA_COLIMA_DISABLE").is_none(),
            profile: setting("CATA_COLIMA_PROFILE").unwrap_or(d.profile),
            cpu: num("CATA_COLIMA_CPU", d.cpu),
            memory: num("CATA_COLIMA_MEMORY", d.memory),
            disk: num("CATA_COLIMA_DISK", d.disk),
        }
    }
}

#[derive(Clone)]
pub struct Context {
    pub flake_ref: FlakeRef,

    pub verbose: bool,

    /// The operator's docker VM, if they are on a machine that needs one.
    pub colima: Colima,

    /// Clusters the operator said may be destroyed and rebuilt to match the
    /// declaration. Empty means none: `lab up` reports the drift and stops.
    pub recreate: Vec<String>,
}

impl Context {
    pub fn new(flake: String, verbose: bool) -> Result<Self> {
        crate::io::fs::home_dir()?;
        let flake_ref = FlakeRef::parse(&flake)?;

        Ok(Self {
            flake_ref,
            verbose,
            colima: Colima::from_env(),
            recreate: Vec::new(),
        })
    }

    /// Whether this cluster may be destroyed and rebuilt.
    pub fn may_recreate(&self, cluster: &str) -> bool {
        self.recreate.iter().any(|c| c == cluster || c == "*")
    }

    pub fn flake_uri(&self) -> &str {
        &self.flake_ref.uri
    }

    pub fn resolve_cluster_name(&self, explicit: Option<&str>) -> Result<String> {
        if let Some(name) = explicit {
            return Ok(name.to_string());
        }

        let lab_name = self.resolve_lab_name(None).context(
            "no cluster given. The flake fragment names the lab, so pass the cluster as an \
             argument or use --flake <ref>#<lab>",
        )?;
        let lab = crate::io::nix::get_lab_spec(self, &lab_name)?;

        match lab.cluster_names.as_slice() {
            [only] => Ok(only.clone()),
            [] => anyhow::bail!("lab '{lab_name}' declares no clusters"),
            names => anyhow::bail!(
                "lab '{lab_name}' has {} clusters, so which one is ambiguous. \
                 Pass one of: {}",
                names.len(),
                names.join(", "),
            ),
        }
    }

    pub fn resolve_lab_name(&self, explicit: Option<&str>) -> Result<String> {
        match explicit.or(self.flake_ref.fragment.as_deref()) {
            Some(name) => {
                let _ = crate::io::trust::activate(name);
                let _ = crate::io::kubeconfig::activate(name);
                Ok(name.to_string())
            }
            None => {
                anyhow::bail!(
                    "lab name required: use --flake <ref>#<lab>, \
                     or pass it as an argument"
                )
            }
        }
    }
}

#[cfg(test)]
mod flake_ref_tests {
    use super::*;

    #[test]
    fn a_remote_flake_has_nowhere_to_write() {
        for uri in [
            "github:owner/repo",
            "git+https://example.test/r",
            "https://example.test/r.tar.gz",
        ] {
            let r = FlakeRef {
                uri: uri.to_string(),
                fragment: None,
            };
            assert!(r.local_dir().is_none(), "{uri} should have no local dir");
        }
    }

    // `is_remote` calls this remote so that parse leaves it uncanonicalised.
    // It is still a directory a file can be written into.
    #[test]
    fn a_path_flake_is_somewhere_despite_counting_as_remote() {
        let r = FlakeRef {
            uri: "path:/srv/lab".to_string(),
            fragment: None,
        };
        assert_eq!(r.local_dir(), Some(PathBuf::from("/srv/lab")));
    }

    #[test]
    fn a_plain_directory_is_itself() {
        let r = FlakeRef {
            uri: "/srv/lab".to_string(),
            fragment: None,
        };
        assert_eq!(r.local_dir(), Some(PathBuf::from("/srv/lab")));
    }
}

#[cfg(test)]
mod recreate_tests {
    use super::*;

    fn ctx(recreate: &[&str]) -> Context {
        Context {
            flake_ref: FlakeRef::parse(".").unwrap(),
            verbose: false,
            colima: Colima::default(),
            recreate: recreate.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn nothing_may_be_recreated_by_default() {
        assert!(!ctx(&[]).may_recreate("core"));
    }

    #[test]
    fn only_the_named_cluster_may_be_recreated() {
        let c = ctx(&["core"]);
        assert!(c.may_recreate("core"));
        assert!(!c.may_recreate("obs"), "a sibling must not be swept up");
    }

    #[test]
    fn several_clusters_can_be_named() {
        let c = ctx(&["core", "obs"]);
        assert!(c.may_recreate("core"));
        assert!(c.may_recreate("obs"));
        assert!(!c.may_recreate("edge"));
    }

    #[test]
    fn a_star_covers_every_cluster() {
        assert!(ctx(&["*"]).may_recreate("anything"));
    }
}
