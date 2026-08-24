"""What to analyze next, read off what this run found.

A recommendation is not a finding. A finding says what the data said; a
recommendation says what to change to learn more, and it NAMES THE KNOB: the
analysis setting to alter, or the data to fix. Without that it is a wish, and a
deck full of wishes is worse than a deck that ends on its findings.

Two rules hold across everything here.

**Silent by default.** A recommendation that fires on every deck stops being
read, the same reason the cap caveat says nothing when the cap does not bind.
Several of these are expected never to fire on a healthy dataset, which is what
makes the section credible when one of them does.

**Every threshold is named and tunable**, and set higher than the threshold of
the caveat that covers the same ground. A caveat is worth making when something
is worth knowing; a recommendation is worth making when something is worth
DOING, and the gap between those is where these constants live.

Each function returns finished sentences, like the finding blocks, and the
deck rule that owns the slide decides which list they go in.
"""

from __future__ import annotations

import pandas as pd

from mlos_review.blocks import (
    WIDE_MARGIN,
    burden_carrier,
    _gap_day,
    _gap_subjects,
    _unified_stays,
    name_levels,
    observation_gaps,
    summary_fields,
)
from mlos_review.bundle import BASELINE_STRATIFIER, Bundle
from mlos_review.salience import spread

# A level has to hold this many stays before narrowing the whole analysis to it
# is worth suggesting. Not a statistical threshold: it is the point at which a
# level can carry the splits the full analysis makes, three periods against
# four intake types, without every cell becoming the small-stratum problem the
# narrowing was meant to escape.
NARROWING_MINIMUM_STAYS = 1000

# What the cap has to be holding back before changing it is worth recommending.
# Ten times CAP_SENSITIVITY_THRESHOLD, which is where the deck starts SAYING the
# cap shapes an answer: half a percent still in care is worth a caveat, and a
# twentieth is worth a settings change.
CAP_RECOMMENDATION_THRESHOLD = 0.05

# How far a level's tail has to run, relative to the shelter's own, before its
# stays look like two populations rather than one. Measured as the ratio of the
# 90th percentile to the median, which is unitless and comparable across
# shelters, and then against the pooled ratio, so a shelter whose stays are
# dispersed throughout is not flagged level by level for being itself.
TAIL_SPREAD_MULTIPLE = 2.0

# How far below 1 a level's OWN Weibull shape has to sit before its tenure
# dependence is worth calling out. Absolute, not relative to another level: the
# recommendation says time already served predicts more time to come, which is a
# claim about k being under 1, so a ratio against whichever level happens to be
# the reference cannot carry it. The level's whole confidence interval has to
# clear this, not just its estimate.
SHAPE_CEILING = 0.85

# And how far below the SHELTER's own shape, as a fraction of the pooled
# adjusted k. The absolute test alone would fire on every level of a shelter
# whose hazard falls throughout, which is a fact about the shelter that the deck
# states once already; this asks the level to stand out from it. The pooled
# ADJUSTED shape is the comparator, not the crude one: the crude shape is low
# partly because levels differ, so testing a level against it would measure it
# against a number its own difference helped produce.
#
# The two bind on different shelters, crossing at a pooled k of
# SHAPE_CEILING / SHAPE_POOLED_CEILING = 0.895. Below that a level must stand
# out from a shelter that already falls; above it, falling at all is the harder
# test.
SHAPE_POOLED_CEILING = 0.95

# The share of stays a level has to hold before any recommendation names it. A
# recommendation asks for work to be done on a population, so a level too thin
# to survive its own resampling is not one to send anybody to. Set well below
# the levels a shelter actually manages by, so it excludes tool artefacts and
# rounding-error categories rather than small but real groups.
RECOMMENDATION_MINIMUM_SHARE = 0.02


