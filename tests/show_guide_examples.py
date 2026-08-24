#!/usr/bin/env python3
"""Every worked number the documents quote, recomputed from a run.

The Presentation Guide and the math methods document both mark their examples
OC1 or OC2, naming the Orange County run each was read off (see "Worked
examples, and which run they come from"). Those marks make a number dated;
this makes it CHECKABLE. Point it at a results directory and it prints, for
every claim belonging to that dataset, what the document says beside what the
run says, and marks the ones that have parted. Each label names its document,
so a parted claim says where to go.

Only figures a standard run produces are here. The math document also quotes
two derivations that no run performs, the shape-versus-n floor behind the
count guard and the behavior of the starting-value grid, and those live in
`tests/scan_shape_floor.R` instead, which recomputes them on demand.

    python3 tests/show_guide_examples.py                 # the default results/
    python3 tests/show_guide_examples.py results/OC1

Not a test, and deliberately not: these numbers are expected to move when a
dataset or a threshold does, and a suite that failed on a shelter's real data
changing would be a suite people learn to ignore. It reports; you decide
whether the guide or the run is the thing to change.

The dataset is read from the bundle's own `run.data_file` rather than passed
in, so a directory cannot be checked against the wrong set of claims.

A claim the guide makes about both runs is listed here TWICE, once under each
tag, so each copy is checked against the run it names. That is the same reason
the guide says "on OC1 and OC2" rather than "on either run": a claim quantified
over the Orange County runs would silently extend to one nobody had checked.

The expected column is a second copy of what the guide says, which is the one
thing this file has to be maintained in step with. That is the point rather
than a flaw: a second copy nobody compares is how the guide drifted in the
first place, and a second copy something compares every time is a drift alarm.
When a number here is wrong, fix the guide and this file together.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from mlos_review import blocks, recommend, workbook  # noqa: E402
from mlos_review.bundle import Bundle  # noqa: E402
from mlos_review.names import Vocabulary  # noqa: E402
from mlos_review.regression import (  # noqa: E402
    Z_95, comparison, pooled, stratified,
)
from mlos_review.salience import spread  # noqa: E402


def _first(lines: list[str]) -> str:
    """The one sentence a finding block produced, or a stand-in for none."""
    return lines[0] if lines else "(silent)"


# ---------------------------------------------------------------------------
# The claims, in the order the guide makes them
# ---------------------------------------------------------------------------
#
# One row per number the guide quotes: which dataset it belongs to, where in
# the guide it sits, what the guide says, and how to recompute it. The compute
# functions return strings so that a claim about a whole sentence and a claim
# about one figure can be compared the same way.


def _salience_row(bundle: Bundle, stratifier: str) -> str:
    found = spread(bundle, stratifier)
    if found is None:
        return "(no spread)"
    return (f"{len(bundle.levels(stratifier))} levels, "
            f"{found.observed:.2f} / {found.noise:.2f} / {found.deviation:.2f}, "
            f"threshold {found.threshold:.2f}, "
            f"{'salient' if found.salient else 'not salient'}")


def _cox_p_range(bundle: Bundle) -> str:
    frame = comparison(pooled(bundle), stratified(bundle))
    values = frame["p_difference"].dropna()
    return "(none)" if values.empty else f"{values.min():.2f} to {values.max():.2f}"


def _cox_margins(bundle: Bundle) -> str:
    frame = comparison(pooled(bundle), stratified(bundle))
    wide = frame["agreement_margin"].dropna().sort_values()
    if wide.empty:
        return "(none)"
    over = wide[wide >= blocks.WIDE_MARGIN]
    # A decimal, where the guide rounds to whole percent: 24.5 and 25.4 both
    # print as "25%" in prose, and a comparison that cannot tell them apart is
    # not worth running.
    listed = ", ".join(f"{level} {value:.1%}" for (_, level), value in over.items())
    return f"{len(over)} at or past {blocks.WIDE_MARGIN:.0%}" + (f": {listed}" if listed else "")


def _puppy_interval(bundle: Bundle, level: str) -> str:
    """The off-center interval the margin's "further bound" rule turns on."""
    frame = comparison(pooled(bundle), stratified(bundle))
    if ("group", level) not in frame.index:
        return f"(no {level} row)"
    row = frame.loc[("group", level)]
    if row[["hr_ratio_ci_lower", "hr_ratio_ci_upper"]].isna().any():
        return f"({level} is the reference)"
    return (f"[{row['hr_ratio_ci_lower']:.3f}, {row['hr_ratio_ci_upper']:.3f}], "
            f"margin {row['agreement_margin']:.1%} against "
            f"{row['hr_ratio_ci_upper'] - 1:.1%} from the upper bound alone")


