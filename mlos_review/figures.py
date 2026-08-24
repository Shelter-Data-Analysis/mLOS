"""Figures this package draws itself, and the manifest of what it wrote.

**What belongs here, and what does not.** This package draws
spreadsheet-style figures: bars, columns, dots and lines over the rows of a
table it already holds, the kinds of picture a spreadsheet could draw from the
same cells. It does not draw survival-analysis figures. Kaplan-Meier curves,
Aalen-Johansen cumulative incidence, conditional outcome mixes and in-care
tenure profiles are R's, drawn beside the estimator that produced them and
collected here through the bundle's `outputs` manifest. The line is not about
subject matter but about form. Both figures below are of regression output:
`hazard_ratio_comparison` draws the paired Cox bars of the reserve section,
and `ratio_comparison` the three-estimate dots of the hazard-ratio and
length-of-stay ratio slides. Each is a picture of the table beside it, a row
per level, which is what makes it ours. A curve over a time grid would not be,
whatever it plotted.

The reason is that a survival figure is not a picture of a table. It needs the
estimator's own grid, its risk sets, its step conventions and its interval
construction, and a second implementation of any of those is a second chance
to get them subtly different from the numbers the workbook reports. Redrawing
one here would be re-deriving the analysis with a paintbrush.

**Matching the R figures.** These land on the same slides as figures drawn by
R's base graphics, so they copy that look rather than matplotlib's: a bold
title inside the figure, large type, dashed light-gray gridlines, a boxed
legend, and the same 3:2 shape at the same pixel size, so the layout scales
them identically and a reader does not see two houses' styles on one page.

**Where they go.** Beside the deck, in a directory named after it
(`mlos_deck.pptx` gets `mlos_deck_figures/`), with a
`manifest.json` describing them, in the same spirit as the bundle's `outputs`
manifest: a consumer asks for a kind and a stratifier rather than guessing a
filename. Unlike a deck, a figure here IS overwritten on rebuild, and nothing
is lost by it, since the pptx embeds its images and an archived deck keeps the
ones it was built with.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

import matplotlib
import pandas as pd

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

MANIFEST_NAME = "manifest.json"

# The R runs write 3200 x 2133 at 3:2. Matching both the shape and the pixel
# count is what keeps a slide from scaling two figures by different amounts.
FIGURE_INCHES = (8.0, 5.333)
FIGURE_DPI = 400

# Type sizes chosen against the R output at this pixel size, not against
# matplotlib's defaults, which are set for a 100-dpi screen figure and come out
# unreadably small here.
TITLE_SIZE = 16
LABEL_SIZE = 15
TICK_SIZE = 14
LEGEND_SIZE = 14

# Fraction of figure height reserved above the axes for the title alone. The
# legend also sits up there, but it is a child of the axes and `tight_layout`
# already makes room for it, so counting it here again would open a band of
# white between the title and the legend.
#
# The title is set on the FIGURE rather than the axes: an axes title is centered
# on the axes, which start well right of the figure edge once the level names
# are in the margin, so a title only a little wider than the plot runs off the
# page instead of using the space beside it. The legend goes above the axes
# rather than inside them because no position inside is safe when the bars can
# reach any length, and above rather than below because below is where the axis
# label already is.
HEADER_BAND = 0.05

GRID_COLOR = "#999999"
# The reference level's pair of bars are definitional, not estimates, so they
# are drawn faintly: present, countable, and visibly not a measurement.
REFERENCE_ALPHA = 0.35

# Fallback palette for a bundle that carries none. The deck's own colors come
# from `palette.stratum_colors`, which the R run writes so that everything
# downstream can match its plots.
DEFAULT_COLORS = ("#006400", "#0000FF")


@dataclass(frozen=True)
class FigureRecord:
    """One PNG this package wrote, described the way the bundle describes its own.

    Field names follow the bundle's `outputs` entries (`plot`, `kind`,
    `stratifier`, `description`) so a consumer that already reads R's manifest
    reads this one without a second vocabulary. `plot` is relative to the
    manifest, which is what lets the directory be moved or copied whole.

    There is no `csv` field, and its absence is the point rather than an
    omission: R pairs every plot with a companion CSV because the plot is the
    only other place those per-day grids appear. These figures are drawn from a
    table that the workbook writes out in full, so the companion already
    exists, one file over, in a form that holds every column rather than the
    two the picture uses.
    """

    plot: str
    kind: str
    stratifier: str
    description: str


@dataclass
class FigureSet:
    """The figures one build wrote, and where.

    Rules draw through this rather than calling the drawing functions directly,
    so that recording a figure cannot be forgotten separately from drawing it:
    there is one call, and it does both. `build` makes one, hands it to the
    rules, and writes the manifest at the end.

    Passing this around rather than accumulating into a module-level list is
    what lets two builds run in one process, which the test suite does for
    every fixture.
    """

    directory: Path
    records: list[FigureRecord] = field(default_factory=list)

    def path_for(self, stem: str) -> Path:
        return Path(self.directory) / f"{stem}.png"

    def manifest_path(self) -> Path:
        return Path(self.directory) / MANIFEST_NAME

    def write_manifest(self) -> Path | None:
        """Write `manifest.json`, or nothing when the build drew no figures.

        A manifest of an empty list would be indistinguishable from a manifest
        of a run whose figures all failed, and a directory that does not exist
        is the clearer statement that nothing was drawn.
        """
        if not self.records:
            return None
        path = self.manifest_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(
            {"figures": [asdict(record) for record in self.records]},
            indent=2) + "\n")
        return path

    def hazard_ratio_comparison(self, frame: pd.DataFrame, title: str, stem: str,
                                stratifier: str, description: str,
                                palette: list[str] | None = None) -> Path:
        """Draw the paired hazard-ratio bars and record what was drawn."""
        path = hazard_ratio_comparison(frame, title, self.path_for(stem), palette)
        self.records.append(FigureRecord(
            plot=path.name, kind="hr_comparison",
            stratifier=stratifier, description=description))
        return path

    def ratio_comparison(self, frame: pd.DataFrame, series, title: str, stem: str,
                         stratifier: str, description: str, kind: str,
                         palette: list[str] | None = None,
                         log_scale: bool = False) -> Path:
        """Draw the three-way ratio dots and record what was drawn."""
        path = ratio_comparison(frame, series, title, self.path_for(stem),
                                palette, log_scale)
        self.records.append(FigureRecord(
            plot=path.name, kind=kind,
            stratifier=stratifier, description=description))
        return path


def _series_colors(palette: list[str] | None, wanted: int) -> list[str]:
    """One color per reading, from the run's own stratum palette.

    Note what a color encodes on these two figures, which is not what it
    encodes anywhere else in the deck: here it is a METHOD, and on every KM and
    AJ figure it is a stratum. The legend is what carries that, and it is why
    these figures always draw one.
    """
    colors = list(palette or ())
    while len(colors) < wanted:
        colors.extend(DEFAULT_COLORS)
    return colors[:wanted]


def ratio_comparison(frame: pd.DataFrame, series, title: str, path: str | Path,
                     palette: list[str] | None = None,
                     log_scale: bool = False) -> Path:
    """One dot per reading per level, with its 95% interval, on a ratio axis.

    Dots rather than bars, which is the one place this file departs from the
    figure beside it. A bar has to run from zero for its length to mean the
    value, and three bars per level of a quantity whose interesting range is
    0.7 to 3.8 spends most of the ink on the part between zero and one that
    nobody is reading. A dot states a position and nothing else, which is all a
    ratio has to state, and it leaves the interval as the only line on the row.

    The x axis is linear by default and is the audience's axis, not the
    statistician's: a ratio is multiplicative, so 2 and 0.5 are the same size
    of effect and only a log axis draws them that way, but a log axis is a
    thing to be explained from the podium before anything on it can be read.
    `log_scale` turns it on for a reader who wants the symmetry, and the
    setting that reaches it defaults to off.

    The reference level is drawn at full strength like everything else. It is
    already unmistakable: it sits exactly on the dashed line at 1 and carries no
    whiskers, which says "denominator, not estimate" without costing the reader
    any contrast. Fading it, which the bar version does, put
    the least legible mark on the page under the level an audience most often
    asks about.
    """
    keys = [key for key, _, _ in series]
    colors = _series_colors(palette, len(keys))
    levels = list(frame.index)
    positions = range(len(levels))
    spread = 0.24

    figure, axes = plt.subplots(figsize=FIGURE_INCHES, dpi=FIGURE_DPI)

    # Offsets run top to bottom in the legend's order, which is the order the
    # series are declared: the axis is inverted below, so the first series has
    # to sit at the most negative offset to come out on top.
    offsets = [(index - (len(keys) - 1) / 2) * spread for index in range(len(keys))]
    for key, color, offset in zip(keys, colors, offsets):
        for i in positions:
            estimate = frame[key].iloc[i]
            if pd.isna(estimate):
                continue
            lower = frame[f"{key}_ci_lower"].iloc[i]
            upper = frame[f"{key}_ci_upper"].iloc[i]
            if not pd.isna(lower) and not pd.isna(upper):
                axes.plot([lower, upper], [i + offset] * 2, color=color,
                          linewidth=2.0, solid_capstyle="butt", zorder=3)
                for bound in (lower, upper):
                    axes.plot([bound] * 2,
                              [i + offset - spread / 4, i + offset + spread / 4],
                              color=color, linewidth=2.0, zorder=3)
            axes.plot([estimate], [i + offset], marker="o", markersize=8,
                      color=color, markeredgecolor="white", markeredgewidth=0.8,
                      zorder=4)

    axes.axvline(1.0, color="#111111", linestyle="--", linewidth=1.4, zorder=2)

    axes.set_yticks(list(positions))
    axes.set_yticklabels(levels, fontsize=TICK_SIZE)
    axes.set_ylim(len(levels) - 0.5, -0.5)
    if log_scale:
        axes.set_xscale("log")
    else:
        # Padded around the data rather than anchored at zero, which a dot does
        # not need, but always including 1: the dashed line is what the whole
        # figure is read against and a panel that cropped it would be unreadable.
        values = [frame[f"{key}{suffix}"].iloc[i]
                  for key in keys for suffix in ("", "_ci_lower", "_ci_upper")
                  for i in positions if not pd.isna(frame[f"{key}{suffix}"].iloc[i])]
        low, high = min(values + [1.0]), max(values + [1.0])
        margin = 0.06 * (high - low) or 0.1
        axes.set_xlim(max(0.0, low - margin), high + margin)
    axes.tick_params(axis="x", labelsize=TICK_SIZE)
    axes.grid(axis="x", color=GRID_COLOR, linestyle="--", linewidth=0.8, zorder=0)
    axes.set_axisbelow(True)
    for side in ("top", "right"):
        axes.spines[side].set_visible(False)

    # One row, however many series, so the legend reads left to right in the
    # order the dots sit top to bottom within a level. Three entries at the
    # figure's standard legend size overrun the width, so the size steps down
    # past two rather than the row wrapping: a wrapped legend puts the third
    # method on its own line, where it reads as a different kind of thing.
    axes.legend(handles=[Line2D([], [], color=color, marker="o", markersize=8,
                                linewidth=2.0, label=label)
                         for (_, label, _), color in zip(series, colors)],
                fontsize=LEGEND_SIZE if len(keys) < 3 else LEGEND_SIZE - 2,
                frameon=True, edgecolor="#111111", columnspacing=1.2,
                handletextpad=0.5,
                loc="lower center", bbox_to_anchor=(0.5, 1.01), ncol=len(keys))

    figure.suptitle(title, fontsize=TITLE_SIZE, fontweight="bold")
    figure.tight_layout(rect=(0, 0, 1, 1 - HEADER_BAND))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(path, dpi=FIGURE_DPI)
    plt.close(figure)
    return path


def _method_colors(palette: list[str] | None) -> tuple[str, str]:
    """Colors for the two fits.

    Taken from the run's own stratum palette so the deck stays one family of
    colors. Note what they encode HERE: on this figure the two colors are the
    two regressions, where on every KM and AJ figure a color is a stratum. The
    legend says so, and it is why this figure always draws one even with two
    series a caption could have named.
    """
    if not palette or len(palette) < 2:
        return DEFAULT_COLORS
    return palette[0], palette[1]


def hazard_ratio_comparison(frame: pd.DataFrame, title: str, path: str | Path,
                            palette: list[str] | None = None) -> Path:
    """Paired hazard-ratio bars with 95% intervals, one pair per level.

    `frame` is one stratifier's slice of `regression.comparison`, indexed by
    level in canonical order. Two bars per level, the pooled fit and the
    stratified one, each carrying its own interval as a capped whisker.

    Bars run from zero, which is what a bar demands: the length has to mean the
    value, and a bar chart on a ratio axis broken at 1 would make a hazard
    ratio of 0.9 and one of 1.1 look like opposite extremes of the same size.
    The dashed line at 1 is what carries the above/below reading instead, since
    that, not zero, is the value with meaning for a ratio.

    The reference level is drawn as a pair of 1.0 bars, faint and without
    whiskers. Leaving it out would be tidier and worse: a reader would have no
    way to see which level everything else is a multiple of, and the level
    would silently vanish from a figure that claims to show the stratifier's
    levels. The faintness is what marks it, and it is enough on its own, so
    nothing is added to its tick.
    """
    pooled_color, stratified_color = _method_colors(palette)
    levels = list(frame.index)
    positions = range(len(levels))
    height = 0.38

    figure, axes = plt.subplots(figsize=FIGURE_INCHES, dpi=FIGURE_DPI)

    series = [
        ("hr_pooled", pooled_color, "pooled Cox", height / 2),
        ("hr_stratified", stratified_color, "stratified Cox", -height / 2),
    ]
    # Drawn faint where there is no comparison to be uncertain about, which on
    # a stratifier both fits estimated is exactly the reference level. A level
    # one of the fits dropped lands here too, and faint is the right reading
    # for it as well: it has one bar rather than a pair.
    is_reference = [bool(pd.isna(frame["agreement_margin"].iloc[i])) for i in positions]

    for column, color, _, offset in series:
        values = frame[column]
        for i in positions:
            if pd.isna(values.iloc[i]):
                continue
            axes.barh(i + offset, values.iloc[i], height=height, color=color,
                      alpha=REFERENCE_ALPHA if is_reference[i] else 1.0,
                      edgecolor="white", linewidth=0.6, zorder=3)

    # Whiskers are drawn in one pass per series, after the bars, so a cap is
    # never hidden under the next bar's edge.
    for column, _, _, offset in series:
        for i in positions:
            estimate = frame[column].iloc[i]
            lower = frame[f"{column}_ci_lower"].iloc[i]
            upper = frame[f"{column}_ci_upper"].iloc[i]
            if pd.isna(estimate) or pd.isna(lower) or pd.isna(upper):
                continue
            axes.errorbar(estimate, i + offset,
                          xerr=[[estimate - lower], [upper - estimate]],
                          fmt="none", ecolor="#111111", elinewidth=1.6,
                          capsize=5, capthick=1.6, zorder=4)

    axes.axvline(1.0, color="#111111", linestyle="--", linewidth=1.4, zorder=2)

    # Level names alone: the faint pair of bars already says which one is the
    # reference, and a "(reference)" tag beside it says it a second time while
    # making one tick label twice the length of its neighbors.
    axes.set_yticks(list(positions))
    axes.set_yticklabels(levels, fontsize=TICK_SIZE)
    axes.invert_yaxis()
    axes.set_xlim(left=0)
    axes.set_xlabel("Hazard ratio  (above 1 = leaves sooner)", fontsize=LABEL_SIZE)
    axes.tick_params(axis="x", labelsize=TICK_SIZE)
    axes.grid(axis="x", color=GRID_COLOR, linestyle="--", linewidth=0.8, zorder=0)
    axes.set_axisbelow(True)
    for side in ("top", "right"):
        axes.spines[side].set_visible(False)

    # Proxy handles rather than labeled bars: the bars carry the reference
    # level's transparency, and labeling one of those puts a washed-out swatch
    # in the legend for a series drawn at full strength everywhere else.
    axes.legend(handles=[Patch(facecolor=color, label=label) for _, color, label, _ in series],
                fontsize=LEGEND_SIZE, frameon=True, edgecolor="#111111",
                loc="lower center", bbox_to_anchor=(0.5, 1.01), ncol=len(series))

    figure.suptitle(title, fontsize=TITLE_SIZE, fontweight="bold")
    figure.tight_layout(rect=(0, 0, 1, 1 - HEADER_BAND))
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(path, dpi=FIGURE_DPI)
    plt.close(figure)
    return path
