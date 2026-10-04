"""The run's curves read at chosen days, as one workbook sheet.

Each row is one curve, indexed by quantity, factor, and level; each column is a
day already in care. The values are the run's own per-day CSVs read at those
days, found through the outputs manifest, so nothing here computes a number.

The sheet reads the full bundle, like the rest of the workbook: every level,
whatever the run's plot selection shows. A day past the end of a level's curve
is a blank cell.

What the settings name and the run cannot supply refuses the build: a quantity
with no CSV, an outcome, factor, or level the run does not have, or a day off
the grid. What the settings leave to the defaults is simply whatever the run
has.
"""

from __future__ import annotations

import pandas as pd

from mlos_review.blocks import Format, Table
from mlos_review.bundle import BASELINE_STRATIFIER, Bundle
from mlos_review.settings import (CURVE_KINDS, UNIFIED_FACTOR, CurveReadings,
                                  STRATIFIER_KEYS, SettingsError)

# How each quantity is written. Probabilities and shares as percentages, which
# the workbook stores as fractions; days and headcounts to one decimal.
KIND_FORMATS: dict[str, Format] = {
    "km_survival": Format(1, percent=True),
    "km_remaining_los": Format(1),
    "km_in_care_tenure": Format(1, percent=True),
    "km_census_by_tenure": Format(1),
    "aj_cif": Format(1, percent=True),
    "aj_conditional": Format(1, percent=True),
}

# The column prefix of each per-outcome quantity in its whole-sample CSV, which
# holds every outcome side by side rather than one file per outcome.
UNIFIED_PREFIX = {"aj_cif": "cif", "aj_conditional": "conditional"}

FOOTNOTE = ("Columns are days already in care. A blank cell is a curve that "
            "ends before that day.")


def _setting_name(stratifier: str) -> str:
    """The word the settings file uses for a bundle stratifier id."""
    if stratifier == BASELINE_STRATIFIER:
        return UNIFIED_FACTOR
    return next((key for key, value in STRATIFIER_KEYS.items()
                 if value == stratifier), stratifier)


def _csv(bundle: Bundle, kind: str, stratifier: str,
         outcome: str | None) -> pd.DataFrame | None:
    """One manifest entry's CSV, indexed by day; None if the run has none."""
    for entry in bundle.value("outputs", default=[]):
        if (entry.get("kind") == kind and entry.get("stratifier") == stratifier
                and entry.get("outcome") == outcome
                and entry.get("variant", "lines") == "lines"):
            name = entry.get("csv")
            path = bundle.root / name if name else None
            if path is None or not path.exists():
                return None
            # Round-trip parsing, so a cell holds exactly the CSV's value: the
            # fast default parser can be off in the last bit.
            frame = pd.read_csv(path, dtype={"days": str},
                                float_precision="round_trip")
            # The summary rows above the grid are labelled, not numbered.
            frame = frame[frame["days"].str.fullmatch(r"\d+")]
            return frame.set_index(frame["days"].astype(int)).drop(columns="days")
    return None


def _outcomes(bundle: Bundle, kind: str) -> list[str]:
    """The outcomes a per-outcome quantity has in this run, in outcome order."""
    states = [str(s) for s in bundle.value("aj", "outcome_states", default=[])]
    unified = _csv(bundle, kind, BASELINE_STRATIFIER, None)
    found = []
    for outcome in states + ["Any"]:
        in_unified = (unified is not None
                      and f"{UNIFIED_PREFIX[kind]}_{outcome}" in unified.columns)
        stratified = any(entry.get("kind") == kind and entry.get("outcome") == outcome
                         for entry in bundle.value("outputs", default=[]))
        if in_unified or stratified:
            found.append(outcome)
    return found


