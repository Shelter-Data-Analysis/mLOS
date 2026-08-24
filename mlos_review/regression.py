"""The Cox regressions as frames, and the one comparison between them.

Two regressions in the bundle answer the same question about each stratifier.
`cox.hr_table` is the pooled fit of §6.1: every stratifier in one linear
predictor, sharing one baseline hazard. `cox.stratified_variants` holds the
per-predictor fits of §6.8: one model per stratifier, carrying that stratifier
alone while the others move into `strata()`, so every combination of their
levels gets its own baseline. Where the two agree, the shared baseline was
costing nothing; where they part, proportional hazards is straining on the
dimensions being adjusted for.

`pooled()` and `stratified()` return that pair, indexed identically so the two
can be subtracted, joined, or laid side by side without alignment work. The
identity is structural rather than arranged: the pooled table carries one row
per level of every qualifying predictor, and each variant carries one row per
level of its own, so the union of the variants is exactly the pooled row set.

**This module computes, within the limit the package sets itself.** The rule
is that the statistics are R's: this side does arithmetic over numbers the
analysis has already computed and published, of the kind a reader could redo in
a spreadsheet from the same cells, and nothing that needs a risk set, a
likelihood, a grid, or a resample. `comparison()` is the most that has been
asked of it and is meant to stay near the edge: it puts two published hazard
ratios and their published intervals over each other and reads off a p-value
and an equivalence margin, which is normal-theory arithmetic on numbers already
in the file. Anything heavier belongs on the other side of results.json, where
the fits are, and where the test suite pins them against generating truth.

Standard errors are recovered from the reported confidence intervals rather
than carried separately, since `se = (log(upper) - log(lower)) / (2 * 1.96)`
inverts exactly what `survival` wrote them from. That keeps the bundle's
interval, the one a reader sees, as the single source of the uncertainty, and
means this module cannot drift from it.

Worked numbers below marked OC1 come from the older Orange County dataset;
the Presentation Guide says how to regenerate that run.
"""

from __future__ import annotations

import math

import pandas as pd

from mlos_review.bundle import Bundle

# The normal quantile `survival` uses for a 95% interval. Named rather than
# written as 1.96 in three places: the confidence level is a property of the
# intervals the bundle already holds, not a choice made here, and recovering a
# standard error with a slightly different constant would put this module's
# arithmetic quietly out of step with the numbers it reads.
Z_95 = 1.959963984540054

# Both regression frames carry these, in this order.
HR_COLUMNS = ["hr", "hr_ci_lower", "hr_ci_upper", "p_value"]

# What `comparison` holds. Every bound keeps the `_ci_lower` / `_ci_upper`
# suffix the vocabulary parses into a role, so each estimate and its interval
# render as one header over three columns, the same as everywhere else.
#
# Both fits' own intervals are carried alongside the ratio's, rather than left
# to be fetched from the two source frames. It costs four columns and makes the
# frame sufficient on its own for everything built from it so far, the slide
# table and the paired-bar figure included, neither of which then has to hold
# three frames in step to draw one stratifier.
COMPARISON_COLUMNS = [
    "hr_pooled",
    "hr_pooled_ci_lower",
    "hr_pooled_ci_upper",
    "hr_stratified",
    "hr_stratified_ci_lower",
    "hr_stratified_ci_upper",
    "hr_ratio",
    "hr_ratio_ci_lower",
    "hr_ratio_ci_upper",
    "p_difference",
    "agreement_margin",
]

INDEX_NAMES = ["stratifier", "level"]


def _se_from_ci(lower: float | None, upper: float | None) -> float | None:
    """The standard error of a log ratio, back out of its 95% interval."""
    if lower is None or upper is None:
        return None
    if not (lower > 0 and upper > 0):
        return None
    return (math.log(upper) - math.log(lower)) / (2 * Z_95)