def _hausman_negative(bundle: Bundle) -> str:
    """Rows where `Var_s - Var_p` comes out negative, which is why it is unused.

    Recovered from the published intervals the same way `regression` recovers
    every standard error here, so this reads the numbers a reader sees.
    """
    frame = comparison(pooled(bundle), stratified(bundle))
    negative = estimated = 0
    for _, row in frame.iterrows():
        bounds = [row[f"hr_{fit}_ci_{end}"]
                  for fit in ("pooled", "stratified") for end in ("lower", "upper")]
        if any(value != value for value in bounds):
            continue
        import math
        variance = [((math.log(hi) - math.log(lo)) / (2 * Z_95)) ** 2
                    for lo, hi in (bounds[:2], bounds[2:])]
        estimated += 1
        negative += variance[1] - variance[0] < 0
    return f"{negative} of {estimated} estimated rows"


def _period_census(bundle: Bundle) -> str:
    pooled_census = float(bundle.stratum("all", "census")["expected_census"].iloc[0])
    by_period = bundle.stratum("period", "census")["expected_census"].sum()
    return f"{by_period:.0f} against {pooled_census:.0f}"


def _burden(bundle: Bundle, stratifier: str) -> str:
    found = blocks.burden_carrier(bundle, stratifier)
    if found is None:
        return "no carrier"
    carrier, owed, resident = found
    return f"{carrier} at {owed:.0%} owed against {resident:.0%} of residents"


def _aj_windows(bundle: Bundle) -> str:
    windows = bundle.stratum("group", "aj_window")["aj_analysis_window_days"].dropna()
    shortest, longest = windows.idxmin(), windows.idxmax()
    return (f"{shortest} ends at day {int(windows[shortest])}, "
            f"{longest} runs to {int(windows[longest])}")


def _highlights(bundle: Bundle, stratifier: str) -> str:
    full = blocks.full_table(bundle, stratifier)
    return (f"{len(blocks.highlights_table(bundle, stratifier, full).df)} rows "
            f"of {len(full.df)}")


def _at_cap(bundle: Bundle) -> str:
    at_cap = bundle.stratum("group", "km")["km_still_in_care_at_cap"].dropna()
    worst = at_cap.idxmax()
    return f"{worst} at {at_cap[worst]:.1%}"


def _sheets(bundle: Bundle, vocab: Vocabulary) -> str:
    return f"{len(workbook.sheets(bundle, vocab))} sheets"


def _tail_spread(bundle: Bundle, vocab: Vocabulary, stratifier: str) -> str:
    return _first(recommend.tail_spread(bundle, stratifier, vocab))


def _shape_variant(bundle: Bundle, variant: str) -> dict:
    """One shape variant's block, or an empty one when the fit declined."""
    variants = bundle.value("weibull", "shape_variants", default={}) or {}
    found = variants.get(variant)
    return found if isinstance(found, dict) else {}


def _variant_baseline(bundle: Bundle, variant: str) -> str:
    """The shape at the reference combination, which R writes into the table's
    reference rows rather than into a field of its own."""
    table = _shape_variant(bundle, variant).get("shape_table")
    if not table:
        return "(no shape table)"
    columns = table["columns"]
    for name, ratio, own in zip(columns["variable"], columns["shape_ratio"],
                                columns.get("shape_own", [])):
        if ratio == 1:                       # a reference row of either predictor
            return f"{own:.2f}"
    return "(no reference row)"


def _shape_row(bundle: Bundle, variant: str, term: str) -> str:
    table = _shape_variant(bundle, variant).get("shape_table")
    if not table:
        return "(no shape table)"
    columns = table["columns"]
    if term not in columns["variable"]:
        return f"(no {term} row)"
    index = columns["variable"].index(term)
    return (f"ratio {columns['shape_ratio'][index]:.2f}, "
            f"own {columns['shape_own'][index]:.2f}")


