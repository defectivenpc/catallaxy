# openbao, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  evalWith =
    inputs:
    support.evalFloe {
      name = "openbao";
      inputs = {
        chart = "/dev/null";
      }
      // inputs;
    };

  r = evalWith { };
  values = r.bundles.server.helmCharts.openbao.values;
  init = r.bundles.init;

  jobOf = res: lib.head (lib.attrValues (lib.filterAttrs (_: v: v.kind or "" == "Job") res));
  envOf =
    res: name:
    (lib.head (lib.filter (e: e.name == name) (lib.head (jobOf res).spec.template.spec.containers).env))
    .value;
in
lib.runTests {

  # ---- what it is, and is not ------------------------------------------

  # Not dev mode. Dev is in-memory, so it loses every secret on restart, and
  # its root token is a plain Helm value that renders into the workload —
  # which `secret-material` refuses. A store that forgets is not a store.
  testItStoresToDisk = {
    expr = {
      standalone = values.server.standalone.enabled;
      persisted = values.server.dataStorage.enabled;
    };
    expected = {
      standalone = true;
      persisted = true;
    };
  };

  # The chart's readiness probe is `bao status`, which fails until the vault
  # is initialised *and* unsealed — neither of which has happened when the pod
  # first starts. Left on, nothing becomes Ready and the init Job never gets a
  # server to talk to.
  testTheChartsReadinessProbeIsOff = {
    expr = values.server.readinessProbe.enabled;
    expected = false;
  };

  # So the bundle waits on the workload existing, not on it being Available.
  testReadinessIsExistenceNotHealth = {
    expr = r.bundles.server.ready.kind;
    expected = "exists";
  };

  # ---- the config is HCL, with types -----------------------------------

  # `ui = true`, not `ui = "1"`. The renderer this replaced put every value
  # through `toString` inside quotes, and `false` became the empty string —
  # which HCL accepts and reads as unset.
  testTheConfigKeepsItsTypes = {
    expr = lib.hasInfix "ui = true" values.server.standalone.config;
    expected = true;
  };

  testTheStorageBlockIsLabelled = {
    expr = lib.hasInfix ''storage "file" {'' values.server.standalone.config;
    expected = true;
  };

  # ---- the init Job ----------------------------------------------------

  # Re-rendering the same declaration must produce the same Job name, or every
  # `lab up` re-runs init against a live vault.
  testTheJobIsStableAcrossRenders = {
    expr =
      (jobOf (evalWith { }).bundles.init.resources).metadata.name
      == (jobOf (evalWith { }).bundles.init.resources).metadata.name;
    expected = true;
  };

  # Pinned, because nothing else can say *what* belongs in the re-run
  # trigger. `mkIdempotentJob` hashes what it is handed; whether the right
  # things were handed to it is this floe's decision, and the failure mode is
  # silent — put the base image in `contentInputs` and every image bump
  # re-runs init against a live vault, which is precisely what the hash exists
  # to prevent.
  #
  # A diff here is not necessarily wrong. It means the init Job will run again
  # on the next `lab up`: fine when an input it acts on genuinely changed,
  # and a bug when an implementation detail leaked into the declaration.
  testTheReRunTriggerIsPinned = {
    expr = (jobOf init.resources).metadata.name;
    expected = "openbao-init-9ed0fbad14";
  };

  testChangingTheMountReRunsIt = {
    expr =
      (jobOf init.resources).metadata.name
      == (jobOf (evalWith { kvPath = "other"; }).bundles.init.resources).metadata.name;
    expected = false;
  };

  # Two Roles, because the Job writes into two namespaces: the token has to
  # land where its reader is, and that is not where OpenBao runs.
  testItTakesRbacInBothNamespaces = {
    expr = lib.sort (a: b: a < b) (
      map (r: r.metadata.namespace) (
        lib.attrValues (lib.filterAttrs (_: v: v.kind or "" == "Role") init.resources)
      )
    );
    expected = [
      "external-secrets"
      "openbao"
    ];
  };

  # No KMS on a lab's docker host, so there is nothing to auto-unseal
  # against: the Job generates real unseal keys, uses them inline, and prints
  # them once.
  testItSealsWithShamir = {
    expr = envOf init.resources "SEAL_MODE";
    expected = "shamir";
  };

  # Nothing in the rendered manifests reads it — the Job mints it — so the
  # cluster's coherence check has to be told it will exist.
  testItDeclaresTheTokenItMints = {
    expr = init.secrets;
    expected = [ "external-secrets/openbao-token" ];
  };

  # ---- the signature ---------------------------------------------------

  # A consumer's token is only good once the Job has written it, and the Job
  # cannot run until the server answers. Naming both is what orders a consumer
  # after the whole of it without naming either bundle.
  testTheProvideIsBackedByBothHalves = {
    expr = lib.sort (a: b: a < b) r.component.backs.vault;
    expected = [
      "init"
      "server"
    ];
  };

  # The honest half of the signature. A shamir-sealed vault does not come back
  # from a restart on its own, and a consumer that waits for it to answer
  # waits forever rather than failing.
  testItSaysItDoesNotAutoUnseal = {
    expr = r.provides.vault.autoUnseals;
    expected = false;
  };

  testTheProvideNamesTheTokenSecret = {
    expr = r.provides.vault.tokenSecret;
    expected = {
      namespace = "external-secrets";
      name = "openbao-token";
      key = "token";
    };
  };

  # Keeping the token beside the server it opens defeats the scoping.
  testATokenInTheServersOwnNamespaceIsRefused = {
    expr = map (a: a.assertion) (evalWith { secretNamespace = "openbao"; }).component.assertions;
    expected = [ false ];
  };

  testTheDefaultPlacementIsAccepted = {
    expr = map (a: a.assertion) r.component.assertions;
    expected = [ true ];
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
