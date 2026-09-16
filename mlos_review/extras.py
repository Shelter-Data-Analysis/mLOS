"""Slides a variant outline asks for by name with `@extra`, outside the deck.

An extra is built from files a separate tool writes beside a run, not from the
bundle alone, so no standard deck carries one and `@insert` cannot reach one.
Each builder returns its slide, or None with the reason it was skipped: files
that are missing, or that belong to a different run, cost the variant that one
slide and a warning, never the build.
"""

from __future__ import annotations

import re
from collections.abc import Callable

import pandas as pd

from mlos_review.blocks import FORMATS, Table
from mlos_review.bundle import Bundle
from mlos_review.figures import FigureSet
from mlos_review.render_pptx import Slide

# The three marks each side of the HistLOS slide carries, as bundle keys.
LOS_MARKS = ["km_median_los", "km_restricted_mean", "km_p90_los"]

# Where tools/histlos_by_period.R writes by default, relative to the run.
HISTLOS_DIRECTORY = "histlos"

# The fields a HistLOS output shares with the run it claims to belong to, under
# the names both files give them.
PROVENANCE_FIELDS = ("mlos_version", "data_sha256", "settings_sha256")

SHA256 = re.compile(r"^[0-9a-f]{64}$")

HISTLOS_TITLE = "ExitLOS vs HistLOS by Period"


def _mismatch(bundle: Bundle, inputs: pd.DataFrame) -> str:
    """Why these HistLOS outputs are not this run's, or "" when they are.

    A hash is accepted only as a real digest: without the digest package R
    writes a placeholder string, and two placeholders would match.
    """
    for name in PROVENANCE_FIELDS:
        theirs = str(inputs[name].iloc[0]) if name in inputs else ""
        ours = str(bundle.value("run", name, default=""))
        if name.endswith("sha256") and not SHA256.match(ours):
            return f"the run records no usable {name} ({ours!r})"
        if theirs != ours:
            return f"{name} is {theirs!r} there and {ours!r} in the run"
    return ""


def _los_table(df: pd.DataFrame, title: str) -> Table:
    return Table(df=df[LOS_MARKS], title=title,
                 formats={key: FORMATS[key] for key in LOS_MARKS})


def histlos(bundle: Bundle, figures: FigureSet) -> tuple[Slide | None, str]:
    """ExitLOS and HistLOS by period, side by side, each over its own table.

    ExitLOS takes the left, where it sits on the standard LOS-by-period slide.
    """
    source = bundle.root / HISTLOS_DIRECTORY
    plot = source / "histlos_by_period.png"
    summary = source / "histlos_by_period_summary.csv"
    inputs = source / "histlos_inputs.csv"
    missing = [p.name for p in (plot, summary, inputs) if not p.exists()]
    if missing:
        return None, (f"no {', '.join(missing)} in {source}. Run "
                      f"tools/histlos_by_period.R with --results {source}.")

    reason = _mismatch(bundle, pd.read_csv(inputs, dtype=str))
    if reason:
        return None, (f"the HistLOS outputs in {source} are not this run's: "
                      f"{reason}. Rerun tools/histlos_by_period.R.")

    exit_plot = bundle.figure("km_survival", "period")
    if exit_plot is None or not bundle.has("strata", "period", "km"):
        return None, "this run has no Kaplan-Meier curves by period."

    exit_df = bundle.stratum("period", "km")
    hist_df = pd.read_csv(summary, index_col="period", dtype={"period": str})
    if list(hist_df.index) != list(exit_df.index):
        return None, (f"the periods in {summary} ({list(hist_df.index)}) are "
                      f"not the run's ({list(exit_df.index)}).")

    copied = figures.copy(
        plot, "histlos_by_period", kind="histlos", stratifier="period",
        description=f"HistLOS by period, copied from {HISTLOS_DIRECTORY}/ "
                    f"beside the run's results.json, where its CSVs are.")
    return Slide(
        title=HISTLOS_TITLE,
        figures=[exit_plot, copied],
        tables=[_los_table(exit_df, "ExitLOS"), _los_table(hist_df, "HistLOS")],
        notes=["ExitLOS is what mLOS reports: each period sees only the part "
               "of a stay that falls inside it. HistLOS counts the whole stay "
               "of every animal that left during the period, as a shelter's "
               "usual average does."],
        layout="STACKED",
    ), ""


EXTRAS: dict[str, Callable[[Bundle, FigureSet], tuple[Slide | None, str]]] = {
    "HistLOS": histlos,
}