def _term_to_stratifier(bundle: Bundle) -> dict[str, str]:
    """R model term (`animal_group`) to stratifier id (`group`).

    The bundle states this outright wherever a stratified variant exists: each
    variant knows its own `effect_stratifier` and carries `xlevels` for exactly
    the one term it estimates. Preferring that to any string manipulation
    matters because the two vocabularies genuinely differ (`intake_type` is
    `intake`, `animal_group` is `group`) and the mapping lives in the R
    stratifier registry, which this package cannot see.

    Without variants there is nothing to compare and only `pooled()` can be
    built, so the fallback matches a term's level set against each stratifier's
    labels. Ambiguity there would need two stratifiers with identical level
    sets, which would make the two indistinguishable from here whatever we did;
    such a term is left out rather than guessed at.
    """
    mapping: dict[str, str] = {}
    for variant in (bundle.value("cox", "stratified_variants") or {}).values():
        if not variant.get("has_analysis"):
            continue
        for term in variant.get("xlevels", {}):
            mapping[term] = variant["effect_stratifier"]
    if mapping:
        return mapping

    by_labels: dict[frozenset, list[str]] = {}
    for stratifier in bundle.stratifiers():
        by_labels.setdefault(frozenset(bundle.levels(stratifier)), []).append(stratifier)
    for term, levels in (bundle.value("cox", "xlevels") or {}).items():
        candidates = by_labels.get(frozenset(levels), [])
        if len(candidates) == 1:
            mapping[term] = candidates[0]
    return mapping


def _empty() -> pd.DataFrame:
    """The shape both readers return when there is no regression to report."""
    index = pd.MultiIndex.from_arrays([[], []], names=INDEX_NAMES)
    return pd.DataFrame(columns=HR_COLUMNS, index=index, dtype=float)


def _rows_from(table: pd.DataFrame, xlevels: dict, terms: dict[str, str],
               value: str = "hr") -> pd.DataFrame:
    """One hr_table plus the xlevels that name its rows, as an indexed frame.

    The row names in the bundle are `paste0(term, level)`, which is not
    decomposable by splitting on anything: `animal_groupXL` has no separator,
    and both halves can contain underscores. `xlevels` supplies the two pieces,
    so each name is rebuilt from them and matched, rather than taken apart.

    **Rows come out in the table's own order, not `xlevels`'.** They are not
    the same order and the difference is not cosmetic: `xlevels` is the
    RELEVELED order, reference first, while R writes the table back in the
    canonical order every worksheet, plot and stratum table in the project
    uses, chronological for periods and alphabetical for the rest. Reading
    `xlevels` for the order puts the reference level first, so one deck would
    show its animal groups in two different orders on consecutive slides.

    A level with no row at all is appended with everything missing, keeping the
    frame's levels equal to the stratifier's whatever the fit dropped.

    `value` names the estimate column in the table being read, `hr` for a
    hazard-ratio table and `los_ratio` for the Weibull's time-ratio one. It is
    renamed to `hr` on the way out, and the frame's shape does not otherwise
    change: the two tables are the same estimate under two link functions and
    everything downstream treats a ratio as a ratio.
    """
    lookup = {f"{term}{level}": (terms[term], level)
              for term, levels in xlevels.items() if term in terms
              for level in levels}

    index: list[tuple[str, str]] = []
    records: list[dict] = []
    for row in table.itertuples(index=False):
        key = lookup.get(row.variable)
        if key is None:
            continue
        index.append(key)
        records.append({"hr": getattr(row, value), "hr_ci_lower": row.ci_lower,
                        "hr_ci_upper": row.ci_upper, "p_value": row.p_value})
    for key in lookup.values():
        if key not in index:
            index.append(key)
            records.append({})

    frame = pd.DataFrame(records, index=pd.MultiIndex.from_tuples(index, names=INDEX_NAMES)
                         if index else pd.MultiIndex.from_arrays([[], []], names=INDEX_NAMES))
    return frame.reindex(columns=HR_COLUMNS).astype(float)


def pooled(bundle: Bundle) -> pd.DataFrame:
    """The main Cox regression, one row per level of every qualifying predictor.

    Indexed by (stratifier, level), with the reference level present as the
    definitional row R wrote: hazard ratio exactly 1, interval and p-value
    missing, because the reference is the denominator of the ratios and not an
    estimate of anything. Levels stay in the canonical order `xlevels` gives,
    chronological for periods and alphabetical for the rest, which is the order
    every table and worksheet in the project uses.

    Empty when the run had no qualifying predictor and skipped Cox entirely.
    """
    if not bundle.value("cox", "has_analysis"):
        return _empty()
    return _rows_from(bundle.table("cox", "hr_table"),
                      bundle.value("cox", "xlevels") or {},
                      _term_to_stratifier(bundle))


