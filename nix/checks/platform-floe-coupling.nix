# Which floes the platform still knows by name, as a shrink-only baseline.
#
# The floe set is a parameter now: `mkLab` takes one, and a lab can be built
# from a set that contains none of the floes this repo ships. That claim is
# only as true as the platform's independence from particular floe names, and
# the platform is not independent yet. `modules/lab/cluster/secrets.nix` emits
# external-secrets CRDs; `security.nix` switches network-policy dialect on
# cilium; `lib/floe/gateway-options.nix` reads the gateway floe's exports
# while computing an option default, which is why a set with harbor and no
# gateway does not evaluate at all.
#
# Fixing that is a larger project than separating the two trees was. What this
# check buys in the meantime is that the surface is written down, reviewed,
# and cannot quietly grow: every entry is one place a bring-your-own floe set
# has to satisfy, and the list only ever gets shorter.
#
# The counterpart rule for floes is `floe-boundary`, which enforces that a
# floe reads another floe's `exports` and never its internals. The platform
# was never held to it — `floe-boundary` scans only the floe tree — and
# `modules/lab/cluster/out.nix` reading `floes.gateway.internalHostnames`,
# a private option, is what that gap looks like.
{ pkgs, self }:

{
  the-platform-names-no-new-floes =
    pkgs.runCommand "the-platform-names-no-new-floes"
      {
        nativeBuildInputs = [ pkgs.ripgrep ];
      }
      ''
        # Searched from the source root so the paths in the baseline are
        # repo-relative and readable, but written back here: the source is a
        # store path and read-only.
        build=$PWD
        cd ${self}

        # Comments are stripped before matching. Prose that mentions a floe by
        # name is not coupling — a docstring saying "the gateway floe exports
        # this" costs a bring-your-own set nothing, while `config.floes.gateway`
        # costs it everything. Counting both made the baseline grow whenever
        # someone explained the problem, which is the opposite of the
        # incentive this is meant to create.
        #
        # `cluster` and `lab` are the floe set's two scopes rather than floe
        # names, and `nix` is the tail of the filename `floes.nix`.
        find modules lib -name '*.nix' \
             -not -path 'lib/tests/*' -not -path 'lib/floe-checks/*' \
          | sort \
          | while read -r f; do
              # `|| true` because most files match nothing and grep exits 1,
              # which under the builder's `set -e -o pipefail` would abort the
              # whole check on the first unrelated file.
              sed 's/#.*//' "$f" \
                | { grep -o 'floes\.[a-z][a-z0-9-]*' || true; } \
                | sed "s|^floes\.|$f |"
            done \
          | grep -vE ' (cluster|lab|nix)$' \
          | sort -u > "$build/actual.txt"

        cd "$build"

        # Or the pattern has stopped matching and every entry reads as removed.
        if [ ! -s actual.txt ]; then
          echo "found no floe names in the platform at all, which cannot be" >&2
          echo "right while the baseline is non-empty. The pattern in this" >&2
          echo "check has gone blind." >&2
          exit 1
        fi

        added=$(comm -13 ${./platform-floe-coupling.txt} actual.txt)
        removed=$(comm -23 ${./platform-floe-coupling.txt} actual.txt)

        if [ -n "$added" ]; then
          echo "the platform now names floes it did not before:" >&2
          printf '%s\n' "$added" | sed 's/^/  /' >&2
          echo "" >&2
          echo "Platform code that reads a named floe is platform code a" >&2
          echo "bring-your-own floe set has to satisfy. Reach for the" >&2
          echo "capability system instead: a floe claims a capability, and" >&2
          echo "the platform reads cluster.capabilities.resolved.<name>," >&2
          echo "which any floe can provide. See lib/contracts/." >&2
          echo "" >&2
          echo "If the coupling is genuinely unavoidable, add the line to" >&2
          echo "nix/checks/platform-floe-coupling.txt with a reason in the" >&2
          echo "commit message." >&2
          exit 1
        fi

        if [ -n "$removed" ]; then
          echo "these couplings are gone, which is the point:" >&2
          printf '%s\n' "$removed" | sed 's/^/  /' >&2
          echo "" >&2
          echo "Delete them from nix/checks/platform-floe-coupling.txt so the" >&2
          echo "baseline keeps shrinking and cannot drift back." >&2
          exit 1
        fi

        wc -l < actual.txt > $out
      '';
}
