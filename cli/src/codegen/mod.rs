//! Turning a pinned schema into something Nix can check against.
//!
//! `document` emits the lab document's shape from the Rust types `cata` parses
//! it into. `crd` hands a CRD's `openAPIV3Schema` over as JSON, because Nix has
//! no `fromYAML` and that format change is the only thing generation buys —
//! `lib/kubernetes/schema-to-type.nix` does the converting, for both the
//! Kubernetes API and every CRD, in one vocabulary.
pub mod crd;
pub mod document;