def stratified(bundle: Bundle) -> pd.DataFrame:
    """The per-predictor stratified Cox fits, in `pooled`'s shape exactly.

    Each variant contributes the rows for its own stratifier and no others,
    since the rest of them are inside `strata()` and have no coefficients. The
    union across variants is therefore the pooled frame's row set, provided
    every qualifying predictor got a variant, which it does whenever two of
    them qualify at all.

    Empty when fewer than two stratifiers qualified, in which case no variant
    was attempted and there is nothing here to compare the pooled fit against.
    A variant whose own fit failed contributes nothing either, so its
    stratifier's levels are simply absent and `comparison` reports the pooled
    numbers with the comparison missing.
    """
    variants = bundle.value("cox", "stratified_variants") or {}
    terms = _term_to_stratifier(bundle)
    frames = [
        _rows_from(pd.DataFrame(variant["hr_table"]["columns"]), variant["xlevels"], terms)
        for variant in variants.values() if variant.get("has_analysis")
    ]
    if not frames:
        return _empty()
    return pd.concat(frames)


# The three readings each panel puts side by side, in the order they are drawn
# and tabled. `key` is the column prefix, `label` what the audience is told,
# and `note` is the one thing a presenter has to know about that column and
# cannot see: what it adjusted for and what it assumed.
#
# The two panels share their middle: the Weibull time ratio and the Weibull
# hazard ratio are ONE estimate under two link functions, HR = ratio^(-k) with
# k the fitted shape. That is a feature of the pair of slides rather than a
# duplication, since it is the bridge between "leaves sooner" and "stays
# longer", but a deck that showed them as independent evidence would be
# claiming something it has not got, which is why both notes say so.
HR_SERIES = (
    ("hr_cox_pooled", "Cox pooled",
     "every dimension in one model, one shared baseline hazard"),
    ("hr_cox_stratified", "Cox stratified",
     "the other dimensions given their own baselines"),
    ("hr_weibull_pooled", "Weibull pooled",
     "the same model with a Weibull baseline imposed"),
)

LOS_SERIES = (
    ("los_weibull_pooled", "Weibull pooled",
     "adjusted for the other dimensions, one shape"),
    ("los_weibull_stratified", "Weibull freed shape",
     "adjusted, with the other dimensions' shapes free"),
    ("los_km_ratio", "KM unadjusted",
     "unadjusted: each level's own curve, mix and all"),
)


def _panel(series: list[tuple[str, pd.DataFrame]]) -> pd.DataFrame:
    """Named estimate frames laid over each other on one index.

    Each contributes three columns, the estimate and its two bounds, under its
    own key. The index is the union of the frames' indexes in first-seen order,
    so a level one reading dropped keeps its row and shows a gap rather than
    disappearing from a slide the other two could still fill.
    """
    index: list[tuple[str, str]] = []
    for _, frame in series:
        for key in frame.index:
            if key not in index:
                index.append(key)
    if not index:
        return pd.DataFrame(index=pd.MultiIndex.from_arrays([[], []], names=INDEX_NAMES))

    panel = pd.DataFrame(index=pd.MultiIndex.from_tuples(index, names=INDEX_NAMES))
    for name, frame in series:
        aligned = frame.reindex(panel.index)
        panel[name] = aligned["hr"]
        panel[f"{name}_ci_lower"] = aligned["hr_ci_lower"]
        panel[f"{name}_ci_upper"] = aligned["hr_ci_upper"]
    return panel


def _weibull_pooled(bundle: Bundle, table: str, value: str) -> pd.DataFrame:
    if not bundle.value("weibull", "has_analysis"):
        return _empty()
    return _rows_from(bundle.table("weibull", table),
                      bundle.value("weibull", "xlevels") or {},
                      _term_to_stratifier(bundle), value=value)


def _weibull_variants(bundle: Bundle, table: str, value: str) -> pd.DataFrame:
    """Each stratifier's own rows from its own shape variant.

    A shape variant keeps every dimension in the scale, so its table carries
    rows for all of them; what makes it that stratifier's variant is which
    dimension it left in the scale alone while freeing the others' shapes. Only
    those rows are taken, which is what makes the union of the variants the
    same row set the pooled fit has, exactly as on the Cox side.

    The variants carry no `xlevels` of their own, the pooled fit's being the
    same model's, so the row names are decoded with those.
    """
    terms = _term_to_stratifier(bundle)
    xlevels = bundle.value("weibull", "xlevels") or {}
    frames = []
    for stratifier, variant in (bundle.value("weibull", "shape_variants") or {}).items():
        if not variant.get("has_analysis") or table not in variant:
            continue
        rows = _rows_from(pd.DataFrame(variant[table]["columns"]), xlevels, terms,
                          value=value)
        if not rows.empty:
            frames.append(rows[rows.index.get_level_values("stratifier") == stratifier])
    return pd.concat(frames) if frames else _empty()