def _curves(bundle: Bundle, kind: str, outcome: str | None, stratifier: str,
            levels: list[str]) -> pd.DataFrame | None:
    """The chosen levels' curves for one quantity and factor, one column each.

    None when the run wrote no CSV for them.
    """
    if stratifier == BASELINE_STRATIFIER:
        frame = _csv(bundle, kind, stratifier, None)
        if frame is None:
            return None
        if outcome is None:
            # The whole-sample estimate is the first column; the bounds follow.
            column = frame.columns[0]
        else:
            column = f"{UNIFIED_PREFIX[kind]}_{outcome}"
            if column not in frame.columns:
                return None
        return frame[[column]].set_axis(levels, axis=1)
    frame = _csv(bundle, kind, stratifier, outcome)
    if frame is None:
        return None
    return frame.reindex(columns=levels)


def curve_readings_table(bundle: Bundle, spec: CurveReadings | None,
                         vocab) -> Table | None:
    """The readings table, or None when the settings ask for none.

    Raises SettingsError for anything the settings name that this run cannot
    supply.
    """
    if spec is None:
        return None
    bundle = bundle.complete()

    cap = int(bundle.value("settings", "restricted_stay_cap"))
    off_grid = [day for day in spec.days if day >= cap]
    if off_grid:
        raise SettingsError(
            f"curve_readings.days: {', '.join(map(str, off_grid))} is past the "
            f"grid, which runs from 0 to {cap - 1} (restricted_stay_cap is {cap}).")

    present = bundle.stratifiers()
    if spec.factors is None:
        factors = [(s, None) for s in present]
    else:
        factors = list(spec.factors)
        for stratifier, levels in factors:
            name = _setting_name(stratifier)
            if stratifier not in present:
                raise SettingsError(
                    f"curve_readings.factors: this run has no {name}.")
            absent = [lv for lv in levels or [] if lv not in bundle.levels(stratifier)]
            if absent:
                raise SettingsError(
                    f"curve_readings.factors.{name}: this run has no level "
                    f"{', '.join(absent)}. Its levels are "
                    f"{', '.join(bundle.levels(stratifier))}.")
    factors = [(s, list(levels) if levels else bundle.levels(s))
               for s, levels in factors]

    named = spec.quantities is not None
    quantities = list(spec.quantities) if named else [(k, None) for k in CURVE_KINDS]
    curves = []        # (kind, outcome or None)
    for kind, chosen in quantities:
        if not CURVE_KINDS[kind]:
            curves.append((kind, None))
            continue
        available = _outcomes(bundle, kind)
        if named and not available:
            raise SettingsError(
                f"curve_readings.quantities: this run wrote no {kind} CSVs.")
        absent = [o for o in chosen or [] if o not in available]
        if absent:
            raise SettingsError(
                f"curve_readings.quantities.{kind}: this run has no outcome "
                f"{', '.join(absent)}. Its outcomes are {', '.join(available)}.")
        curves.extend((kind, o) for o in (chosen or available))

    rows, formats, filled = [], {}, set()
    for kind, outcome in curves:
        label = vocab.kind(kind).label
        if outcome is not None:
            label = f"{label}, {vocab.outcome_labels.get(outcome, outcome)}"
        formats[label] = KIND_FORMATS[kind]
        for stratifier, levels in factors:
            frame = _curves(bundle, kind, outcome, stratifier, levels)
            if frame is None:
                if named and spec.factors is not None:
                    raise SettingsError(
                        f"curve_readings: this run wrote no {kind} CSV for "
                        f"{_setting_name(stratifier)}"
                        f"{f', outcome {outcome}' if outcome else ''}.")
                continue
            factor = vocab.stratifier(stratifier).label
            filled.add(kind)
            readings = frame.reindex(index=list(spec.days))
            for level in levels:
                rows.append(((label, factor, level), readings[level].tolist()))

    if named:
        empty = [kind for kind, _ in quantities if kind not in filled]
        if empty:
            raise SettingsError(
                f"curve_readings.quantities: this run wrote no CSVs for "
                f"{', '.join(empty)}.")
    if not rows:
        return None
    columns = [str(day) for day in spec.days]
    df = pd.DataFrame([values for _, values in rows], columns=columns,
                      index=pd.MultiIndex.from_tuples(
                          [key for key, _ in rows],
                          names=["quantity", "factor", "level"]))
    return Table(df=df, title="curves read at chosen days",
                 headers={c: c for c in columns}, footnotes=[FOOTNOTE],
                 row_formats=formats, row_format_part=0)