def narrowing(bundle: Bundle, vocab) -> list[str]:
    """Rerun the analysis on the level that holds most of the workload.

    Fires where one level owns a majority of the care days still owed and is
    big enough to be analyzed on its own. Those two conditions are the whole
    recommendation: the first says the shelter's workload is really one level's
    story, and the second says the tool can tell that story properly instead of
    inferring it from a level of a pooled model.

    HOW to narrow is half the recommendation and the half that is easy to get
    wrong. Filtering the stratifier's own column leaves that dimension with a
    single level, which spends the run's most interesting split on a constant;
    filtering through `other_filter_column_name` narrows the same rows and
    leaves the column free to carry something else. See `_narrowing_method`.

    And the complement is worth its own run: with the carrier gone, the levels
    it was swamping get to state their own behavior on every other split and
    in both regressions, where at present they are pooled with a level several
    times their size.
    """
    lines = []
    for stratifier in summary_fields(bundle):
        found = burden_carrier(bundle, stratifier)
        if found is None:
            continue
        carrier, owed_share, _ = found
        # The unified counts, so this is stays and not intakes. The two differ
        # by the stays already open when observation began, and it is stays
        # that decide whether a level can carry the analysis on its own:
        # a left-truncated stay is a stay the model uses.
        # `summary_fields` returns only stratifiers that carry these counts.
        stays = _unified_stays(bundle, stratifier)
        if carrier not in stays.index or stays[carrier] < NARROWING_MINIMUM_STAYS:
            continue
        label = vocab.stratifier(stratifier).label
        lines.append(
            f"Rerun narrowed to {carrier}, which holds {owed_share * 100:.0f}% "
            f"of the care days still owed and {stays[carrier]:,.0f} stays of its "
            f"own, enough to carry the same splits the whole analysis makes. "
            f"Every level of {label} that is not "
            f"{carrier} is a different shelter sharing a building, and pooling "
            f"them is what the numbers on these slides had to do."
            + _narrowing_method(bundle, stratifier, carrier, label))
    return lines


# The analysis setting that narrows a run to some levels of a stratifier, and
# the setting that says where the stratifier's column comes from. The filter
# settings are named so a recommendation can tell the reader what to change
# rather than leaving them to find it; the SOURCE settings are what let it
# recommend the better of the two ways to change it.
FILTER_SETTINGS = {
    "intake": "intake_filter",
    "group": "animal_group_filter",
}

# `group` is composed by the tool from `animal_group_columns`, so it can be
# repointed at any attribute of the same animals; `intake` is a column of the
# data and cannot, which is why it is absent here rather than mapped to itself.
SOURCE_COLUMN_SETTINGS = {
    "group": "animal_group_columns",
}


def _narrowing_method(bundle: Bundle, stratifier: str, carrier: str,
                      label: str) -> str:
    """How to run the narrowed analysis, and what to run beside it.

    Filtering on the stratifier's own column is the obvious move and the poor
    one: it narrows the rows AND flattens the dimension, so the rerun has one
    fewer split than the run that suggested it. Filtering the SOURCE column
    through `other_filter_column_name`, which exists to filter a column the
    analysis does not otherwise use, narrows the same rows and leaves the
    dimension free to be pointed at something else about the same animals.

    Falls back to naming the plain filter for a stratifier whose column the
    tool does not compose, where there is nothing to repoint and the flattening
    is unavoidable.
    """
    source_setting = SOURCE_COLUMN_SETTINGS.get(stratifier)
    source_column = (bundle.value("settings", source_setting)
                     if source_setting else None)
    if not source_column or not isinstance(source_column, str):
        setting = FILTER_SETTINGS.get(stratifier)
        return f" Set `{setting}` in the analysis settings." if setting else ""

    return (
        f" To do it without losing the dimension: set "
        f"`other_filter_column_name: {source_column}` with "
        f"`other_filter_pass: [{carrier}]`, which narrows the rows, and then "
        f"point `{source_setting}` at another attribute of the same animals, "
        f"an age band for instance, so {label} goes on splitting the analysis "
        f"instead of collapsing to one level. Filtering "
        f"`{FILTER_SETTINGS.get(stratifier, source_setting)}` instead would "
        f"narrow the same rows and flatten the split at the same time. "
        f"The mirror run is worth as much: the same column as "
        f"`other_filter_cut` keeps everything EXCEPT {carrier}, and the levels "
        f"it was swamping finally state their own behavior on the other "
        f"splits and in both regressions.")