def _km_ratios(bundle: Bundle) -> pd.DataFrame:
    """The restricted-mean ratios R publishes, in the regression frames' shape.

    Read, not computed: the ratio and its interval are rows of each
    stratifier's KM matrix, against the same reference level the regressions
    use, so this side arranges them and nothing more.

    The whole sample is skipped. It is a stratifier with one level, and one
    level is its own reference, so its ratio is the definitional 1 and says
    nothing.
    """
    index: list[tuple[str, str]] = []
    records: list[dict] = []
    for stratifier in bundle.stratifiers():
        if stratifier == "all" or not bundle.has("strata", stratifier, "km"):
            continue
        km = bundle.stratum(stratifier, "km")
        if "km_restricted_mean_ratio" not in km.columns:
            continue
        for level in km.index:
            index.append((stratifier, str(level)))
            records.append({
                "hr": km.at[level, "km_restricted_mean_ratio"],
                "hr_ci_lower": km.at[level, "km_restricted_mean_ratio_ci_lower"],
                "hr_ci_upper": km.at[level, "km_restricted_mean_ratio_ci_upper"],
                "p_value": float("nan"),
            })
    if not index:
        return _empty()
    return pd.DataFrame(records,
                        index=pd.MultiIndex.from_tuples(index, names=INDEX_NAMES))


def hazard_ratio_panel(bundle: Bundle) -> pd.DataFrame:
    """The three hazard ratios per level: two Cox fits and the Weibull's."""
    return _panel([
        ("hr_cox_pooled", pooled(bundle)),
        ("hr_cox_stratified", stratified(bundle)),
        ("hr_weibull_pooled", _weibull_pooled(bundle, "hr_table", "hr")),
    ])


def los_ratio_panel(bundle: Bundle) -> pd.DataFrame:
    """The three length-of-stay ratios per level, two fitted and one not.

    The last of them is what the deck's earlier slides actually showed, since
    every length-of-stay slide before this one is unadjusted Kaplan-Meier. Its
    distance from the two beside it is therefore not a disagreement between
    methods: it is how much of what those slides showed was the mix of the
    other dimensions rather than the dimension on the slide.
    """
    return _panel([
        ("los_weibull_pooled", _weibull_pooled(bundle, "los_table", "los_ratio")),
        ("los_weibull_stratified", _weibull_variants(bundle, "los_table", "los_ratio")),
        ("los_km_ratio", _km_ratios(bundle)),
    ])


def panel_stratifiers(panel: pd.DataFrame, keys) -> list[str]:
    """Stratifiers with at least two of a panel's three readings, in order.

    Two rather than one, because the slide's whole point is the comparison: a
    stratifier with a single reading is a bar chart of one number per level,
    which the length-of-stay slides already showed better.
    """
    if panel.empty:
        return []
    present = pd.concat([panel[key].notna() for key, _, _ in keys], axis=1)
    enough = present.sum(axis=1).groupby(level="stratifier").max()
    return [name for name in panel.index.get_level_values("stratifier").unique()
            if enough.get(name, 0) >= 2]


