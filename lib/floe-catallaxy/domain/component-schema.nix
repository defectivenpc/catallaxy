{ lib, floe }:

let
  T = floe.T;

  stepType = import ../../eval/step-type.nix {
    inherit lib;
    planTokens = import ../../plan-tokens.nix { inherit lib; };
    stepKinds = import ../../step-kinds.nix { inherit lib; };
  };

  helmChartSchema = T.named "helmChart" (
    T.record {
      chart = T.str;
      releaseName = T.str;
      namespace = T.k8sName;
      values = T.helmValues;

      replacedHooks = T.attrsOf T.str;
    }
  );

  imageSchema = T.named "image" (
    T.record {
      registry = T.str;
      repository = T.str;
      tag = T.nullOr T.str;
      digest = T.nullOr T.str;
    }
  );

  opsOptionSchema = T.named "opsOption" (
    T.record {
      type = T.enum [
        "str"
        "bool"
        "enum"
      ];
      values = T.listOf T.str;
      required = T.bool;
      default = T.nullOr T.str;
      description = T.str;
    }
  );

  opsArgSchema = T.named "opsArg" (
    T.record {
      name = T.str;
      description = T.str;
      required = T.bool;
      variadic = T.bool;
    }
  );

  opsCommandSchema = T.named "opsCommand" (
    T.record {
      description = T.str;
      command = T.listOf T.str;
      package = T.nullOr T.str;
      options = T.attrsOf opsOptionSchema;
      args = T.listOf opsArgSchema;
    }
  );

  lintCheckSchema = T.named "lintCheck" (
    T.record {
      description = T.str;
      severity = T.enum [
        "error"
        "warning"
      ];
      scope = T.enum [
        "per-file"
        "per-cluster"
      ];
      format = T.enum [
        "exit-code"
        "json"
      ];
      command = T.str;
    }
  );

  verifyCheckSchema = T.named "verifyCheck" (
    T.record {
      description = T.str;
      timeout = T.str;
      expect = T.nullOr T.any;
      reject = T.listOf T.any;
    }
  );

  ownerSchema = T.named "owner" (
    T.record {
      bootstrap = T.nullOr (
        T.enum [
          "install-target"
          "argocd"
        ]
      );
      steady = T.nullOr (
        T.enum [
          "imperative"
          "argocd"
        ]
      );
    }
  );

  bundleSchema = T.named "bundle" (
    T.record {
      resources = T.attrsOf T.any;
      helmCharts = T.attrsOf helmChartSchema;
      yamls = T.listOf T.str;

      createNamespaces = T.listOf T.str;

      crds = T.listOf T.str;

      secrets = T.listOf T.str;

      needsSecrets = T.listOf T.str;

      externalSecrets = T.listOf T.str;

      routedHosts = T.listOf T.str;

      ready = T.nullOr (T.attrsOf T.any);
      awaitRollout = T.bool;

      needs = T.listOf T.str;

      owner = ownerSchema;

      images = T.attrsOf imageSchema;

      ops = T.attrsOf (T.attrsOf opsCommandSchema);
      lint = T.attrsOf lintCheckSchema;
      verify = T.attrsOf verifyCheckSchema;
    }
  );

  driftSchema = T.named "drift" (
    T.record {
      reason = T.str;
      group = T.str;
      kinds = T.listOf T.str;
      managedBy = T.listOf T.str;
    }
  );

  assertionSchema = T.named "assertion" (
    T.record {
      assertion = T.bool;
      message = T.str;
    }
  );

  componentSchema = T.named "component" (
    T.record {
      bundles = T.attrsOf bundleSchema;

      backs = T.attrsOf (T.listOf T.str);

      imagesComplete = T.bool;

      assertions = T.listOf assertionSchema;
      warnings = T.listOf T.str;

      drift = T.listOf driftSchema;
    }
  );

in
{
  inherit
    helmChartSchema
    imageSchema
    opsOptionSchema
    opsArgSchema
    opsCommandSchema
    lintCheckSchema
    verifyCheckSchema
    ownerSchema
    bundleSchema
    driftSchema
    assertionSchema
    componentSchema
    ;
}