def dimension_not_separating(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """A stratifier whose levels barely differ: redefine it or drop it.

    The salience test already decides this and reports the number on the slide;
    what this adds is what to DO about a dimension that did not separate. For
    periods that is usually the boundaries, which are a setting rather than a
    property of the data: periods are drawn to bracket something, and periods
    that separate nothing are usually periods drawn around the wrong thing.
    """
    found = spread(bundle, stratifier)
    if found is None or found.salient:
        return []
    label = vocab.stratifier(stratifier).label
    line = (f"{label.capitalize()} did not separate stays: {found.deviation:.1f} "
            f"days of spread against a {found.threshold:.1f}-day threshold. ")
    if stratifier == "period":
        return [line + "If the periods are meant to bracket an intervention or "
                       "a policy change, move `period_dates` onto it and rerun; "
                       "if they are calendar convenience, this analysis says "
                       "the calendar is not where this shelter's variation is."]
    return [line + f"Either the levels of {label} are not the distinction that "
                   f"matters here, or a finer one inside them is."]


def unestimable_levels(bundle: Bundle, stratifier: str,
                       comparison: pd.DataFrame, vocab) -> list[str]:
    """Levels too small to pin down: merge them, or fix why they exist.

    The margin is the one the robustness slide already reports, so this fires
    on exactly the levels that slide says it could not establish anything
    about. `_UNKNOWN_` is called out by name where it appears, because it is
    the tool's own marker for a value the data did not carry: a level nobody
    chose, which no modelling decision can repair and a recording change can.
    """
    if comparison.empty or "agreement_margin" not in comparison.columns:
        return []
    if stratifier not in comparison.index.get_level_values("stratifier"):
        return []
    margins = comparison.xs(stratifier, level="stratifier")["agreement_margin"]
    thin = margins[margins >= WIDE_MARGIN].dropna()
    if thin.empty:
        return []

    label = vocab.stratifier(stratifier).label
    levels = [str(level) for level in thin.index]
    widest = thin.max()
    one = len(levels) == 1
    line = (f"{name_levels(levels)} {'holds' if one else 'hold'} too few stays "
            f"to establish anything closer than {widest * 100:.0f}% about "
            f"{'its hazard ratio' if one else 'their hazard ratios'}. Merging "
            f"{'it' if one else 'them'} into a neighboring level would buy "
            f"precision at the cost of a distinction; leaving "
            f"{'it' if one else 'them'} apart keeps the distinction and reports "
            f"it as unresolved.")
    unknown = [level for level in levels if level.strip("_").upper() == "UNKNOWN"]
    if unknown:
        # Worded around the level rather than around the label, so the sentence
        # does not have to choose an article for a stratifier name it cannot
        # see: "a animal group" is the failure this avoids.
        line += (f" {name_levels(unknown)} is not a level anyone chose: it is "
                 f"the tool's marker for stays whose {label} the data did not "
                 f"record, so fixing it at source is worth more than any "
                 f"modelling choice made here.")
    return [line]


def cap_binding(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """Raise the cap where it is holding back a real share of the stays.

    Higher than the threshold at which the deck starts CAVEATING the cap, and
    deliberately: the caveat says a number is a lower bound, which is true at
    half a percent, and this says to change a setting and rerun, which is not
    worth doing until the cap is shaping the answer.
    """
    if not bundle.has("strata", stratifier, "km"):
        return []
    km = bundle.stratum(stratifier, "km")
    if "km_still_in_care_at_cap" not in km.columns:
        return []
    at_cap = km["km_still_in_care_at_cap"].dropna()
    over = at_cap[at_cap > CAP_RECOMMENDATION_THRESHOLD].sort_values(ascending=False)
    if over.empty:
        return []
    cap = bundle.value("settings", "restricted_stay_cap")
    listing = ", ".join(f"{level} {value * 100:.0f}%" for level, value in over.items())
    return [f"Raise `restricted_stay_cap` and rerun. At {cap} days the curve "
            f"still has stays in care for {listing}, so every duration reported "
            f"for those levels is a lower bound rather than an estimate, and "
            f"the days beyond the cap are exactly the ones a plan has to fund."]


def tail_spread(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """A level whose tail runs far past its middle: look for two populations.

    Measured as the 90th percentile over the median, against the same ratio for
    the whole shelter, so what is flagged is a level MORE dispersed than the
    data it came from rather than a shelter that is dispersed throughout.

    A level whose curve never reaches its 90th percentile forms no ratio and is
    left out. That is the cap's business, and `cap_binding` covers it.
    """
    if not (bundle.has("strata", stratifier, "km")
            and bundle.has("strata", BASELINE_STRATIFIER, "km")):
        return []
    km = bundle.stratum(stratifier, "km")
    if not {"km_median_los", "km_p90_los"} <= set(km.columns):
        return []
    pooled = bundle.stratum(BASELINE_STRATIFIER, "km")
    baseline = _ratio(pooled["km_p90_los"].iloc[0], pooled["km_median_los"].iloc[0])
    if baseline is None:
        return []

    flagged = {}
    for level in km.index:
        ratio = _ratio(km.loc[level, "km_p90_los"], km.loc[level, "km_median_los"])
        if ratio is not None and ratio >= TAIL_SPREAD_MULTIPLE * baseline:
            flagged[str(level)] = ratio
    if not flagged:
        return []

    label = vocab.stratifier(stratifier).label
    lines = []
    for level, ratio in sorted(flagged.items(), key=lambda pair: -pair[1]):
        median = km.loc[level, "km_median_los"]
        p90 = km.loc[level, "km_p90_los"]
        # The stratifier is named in the opening clause rather than in a
        # closing one. It used to close with "the {label} level where an
        # average is least informative", which is a superlative, and two
        # flagged levels then produced two bullets each claiming to be the one.
        lines.append(
            f"Look inside {label} {level}. Its 90th percentile stay is "
            f"{p90:.0f} days against a median of {median:.0f}, a spread "
            f"{ratio / baseline:.1f} times the shelter's own, which is the "
            f"shape of two populations pooled rather than one: most leave "
            f"within days and a tail does not. Splitting {level} by outcome "
            f"type, or by whatever distinguishes its long stays, would say "
            f"which animals are in the tail.")
    return lines


def _ratio(p90, median) -> float | None:
    """P90 over median, where both exist and the median is above zero."""
    if p90 is None or median is None:
        return None
    if p90 != p90 or median != median or median <= 0:
        return None
    return float(p90) / float(median)


def falling_hazard(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """Levels whose discharge hazard falls markedly faster than the shelter's.

    The overall shape is below one on any shelter with a heavy tail, and the
    deck already discusses it; a level whose OWN shape sits well below that is a
    different claim, that time in care is more self-reinforcing THERE than
    elsewhere, and that is where a tenure-targeted intervention has something to
    bite on.

    Read off `shape_own`, the level's own k, and not off the shape RATIO. The
    two come apart whenever the reference cell's shape is high: a ratio of 0.80
    against a baseline of 1.3 is a level whose hazard rises with tenure, which
    this rule would have described as falling and sent an intervention after.
    The ratio is also a comparison against whichever level the settings named as
    the reference -- on OC2, moving `intake_type_reference` from STRAY to OTH
    takes RET from 0.80 to 0.92 with the data untouched -- so it cannot support
    a claim about the shelter. Own k against the pooled k can.

    R fits the shape in variants: each holds one stratifier's scale and lets
    the shape vary by the COMBINATIONS of the others (see the Weibull section of
    the methods), so a level can appear in more than one shape table. Where it
    does, the finding has to hold in EVERY variant that estimated it, and the
    number quoted is the least extreme of them. A level the variants disagree
    about is a level whose shape is a property of the design cell rather than of
    itself.

**One crossed variant silences the rule for the whole run.** When the
    shape varies by ONE other dimension, a level's shape ratio is that level
    against its reference, full stop. When it varies by combinations of two, the
    tabulated ratio is that contrast taken INSIDE the reference level of the
    other dimension, and there is no guarantee the reference cell is the large
    or the interesting one. A recommendation is an instruction to go and do
    something, so it may not rest on a number whose scope the sentence carrying
    it cannot state.

    Skipping such a variant on its own would leave the agreement test above
    running on whichever variants happened to stay additive, so a level could be
    recommended off one fit because the fit that would have checked it was set
    aside. Silence for the run is the answer to that, and it matches what
    `weibull_shape_crossing` is: an experimental reading of the shape structure,
    made on a worksheet. The ratios stay there, where an analyst reads them next
    to the model that produced them; they do not reach a slide.

    Read off the fits the run actually made rather than off the setting, since a
    run that asked for crossing and got none of it, every variant having fallen
    back, is carrying the same additive fits as a default run and has the same
    complete evidence to offer.

    **An additive shape formula is read**, whichever road it arrived by:
    `weibull_shape_crossing` left off, which is the default, or a crossing asked
    for and refused because a cell was thin. The two produce the same fit, and a
    rule that read one but not the other would drop a recommendation from the
    deck for turning an experimental setting ON, which is backwards.

    What an additive fit publishes needs one thing said about it. The shape
    RATIO is unconditional there, since additivity is the assumption that a
    level multiplies the shape by the same factor in every cell. `shape_own` is
    that factor applied to the REFERENCE cell's baseline, so the number quoted
    below belongs to a cell even under an additive fit: on OC2 the period
    variant puts LARGE at 0.67, which is LARGE among strays, while the same fit
    puts LARGE at 0.52 in RET and 0.69 in OWNER.

    The agreement requirement above is what carries the sentence past that, and
    it does so because the variants condition on different things. LARGE also
    comes back at 0.65 from the intake variant, where intake type is not a shape
    term at all and the estimate is therefore pooled across intake types. Two
    fits that hold different things fixed, one answer, and the least extreme of
    them quoted. A level that owed its shape to one reference cell would not
    survive that.

    `vocab` is unused and kept anyway: the four per-stratifier recommendation
    rules share one signature and are summed at a single call site in `deck`, so
    the uniformity is worth more than the argument.

    R keeps the per-combination terms out of the shape table, publishing them in
    a `shape_interaction_table` of their own that nothing here reads. That is
    what lets the suffix recovery in `_shape_level` stay safe: a row named for
    the product of two terms ends in one of the two levels and would be read as
    that level's own ratio. Any future rule that wants them has to select the
    main effects itself rather than trust the table it is handed -- and at that
    point it should be reading shapes per cell instead, which is the version
    that would let a crossed variant speak again.
    """
    pooled = bundle.value("weibull", "shape")
    # Both tests at once: the tighter of the two bounds is the one to clear.
    # A bundle without a pooled shape (the fit declined) keeps the absolute test
    # rather than losing the rule.
    ceiling = SHAPE_CEILING
    if pooled is not None and pooled == pooled:
        ceiling = min(ceiling, float(pooled) * SHAPE_POOLED_CEILING)

    variants = bundle.value("weibull", "shape_variants", default={}) or {}
    if any(isinstance(variant, dict)
           and (variant.get("shape_crossing") or {}).get("crossed")
           for variant in variants.values()):
        return []

    shapes: dict[str, list[tuple[float, float]]] = {}
    for variant in variants.values():
        if not isinstance(variant, dict) or "shape_table" not in variant:
            continue
        table = pd.DataFrame(variant["shape_table"]["columns"])
        # Bundles written before own k was published carry the ratio alone.
        # Silence is the right answer there: the ratio cannot be converted
        # without the baseline's covariance, and guessing is what this rewrite
        # exists to stop.
        if "shape_own" not in table or "shape_own_upper" not in table:
            continue
        for _, row in table.iterrows():
            level = _shape_level(str(row["variable"]), stratifier, bundle)
            if level is None:
                continue
            own, upper = row.get("shape_own"), row.get("shape_own_upper")
            if own is None or own != own:
                continue
            shapes.setdefault(level, []).append((float(own), upper))

    # Asked for rather than caught: `falling_hazard` is called for every
    # stratifier the deck draws, not only the ones `summary_fields` vouches for,
    # so a stratifier without these counts is an ordinary answer here. Without
    # them the share test cannot run and every level is let through, which is
    # the pre-existing behavior rather than a silent refusal of everything.
    stays = (_unified_stays(bundle, stratifier)
             if shapes and bundle.has("strata", stratifier, "unified_stay_counts")
             else None)
    total_stays = float(stays.sum()) if stays is not None else 0.0

    flagged = {}
    for level, seen in shapes.items():
        # Too small a level is not refused for being uninteresting -- it is
        # refused because a shape estimated off a handful of stays is a shape
        # the next run may not reproduce, and this rule points at an
        # intervention. Doing this by share rather than by naming particular
        # levels is what keeps the _UNKNOWN_ fill out of the recommendations
        # without the deck holding a special case for it: on a shelter where
        # unknowns are 1% of stays it drops out here, and on one where they are
        # a fifth it is a real population and says so.
        if total_stays > 0 and level in stays.index:
            if float(stays[level]) / total_stays < RECOMMENDATION_MINIMUM_SHARE:
                continue
        # Every variant that estimated it has to agree. A reference level's own
        # k is the baseline, which is an estimate and carries an interval, so
        # unlike the ratio table it is real evidence and is counted: a reference
        # level whose own shape clears the ceiling is as flaggable as any other.
        estimated = [(own, upper) for own, upper in seen
                     if upper is not None and upper == upper]
        if not estimated:
            continue
        # The whole interval below the ceiling, not just the estimate. A point
        # estimate at 0.84 whose interval reaches 0.99 is a level that may sit
        # anywhere from markedly faster-falling to flat, and the sentence below
        # would read the same either way.
        if any(upper >= ceiling for _, upper in estimated):
            continue
        flagged[level] = max(own for own, _ in estimated)
    if not flagged:
        return []

    named = name_levels([f"{level} at {own:.2f}"
                         for level, own in sorted(flagged.items(),
                                                  key=lambda pair: pair[1])])
    against = (f", against {float(pooled):.2f} for the shelter as a whole"
               if pooled is not None and pooled == pooled else "")
    return [f"The discharge hazard falls faster with tenure inside "
            f"{name_levels(sorted(flagged))} than it does across the shelter: "
            f"their own Weibull shapes are {named}{against}, and a shape under "
            f"1 is a hazard that falls as a stay lengthens. Time already served "
            f"predicts more time to come more strongly there than elsewhere, so "
            f"an intervention aimed at animals past a tenure threshold has the "
            f"most to bite on in {name_levels(sorted(flagged))}. The "
            f"census-by-tenure curves say where to set it."]


def _shape_level(term: str, stratifier: str, bundle: Bundle) -> str | None:
    """The level a shape-table term names, when it belongs to this stratifier.

    R writes model terms as the data column and the level run together,
    `animal_groupLARGE`, and the bundle publishes the levels but not the column
    names, so the level is recovered as a suffix rather than by stripping a
    known prefix.

    A term two different levels could both claim is refused rather than
    assigned to the first match. That takes one level ending exactly as another
    does, whether they belong to the same stratifier (LARGE inside XLARGE) or
    to two of them, which is unlikely and not impossible. The cost of refusing
    is one recommendation not made; the cost of guessing is a recommendation
    about the wrong level.
    """
    claimed = None
    for candidate in bundle.stratifiers():
        if candidate == BASELINE_STRATIFIER:
            continue
        try:
            levels = [str(level) for level in bundle.levels(candidate)]
        except KeyError:
            continue
        for level in levels:
            if term.endswith(level) and len(term) > len(level):
                if claimed is not None and claimed != (candidate, level):
                    return None
                claimed = (candidate, level)
    if claimed is None or claimed[0] != stratifier:
        return None
    return claimed[1]


def gap_remedy(bundle: Bundle, vocab) -> list[str]:
    """What to change when a curve the deck plots runs across a hole.

    The three remedies are the User Guide's, said in the order they cost: a
    wider period keeps more animals under observation on every day, a coarser
    stratifier makes each level bigger, and a lower cap stops the analysis
    before the sparse tail where gaps happen. Only for gaps inside the plot
    cap, matching the finding, since a gap no figure reaches is not what a
    settings change is for.
    """
    gaps = observation_gaps(bundle, bundle.stratifiers())
    if gaps.empty:
        return []
    plot_cap = bundle.value("settings", "presentation", "plot_stay_cap")
    if plot_cap is not None:
        gaps = gaps[gaps["gap_start_day"] < plot_cap]
    if gaps.empty:
        return []
    return [f"Close the observation gap in {_gap_subjects(gaps, vocab)} before "
            f"quoting anything past day {_gap_day(gaps['gap_start_day'].min())}. "
            f"Longer periods keep more animals under observation on every day "
            f"(`period_dates`), a coarser stratifier makes each level bigger "
            f"(`animal_group_columns`), and a lower `restricted_stay_cap` stops "
            f"the analysis before the sparse tail where gaps form. The first "
            f"that works is the one that costs the least detail."]
