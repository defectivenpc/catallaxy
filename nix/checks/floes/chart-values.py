"""Every chart value a floe writes does something.

`helmCharts.*.values` is untyped, and Helm ignores a value it has no setting
for — so a value left behind by a chart upgrade keeps rendering the chart on
defaults and nothing objects. Four of those were live when this was written.

The test is empirical, not a reading of the templates: render the chart, render
it again without one value, and compare. Static detection was tried four ways
first and each leaked — chart `values.yaml` files omit settings they honour,
free-form sections pass arbitrary keys through, Helm reads
`Chart.yaml` dependency conditions itself, and `index .Values "grafana.ini"`
defeats any search for `.Values.<path>`. A render answers all of that at once.

Two findings come out of one measurement, and only one is a fault:

  unread      the path is absent from the chart's defaults and removing it
              changes nothing -> the chart has no such value
  redundant   the path is in the chart's defaults and removing it changes
              nothing -> the floe wrote the chart's own default

Redundant is not reported. Writing a default explicitly pins behaviour against
upstream changing it, which is the opposite of the mistake being hunted.
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def yq(expr, path):
    r = subprocess.run(["yq", "-N", "-o=json", expr, str(path)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout or "null")
    except json.JSONDecodeError:
        return None


def chart_name(chart: Path) -> str:
    return (yq(".name", chart / "Chart.yaml") or chart.name) if (
        chart / "Chart.yaml").exists() else chart.name


def defaults_of(chart: Path) -> dict:
    """The chart's own values.yaml, plus each subchart's under its name.

    A subchart's settings are addressed from the parent as
    `<subchart>.<path>`, and they live in the subchart's values.yaml — so
    without this, every subchart setting a floe writes looks unread.
    """
    base = yq(".", chart / "values.yaml") or {} if (
        chart / "values.yaml").exists() else {}
    if not isinstance(base, dict):
        base = {}
    subs = chart / "charts"
    if subs.is_dir():
        for sub in sorted(subs.iterdir()):
            if (sub / "values.yaml").exists():
                base.setdefault(chart_name(sub), yq(".", sub / "values.yaml") or {})
    return base


def paths(obj, prefix=()):
    """Every key path, as a tuple so a literal dot in a key stays one key."""
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = prefix + (k,)
            out.append(p)
            out += paths(v, p)
    return out


def without(obj, path):
    if not path:
        return obj
    return {
        k: (without(v, path[1:]) if k == path[0] else v)
        for k, v in obj.items()
        if not (k == path[0] and len(path) == 1)
    }


def declares(defaults, path) -> bool:
    cur = defaults
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return False
        cur = cur[key]
    return True


def render(chart, values):
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
        json.dump(values, f)
        f.flush()
        r = subprocess.run(["helm", "template", "r", str(chart), "-f", f.name],
                           capture_output=True, text=True)
    os.unlink(f.name)
    return r.stdout if r.returncode == 0 else None


def main(instantiations_path):
    rows = json.loads(Path(instantiations_path).read_text())

    # One render per distinct chart+values, not per instantiation: the same
    # chart with the same values appears in as many labs as use it.
    work = {}
    for row in rows:
        if row["values"]:
            work.setdefault(
                (row["chart"], json.dumps(row["values"], sort_keys=True)), []
            ).append(row["where"])

    unread, redundant, unrenderable, no_schema = [], 0, [], []
    for (chart, vjson), wheres in sorted(work.items()):
        chart = Path(chart)
        values = json.loads(vjson)
        name = chart_name(chart)

        if not (chart / "values.schema.json").exists():
            no_schema.append(name)

        base = render(chart, values)
        if base is None:
            unrenderable.append(name)
            continue

        defaults = defaults_of(chart)
        for path in paths(values):
            if render(chart, without(values, path)) != base:
                continue
            if declares(defaults, path):
                redundant += 1
            else:
                unread.append((name, ".".join(path), sorted(wheres)[0]))

    for name, path, where in unread:
        print(f"{where}: chart '{name}' has no value '{path}'", file=sys.stderr)

    if unrenderable:
        print(f"\ncharts that would not render: {sorted(set(unrenderable))}",
              file=sys.stderr)

    if unread:
        print(
            "\nHelm ignores a value it has no setting for, so this renders the\n"
            "chart on its defaults and reports success. It is usually a value\n"
            "the chart dropped in an upgrade.\n\n"
            "Remove it, or find the setting the chart does have. Check the\n"
            "comment beside it too: an explanation naming a value that no\n"
            "longer exists is as stale as the value.",
            file=sys.stderr,
        )
        return 1

    # A limit worth stating rather than rediscovering: without a values schema
    # Helm cannot type-check a value it *does* have, so a wrong type on a real
    # setting still renders. Derived, so it corrects itself upstream.
    print(f"{sum(len(v) for v in work.values())} chart instantiations, "
          f"{len(work)} distinct renders, every written value has an effect")
    print(f"{redundant} write the chart's own default, which is not a fault")
    print(f"no values.schema.json, so unchecked types: "
          f"{len(set(no_schema))} of {len({c for c, _ in work})} charts")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