def _own_shape_in_cell(bundle: Bundle, variant: str, level_term: str,
                       other_terms: tuple[str, ...]) -> str:
    """A level's own k away from the reference cell, under an additive shape fit.

    Section 6.7 quotes these to show that a published own k belongs to the
    reference cell even when the shape formula is additive: the level's ratio
    still applies elsewhere, multiplied by the other shape predictor's ratio.
    """
    table = _shape_variant(bundle, variant).get("shape_table")
    if not table:
        return "(no shape table)"
    columns = table["columns"]
    baseline = (_shape_variant(bundle, variant).get("shape_reference") or {}).get("k")
    if baseline is None or level_term not in columns["variable"]:
        return f"(no {level_term} row)"
    own = baseline * columns["shape_ratio"][columns["variable"].index(level_term)]
    parts = []
    for term in other_terms:
        if term not in columns["variable"]:
            return f"(no {term} row)"
        ratio = columns["shape_ratio"][columns["variable"].index(term)]
        parts.append(f"{own * ratio:.2f} in {term.split('intake_type')[-1]}")
    return " and ".join(parts)


def _crude_and_adjusted(bundle: Bundle) -> str:
    crude = bundle.value("weibull", "crude", default={}) or {}
    return f"{crude.get('shape', float('nan')):.2f} and " \
           f"{bundle.value('weibull', 'shape'):.2f}"


def _guard_summary(bundle: Bundle) -> str:
    """Which shape formula each variant used, and why it was that one.

    The claim below belongs to a default run, where crossing is off and the
    answer is the same three words for any dataset. A run made with
    `weibull_shape_crossing` enabled reports which variants crossed and why the
    others did not, and parts from the claim, correctly: section 6.7 marks that
    example as the enabled run's and leaves the per-cell counts behind it to
    `tests/scan_shape_floor.R`.
    """
    enabled = bool(bundle.value("settings", "weibull_shape_crossing"))
    if not enabled:
        return "crossing off: all three additive"
    refused, crossed = [], []
    for name in ("period", "intake", "group"):
        crossing = _shape_variant(bundle, name).get("shape_crossing") or {}
        if crossing.get("crossed"):
            crossed.append(name)
        else:
            refused.append(f"{name} refused: {crossing.get('fallback_reason')}")
    return "; ".join(refused + [" and ".join(crossed) + " crossed"])


def _strata_counts(bundle: Bundle) -> str:
    variants = bundle.value("cox", "stratified_variants", default={}) or {}
    counts, with_events, events = [], [], 0
    for name in ("period", "intake", "group"):
        found = variants.get(name) or {}
        counts.append(found.get("n_strata"))
        with_events.append(found.get("n_strata_with_events"))
        events = max(events, found.get("n_events") or 0)
    all_hold = counts == with_events
    return (f"{counts[0]}, {counts[1]} and {counts[2]} baseline strata, "
            f"{'all holding events' if all_hold else 'NOT all holding events'}, "
            f"over {events:,} events")


