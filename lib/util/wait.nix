{
  lib,
  # The images catallaxy's own probe containers run, as assembled references.
  # These are not any floe's software: they are the kubectl, curl and busybox
  # that every waiter in every lab rides, which until now were three literals
  # nothing could reach. `lab.images.wait` sets them.
  images ? { },
}:

let
  inherit (import ../kubernetes/labels.nix { }) catallaxyManaged;

  inherit (lib)
    concatStringsSep
    optionalAttrs
    optionalString
    hasAttr
    ;

  defaultKubectlImage = images.kubectl or "alpine/k8s:1.32.4";
  defaultCurlImage = images.curl or "curlimages/curl:8.10.1";
  defaultNetworkImage = images.network or "busybox:1.36";

  caBundleVolumeName = "ca-bundle";

  parseDurationSeconds = (import ./duration.nix { inherit lib; }).toSeconds "wait.nix";

  divCeil = a: b: (a + b - 1) / b;

  loopPreamble = ''
    set -eu
    log() { echo "[wait] $*"; }
    trap 'log "ERROR at line $LINENO"' ERR
  '';

  renderCondition =
    p:
    let
      timeout = p.timeout or "5m";
      image = p.image or defaultKubectlImage;
    in
    {
      inherit image;
      command = [
        "kubectl"
        "wait"
        "--for=condition=${p.condition}=True"
        p.resource
        "-n"
        p.namespace
        "--timeout=${timeout}"
      ];
      args = [ ];
    };

  renderJsonpath =
    p:
    let
      timeout = p.timeout or "10m";
      image = p.image or defaultKubectlImage;

      valueSuffix = if p ? value then "=${toString p.value}" else "";
    in
    {
      inherit image;
      command = [
        "sh"
        "-c"
      ];
      args = [
        ''
          ${loopPreamble}
          log "waiting for ${p.namespace}/${p.resource} to be created"
          kubectl wait --for=create ${p.resource} -n ${p.namespace} --timeout=${timeout}
          log "waiting for ${p.jsonpath}${valueSuffix} on ${p.namespace}/${p.resource}"
          kubectl wait --for=jsonpath='${p.jsonpath}'${valueSuffix} ${p.resource} -n ${p.namespace} --timeout=${timeout}
          log "done"
        ''
      ];
    };

  renderExists =
    p:
    let
      timeout = p.timeout or "5m";
      image = p.image or defaultKubectlImage;
    in
    {
      inherit image;
      command = [
        "kubectl"
        "wait"
        "--for=create"
        p.resource
        "-n"
        p.namespace
        "--timeout=${timeout}"
      ];
      args = [ ];
    };

  renderHttp =
    p:
    let
      timeout = p.timeout or "10m";
      interval = p.interval or "15s";
      expectedStatus = toString (p.expectedStatus or 200);
      totalSeconds = parseDurationSeconds timeout;
      intervalSeconds = parseDurationSeconds interval;
      attempts = divCeil totalSeconds intervalSeconds;
      image = p.image or defaultCurlImage;
      caBundleMount = p.caBundleMount or null;

      caFilename = if caBundleMount == null then null else caBundleMount.filename or caBundleMount.key;
      caFlag = optionalString (caBundleMount != null) "--cacert ${caBundleMount.mountPath}/${caFilename}";
      caVolumeMount = optionalAttrs (caBundleMount != null) {
        volumeMounts = [
          {
            name = caBundleVolumeName;
            mountPath = caBundleMount.mountPath;
            readOnly = true;
          }
        ];
      };
    in
    {
      inherit image;
      command = [
        "sh"
        "-c"
      ];
      args = [
        ''
          ${loopPreamble}
          for attempt in $(seq 1 ${toString attempts}); do
            CODE=$(curl -s -o /dev/null -w '%{http_code}' ${caFlag} '${p.url}' 2>/dev/null || echo 000)
            if [ "$CODE" = "${expectedStatus}" ]; then
              log "'${p.url}' returned $CODE after $attempt attempt(s)"
              exit 0
            fi
            log "waiting for '${p.url}' (attempt $attempt/${toString attempts}, got HTTP $CODE)..."
            sleep ${toString intervalSeconds}
          done
          log "'${p.url}' never returned ${expectedStatus} after ${timeout}"
          exit 1
        ''
      ];
    }
    // caVolumeMount;

  renderTcp =
    p:
    let
      timeout = p.timeout or "5m";
      interval = p.interval or "5s";
      totalSeconds = parseDurationSeconds timeout;
      intervalSeconds = parseDurationSeconds interval;
      attempts = divCeil totalSeconds intervalSeconds;
      image = p.image or defaultNetworkImage;
    in
    {
      inherit image;
      command = [
        "sh"
        "-c"
      ];
      args = [
        ''
          ${loopPreamble}
          for attempt in $(seq 1 ${toString attempts}); do
            if nc -z -w 3 '${p.host}' ${toString p.port}; then
              log "'${p.host}:${toString p.port}' reachable after $attempt attempt(s)"
              exit 0
            fi
            log "waiting for '${p.host}:${toString p.port}' (attempt $attempt/${toString attempts})..."
            sleep ${toString intervalSeconds}
          done
          log "'${p.host}:${toString p.port}' never accepted a connection after ${timeout}"
          exit 1
        ''
      ];
    };

  renderDns =
    p:
    let
      timeout = p.timeout or "5m";
      interval = p.interval or "5s";
      totalSeconds = parseDurationSeconds timeout;
      intervalSeconds = parseDurationSeconds interval;
      attempts = divCeil totalSeconds intervalSeconds;
      image = p.image or defaultNetworkImage;
    in
    {
      inherit image;
      command = [
        "sh"
        "-c"
      ];
      args = [
        ''
          ${loopPreamble}
          for attempt in $(seq 1 ${toString attempts}); do
            if nslookup '${p.hostname}' >/dev/null 2>&1; then
              log "'${p.hostname}' resolves after $attempt attempt(s)"
              exit 0
            fi
            log "waiting for '${p.hostname}' to resolve (attempt $attempt/${toString attempts})..."
            sleep ${toString intervalSeconds}
          done
          log "'${p.hostname}' never resolved after ${timeout}"
          exit 1
        ''
      ];
    };

  renderScript =
    p:
    let
      image = p.image or defaultKubectlImage;
    in
    {
      inherit image;
      command = [
        "sh"
        "-c"
      ];
      args = [ p.script ];
    };

  renderers = {
    condition = renderCondition;
    jsonpath = renderJsonpath;
    exists = renderExists;
    http = renderHttp;
    tcp = renderTcp;
    dns = renderDns;
    script = renderScript;
  };

  requiredBy = {
    condition = [
      "resource"
      "condition"
    ];
    jsonpath = [
      "resource"
      "jsonpath"
    ];
    exists = [ "resource" ];
    http = [ "url" ];
    tcp = [
      "host"
      "port"
    ];
    dns = [ "hostname" ];
    script = [ "script" ];
  };

  missingFields =
    probe: builtins.filter (f: (probe.${f} or null) == null) (requiredBy.${probe.kind} or [ ]);

  # Workload kinds that carry no `.status.conditions` at all.
  #
  # `kubectl wait --for=condition=X` on one of these does not fail fast: it
  # polls until the timeout and *then* reports the condition was never met, so
  # a bundle looks like a slow deploy rather than a malformed probe. That cost
  # cilium ten minutes on a cluster it had already brought up successfully,
  # and otel-collector's agent the same before it.
  #
  # A comment on each floe was the first attempt at preventing this, and it
  # did not: the same mistake was made three floes after the comment was
  # written, by the same person. `awaitRollout` is the answer for all of them —
  # for a DaemonSet it asks the better question anyway, since what matters is
  # that every node has the pod rather than that some quorum does.
  # DaemonSets only, and the exclusions matter as much as the entry.
  #
  # A Job *does* carry conditions — `Complete` and `Failed` — and
  # `--for=condition=Complete job/x` is the standard way to wait on one;
  # openbao's init bundle does exactly that. Listing Jobs here was a guess
  # that this check itself caught on the first run, which is the argument for
  # it being a check rather than a comment.
  #
  # StatefulSets and Deployments carry conditions too. A DaemonSet is the odd
  # one: its status is counters (`numberReady`, `desiredNumberScheduled`) and
  # nothing else, so there is no condition for a wait to match.
  conditionlessKinds = [
    "daemonset"
    "daemonsets"
    "ds"
  ];

  # `""` when the probe is fine, otherwise why it is not.
  conditionOnConditionless =
    probe:
    let
      kind = lib.toLower (lib.head (lib.splitString "/" (probe.resource or "")));
    in
    if (probe.kind or "") == "condition" && lib.elem kind conditionlessKinds then
      ''
        probe waits on '${probe.resource}' with `kind = "condition"`, and a ${kind} has no
        `.status.conditions` for one to match.

        `kubectl wait` does not refuse this — it polls until the timeout and
        then reports the condition was never met, so the bundle reads as a slow
        deploy rather than a broken probe.

        Drop the probe and let `awaitRollout` do it.
      ''
    else
      "";

  renderProbe =
    probe:
    let
      missing = missingFields probe;
    in
    if !(probe ? kind) then
      throw "wait.nix: probe missing 'kind' field (attrs: ${toString (builtins.attrNames probe)})"
    else if !(hasAttr probe.kind renderers) then
      throw "wait.nix: unknown probe kind '${probe.kind}' (valid: ${concatStringsSep ", " (builtins.attrNames renderers)})"
    else if missing != [ ] then
      throw ''
        wait.nix: a '${probe.kind}' probe needs ${concatStringsSep " and " missing}, and has ${
          if builtins.length missing == 1 then "none" else "neither"
        }.

        The command would render with an empty argument, which does not fail:
        it waits on a resource whose name is the empty string until the
        timeout, and reports the bundle as never becoming ready.
      ''
    else
      renderers.${probe.kind} probe;

