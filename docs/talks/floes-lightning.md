---
title: "Floes — typed holes for infrastructure components"
theme: night
highlightTheme: monokai
revealOptions:
  transition: none
  hash: true
  slideNumber: "c/t"
---

<style>
:root {
  --ink: #e9edf2;
  --muted: #8592a3;
  --sig: #f0b429;
  --ok: #6fd3b8;
  --bad: #ff7b72;
  --box: #171d26;
  --edge: #3b4a5f;
}

.reveal-viewport { background: #0d1117; }
.reveal { color: var(--ink); }
.reveal h1,
.reveal h2 { color: var(--ink); text-transform: none; letter-spacing: -0.015em; }
.reveal h1 { font-size: 2.6em; }
.reveal h2 { font-size: 1.3em; margin-bottom: 0.9em; }
.reveal h3 { font-size: 1em; font-weight: 400; color: var(--ink); line-height: 1.5; margin: 0.6em auto 0; max-width: 24em; }
.reveal ul { display: inline-block; text-align: left; }
.reveal li { margin-bottom: 0.35em; }
.reveal a { color: var(--ok); }
.reveal pre { width: 100%; box-shadow: none; font-size: 0.6em; margin: 0; }
.reveal pre code {
  max-height: none;
  padding: 0.9rem 1.1rem;
  border-radius: 8px;
  background: var(--box);
  border: 1px solid var(--edge);
}

.sub { color: var(--muted); font-size: 0.8em; margin-top: -0.3em; }

.dia { display: flex; align-items: center; justify-content: center; gap: 1.1rem; flex-wrap: wrap; }
.col { display: flex; flex-direction: column; align-items: center; gap: 0.65rem; }

.floe,
.sig,
.hole {
  padding: 0.5em 0.9em;
  border-radius: 8px;
  font-family: monospace;
  font-size: 0.72em;
  line-height: 1.4;
  white-space: nowrap;
}
.floe { background: var(--box); border: 2px solid var(--edge); }
.sig { background: rgba(240, 180, 41, 0.08); border: 3px double var(--sig); color: var(--sig); }
.hole { background: none; border: 2px dashed var(--muted); color: var(--muted); }
.ghost { border-style: dashed; color: var(--muted); background: none; }
.fields { display: block; font-size: 0.72em; color: var(--muted); margin-top: 0.25em; }

.arrow { color: var(--ok); font-size: 1.5em; line-height: 1; }
.arrow.want { color: var(--muted); }
.arrow.bad { color: var(--bad); }

.label { color: var(--muted); font-family: monospace; font-size: 0.6em; letter-spacing: 0.04em; }
.caption { color: var(--muted); font-size: 0.68em; margin: 0.35em 0 0; }
.caption em { color: var(--bad); font-style: normal; }
.caption strong { color: var(--ink); font-weight: normal; }

.tree { border: 2px solid var(--edge); border-radius: 10px; padding: 1.1rem 1.4rem 1.3rem; display: inline-block; }
.tree .label { display: block; margin-bottom: 0.9rem; }

.cols { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1.1rem; align-items: start; }
.cols pre { font-size: 0.46em; }
.who { color: var(--muted); font-family: monospace; font-size: 0.58em; text-align: left; margin-bottom: 0.4rem; }

.sigcode { width: 78%; margin: 0 auto 1.1rem; }
.sigcode pre { font-size: 0.46em; }
.sigcode pre code { border-color: var(--sig); border-width: 2px; background: rgba(240, 180, 41, 0.05); }

.wiring { display: grid; grid-template-columns: repeat(5, auto); justify-content: center; align-items: center; gap: 0.5rem 1.1rem; }
.wiring .label { text-align: center; }
</style>

# Floes

### Typed holes for infrastructure components

<p class="sub">a module system for Nix, borrowed from Haskell's Backpack</p>

---

## <p class="caption">How do we get to a world where we share nix expressions instead of helm charts?</p>

---

## Just wrap Helm in Nix

<div class="cols">
<div>
<div class="who">traefik / values.yaml</div>
<pre><code class="language-yaml">tls:
  issuerRef:
    name: lab-ca</code></pre>
</div>
<div>
<div class="who">cert-manager / values.yaml</div>
<pre><code class="language-yaml">issuer:
  name: lab-ca</code></pre>
</div>
</div>

<p class="caption">Hidden implicit dependencies aren't captured in helm charts</p>

---

## NixOS modules, then?

<div class="tree">
<span class="label">config.* — one option tree, no walls</span>
<div class="dia">
<div class="floe">traefik</div>
<div class="arrow bad">&#8646;</div>
<div class="floe">cert-manager</div>
</div>
</div>

<p class="caption">Each one can read and set anything the other declared.</p>

---

## The hole is the interface

<div class="wiring">
<div class="floe">traefik</div>
<div class="arrow want">&#8594;</div>
<div class="sig">X509_ISSUANCE</div>
<div class="arrow">&#8592;</div>
<div class="floe">cert-manager</div>
<div class="label">requires</div>
<div></div>
<div></div>
<div></div>
<div class="label">provides</div>
</div>

<p class="caption">neither one names the other.</p>
<p class="caption"><strong>the linker matches them at eval.</strong></p>

---

## Keep the module system

- **inside** a floe: NixOS modules, unchanged
- **between** floes: signatures, checked at Nix eval
- exactly one provider, or it is an error

<p class="caption">a floe is a module with an API bolted on the outside.</p>

---

## How it looks

<div class="sigcode">
<div class="who">lib/floe-catallaxy/sigs.nix</div>
<pre><code class="language-nix">X509_ISSUANCE = mkSig {
  name = "X509_ISSUANCE";
  fields.issuerRef =
    T.local (T.record { name = T.str; kind = T.str; });
};</code></pre>
</div>

<div class="cols">
<div>
<div class="who">floes/cluster/cert-manager.nix</div>
<pre><code class="language-nix">provides.issuance = sigs.X509_ISSUANCE;
issuerRef = {
  name = "lab-ca";
  kind = "ClusterIssuer";
};</code></pre>
</div>
<div>
<div class="who">floes/cluster/gateway.nix</div>
<pre><code class="language-nix">requires.issuance = sigs.X509_ISSUANCE;
spec = {
  secretName = certSecret;
  inherit (issuance) issuerRef;
};</code></pre>
</div>
</div>

<p class="caption">This decouples the components and allows for parallel independent work.</p>