CLAIMS: list[tuple[str, str, str, object]] = [
    # -- Salience -----------------------------------------------------------
    ("OC1", "salience, period", "3 levels, 3.46 / 0.44 / 3.43, threshold 3.53, not salient",
     lambda b, v: _salience_row(b, "period")),
    ("OC1", "salience, intake type", "3 levels, 4.49 / 0.55 / 4.46, threshold 3.53, salient",
     lambda b, v: _salience_row(b, "intake")),
    ("OC1", "salience, animal group", "7 levels, 11.09 / 0.64 / 11.07, threshold 3.53, salient",
     lambda b, v: _salience_row(b, "group")),
    ("OC2", "salience, intake type", "4 levels, 4.56 / 0.64 / 4.51, threshold 3.51, salient",
     lambda b, v: _salience_row(b, "intake")),
    ("OC2", "salience, animal group", "5 levels, 11.04 / 0.44 / 11.03, threshold 3.51, salient",
     lambda b, v: _salience_row(b, "group")),
    ("OC2", "arrivals behind the noise floor", "15,597",
     lambda b, v: f"{int(b.stratum('all', 'observations')['total_intakes'].iloc[0]):,}"),

    # -- The two Cox fits ---------------------------------------------------
    ("OC2", "Cox p-value range", "0.40 to 0.98", lambda b, v: _cox_p_range(b)),
    # The guide rounds this to 24%.
    ("OC2", "margins past WIDE_MARGIN",
     "1 at or past 20%: _UNKNOWN_ 24.0%",
     lambda b, v: _cox_margins(b)),
    ("OC2", "the off-center interval",
     "[0.904, 1.067], margin 10.7% against 6.7% from the upper bound alone",
     lambda b, v: _puppy_interval(b, "PUPPY")),
    ("OC2", "Hausman variance goes negative", "3 of 9 estimated rows",
     lambda b, v: _hausman_negative(b)),

    # -- Census, workload, windows -----------------------------------------
    ("OC2", "period censuses against the true one", "571 against 191",
     lambda b, v: _period_census(b)),
    ("OC2", "burden carrier, animal group", "LARGE at 93% owed against 70% of residents",
     lambda b, v: _burden(b, "group")),
    ("OC1", "burden carrier, intake type", "no carrier", lambda b, v: _burden(b, "intake")),
    ("OC2", "burden carrier, intake type", "no carrier", lambda b, v: _burden(b, "intake")),
    ("OC2", "AJ windows by animal group", "MED ends at day 132, LARGE runs to 365",
     lambda b, v: _aj_windows(b)),
    ("OC2", "cap binding hardest", "LARGE at 0.9%", lambda b, v: _at_cap(b)),

    # -- Selection and sheets ----------------------------------------------
    ("OC1", "highlights collapse, animal group", "2 rows of 7",
     lambda b, v: _highlights(b, "group")),
    ("OC2", "highlights collapse, animal group", "2 rows of 5",
     lambda b, v: _highlights(b, "group")),
    ("OC1", "workbook sheets", "11 sheets", _sheets),
    ("OC2", "workbook sheets", "11 sheets", _sheets),

    # -- Findings and recommendations --------------------------------------
    ("OC1", "outcome sweep, animal group", "(silent)",
     lambda b, v: _first(blocks._outcome_sweep(
         {code: blocks.aj_levels_table(b, "group", v).df[f"aj_restricted_mean_{code}"].dropna()
          for code in blocks.aj_outcome_codes(b, "group")}, "animal group") or [])),
    ("OC2", "outcome sweep, animal group",
     "By animal group, PUPPY is the fastest in every outcome type.",
     lambda b, v: blocks._outcome_sweep(
         {code: blocks.aj_levels_table(b, "group", v).df[f"aj_restricted_mean_{code}"].dropna()
          for code in blocks.aj_outcome_codes(b, "group")}, "animal group") or "(silent)"),
    # The guide quotes the opening of this sentence and trails off; the
    # expected value is the part it quotes, matched inside the whole.
    ("OC2", "time to outcome, animal group",
     "for community live outcomes, LARGE is slowest (20.7 days) and PUPPY is "
     "fastest (5.7 days). For other live outcomes, LARGE is slowest (65.7 days) "
     "and PUPPY is fastest (4.8 days)",
     lambda b, v: _first(blocks.findings_for_aj(
         blocks.aj_levels_table(b, "group", v), "animal group", v)[-1:])),
    ("OC2", "outcome spread, animal group",
     "LARGE at 39 days against PUPPY at 2, a 19.9-fold gap",
     lambda b, v: _first(blocks.findings_for_outcome_spread(b, "group", "animal group", v))),
    ("OC2", "outcome contrast, intake type",
     "for OTH: its other live outcomes take 56 days against 12 for its "
     "community live ones, 4.5 times as long",
     lambda b, v: _first(blocks.findings_for_outcome_contrast(b, "intake", "intake type", v))),
    ("OC2", "tail spread, intake type",
     "90th percentile stay is 37 days against a median of 3, a spread 2.1 "
     "times the shelter's own",
     lambda b, v: _tail_spread(b, v, "intake")),
    # The rule reads an additive shape formula, which is what a default run
    # fits, and refuses a crossed one. A run made with weibull_shape_crossing
    # enabled therefore has less to read and can fall silent here, which is one
    # of the reasons the setting is discouraged.
    ("OC2", "falling hazard, animal group",
     "The discharge hazard falls faster with tenure inside LARGE than it does "
     "across the shelter: their own Weibull shapes are LARGE at 0.67, against "
     "0.82 for the shelter as a whole, and a shape under 1 is a hazard that "
     "falls as a stay lengthens. Time already served predicts more time to "
     "come more strongly there than elsewhere, so an intervention aimed at "
     "animals past a tenure threshold has the most to bite on in LARGE. The "
     "census-by-tenure curves say where to set it.",
     lambda b, v: _first(recommend.falling_hazard(b, "group", v))),

    # -- Math methods, section 6.7: shapes and the count guard ---------------
    # The section reads the baseline and the ratio column together, so both
    # halves of that multiplication are checked: a baseline that moved without
    # its ratios would leave the prose arithmetically wrong while every
    # individual number still looked plausible.
    ("OC2", "math 6.6: crude shape against adjusted", "0.71 and 0.82",
     lambda b, v: _crude_and_adjusted(b)),
    ("OC2", "math 6.7: baseline shape of the period variant", "0.99",
     lambda b, v: _variant_baseline(b, "period")),
    ("OC2", "math 6.7: LARGE ratio 0.68 puts its own shape at 0.67",
     "ratio 0.68, own 0.67",
     lambda b, v: _shape_row(b, "period", "animal_groupLARGE")),
    ("OC2", "math 6.7: PUPPY ratio 1.08 puts its own shape at 1.07",
     "ratio 1.08, own 1.07",
     lambda b, v: _shape_row(b, "period", "animal_groupPUPPY")),
    # The same LARGE row read outside the reference cell, which is the point
    # the section makes about an own k under an additive shape formula.
    ("OC2", "math 6.7: LARGE's own shape away from the reference intake",
     "0.52 in RET and 0.69 in OWNER",
     lambda b, v: _own_shape_in_cell(b, "period", "animal_groupLARGE",
                                     ("intake_typeRET", "intake_typeOWNER"))),
    ("OC2", "math 6.7: the shape formula each variant used (default run)",
     "crossing off: all three additive",
     lambda b, v: _guard_summary(b)),

    # -- Math methods, section 6.8: the stratified Cox variants --------------
    ("OC2", "math 6.8: baseline strata per variant",
     "20, 15 and 12 baseline strata, all holding events, over 15,521 events",
     lambda b, v: _strata_counts(b)),
]