def comparison(pooled_frame: pd.DataFrame, stratified_frame: pd.DataFrame) -> pd.DataFrame:
    """The two fits side by side, and the two ways of asking whether they part.

    Columns: both hazard ratios, their ratio with a 95% interval,
    `p_difference`, and `agreement_margin`.

    **The two answer different questions and neither substitutes for the
    other.** `p_difference` asks whether there is evidence the two fits
    disagree, and a small value is the finding. `agreement_margin` asks how
    closely they are shown to agree, and a small value is the finding there
    too, but it is the opposite kind of claim. A large p and a tight margin
    together are what "these agree" looks like; a large p and a wide margin
    mean nothing was established either way, which the p alone cannot tell you.

    **Reading the margin.** A margin of 0.08 says the data establish, at 95%
    confidence, that the two methods agree within 8%: the interval for their
    ratio lies inside [1/1.08, 1.08]. It is the TOST statement rather than a
    difference test's, and the difference matters, because a difference test
    that fails to reject says only that a gap was not detected, which a small
    sample earns for free. The margin cannot be earned that way: thin data
    widens the interval and the margin grows, reporting honestly that little
    was established. On OC2 the well-populated levels come in between 7% and
    11% while the one animal group the data barely holds reaches 24%, which is
    the sample size speaking and not the methods disagreeing.

    It is the smallest symmetric margin the interval fits inside, so it takes
    the bound of larger MAGNITUDE, not the larger bound. Those differ whenever
    the interval sits off center, and on OC2 they differ on a real row: the
    PUPPY interval is [0.904, 1.067], whose lower bound is the further from 1,
    making the margin 10.7% rather than the 6.7% the upper bound alone suggests.
    Taking the signed maximum would understate the margin there, and on an
    interval lying entirely below 1 it would return a negative one.

    **Both share one variance, and it treats the two fits as independent**,
    which they are not: they are computed from the same rows, and their
    correlation is almost certainly positive, so the true variance of their
    difference, `Var_p + Var_s - 2*Cov`, is smaller than the sum used here.

    That single assumption makes BOTH columns conservative, in the direction
    each of them can afford. Too large a variance widens the interval, so the
    margin comes out larger than the data strictly require and the agreement
    claim understates itself; and it shrinks every z statistic, so the p-value
    comes out larger and a difference is under-reported rather than invented.
    Neither column can overstate its own finding on account of it. What the p
    loses is power: on OC2 it lands between 0.40 and 0.98 on
    every level, which is why it is reported beside the margin and not instead
    of it.

    The correlation-aware alternative, Hausman's `Var_s - Var_p`, is not
    available here regardless, because these are clustered robust standard
    errors rather than model-based ones and the efficiency result it rests on
    does not hold for them; on OC2 it returns a negative variance on three of
    the nine estimated rows.

    Reference levels carry 1.0 in the ratio column and nothing in the interval,
    the p-value or the margin. Both fits put the reference at exactly 1 by
    construction, so there is nothing there for a comparison to be uncertain
    about.
    """
    frame = pd.DataFrame(index=pooled_frame.index, columns=COMPARISON_COLUMNS, dtype=float)
    aligned = stratified_frame.reindex(pooled_frame.index)
    for prefix, source in (("hr_pooled", pooled_frame), ("hr_stratified", aligned)):
        frame[prefix] = source["hr"]
        frame[f"{prefix}_ci_lower"] = source["hr_ci_lower"]
        frame[f"{prefix}_ci_upper"] = source["hr_ci_upper"]

    for key in pooled_frame.index:
        hr_p = pooled_frame.at[key, "hr"]
        hr_s = frame.at[key, "hr_stratified"]
        if pd.isna(hr_p) or pd.isna(hr_s) or hr_p <= 0 or hr_s <= 0:
            continue
        frame.at[key, "hr_ratio"] = hr_s / hr_p

        se_p = _se_from_ci(frame.at[key, "hr_pooled_ci_lower"], frame.at[key, "hr_pooled_ci_upper"])
        se_s = _se_from_ci(frame.at[key, "hr_stratified_ci_lower"],
                           frame.at[key, "hr_stratified_ci_upper"])
        # A reference level has an interval on neither side, which is the
        # ordinary case here rather than a gap: the ratio is 1 and certain.
        if se_p is None or se_s is None:
            continue

        difference = math.log(hr_s) - math.log(hr_p)
        standard_error = math.hypot(se_s, se_p)
        half_width = Z_95 * standard_error
        frame.at[key, "hr_ratio_ci_lower"] = math.exp(difference - half_width)
        frame.at[key, "hr_ratio_ci_upper"] = math.exp(difference + half_width)
        frame.at[key, "agreement_margin"] = math.exp(abs(difference) + half_width) - 1
        # Two-sided normal tail, from the standard library's erfc rather than
        # from scipy, which nothing else here would need.
        frame.at[key, "p_difference"] = math.erfc(
            abs(difference) / (standard_error * math.sqrt(2)))

    return frame


def comparable_stratifiers(comparison_frame: pd.DataFrame) -> list[str]:
    """Stratifiers with both fits present, in the frame's own order.

    A stratifier whose variant was never built, or whose fit failed, has the
    pooled column filled and the stratified one empty throughout. There is no
    comparison to draw for it, and a slide built from it would be a table of
    blanks, so rules ask here before building rather than after.
    """
    if comparison_frame.empty:
        return []
    usable = comparison_frame["hr_stratified"].notna().groupby(level="stratifier").any()
    return [name for name in comparison_frame.index.get_level_values("stratifier").unique()
            if usable.get(name, False)]