in
{
  inherit
    renderProbe
    caBundleVolumeName
    missingFields
    conditionOnConditionless
    ;

  mkWaitInitContainer =
    {
      probe,
      name ? "wait",
    }:
    let
      rendered = renderProbe probe;
    in
    {
      inherit name;
      inherit (rendered) image command;
    }

    // optionalAttrs (rendered.args or [ ] != [ ]) { inherit (rendered) args; }
    // optionalAttrs (rendered ? volumeMounts) { inherit (rendered) volumeMounts; };

  mkWaitJob =
    {
      probe,
      namespace,
      name,
      serviceAccountName,
      labels ? { },
    }:
    let
      rendered = renderProbe probe;
      commonLabels = catallaxyManaged // labels;
      podSpec = {
        inherit serviceAccountName;
        restartPolicy = "OnFailure";
        containers = [
          (
            {
              name = "wait";
              inherit (rendered) image command;
            }

            // optionalAttrs (rendered.args or [ ] != [ ]) { inherit (rendered) args; }
            // optionalAttrs (rendered ? volumeMounts) { inherit (rendered) volumeMounts; }
          )
        ];
      }
      // optionalAttrs (rendered ? volumes) { inherit (rendered) volumes; };
    in
    {
      ${name} = {
        apiVersion = "batch/v1";
        kind = "Job";
        metadata = {
          inherit name namespace;
          labels = commonLabels;
        };
        spec = {
          backoffLimit = 3;
          template = {
            metadata.labels = commonLabels;
            spec = podSpec;
          };
        };
      };
    };
}