def dataset_tag(bundle: Bundle) -> str | None:
    """Which Orange County run this is, from the bundle's own provenance."""
    source = str(bundle.value("run", "data_file", default=""))
    for tag in ("OC1", "OC2"):
        if tag in source:
            return tag
    return None


def main(argv: list[str]) -> int:
    results = argv[1] if len(argv) > 1 else "results"
    bundle = Bundle.load(results)
    vocab = Vocabulary(bundle.data)

    tag = dataset_tag(bundle)
    source = bundle.value("run", "data_file", default="(unrecorded)")
    print(f"{results}  ->  {source}")
    if tag is None:
        print("\nThis is not an Orange County run, so none of the guide's marked "
              "examples apply to it. Nothing to compare.")
        return 0

    wanted = [claim for claim in CLAIMS if claim[0] == tag]
    print(f"Checking the {len(wanted)} example(s) the guide marks {tag}.\n")

    parted = 0
    for _, label, expected, compute in wanted:
        try:
            found = str(compute(bundle, vocab))
        except Exception as exc:                       # noqa: BLE001
            found = f"({type(exc).__name__}: {exc})"
        # Substring rather than equality: several of these quote a phrase out
        # of a generated sentence, and the guide is entitled to quote a part.
        agrees = expected in found or found in expected
        print(f"  {'ok ' if agrees else 'X  '} {label}")
        print(f"        guide: {expected}")
        print(f"        run:   {found}")
        if not agrees:
            parted += 1
    print()
    if parted:
        print(f"{parted} of {len(wanted)} have parted from the guide. Fix "
              f"presentation_guide.md and the expected value in this file "
              f"together, or the next reader gets the same surprise.")
    else:
        print(f"All {len(wanted)} agree with the guide.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
