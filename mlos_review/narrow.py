"""The bundle narrowed to the levels the run's plots show.

mLOS's `plot_periods`, `plot_intake_types`, and `plot_animal_groups` name the
levels a stratifier's plots draw, and the run records them under
`settings.presentation.plot_levels`. The deck shows those levels wherever it
shows the stratifier, so a slide's tables list the levels its figures draw, and
the regression tables follow (mLOS requires the reference level among them, so
every ratio shown has its denominator on the slide).

Narrowing is a matter of display. Every number is the one the run computed over
all levels, and a reading that spans the levels, such as a share of the total,
reads `Bundle.complete()` rather than the narrowed bundle. The opening slide
that describes the sample, and the review workbook, read the full bundle.
"""

from __future__ import annotations

import copy

from mlos_review.bundle import Bundle
from mlos_review.regression import _term_to_stratifier


def plot_levels(bundle: Bundle) -> dict[str, list[str]]:
    """The run's plot selection, by stratifier id; empty when there is none."""
    raw = bundle.value("settings", "presentation", "plot_levels") or {}
    return {stratifier: [str(level) for level in
                         (levels if isinstance(levels, list) else [levels])]
            for stratifier, levels in raw.items()}


def hidden_levels(bundle: Bundle, stratifier: str) -> list[str]:
    """The levels of a stratifier that the run's plot selection leaves out."""
    full = bundle.complete()
    if not full.has("strata", stratifier):
        return []
    selection = plot_levels(full).get(stratifier)
    if selection is None:
        return []
    return [level for level in full.levels(stratifier) if level not in selection]


def _narrow_matrix(node: dict, labels: set[str], shown: list[str]) -> None:
    """Keep the columns of a level-keyed matrix that are shown."""
    columns = node["columns"]
    columns = [columns] if isinstance(columns, str) else list(columns)
    if not columns or not set(columns) <= labels:
        return
    keep = [i for i, column in enumerate(columns) if column in shown]
    node["columns"] = [columns[i] for i in keep]
    node["values"] = [[row[i] for i in keep] if isinstance(row, list) else row
                      for row in node["values"]]


def _narrow_table(node: dict, labels: set[str], shown: list[str]) -> None:
    """Keep the rows of a table keyed by level in its `period_label` column.

    The column is called `period_label` whatever the stratifier is (see
    `blocks._unified_stays`). A table keyed any other way is left whole.
    """
    columns = node["columns"]
    key = columns.get("period_label")
    if key is None:
        return
    key = key if isinstance(key, list) else [key]
    if not set(map(str, key)) <= labels:
        return
    keep = [i for i, level in enumerate(key) if str(level) in shown]
    for name, values in columns.items():
        values = values if isinstance(values, list) else [values]
        columns[name] = [values[i] for i in keep]


def narrowed(bundle: Bundle) -> Bundle:
    """The bundle showing only the levels the run's plots draw.

    Returns the bundle itself when the run has no plot selection. Otherwise, for
    each stratifier with one: its labels, the level columns of its matrices, the
    rows of its per-level tables, and its levels in the regressions' `xlevels`,
    from which every regression table is read. The result remembers the bundle
    it came from, as `complete()`.
    """
    selection = plot_levels(bundle)
    if not selection:
        return bundle
    data = copy.deepcopy(bundle.data)
    terms = _term_to_stratifier(bundle)

    for stratifier, wanted in selection.items():
        node = data.get("strata", {}).get(stratifier)
        if node is None:
            continue
        labels = bundle.levels(stratifier)
        shown = [level for level in labels if level in wanted]
        node["labels"] = shown
        for child in node.values():
            if not isinstance(child, dict):
                continue
            if child.get("type") == "matrix":
                _narrow_matrix(child, set(labels), shown)
            elif child.get("type") == "table":
                _narrow_table(child, set(labels), shown)

        own_terms = [term for term, owner in terms.items() if owner == stratifier]
        holders = [data.get("cox", {}), data.get("weibull", {})]
        holders += list((data.get("cox", {}).get("stratified_variants") or {}).values())
        for holder in holders:
            xlevels = holder.get("xlevels") if isinstance(holder, dict) else None
            if not isinstance(xlevels, dict):
                continue
            for term in own_terms:
                if term in xlevels:
                    levels = xlevels[term]
                    levels = levels if isinstance(levels, list) else [levels]
                    xlevels[term] = [level for level in levels if level in shown]

    return Bundle(data=data, root=bundle.root, full=bundle)
