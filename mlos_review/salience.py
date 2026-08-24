"""How much a stratifier separates the data, and whether that earns it slides.

The first piece of the deck plan (see the Presentation Guide) to be built: a
number per stratifier saying how far apart its levels' stays are, and a
threshold saying when that is worth a slide. The planner it belongs to does not
exist yet, so nothing here ranks stratifiers against each other; it answers one
question about one stratifier at a time, which is what `emphasis: AUTO` needs.

Salience is computed HERE, never in R. It is a presentation heuristic, not a
finding: in results.json it would sit beside estimates that survived a test
suite and would read as a claim about the shelter rather than a claim about the
deck. It is also expected to be tuned, and tuning it in R would cost a re-run
and twenty-eight regenerated golden files per adjustment.

Everything below is arithmetic over numbers R already published and tested: the
levels' restricted means, their standard errors, and their intake counts.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from mlos_review.bundle import BASELINE_STRATIFIER, Bundle
from mlos_review.settings import Emphasis

# The threshold a stratifier's spread has to clear, in days:
#
#     STAY_DAYS_DEVIATION_FLOOR + STAY_DAYS_DEVIATION_SHARE * mean LOS
#
# A floor PLUS a share, not the larger of the two, so the threshold is smooth
# in mean LOS and a shelter near the crossover does not see the rule change
# character. The two terms answer different objections. Without the floor, a
# short-stay shelter would be salient on a spread of a few hours: 15% of a
# 4-day average is half a day, which no plan can act on. Without the share, a
# long-stay shelter would be salient on anything at all, a day's spread being
# nothing against a 200-day average.
#
# They cross at 6.7 days of mean LOS. Below that the floor dominates and the
# rule is close to "a day"; above it the share takes over, and it takes over
# early enough that on any shelter but a very fast one the share is the term
# that decides. OC sits at 16.8, where the share contributes 2.5 days against
# the floor's 1.
STAY_DAYS_DEVIATION_FLOOR = 1.0
STAY_DAYS_DEVIATION_SHARE = 0.15


@dataclass(frozen=True)
class Spread:
    """How far apart a stratifier's levels are, and what that has to beat.

    Three spreads, all in days, all standard deviations of the same thing:

    `observed`  what the levels' restricted means actually spread by, weighted
                by intakes.
    `noise`     what that spread would have been if every level had the same
                true average stay and only sampling error separated them.
    `deviation` what is left after taking the second out of the first, which is
                the estimated spread that is really there. This is
                `stay_days_deviation`, and it is what the threshold judges.

    The other two are what the verdict was reached against, carried so the
    speaker notes can show their working: `threshold` is the bar `deviation`
    had to clear, and `mean_los` the pooled restricted mean the share of it was
    taken on.
    """

    observed: float
    noise: float
    deviation: float
    threshold: float
    mean_los: float

    @property
    def salient(self) -> bool:
        return self.deviation > self.threshold


def _weighted(bundle: Bundle, stratifier: str):
    """The levels' restricted means, standard errors and intake weights.

    Levels with no restricted mean or no arrivals are dropped: an unestimated
    level cannot be far from anything, and a level nobody arrived into carries
    no weight by construction. Returns None when fewer than two survive, since
    a spread needs two points.
    """
    if not (bundle.has("strata", stratifier, "km")
            and bundle.has("strata", stratifier, "observations")):
        return None
    km = bundle.stratum(stratifier, "km")
    observations = bundle.stratum(stratifier, "observations")
    if "km_restricted_mean" not in km.columns:
        return None
    if "total_intakes" not in observations.columns:
        return None

    stays = km["km_restricted_mean"]
    weights = observations["total_intakes"]
    keep = stays.notna() & weights.notna() & (weights > 0)
    if int(keep.sum()) < 2:
        return None

    # A run without standard errors is judged on its raw spread rather than
    # not at all: no correction is a weaker test, not a broken one.
    errors = (km["km_restricted_mean_se"] if "km_restricted_mean_se" in km.columns
              else stays * 0.0)
    return stays[keep], errors[keep].fillna(0.0), weights[keep]


def spread(bundle: Bundle, stratifier: str) -> Spread | None:
    """`stay_days_deviation` for one stratifier, with what it is judged against.

    The observed spread is the intake-weighted standard deviation of the
    levels' restricted mean stays. Weighted by intakes because for length of
    stay the arriving cohort is the natural view, and by intake COUNTS rather
    than by daily rates because counts partition across the levels of every
    stratifier while rates do not: each period carries its own denominator, so
    weighting periods by rate would make a short busy period look like a large
    share of arrivals.

    The noise floor is the same weighted variance's expectation under the null
    that every level has the same true average stay:

        E[observed variance] = sum_i w_i SE_i^2 (1 - w_i / W) / W

    which is what ANOVA does when it splits observed variation into a
    between-group part and a within-group part, and is the method-of-moments
    estimate of between-group variance used in meta-analysis. The
    `(1 - w_i / W)` factor is not decoration: each level helps set the mean it
    is then measured against, which shrinks the spread it can show, and with
    two levels ignoring it overstates the floor by a factor of two.

    Subtracting in quadrature and flooring at zero is the whole correction. A
    negative result means the levels are no further apart than sampling error
    alone would have put them, which is reported as no spread rather than as a
    negative one.
    """
    parts = _weighted(bundle, stratifier)
    if parts is None:
        return None
    stays, errors, weights = parts

    total = float(weights.sum())
    mean = float((stays * weights).sum() / total)
    observed = float((weights * (stays - mean) ** 2).sum() / total)
    noise = float((weights * errors ** 2 * (1 - weights / total)).sum() / total)

    # The pooled figure rather than the weighted mean just computed, which it
    # is within a fraction of a day of, because it is the number on the
    # whole-sample slide: a reader checking the threshold can find it. Falls
    # back to the weighted mean where the bundle has no pooled row.
    pooled = mean
    if bundle.has("strata", BASELINE_STRATIFIER, "km"):
        published = bundle.stratum(BASELINE_STRATIFIER, "km")["km_restricted_mean"]
        if len(published) and published.iloc[0] == published.iloc[0]:
            pooled = float(published.iloc[0])

    return Spread(
        observed=math.sqrt(observed),
        noise=math.sqrt(noise),
        deviation=math.sqrt(max(0.0, observed - noise)),
        threshold=STAY_DAYS_DEVIATION_FLOOR + STAY_DAYS_DEVIATION_SHARE * pooled,
        mean_los=pooled,
    )


def is_salient(bundle: Bundle, stratifier: str) -> bool:
    """Whether this stratifier's levels are far enough apart to earn slides.

    False when the spread cannot be computed at all, which is the conservative
    answer: a stratifier with one level, or with no restricted means, has shown
    nothing, and the deck's extra slides are for stratifiers that have.
    """
    found = spread(bundle, stratifier)
    return found is not None and found.salient


def earns_slides(bundle: Bundle, stratifier: str, emphasis: Emphasis) -> bool:
    """The settings' answer where they give one, the data's where they do not.

    One place, so a rule cannot ask the question a slightly different way from
    the rule beside it.
    """
    if emphasis.suppressed:
        return False
    if emphasis.forced:
        return True
    return is_salient(bundle, stratifier)


def findings_for_salience(bundle: Bundle, vocab) -> list[str]:
    """Which dimension of the shelter separates its stays furthest.

    The one finding in the deck that compares stratifiers rather than
    levels, which is why it is here and not in `blocks`: it is the planner's
    kind of statement, made about the whole deck rather than about the slide it
    hangs on. It rides the whole-sample slide, which is the baseline every
    stratified slide splits, so it reads as a preview of what follows.

    Silent below two comparable stratifiers, where "furthest" would be a
    superlative over one thing, and silent when the leader ties, on the rule
    `extreme_levels` applies to levels: naming one of two equals is a choice
    the data did not make.
    """
    found = {stratifier: spread(bundle, stratifier)
             for stratifier in bundle.stratifiers()
             if stratifier != BASELINE_STRATIFIER}
    found = {name: value for name, value in found.items() if value is not None}
    if len(found) < 2:
        return []

    ranked = sorted(found.items(), key=lambda pair: pair[1].deviation, reverse=True)
    if ranked[0][1].deviation == ranked[1][1].deviation:
        return []

    leader, best = ranked[0]
    # `name_levels` rather than a join, so three stratifiers read as a list and
    # two read as a pair. blocks does not import this module, so the direction
    # of the dependency is safe.
    from mlos_review.blocks import name_levels

    rest = name_levels([f"{value.deviation:.1f} for {vocab.stratifier(name).label}"
                        for name, value in ranked[1:]])
    return [f"{vocab.stratifier(leader).label.capitalize()} separates stays "
            f"furthest: its levels differ by {best.deviation:.1f} days of "
            f"average stay, against {rest}."]


def salience_notes(bundle: Bundle, stratifier: str, emphasis: Emphasis,
                   vocab) -> list[str]:
    """What the spread came to, and what it did or did not buy.

    Reported whether or not the test decided anything. Where the settings force
    a stratifier in, the number still says what the data would have answered,
    which is how a reader tells a setting that is carrying a stratifier from
    one that is merely agreeing with it.
    """
    found = spread(bundle, stratifier)
    if found is None:
        return []

    label = vocab.stratifier(stratifier).label
    lines = [
        f"Salience. The levels' average stays spread by {found.observed:.1f} "
        f"days around their intake-weighted mean. Of that, {found.noise:.1f} "
        f"days is what the spread would have been if every {label} had the "
        f"same true average stay and only sampling error separated them, so "
        f"the spread really there is {found.deviation:.1f} days. That is "
        f"stay_days_deviation, and it is judged against "
        f"{found.threshold:.1f} days: {STAY_DAYS_DEVIATION_FLOOR:g} day, plus "
        f"{STAY_DAYS_DEVIATION_SHARE * 100:g}% of the {found.mean_los:.1f}-day "
        f"average stay over the whole sample.",
    ]

    verdict = "above the threshold" if found.salient else "below the threshold"
    if emphasis.forced:
        lines.append(
            f"The settings mark this stratifier salient outright, so the test "
            f"decided nothing here. It lands {verdict}, so the data "
            f"{'agrees' if found.salient else 'does not agree'} with the "
            f"setting. Either way it gets the resident-outlook slide that "
            f"follows.")
    elif found.salient:
        lines.append(
            "That is above the threshold, so the deck treats this stratifier "
            "as salient and gives it the resident-outlook slide that follows: "
            "what its levels' animals already in care still owe.")
    else:
        lines.append(
            "That is below the threshold, so the deck stops here for this "
            "stratifier rather than spending a second slide on levels whose "
            "stays are much the same length. Set its emphasis to ALWAYS in the "
            "deck settings to override that.")
    return lines
