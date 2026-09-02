"""The example deck: what was analyzed, length of stay, then where stays end.

An experiment, not the finished planner. It stands in for Parts 2 and 3 of the
design with a handful of hardcoded rules, called in a fixed order, so the block
layer and the renderer can be exercised end to end against real output. The
rule shape they use (ask what the bundle has, build what is possible, fall back
rather than leave a hole) is the part meant to survive into the real registry;
the order they are called in is not.

Which is also the honest account of what a deck built here is worth. The rules
fire on thresholds, not on judgment: a run with nothing much in it fills the
same slides as a run with something in it, and a stratifier this file does not
happen to call a rule for contributes nothing no matter what it holds. The
slides being right about their numbers, which the tests do check, says nothing
about their being the right slides. See the package docstring; anyone handed a
deck should be told the same.

    python3 -m mlos_review.deck [results_dir] [out.pptx] [--settings=FILE]
                                [--template=FILE]

With no arguments it reads `results/`, takes its settings from
`data/OC_deck_settings.yaml` if that exists, and writes `reports/mlos_deck.pptx`,
archiving any deck already there.
"""

from __future__ import annotations

import sys
from collections.abc import Sequence
from dataclasses import replace
from datetime import datetime
from pathlib import Path

from mlos_review.blocks import (
    aj_highlights_table,
    aj_levels_table,
    aj_outcome_codes,
    aj_teaser_table,
    aj_window_notes,
    findings_for_model_drift,
    findings_for_representation,
    requires_workload,
    workload_table,
    cox_comparison_table,
    ratio_panel_table,
    requires_cox_comparison,
    findings_for_aj,
    findings_for_care_days,
    findings_for_cox_comparison,
    findings_for_gaps,
    findings_for_order_shifts,
    findings_for_outcome_contrast,
    findings_for_outcome_spread,
    findings_for_outlook,
    findings_for_parametric_agreement,
    findings_for_outlook_stratifier,
    findings_for_overall,
    findings_for_stratifier,
    full_table,
    highlights_table,
    outlook_by_tenure_table,
    sub_table,
    INTERVAL_SLIDE_MEASURES,
    LOS_SLIDE_MEASURES,
    OUTLOOK_SLIDE_MEASURES,
    level_counts_table,
    los_standing_notes,
    order_shift_notes,
    sample_table,
    SHARE_AND_DAYS_NOTE,
    study_window_table,
    summary_fields,
    requires_aj,
    requires_aj_teaser,
    requires_level_counts,
    requires_sample,
    requires_study_window,
    sample_gap_notes,
    stacked_by_measure,
    requires_full_table,
    window_gap_notes,
)
from mlos_review.bundle import Bundle
from mlos_review.figures import FigureSet
from mlos_review.names import Vocabulary
from mlos_review.output import prepare_output
from mlos_review.regression import (comparison as cox_comparison, pooled,
                                    stratified, hazard_ratio_panel,
                                    los_ratio_panel, panel_stratifiers,
                                    HR_SERIES, LOS_SERIES)
from mlos_review.recommend import (cap_binding, dimension_not_separating,
                                   falling_hazard, gap_remedy, narrowing,
                                   tail_spread, unestimable_levels)
from mlos_review.salience import (earns_slides, findings_for_salience,
                                  salience_notes)
from mlos_review.render_pptx import (Bullet, Slide, bullet_pages, lead_height,
                                     render, template_band, text_budget)
from mlos_review.settings import (Settings, load as load_settings,
                                  parse_template)
from mlos_review import workbook


# The three things a build writes, beside each other under `reports/`. Derived
# from the deck's path rather than configured separately, so moving the deck
# moves its companions with it and a caller cannot end up with a workbook
# describing a different run from the deck next to it.
#
# Named after the deck FILE and not its directory, so two decks can share one
# directory. Deriving them from the directory meant a second build there took
# the first one's workbook and figures while leaving its deck untouched: the
# deck still opened, the workbook beside it described a different dataset, and
# nothing said so. Building OC1 next to OC2 is the obvious way to meet that,
# and it is a thing people do.
WORKBOOK_SUFFIX = "_tables.xlsx"
FIGURE_SUFFIX = "_figures"


def workbook_path(deck_path: str | Path) -> Path:
    deck_path = Path(deck_path)
    return deck_path.parent / (deck_path.stem + WORKBOOK_SUFFIX)


def figure_directory(deck_path: str | Path) -> Path:
    deck_path = Path(deck_path)
    return deck_path.parent / (deck_path.stem + FIGURE_SUFFIX)


# The pair of figures an LOS slide is built around, in reading order: the
# arriving cohort on the left, the standing population it implies on the right.
# Both are optional, because output flags can switch either off. With one
# missing the survivor runs full width; with both missing the table still
# carries the slide, so a run with figures disabled degrades rather than
# producing an empty page.
LOS_FIGURE_KINDS = ("km_survival", "km_in_care_tenure")

def _los_figures(bundle: Bundle, stratifier: str) -> list:
    """Both LOS figures for one stratifier, dropping any the run did not emit."""
    found = [bundle.figure(kind, stratifier) for kind in LOS_FIGURE_KINDS]
    return [f for f in found if f is not None]


def _aj_figures(bundle: Bundle, stratifier: str) -> list[tuple[str, Path]]:
    """The cumulative-incidence panels that exist, each with its outcome code.

    Paired rather than returned as a bare list of paths, because an outcome the
    run drew no figure for must drop its code with it: a caller that zipped
    codes against a filtered list of paths would label the wrong panel, and the
    label is what tells the audience which outcome it is looking at.

    Shared by the slides and by the teaser's pick of a stratifier, which has to
    know whether there would be panels before choosing one.
    """
    found = [(code, bundle.figure("aj_cif", stratifier, outcome=code))
             for code in aj_outcome_codes(bundle, stratifier)]
    return [(code, path) for code, path in found if path is not None]


# ---------------------------------------------------------------------------
# The opening: what this is, and what it was computed over
# ---------------------------------------------------------------------------

DECK_TITLE = "Length of stay (LOS) analysis"

# The caveat itself, in the words it is to be read in. A constant because it
# appears twice, on the title slide and heading the Findings section, and the
# two must not drift: a reader who meets it again in a different wording has to
# work out whether it is a different claim.
AUTOMATION_CAVEAT = (
    "This report is generated by an automated experimental system. It may "
    "highlight inconsequential findings and miss important ones.")

# What an audience has to know before reading a number off any later slide: the
# statistics are tested, the slides around them are not.
#
# The caveat says both halves of that, so it replaced a terser second bullet
# ("Slide generation pipeline is experimental and incomplete") rather than
# joining it. Two near-identical warnings on one slide read as one warning
# said twice, which is weaker than either alone, and the one that went says
# less: incomplete is a promise that it will be finished, and what an audience
# needs is what the thing in front of them can and cannot be trusted to do.
OPENING_BULLETS = [
    "Underlying statistical analysis by the mLOS tool, extensively tested",
    AUTOMATION_CAVEAT,
]

# The diagram that opens the deck: which part of a stay the study window sees,
# and which part it does not. It rides on the title slide because left
# truncation and right censoring are not a finding, they are the reading every
# later number is made under, and an audience that has not seen this picture
# will read the first survival curve as a curve over completed stays.
#
# A committed PNG rather than the SVG, because pptx has no SVG and python-pptx
# would not embed one. The SVG beside it is the source: edit that, then
# regenerate the PNG with
#
#     "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
#       --headless --disable-gpu --hide-scrollbars --window-size=2670,1800 \
#       --screenshot=mlos_review/kaplan_meier_diagram.png \
#       mlos_review/kaplan_meier_diagram.svg
#
# 2670 x 1800 is the viewBox at 3x, which lands this figure at the pixel
# density R writes its own plots at, so a slide scales them alike.
OPENING_DIAGRAM = Path(__file__).with_name("kaplan_meier_diagram.png")

# What the diagram says, for whoever is presenting it. Four cases and the one
# sentence that matters about each, because the picture labels them but does
# not say why a shelter's data is full of cases 2 and 4.
OPENING_DIAGRAM_NOTES = [
    "The diagram is the whole reason this analysis is survival analysis rather "
    "than an average of stay lengths. A study window sees part of a stay, and "
    "which part it misses changes what the data is allowed to say.",
    "Case 1 is the easy one: the stay starts and ends inside the window, and "
    "its length is observed. Case 2 was already in care when the window "
    "opened, so its early days are unobserved and it is left-truncated: it "
    "enters the risk set at the window's start rather than at intake, which is "
    "what stops long stays from being over-counted. Case 3 was still in care "
    "when the window closed, so all that is known is that the stay lasted at "
    "least this long, and it is right-censored. Case 4 is both.",
    "Dropping cases 3 and 4 would bias the answer short, because the stays "
    "still in care are the long ones. Kaplan-Meier and Cox both use them for "
    "as long as they were observed and no further. Averaging the stays that "
    "finished would be the alternative, and it always returns a number, which "
    "is the trap: on data like this the number it returns is too short, "
    "because the stays it can average are the ones that ended.",
]

TIMESTAMP = "%Y-%m-%d %H:%M:%S"


def _to_seconds(stamp: str) -> str:
    """A bundle timestamp at second resolution, or as written if it is not one.

    R records fractions of a second, which no reader wants and which would
    change between two otherwise identical runs of the same
    analysis. Reformatted rather than truncated, so a stamp in a shape this
    does not recognize is printed as it came rather than sliced into a lie.
    """
    for shape in (f"{TIMESTAMP}.%f", TIMESTAMP):
        try:
            return datetime.strptime(stamp, shape).strftime(TIMESTAMP)
        except ValueError:
            continue
    return stamp


def provenance(bundle: Bundle, now: datetime | None = None) -> str:
    """What computed the numbers, when, and when this deck was built from them.

    Two stamps because they are two events, and the gap between them is the
    thing worth seeing: a deck rebuilt today from a bundle computed in March is
    a deck showing March's shelter. The version leads them because a deposited
    deck is citable, and a citation is checkable only as a version beside a
    DOI. Each of the three is dropped rather than guessed at when the bundle
    does not carry it.
    """
    deck = (now or datetime.now()).strftime(TIMESTAMP)
    generated = bundle.value("run", "generated_at")
    version = bundle.value("run", "mlos_version")
    lead = f"mLOS {version}. " if version else ""
    if not generated:
        return f"{lead}Deck generated on {deck}."
    return (f"{lead}Statistics generated on {_to_seconds(str(generated))}, "
            f"deck on {deck}.")


def title_slide(bundle: Bundle, vocab: Vocabulary,
                now: datetime | None = None) -> Slide:
    """The opening slide, and the stretch of calendar the deck is about.

    Built unconditionally: a deck always has a title. The study window rides
    here rather than on the summary slide because it is the one descriptive
    fact that qualifies the deck's title rather than its numbers. "Length of
    stay analysis" is a claim about a shelter over a period, and the period
    belongs beside the claim.

    The truncation and censoring diagram rides here for a related reason: it
    is about the window, not about any number computed inside it. It is the
    one figure in the deck that is not drawn from this run, so it is taken
    from the package rather than from the bundle, and it is dropped rather
    than raising if the file is not beside the code.

    The observation-gap scan over the periods closes the notes, for the reason
    the periods table sits here at all: a gap is a hole in the calendar's
    coverage, and it qualifies the window rather than any one statistic
    computed inside it. The rest of the scan is on the slide after this one
    (see `window_gap_notes` and `sample_gap_notes`, which between them account
    for every analysis R scanned).
    """
    tables = [study_window_table(bundle)] if requires_study_window(bundle) else []
    figures = [OPENING_DIAGRAM] if OPENING_DIAGRAM.exists() else []
    # The diagram's notes lead when there is a diagram: it is what an audience
    # has to be talked through on that slide, and the rest of these qualify the
    # deck rather than the page.
    notes = list(OPENING_DIAGRAM_NOTES) if figures else []
    notes += [
        "The numbers in this deck come from the mLOS analysis, which has its "
        "own test suite and its own methods document. The slides around them "
        "are generated by a builder that is still being written: what it "
        "chooses to show, and how it arranges it, will change.",
        "The two stamps at the foot of this slide are two different events, and "
        "both are computation times rather than anything the shelter did. If "
        "the deck is much newer than the statistics, it was rebuilt from a "
        "bundle computed earlier and shows the statistics that run generated on "
        "that day. The stretch of shelter time behind the numbers is the study "
        "window, in the table on this slide.",
    ]
    if tables:
        notes.append(
            "The periods are a setting, not something the data decided. They "
            "partition the window, each one taking its start date and leaving "
            "its end date to the next, so a stay open across a boundary is "
            "counted in both periods by the per-period analysis and once by "
            "everything on the slide that follows.")
    notes.extend(window_gap_notes(bundle, vocab))
    return Slide(
        title=DECK_TITLE,
        bullets=list(OPENING_BULLETS),
        figures=figures,
        tables=tables,
        footnote=provenance(bundle, now),
        notes=notes,
        # The one finding the opening carries, and it rides the slide that
        # is never absent: a curve the deck plots and cannot estimate is a
        # finding that must not be lost because a bundle had no summary slide.
        # Leading the closing list is right for it, since it qualifies
        # everything gathered after it.
        findings=findings_for_gaps(bundle, vocab),
        # The remedy belongs beside the finding, and both are gated on a gap
        # inside the plot: a settings change is for a curve someone is reading.
        recommendations=gap_remedy(bundle, vocab),
        layout="TITLE",
    )


def summary_slide(bundle: Bundle, vocab: Vocabulary) -> Slide | None:
    """What was analyzed: the sample, how it ended, and how it divides.

    Small tables side by side rather than a slide each, because none of them is
    a finding and together they answer one question. There are at most three:
    the sample, and a tally per stratifying field small enough to list. A run
    missing any of them shows the rest; with none there is no slide, which is
    the ordinary absence rule and not a failure.
    """
    tables = [sample_table(bundle, vocab)] if requires_sample(bundle) else []
    listed = [stratifier for stratifier in summary_fields(bundle)
              if requires_level_counts(bundle, stratifier)]
    tables.extend(level_counts_table(bundle, stratifier, vocab)
                  for stratifier in listed)
    if not tables:
        return None

    notes = [
        "Everything on this slide describes the data after it was narrowed to "
        "the study window. None of it is a model output, and none of it is a "
        "raw count from the data file either: rows outside the window, "
        "duplicate stays and overlapping stays are already gone.",
        "Stays and intakes differ by the stays that were already open when "
        "observation began, which the analysis enters at the window boundary "
        "rather than at intake. A stay that ran past the cap is counted in "
        "full up to it, and the days beyond it are excluded from every "
        "duration the deck reports.",
        "Outcome counts are tallies from the data, not the competing-risk "
        "analysis. The slides at the end of the deck are what the analysis "
        "makes of them.",
    ]
    if listed:
        notes.append(
            "Each stay belongs to exactly one level of each field, so the "
            "tallies add up to the stay count beside them. They are counted "
            "once per stay, not once per period, so they do not match the "
            "period-level counts elsewhere in the deck.")
    if len(listed) < len(summary_fields(bundle)):
        notes.append("A field with more levels than this run plots is left off "
                     "rather than listed level by level.")
    # Whether the whole sample and each field were observed without a hole in
    # them, which belongs to the slide that says what was analyzed rather than
    # to the findings. Said whichever way it comes out, unlike the caveats
    # later in the deck: see `_gap_notes`. The periods are scanned too, and
    # reported on the slide before this one, which is where they are listed.
    notes.extend(sample_gap_notes(bundle, vocab))

    return Slide(
        title="What was analyzed",
        tables=tables,
        notes=notes,
        layout="TABLES",
    )


def opening_slides(bundle: Bundle, vocab: Vocabulary,
                   now: datetime | None = None) -> list[Slide]:
    """The title slide and the descriptive summary, in that order.

    Gathered into one function so that `build` and anything counting slides
    agree on what the opening is, rather than each assembling its own idea of
    it.
    """
    slides = [title_slide(bundle, vocab, now)]
    summary = summary_slide(bundle, vocab)
    return slides if summary is None else slides + [summary]


def los_by_stratifier(bundle: Bundle, stratifier: str, vocab: Vocabulary,
                      settings: Settings | None = None) -> Slide | None:
    """The slide the design brief asked for, one stratifier at a time."""
    if not requires_full_table(bundle, stratifier):
        return None

    figures = _los_figures(bundle, stratifier)

    settings = settings or Settings()
    emphasis = settings.emphasis_for(stratifier)

    full = full_table(bundle, stratifier)
    highlights = highlights_table(bundle, stratifier, full, pinned=emphasis.levels)
    # The same columns the whole-sample slide leads with. The rest of the table
    # is what a resident still owes, which is a whole-sample story here: the
    # remaining-LOS curve is marked per level nowhere, and thirteen columns of
    # several levels each is a sheet rather than a slide. The workbook has it.
    highlights = sub_table(highlights, LOS_SLIDE_MEASURES)

    label = vocab.stratifier(stratifier).label
    notes = [
        f"Left: Kaplan-Meier survival by {label}, the arriving cohort's view. "
        f"Right: in-care tenure profile, the standing population's view.",
        "The two answer different questions and routinely disagree: a level "
        "whose stays are long accumulates residents, so its typical resident "
        "has been in care far longer than its typical arrival will stay.",
    ]
    # Where the three marks on a figure disagree about which levels are ahead.
    # Judged on the full table, not the highlights: a pair that swaps places is
    # a caution about the ranking the slide is presenting, whether or not both
    # of its levels won a row.
    notes.extend(order_shift_notes(full, label, vocab))
    # How far apart this stratifier's levels are, and whether that earned it
    # the slide after this one. It sits here rather than on that slide because
    # a stratifier that failed the test HAS no slide after this one, and the
    # number is most worth reading in exactly that case.
    notes.extend(salience_notes(bundle, stratifier, emphasis, vocab))
    notes.extend(los_standing_notes(bundle, stratifier, vocab))

    return Slide(
        title=f"LOS by {label}",
        figures=figures,
        table=highlights,
        notes=notes,
        findings=(findings_for_stratifier(bundle, stratifier, full, label)
                     + findings_for_order_shifts(full, label)),
        # Four rules read this stratifier's levels and none of them fires on a
        # healthy one: a dimension that did not separate, a tail that runs far
        # past its middle, a hazard that falls faster inside a level than
        # outside it, and a cap holding back a real share of the stays. The
        # fifth, about levels too small to estimate, rides the robustness slide
        # where the margins it reads are already on the page.
        recommendations=(dimension_not_separating(bundle, stratifier, vocab)
                         + tail_spread(bundle, stratifier, vocab)
                         + falling_hazard(bundle, stratifier, vocab)
                         + cap_binding(bundle, stratifier, vocab)),
    )


def los_overall(bundle: Bundle, vocab: Vocabulary) -> Slide | None:
    """The whole sample, as the baseline the stratified slides are read against.

    Its own rule rather than `los_by_stratifier` with a special case, because
    almost everything that function does is about comparing levels and none of
    it applies here: there is no highlights selection to make from one row, no
    level worth pinning, and no highest or lowest to flag. What is left is the
    two figures, one row of numbers, and a different thing to say about them.

    Its figures come from the manifest under stratifier `"all"`, the same key
    its numbers come from, so nothing here has to know that R draws the pooled
    plots by a different code path and files them under `_unified` names.
    """
    if not requires_full_table(bundle, "all"):
        return None

    figures = _los_figures(bundle, "all")

    # One table for both whole-sample slides, divided between them: this slide
    # takes the arrivals and the length of stay, the next takes what the
    # standing population still owes, and the tenure trio is on both because the
    # tenure figure is on both. Sliced rather than built twice, so the two
    # slides cannot print different numbers for the same measure.
    full = full_table(bundle, "all")

    notes = [
        "Left: the Kaplan-Meier survival curve over every stay in the data. "
        "Right: the in-care tenure profile of the standing population those "
        "stays imply. This is the baseline; the slides that follow split it.",
        "One row, and the two halves of it disagree on purpose. Median LOS "
        "describes an animal arriving; median tenure describes an animal here "
        "now. Both come from the same curve. Long stays accumulate in the "
        "population while short ones pass through, so on a shelter the resident "
        "figures run longer, usually by a lot.",
        "Where the heavy tail comes from is worth having ready, because the "
        "answer is usually not that any one kind of animal has an unpredictable "
        "stay. Mixing populations produces it on its own. Two groups whose "
        "stays are each perfectly memoryless, a constant discharge hazard and "
        "no tail at all, but at different rates, pool into a distribution with "
        "a falling hazard and a heavy tail: early on the quick group is "
        "leaving and sets the pace, and what is left later is increasingly the "
        "slow group. The pooled curve is then a fact about the shelter's MIX, "
        "and the slides that split it are where the components show up "
        "separately.",
        "Which way that gap goes is a property of the spread of the stays, not "
        "of the shelter's good intentions, and it has an exact form: mean "
        "tenure is about half the mean stay times one plus the squared "
        "coefficient of variation. A constant discharge hazard puts the two "
        "level. A heavy tail, which is the usual shelter case and always what a "
        "falling hazard produces, puts residents ahead. Stays that all ran to "
        "much the same length would put residents BEHIND, at about half the "
        "stay, so the gap is read off this table rather than assumed. Note what "
        "is always true and is a different statement: the total stays of the "
        "animals in care now, start to finish, are longer than an arriving "
        "animal's on any shelter, because a long stay is more likely to be "
        "caught in the building than a short one. This slide's tenure figures "
        "are time served out of that total, not the total.",
        "Both figures carry the same three dashed marks, red for the median, "
        "orange for the 90th percentile, green for the mean, each with its "
        "value in the legend. A mark that falls beyond the right edge keeps "
        "its legend row and says it is off scale rather than disappearing, "
        "which on a shelter is usually the resident 90th percentile and is a "
        "finding rather than a nuisance.",
    ]
    notes.extend(los_standing_notes(bundle, "all", vocab))

    return Slide(
        title="How long stays last, over the whole sample",
        figures=figures,
        table=sub_table(full, LOS_SLIDE_MEASURES),
        notes=notes,
        # Two, and the second is about the slides that follow rather than about
        # this one: which split separates the shelter furthest. It rides here
        # because this is the baseline they all split, so it reads as a preview.
        findings=findings_for_overall(full) + findings_for_salience(bundle, vocab),
    )


def resident_outlook(bundle: Bundle, vocab: Vocabulary) -> Slide | None:
    """What an animal already in care still owes, read at the tenures that mean
    something.

    Its own slide rather than a third figure on the one before it, and built to
    the same shape as that one: the standing population on the left, the
    remaining-LOS curve beside it, the numbers underneath.

    The left figure is the census by tenure, which is the WEIGHT the right-hand
    curve has to be read against. Future demand is the number of residents at
    each tenure times the days each of them still owes, summed, so the two
    figures multiply and the slide holds both factors. The in-care tenure
    profile that used to sit there is the same information integrated, the tail
    of this curve rather than the curve, and a cumulative form cannot be
    multiplied by the one beside it.

    It follows the whole-sample slide immediately, and its table is the other
    half of that slide's: the tenure trio in both, then what the curve reads at
    each of them.
    """
    figures = [f for f in (bundle.figure("km_census_by_tenure", "all"),
                           bundle.figure("km_remaining_los", "all")) if f is not None]
    if not requires_full_table(bundle, "all") or not figures:
        return None

    notes = [
        "Left is the shelter's standing population, laid out by how long each "
        "animal has been here: the expected number in care at exactly that "
        "tenure, on an average day. It starts at the daily intake rate, since "
        "everyone arriving today is at tenure zero, and the area under it is "
        "the whole census. Right is what each of those animals still owes. The "
        "slide holds the two factors of one multiplication, which is the "
        "planning reading below.",
        "The left figure is a count at each tenure, not a share of anything "
        "and not a cumulative curve: it says how many animals have precisely "
        "that many days behind them, never more than or fewer than. Its "
        "falling shape carries no news, since fewer animals reach each further "
        "day whatever the hazard does; what it shows is where the population "
        "actually sits, which on a shelter is a tall spike of new arrivals and "
        "a long flat tail of residents nobody would have guessed at.",
        "Read the right-hand slope first. A rising curve says the longer an "
        "animal has been here, the longer it still has to go, which is what a "
        "falling discharge hazard looks like from the standing population's "
        "side and is the usual shelter shape. A falling curve would say the "
        "opposite, that stays run to a length and time served is time off the "
        "total.",
        "Both figures carry the same three marks, the median, P90 and mean "
        "tenure of the animals in care, because both are readings of the same "
        "tenure distribution: the left curve is its shape and the profile on "
        "the slide before was its tail. The right-hand legend reports what the "
        "remaining-LOS curve reads at each mark, and the table pairs them off. "
        "The marks are borrowed because that curve has no median of its own "
        "worth taking: it is a function of tenure, not a distribution over "
        "animals, so a median of its values would be a median over days on a "
        "chart, which answers nothing. Remaining stay AT the median tenure is "
        "a statement about an animal, the one in the middle of the population "
        "in the building on an average day, and that is the number to quote "
        "off this slide.",
        "One caution if anyone asks about the green mark. The stay read at the "
        "mean tenure is not the average remaining stay across residents. That "
        "average is the mean tenure plus exactly one day, and it is the last "
        "column of the table, headed Remaining per resident; it is much the "
        "smaller of the "
        "two, because the curve climbs steeply early and then flattens, so "
        "reading it at the average tenure is not the same as averaging it over "
        "residents. Quote the mark for a typical resident's outlook, quote the "
        "last column for the whole population's per-head workload.",
        "A forward planning view multiplies the two figures day by day: the "
        "residents at each tenure times the days they still owe at that "
        "tenure, summed over the tenures, is the care the current population "
        "is already committed to, within the cap. That total is on the "
        "workload slide later in this section.",
    ]
    notes.extend(los_standing_notes(bundle, "all", vocab))

    full = full_table(bundle, "all")
    table = sub_table(full, OUTLOOK_SLIDE_MEASURES)
    # The vocabulary heads this column "remaining", which is exactly what the
    # three columns to its left also are. Everywhere else that is unambiguous;
    # here the whole slide turns on the difference, so this table names it.
    table.headers["per_resident_future_days"] = "Remaining per resident"

    return Slide(
        title="What an average day's residents still owe",
        figures=figures,
        table=table,
        notes=notes,
        findings=findings_for_outlook(full),
    )


# The whole-sample outlook slide, and the same slide per level. Both are built
# on the same pair of figures, census by tenure against remaining LOS, and on
# the same measures. What differs is where the numbers are read.
#
# The unified census figure carries the three tenure marks and its legend
# prints them. The stratified one carries none, and that is R's decision rather
# than an omission here: each level has its own median, P90 and mean tenure, so
# a panel of curves has no single curve to hang one set on (see
# .plot_km_companion in mlos_km.R). The stratified slide's numbers therefore
# live entirely in its table, one row per level, and its figures are there for
# the shape, the ordering and the relative heights.
#
# Stratified, the census figure earns its half of the page twice over: the
# curves are in animals rather than in each level's own fraction, so at any
# tenure their heights divide that day's residents between the levels.
def resident_outlook_by_stratifier(bundle: Bundle, stratifier: str,
                                   vocab: Vocabulary,
                                   settings: Settings | None = None) -> Slide | None:
    """The outlook slide for one stratifier, level by level.

    Built for a SALIENT stratifier only, and follows that stratifier's
    length-of-stay slide. Every stratifier gets the length-of-stay slide,
    because a deck that splits by a dimension at all has to show it; this one
    answers a further question, about the population standing in the building
    rather than about the stays, and a deck that asked it of every dimension
    would ask it three times of an audience that wanted it once.

    Salient means the settings said so, or, under AUTO, that the stratifier's
    levels differ in average stay by more than the threshold in
    `mlos_review.salience`. The slide before this one reports the number either
    way, so a stratifier that did not earn this slide says why.

    Its rows are the rows of the slide before it, chosen by the same selectors
    from the same table, so the pair reads as one statement about the same
    levels rather than as two tables to be matched up by eye.
    """
    settings = settings or Settings()
    emphasis = settings.emphasis_for(stratifier)
    if not earns_slides(bundle, stratifier, emphasis):
        return None

    figures = [f for f in (bundle.figure("km_census_by_tenure", stratifier),
                           bundle.figure("km_remaining_los", stratifier))
               if f is not None]
    if not requires_full_table(bundle, stratifier) or not figures:
        return None

    label = vocab.stratifier(stratifier).label
    notes = [
        f"The same question as the whole-sample slide, by {label}: what an "
        f"animal already in care still owes. Left, who is standing in the "
        f"building, by level and by how long they have been here. Right, the "
        f"remaining stay each level's residents expect as a function of that "
        f"same tenure.",
        f"The left figure is in ANIMALS, not in shares, and that is what makes "
        f"it worth the space instead of the tenure profile from the slide "
        f"before. Each curve is the expected number of that level in care at "
        f"each day of tenure on an average day, so the curves are directly "
        f"comparable: at any tenure the heights divide that day's residents "
        f"between the levels, and the area under a curve is that level's "
        f"expected census, what it contributes to the total. A level can hold "
        f"a small fraction of the "
        f"arrivals and still be most of what is standing in the building at "
        f"long tenures, which a per-level profile normalized to itself cannot "
        f"show and this figure does.",
        "The left figure is counts, not probabilities, and most of it sits "
        "below one animal. That is the arithmetic of spreading a day's arrivals "
        "over every tenure they might reach rather than a sign of something "
        "too small to matter: a curve at 0.3 on day 20 says that on an average "
        "day there is about a 30% chance of finding one animal of that level "
        "with exactly 20 days behind it, and across a 10-day band of tenures it "
        "is about 3 animals. Each curve starts at that level's daily intake "
        "rate, which is the anchor to read the rest against, and it is the "
        "area under a stretch of curve rather than its height that a plan can "
        "act on.",
        "On the right, read the slope first. A rising curve says the longer an "
        "animal has been here, the longer it still has to go, which is what a "
        "falling discharge hazard looks like from the standing population's "
        "side and is the usual shelter shape. A falling curve would say the "
        "opposite, that stays run to a length and time served is time off the "
        "total. Levels can differ in slope as well as in height, and a level "
        "whose curve climbs faster is one whose long stays run longest. The "
        "left figure falls whatever the hazard does, since fewer animals reach "
        "each further day, so its slope carries no such reading.",
        "Neither figure here carries the dashed marks the whole-sample slide "
        "has, and that is deliberate rather than missing: each level has its "
        "own median, P90 and mean tenure, and a full set of marks per curve "
        "would be unreadable on one panel. The table is where they are read. "
        "Each row pairs a level's three tenure statistics with what that "
        "level's own remaining-LOS curve reads at each of them, which is the "
        "same pairing the marks make on the slide for the whole sample.",
        "Remaining stay AT the median tenure is the number to quote: it is a "
        "statement about an animal, the one in the middle of that level's "
        "standing population. The curve itself has no median worth taking, "
        "being a function of tenure rather than a distribution over animals, "
        "so a median of its values would be a median over days on a chart.",
        "One caution on the mean column. The stay read at a level's mean "
        "tenure is not the average remaining stay across its residents. That "
        "average is the mean tenure plus exactly one day, and it is the last "
        "column, per_resident_future_days; it is much the smaller of the two, "
        "because the curve climbs steeply early and then flattens, so reading "
        "it at the average tenure is not the same as averaging it over "
        "residents. Quote the paired column for a typical resident's outlook, "
        "the last one for a level's per-head workload.",
        f"A forward planning view uses the two figures together: the left one "
        f"is the census at each tenure and the "
        f"right one is the days still owed at that tenure, so multiplying them "
        f"day by day gives the future care demand that {label}'s current "
        f"population is committed to, within the cap. Summed over the levels "
        f"it is the whole-sample figure from the earlier slide, divided into "
        f"the parts a plan can act on separately.",
    ]
    notes.extend(los_standing_notes(bundle, stratifier, vocab))

    full = full_table(bundle, stratifier)
    table = sub_table(
        highlights_table(bundle, stratifier, full, pinned=emphasis.levels),
        OUTLOOK_SLIDE_MEASURES)
    table.headers["per_resident_future_days"] = "Remaining per resident"

    return Slide(
        title=f"What an average day's residents still owe, by {label}",
        figures=figures,
        table=table,
        notes=notes,
        findings=findings_for_outlook_stratifier(full, label),
    )


# The three workload slides, in the order they build on each other: how many
# animals are in care, how long each has been here, and what those multiply to.
# Each is one question asked of every stratifier at once, three small tables
# side by side, because the comparison an audience wants is ACROSS the
# dimensions and cannot be made by turning pages.
#
# Three slides rather than one wide table because they are three different
# questions, and because the third is literally the first two multiplied:
# residents times tenure is animal-days, on the counted side and on the fitted
# side alike. An audience that has read the first two arrives at the third
# knowing what it is made of, and a discrepancy there is the two before it
# compounded rather than new evidence.
#
# Every one of them pairs a counted column with a fitted one. That pairing is
# the point of the run: it holds the model against the data, and by this slide
# the audience has taken four slides of KM-implied figures on trust.
WORKLOAD_SLIDES = {
    "census": "Who is in care on an average day",
    "tenure": "How long an average day's residents have been here",
    "animal_days": "The residents' past and future care, summed into animal-days",
}

# The one sentence each slide is FOR, set above its tables. Not a finding, which
# is generated from this run's numbers and might not fire; this is the reading
# the slide exists to support, true of any shelter, and the audience should
# have it before the columns rather than after them.
WORKLOAD_LEADS = {
    "census": ("Categories with longer stays are over-represented in the "
               "census compared with intake."),
    "tenure": ("At steady state, the average per-resident future and past "
               "stays are related."),
    "animal_days": ("Categories with longer stays dominate the expected future "
                    "animal-days for current residents on an average day."),
}


def workload_slide(bundle: Bundle, vocab: Vocabulary, section: str,
                   settings: Settings | None = None) -> Slide | None:
    """One of the three workload slides, for every stratifier that can fill it.

    A stratifier suppressed by the settings is left out, as everywhere else,
    and one whose bundle lacks either side of the comparison is left out too:
    half of this table is not a smaller version of it.
    """
    settings = settings or Settings()
    wanted = [stratifier for stratifier in bundle.stratifiers()
              if stratifier != "all"
              and not settings.emphasis_for(stratifier).suppressed
              and requires_workload(bundle, stratifier, section)]
    if not wanted:
        return None

    shared = [
        "Every figure on this slide is for an AVERAGE DAY of the study window, "
        "not for any particular date and not a total over the window. Counted "
        "columns are tallies from the data; fitted ones are what the survival "
        "curves imply at each level's observed intake rate. The table titles "
        "say which quantity is being counted and fitted, since the columns "
        "have room only to say which of the two they are.",
        "Where the two agree, and they mostly will, the reading is worth "
        "saying out loud rather than passing over: everything else in this "
        "deck is fitted, and this is the slide where the fit is checked "
        "against a count of what was actually there.",
        "Where they part, the fitted side is the one making an assumption. It "
        "takes the level's average intake rate over the whole window and asks "
        "what population that would settle at; the counted side simply "
        "remembers what happened. So a level counted ABOVE its fitted figure "
        "was carrying more than its own steady state would hold, which is what "
        "a fall in intakes leaves behind, the long stays of a busier past "
        "still in the building. Counted below, and it was still filling up "
        "behind a rise. It is a dynamic reading in a deck that otherwise "
        "looks at steady state, and the period table is where to look for "
        "it: a change over time can only show up in the dimension that divides "
        "the calendar.",
    ]

    notes = {
        "census": [
            "Two questions on one slide. How many animals does each level put "
            "in the building on an average day, and does the fitted answer "
            "match the counted one.",
            "The two percentage columns are where the first question is "
            "answered, and they are the whole reading: the first is each "
            "level's share of the ARRIVALS, the second its share of the "
            "animals in the building. A level whose second number runs above "
            "its first is over-represented among the residents, and by an "
            "exact amount, since the ratio of the two is that level's mean "
            "stay divided by the shelter's. A level at 38% of the arrivals and "
            "70% of the residents has stays about twice the shelter's average, "
            "and it is the same arithmetic either way round.",
            "This is a statement about DIFFERENCES BETWEEN levels, and it is "
            "not the same statement as the one on the whole-sample slide. That "
            "one was about the shape of a single distribution, where residents "
            "look longer-tenured than arrivals because the pooled distribution "
            "has a heavy tail, and the reason it has one is that it lumps "
            "together levels whose stays are nothing like each other. This one "
            "is the lumping itself, seen directly: even if every level's stays "
            "were perfectly predictable, the levels that stay longer would "
            "still fill the building out of proportion to how they arrive.",
        ],
        "tenure": [
            "How long the animals in care on an average day have already been "
            "here, per resident. Not how long stays last: these are the same "
            "animals as the slide before, counted by their time served rather "
            "than by their number.",
            "Read the last column against the one before it, and the whole "
            "arithmetic of this slide is on the page: what an average day's "
            "residents still have to come is what they have already served "
            "plus exactly one day, on every level, always. It is not an "
            "approximation and not a coincidence. In a population at steady "
            "state, time already served and time still to come have the same "
            "distribution, and the extra day is the day the animal is having. "
            "So an average day's residents have as much ahead of them as "
            "behind them, which is the least intuitive true thing in this deck "
            "and the one worth saying slowly.",
            "It also means this column cannot be read as an average remaining "
            "stay for an individual animal. The outlook slides earlier in the "
            "deck are where that reading lives, against the tenure the animal "
            "has actually served.",
        ],
        "animal_days": [
            "An animal-day is one animal in care for one day. It is the unit "
            "for the shelter's workload. Here, durations become a quantity of "
            "care, provided or anticipated.",
            "This table is the two before it multiplied: residents times "
            "tenure per resident is animal-days, on the counted side and on "
            "the fitted side alike, exactly. So the gap between counted and "
            "fitted here is the gap on the first slide compounded with the gap "
            "on the second, not a third piece of evidence.",
            "The days-owed column is the forward-looking one and has no "
            "counted counterpart, since nobody can count a day that has not "
            "happened. It relates to the column beside it as simply as the "
            "tenure columns did: days owed minus animal-days elapsed is the "
            "census, the number on the first slide, because every resident "
            "owes one day more than it has served. On an average day this "
            "shelter's residents have consumed a little over ten thousand "
            "animal-days and will consume the census more.",
            "Where the future workload SITS is the reading to take away, and "
            "the findings state it in words, since this table has no room for "
            "a fourth column: a level's share of the days owed is not its "
            "share of the residents, and the ratio between the two is that "
            "level's mean tenure over the shelter's. That is the inspection "
            "paradox again and says nothing about time. A level can hold a "
            "steady place in the shelter for a decade and still own far more "
            "of the days owed than of the animals, because its animals are the "
            "ones that stay. The workbook carries the share as a column.",
        ],
    }[section]

    if section == "animal_days":
        notes.append(
            "Periods carry days owed but no share of them. A day of care falls "
            "in exactly one period, so the elapsed days divide cleanly, but the "
            "days owed are a property of the population standing in the "
            "building at one moment and periods divide the calendar rather "
            "than that population. Each period's figure is the commitment an "
            "average day's residents carried under that regime, worth comparing "
            "across the periods and not a part of any one total.")

    findings = findings_for_model_drift(bundle, vocab, section)
    if section == "census":
        findings = findings_for_representation(bundle, vocab) + findings
    if section == "animal_days":
        findings = findings_for_care_days(bundle) + findings

    return Slide(
        title=WORKLOAD_SLIDES[section],
        lead=WORKLOAD_LEADS[section],
        tables=[workload_table(bundle, stratifier, vocab, section)
                for stratifier in wanted],
        notes=notes + shared,
        findings=findings,
        # The narrowing suggestion rides the animal-days slide, where the share
        # of the workload it acts on is on the page.
        recommendations=narrowing(bundle, vocab) if section == "animal_days" else [],
        layout="TABLES",
    )


def _follow_on_note(labels: Sequence[str]) -> str:
    """What the teaser promises next, given what the deck actually goes on to do.

    Written from the slides that were built rather than from the stratifiers
    the dataset happens to have, so the teaser cannot promise a breakdown this
    deck does not contain.
    """
    if not labels:
        return ("A fuller treatment breaks this down by every dimension in the "
                "data, with confidence bounds.")
    if len(labels) == 1:
        return (f"The slide that follows does exactly this by {labels[0]}, a "
                f"panel per outcome. A fuller treatment covers every dimension, "
                f"with confidence bounds.")
    listing = ", ".join(labels[:-1]) + f" and {labels[-1]}"
    return (f"The slides that follow break this down by {listing}, a panel per "
            f"outcome. Confidence bounds stay in the workbook.")


def aj_teaser(bundle: Bundle, vocab: Vocabulary,
              follow_on: Sequence[str] = ()) -> Slide | None:
    """One slide showing what competing risks can say, without saying it all.

    The two figures answer the two questions the method exists for. The
    cumulative incidence is where a stay ends up: outcomes that separate,
    rather than one survival curve that cannot tell an adoption from a
    euthanasia. The conditional mix is the follow-on a shelter actually asks:
    given an animal still here on day X, what happens to it?

    Both are drawn as stacks. Each question is about shares of a whole, which
    is what bands show and lines only imply, and a pair of figures that share a
    reading is one thing to explain from the podium rather than two. The line
    versions are where the per-outcome detail belongs, in the fuller treatment
    this slide is a teaser for.

    Deliberately no per-stratum breakdown and no confidence bounds. A teaser
    that answered everything would not be one.
    """
    if not requires_aj_teaser(bundle):
        return None

    figures = [
        bundle.figure("aj_cif", "all", variant="stack"),
        bundle.figure("aj_conditional", "all", variant="stack"),
    ]
    figures = [f for f in figures if f is not None]

    notes = [
        "Left: cumulative incidence, the probability a stay has ended each way "
        "by day X, stacked, so the top of the bands is the chance of having "
        "left at all and the space above it the chance of still being here. "
        "Right: the same analysis read forward, the outcome mix among stays "
        "still in care on day X.",
        "This is what a survival curve cannot do. One curve says whether an "
        "animal is still here; these say where it went, and treat the other "
        "outcomes as competing rather than as censoring.",
    ]
    notes.append(SHARE_AND_DAYS_NOTE)
    notes.extend(aj_window_notes(bundle, "all"))
    notes.append(_follow_on_note(follow_on))

    return Slide(
        title="Where stays end, not just how long they last",
        figures=figures,
        table=aj_teaser_table(bundle, vocab),
        notes=notes,
    )


def resident_destination(bundle: Bundle, vocab: Vocabulary) -> Slide | None:
    """Where the animals in the building today are heading, given their tenure.

    The third whole-sample competing-risk slide, and the one that joins the two
    questions the deck has asked separately. The length-of-stay section said
    how much longer a resident of a given tenure has to go; the teaser before
    this said where stays end. Neither says where THIS animal, already here
    this long, is going, and that is the question a shelter asks about the
    animals it is looking at.

    The figures are the two curves the table is read off: remaining stay
    against tenure on the left, the conditional outcome mix against tenure on
    the right. A reader can put a finger on a tenure and take a row off both.

    The mix comes from the bundle rather than from the figure's grid, so the
    number and the line a reader would draw at that tenure name the same day;
    see `outlook_by_tenure_table`.
    """
    table = outlook_by_tenure_table(bundle, vocab)
    if table is None:
        return None

    figures = [bundle.figure("km_remaining_los", "all"),
               bundle.figure("aj_conditional", "all", variant="stack")]
    figures = [figure for figure in figures if figure is not None]

    notes = [
        "Left: how much longer an animal has to go, against how long it has "
        "already been here. Right: the outcome mix it is heading for, against "
        "the same tenure. The table takes three tenures off both: the median "
        "resident, the average resident, and the long-staying one at the 90th "
        "percentile.",
        "Every outcome column is conditional on having reached that tenure. "
        "They are not the shares in the teaser before this, which are over all "
        "stays from intake; an animal that has already been here months has "
        "left most of the quick exits behind it, and the mix moves as tenure "
        "grows.",
        "The columns stop short of 100%, and `at cap` is the rest: still in "
        "care when the analysis window closes, with no outcome yet to assign. "
        "It grows with tenure, which is why it is a column rather than a "
        "footnote.",
        "The tenures are properties of the standing population, not of an "
        "arriving animal, so they run longer than the length-of-stay figures "
        "earlier in the deck. Long stays accumulate in the building while "
        "short ones pass through.",
    ]
    notes.extend(aj_window_notes(bundle, "all"))

    plot_cap = bundle.value("settings", "presentation", "plot_stay_cap")
    beyond = [label for label, value in
              zip(table.df.index, table.df[table.df.columns[0]])
              if plot_cap is not None and value > plot_cap]
    if beyond:
        notes.append(
            f"One row sits beyond the right edge of both figures: "
            f"{', '.join(beyond)} is past the plotted range, which stops at "
            f"day {plot_cap}. The number is on the curve either way, the same "
            f"way a mark that falls off scale keeps its value.")

    return Slide(
        title="Where residents are heading, given how long they have been here",
        figures=figures,
        table=table,
        notes=notes,
    )


def aj_by_stratifier(bundle: Bundle, stratifier: str, vocab: Vocabulary,
                     settings: Settings | None = None) -> list[Slide]:
    """One competing-risk SECTION for one stratifier: a slide per outcome.

    Each slide holds one outcome's cumulative incidence by level, against the
    same table of levels. The reader compares levels WITHIN a panel, which is
    the comparison the analysis supports; a plot holding outcomes and levels at
    once supports neither.

    The slides are a flip-book, one per outcome. Title, table, footnote and
    geometry are identical across the run, and the figures are identical in
    size because R draws them on one canvas with margins fixed in lines rather
    than to content. So what moves when the presenter clicks is the curves
    inside the frame, which reads as the panel changing rather than the slide
    changing. That is worth more than any static arrangement of the
    same panels: it puts one outcome in front of the audience at a time, at
    7.8 by 5.2 inches on the OC run instead of the 4.3 by 2.9 a quadrant cell
    allowed, with the numbers still in view beside it.

    The finding rides on the FIRST slide only. It is one finding about the
    stratifier, not one per outcome, and the closing section would otherwise
    print it three times.

    With no AJ figures emitted at all this degrades to a single stacked slide
    carrying just the table, in the same spirit as the LOS slide with its
    figures switched off.
    """
    if not requires_aj(bundle, stratifier):
        return []

    panels = _aj_figures(bundle, stratifier)

    settings = settings or Settings()
    emphasis = settings.emphasis_for(stratifier)

    levels = aj_levels_table(bundle, stratifier, vocab)
    flat = aj_highlights_table(bundle, stratifier, vocab, levels,
                               pinned=emphasis.levels)

    label = vocab.stratifier(stratifier).label
    title = f"Where stays end, by {label}"
    shared = [
        "In comparing levels, a high final incidence is good for L and bad for "
        "N: the panels do not share a direction, so a level that sits high on "
        "one of them is not doing better overall. Where two levels finish at "
        "the same incidence, the one that gets there sooner has spent less "
        "time in care to do it, which is unambiguously better for a live "
        "outcome and is a cost statement rather than a welfare one for a "
        "non-live one. Read the three panels together to spot the trade-offs "
        "between length of stay and the preferred outcome.",
        "The table is the end state of these curves and does not change as the "
        "panels do: where each level's stays ended up, and how long the ones "
        "that ended that way took.",
    ]
    shared.append(SHARE_AND_DAYS_NOTE)
    shared.extend(aj_window_notes(bundle, stratifier))
    # Both spread findings ride the same slide as the timings they summarize,
    # after them: one reads that table down its columns, comparing levels on an
    # outcome, and the other across its rows, comparing a level's outcomes with
    # each other.
    findings = (findings_for_aj(levels, label, vocab)
                + findings_for_outcome_spread(bundle, stratifier, label, vocab)
                + findings_for_outcome_contrast(bundle, stratifier, label, vocab))

    if not panels:
        return [Slide(title=title, table=stacked_by_measure(flat, vocab),
                      notes=["No competing-risk figures were emitted for this "
                             "run, so the table carries the slide."] + shared,
                      findings=findings)]

    slides = []
    for index, (code, figure) in enumerate(panels):
        outcome = vocab.outcome_labels.get(code, code)
        opening = (f"Cumulative incidence of {outcome} ({code}) by {label}: the "
                   f"probability a stay has ended that way by day X.")
        if index == 0:
            opening += (" The slides that follow hold everything but the "
                        "figure still and step through the other outcomes.")
        slides.append(Slide(
            # The title names the outcome and the table's own header carries an
            # arrow to its column, so the audience can see which of the three
            # they are looking at from either half of the slide. It is the one
            # thing that changes across the run besides the curves; the figure
            # and the table do not move.
            title=f"{title}: {code} {outcome} outcomes",
            figures=[figure],
            table=stacked_by_measure(flat, vocab, highlight=code),
            notes=[opening] + shared,
            # Every panel, not just the first. These findings are about the
            # stratifier's whole run of outcomes rather than about one panel,
            # and the presenter standing in front of panel three needs them as
            # much as the one standing in front of panel one. The closing
            # section de-duplicates, so carrying them three times costs nothing
            # there (see `_gathered_section`).
            findings=findings,
            layout="SPLIT",
        ))
    return slides


# The two runs of ratio slides: every stratifier's hazard ratios, then every
# stratifier's length-of-stay ratios. The same levels and the same three-column
# shape throughout, read once as a rate and once as a duration.
#
# All the hazard ratios first, and that is the argument rather than an
# arrangement. The hazard-ratio run is where the model choice is settled: two
# genuinely different estimators sit beside a parametric one, and the question
# it answers is whether the Weibull's form is making the answer. Only then are
# the length-of-stay slides worth reading, because their first column is that
# same Weibull expressed in days, and the pooled Weibull is the link between
# the two runs. Interleaving them would ask the audience to settle the model
# question three separate times, once per dimension, in the middle of a
# comparison about animals.
#
# Length of stay comes second for a second reason: it is the unit a shelter
# thinks in. A run that ends on "twice as long" has ended in the audience's
# vocabulary rather than in the estimator's.
#
# They replaced a robustness check that asked whether the pooled Cox agreed
# with a freer one. That check is still built, and still says something, but it
# was too much statistics for a practitioner and not enough rigour for a
# researcher, and it rested on a claim about the earlier slides that was not
# true: they are unadjusted Kaplan-Meier, not the pooled Cox, and they assume
# no proportional hazard at all. The pair below says the true version of what
# it was reaching for. The old slides live on at the end of the deck, where a
# question can reach them.
#
# What each pair of slides is FOR is different, and the notes have to keep them
# apart. On the hazard-ratio slide the three readings are two genuinely
# different estimators plus a parametric mirror of one of them, so the reading
# is whether the model choice matters. On the length-of-stay slide the third
# column is unadjusted, which makes the gap between it and the other two the
# amount of what the earlier slides showed that was really the mix of the other
# dimensions.
RATIO_FOOTNOTES = [
    "Estimates only; the 95% intervals are the whiskers on the figure.",
    "The reference level is 1 by definition, not by measurement.",
]


def _ratio_slide(bundle: Bundle, stratifier: str, vocab: Vocabulary,
                 figures: FigureSet, settings: Settings, panel, series,
                 kind: str, title: str, figure_title: str, description: str,
                 notes: list[str], findings: list[str] = (),
                 recommendations: list[str] = ()) -> Slide:
    """The shape both ratio slides share: dots on the left, three columns right.

    Written once because the two differ in their numbers and their notes and in
    nothing else. A second copy would be a second place to fix the day the
    layout changes, and the two slides sitting side by side in a deck is
    exactly when a drift between them would show.
    """
    figure = figures.ratio_comparison(
        panel.loc[stratifier], series, figure_title,
        stem=f"{kind}_by_{stratifier}",
        stratifier=stratifier, description=description, kind=kind,
        palette=bundle.value("palette", "stratum_colors"),
        log_scale=settings.ratio_log_scale)

    return Slide(
        title=title,
        figures=[figure],
        table=ratio_panel_table(panel, series, stratifier,
                                title=f"{kind.replace('_', ' ')} by {stratifier}",
                                footnotes=RATIO_FOOTNOTES),
        notes=notes,
        findings=list(findings),
        recommendations=list(recommendations),
        layout="SPLIT",
    )


def _reference_note(bundle: Bundle, stratifier: str, panel, series,
                    vocab: Vocabulary) -> list[str]:
    """Which level everything is divided by, and why that choice is not free.

    Named from the panel rather than from the settings, because the setting for
    periods names a policy (OLDEST, NEWEST) rather than a level and the level
    it resolved to depends on which periods held data.
    """
    keys = [key for key, _, _ in series]
    rows = panel.loc[stratifier]
    reference = [level for level in rows.index
                 if all(rows.at[level, key] == 1 for key in keys
                        if key in rows.columns
                        and rows.at[level, key] == rows.at[level, key])]
    if not reference:
        return []
    label = vocab.stratifier(stratifier).label
    stays = None
    if bundle.has("strata", stratifier, "observations"):
        counts = bundle.stratum(stratifier, "observations").get("total_observations")
        if counts is not None and reference[0] in counts.index:
            stays = counts[reference[0]]
    size = f", which holds {stays:,.0f} of this {label}'s stays" if stays else ""
    return [
        f"Every number on this slide is a multiple of {reference[0]}{size}. That "
        f"choice is not neutral and it is worth saying out loud. The reference "
        f"is the denominator of every ratio, so its own sampling error is in "
        f"every interval on the figure: a reference level with few stays makes "
        f"all the whiskers wide at once, and one that sits at an extreme of "
        f"the stay distribution, all short stays or all long ones, moves every "
        f"estimate together and can make a middling level look remarkable. "
        f"Neither is a finding about the other levels. If the reference looks "
        f"wrong for the audience, it is a setting, and the analysis can be "
        f"rerun against a level the room already has a feel for."
    ]


def hazard_ratios_by_stratifier(bundle: Bundle, stratifier: str, panel,
                                vocab: Vocabulary, figures: FigureSet,
                                settings: Settings,
                                findings: list[str] = (),
                                recommendations: list[str] = ()) -> Slide | None:
    """The three hazard ratios for one stratifier: how much sooner they leave."""
    if stratifier not in panel.index.get_level_values("stratifier"):
        return None

    label = vocab.stratifier(stratifier).label
    notes = [
        f"One question, three ways of answering it: how much sooner or later "
        f"does each {label} leave care than the reference level. A ratio above "
        f"1 means a faster discharge and so a shorter stay; below 1, longer. "
        f"The whiskers are 95% intervals.",
        "The two Cox columns differ in what they assume about everything else. "
        "The pooled fit puts every dimension in one model with one shared "
        "baseline hazard; the stratified one gives each combination of the "
        "other dimensions its own baseline and asks only about this one. Where "
        "they sit on top of each other, the shared baseline was costing "
        "nothing.",
        "The Weibull column is the same pooled model with a Weibull baseline "
        "imposed on it, and it is the one that can differ for a reason that is "
        "not about this dimension at all. Cox lets the baseline hazard take "
        "any shape; Weibull makes it a power of time. Where the two part "
        "company, the parametric shape is not fitting, which is a statement "
        "about the shelter's discharge pattern rather than about the level in "
        "front of you.",
        "This slide is also where the length-of-stay slides later in the deck "
        "are earned. Their leading column is this Weibull expressed in days, "
        "the same estimate under a different link: hazard ratio is the time "
        "ratio to the power of minus the fitted shape, so on OC2 a level 3.34 "
        "times longer at a shape of 0.824 is at 0.37 times the hazard. "
        "Reading the "
        "take from here instead is whether the Weibull column tracks the Cox "
        "ones: where it does, the parametric form is carrying no weight of its "
        "own and the days version can be read straight; where it does not, "
        "that level's time ratio is partly a statement about the assumed "
        "shape, and the Kaplan-Meier column beside it is the check.",
    ]
    notes.extend(_reference_note(bundle, stratifier, panel, HR_SERIES, vocab))

    return _ratio_slide(
        bundle, stratifier, vocab, figures, settings, panel, HR_SERIES,
        kind="hazard_ratios",
        title=f"Hazard ratios (HR) by {label}, three ways",
        figure_title=f"HR by {label.title()}: Three Estimates",
        description=(f"Hazard ratios by {label} from the pooled Cox, the "
                     f"stratified Cox and the pooled Weibull, with 95% "
                     f"confidence intervals."),
        notes=notes, findings=findings, recommendations=recommendations)


def los_ratios_by_stratifier(bundle: Bundle, stratifier: str, panel,
                             vocab: Vocabulary, figures: FigureSet,
                             settings: Settings) -> Slide | None:
    """The same three levels in days rather than in hazard, and the mix effect."""
    if stratifier not in panel.index.get_level_values("stratifier"):
        return None

    label = vocab.stratifier(stratifier).label
    notes = [
        f"The same comparison as the hazard-ratio slides, in the unit the "
        f"audience actually thinks in: how many times as long does each "
        f"{label} stay, against the reference level. Above 1 is longer. The "
        f"first column is the link back: it is the pooled Weibull from the "
        f"hazard-ratio run, the same fit expressed in days rather than in "
        f"rate.",
        "The first two columns are fitted and adjusted. Both hold the other "
        "dimensions constant, so each says what this dimension is worth once "
        "the others are accounted for; the second also lets those other "
        "dimensions have their own hazard shapes rather than one shared shape, "
        "which is the parametric answer to the freer Cox in the run before.",
        "The third column is the one to talk about. It is Kaplan-Meier, each "
        "level's own restricted mean stay against the reference level's, and "
        "it adjusts for NOTHING. It is also what every length-of-stay slide "
        "earlier in this deck showed. So the gap between it and the two "
        "columns beside it is not two methods disagreeing: it is how much of "
        "what those slides showed was really the mix of the other dimensions. "
        "The splits are not independent of each other, so a level can look "
        "long simply because it is full of animals that are long for another "
        "reason.",
        "Two smaller cautions. The KM column is restricted to the stay cap "
        "while the fitted ones are not, so where a real share of stays is "
        "still in care at the cap the KM ratio is pulled toward 1. And the "
        "fitted columns are ratios of a whole distribution under a parametric "
        "model, which multiply every quantile alike, while the KM column is a "
        "ratio of two restricted means; where a level's hazard shape differs "
        "from the reference's, those are not quite the same question.",
    ]
    notes.extend(_reference_note(bundle, stratifier, panel, LOS_SERIES, vocab))

    return _ratio_slide(
        bundle, stratifier, vocab, figures, settings, panel, LOS_SERIES,
        kind="los_ratios",
        title=f"Length of stay by {label}, adjusted and not",
        figure_title=f"LOS Ratio by {label.title()}: Three Estimates",
        description=(f"Length-of-stay ratios by {label} from the pooled "
                     f"Weibull, the freed-shape Weibull and the ratio of "
                     f"Kaplan-Meier restricted means, with 95% confidence "
                     f"intervals."),
        notes=notes)


def cox_comparison_by_stratifier(bundle: Bundle, stratifier: str,
                                 comparison, vocab: Vocabulary,
                                 figures: FigureSet) -> Slide | None:
    """One robustness slide for one stratifier: paired bars against a table.

    Whether the pooled Cox's hazard ratios survive giving every combination of
    the other splits its own baseline, shown as the same ratios refit both
    ways. It is built into the reserve section rather than the flow, because it
    asks a question about the estimator and not about the shelter; see
    reserve_section.

    It is NOT a check on the length-of-stay slides earlier in the deck. Reading
    it as one is what demoted it: those slides are unadjusted Kaplan-Meier and
    assume no proportional hazard at all, so there is no pooled-Cox adjustment
    there for this to be testing. The comparison itself is not lost:
    hazard_ratios_by_stratifier carries both Cox fits as two of its three
    columns, and its notes say what their sitting on top of each other means.
    This slide is that same question drawn at length, for a room that asks.

    Its figure is drawn here rather than placed (see figures.py), because the
    comparison exists nowhere in the R output. It is no longer the only drawn
    one: _ratio_slide draws the three-estimate dots the same way, for the
    slides that replaced this one. The figure goes to the figures directory
    beside the deck, where a reader can pick it up for something else, and is
    regenerated on every build.

    Returns None when the stratifier has no stratified fit to compare against,
    which is the ordinary case for a run with only one usable stratifier.
    """
    if not requires_cox_comparison(comparison, stratifier):
        return None

    label = vocab.stratifier(stratifier).label
    table = cox_comparison_table(comparison, stratifier)
    # The slide title expands the abbreviation once so the figure below it can
    # use it: two lines of "Hazard Ratios by ..." stacked on one page spends
    # the width twice to say the same thing, and the figure is the one with
    # less room.
    figure = figures.hazard_ratio_comparison(
        comparison.loc[stratifier],
        f"HR by {label.title()}: Pooled vs Stratified Cox",
        stem=f"hr_comparison_by_{stratifier}",
        stratifier=stratifier,
        description=(f"Hazard ratios by {label} from the pooled Cox regression "
                     f"and from the fit that stratifies on the other splits, "
                     f"with 95% confidence intervals."),
        palette=bundle.value("palette", "stratum_colors"),
    )

    return Slide(
        title=f"Hazard ratios (HR) by {label}, against a freer model",
        figures=[figure],
        table=table,
        notes=[
            f"Both models estimate the same thing: how much sooner or later "
            f"each {label} leaves care, relative to the reference level. They "
            f"differ in what they assume about everything else. The pooled "
            f"model, which is the one every earlier slide rests on, gives every "
            f"combination of the other splits one shared baseline. The "
            f"stratified model gives each combination its own.",
            "A bar above 1 means that level leaves sooner, so shorter stays; "
            "below 1, longer. The whiskers are 95% confidence intervals, and "
            "the reference level is drawn faintly at exactly 1 because it is "
            "the denominator of the others rather than an estimate.",
            "The last two columns ask different questions and are worth "
            "keeping apart. The p-value asks whether there is evidence the two "
            "models disagree, so a SMALL one would be the finding, and none of "
            "these is small. “Agreement” asks how closely they are shown to "
            "agree, and a small one is the finding there too: 7% means the "
            "data establish, at 95% confidence, that the two are within 7% of "
            "each other.",
            "Why both. A large p-value on its own cannot tell real agreement "
            "from a level too thin to establish anything, because both look "
            "the same to it. The margin separates them: it can only be earned "
            "by having enough stays. So a large p beside a tight margin is "
            "what agreement looks like, while a large p beside a wide margin "
            "means nothing was settled either way.",
            "Both columns assume the two models are statistically independent, "
            "which they are not. They are fitted to the same stays, and their "
            "correlation is almost certainly positive, so the real uncertainty "
            "about their difference is smaller than what is assumed here. That "
            "makes both columns cautious rather than optimistic: the p-values "
            "are larger than they should be, so a genuine difference would be "
            "under-reported rather than invented, and the margins are wider "
            "than they need to be, so the agreement is at least as close as "
            "stated. Neither column can flatter the result.",
            "Where the two bars sit on top of each other, the shared baseline "
            "was costing nothing and the earlier slides stand as they are. A "
            "level whose margin is wide is thinly populated, and the honest "
            "reading there is that little was established either way.",
        ],
        findings=findings_for_cox_comparison(comparison, stratifier, label),
        # The levels this slide could not establish anything about, and what to
        # do about them. It reads the margins already on the page, which is why
        # it lives here rather than on the length-of-stay slide.
        recommendations=unestimable_levels(bundle, stratifier, comparison, vocab),
        layout="SPLIT",
    )


def aj_teaser_stratifier(bundle: Bundle, settings: Settings) -> str | None:
    """The stratifier whose competing-risk panels are the easiest to read.

    Fewest levels wins, because levels are lines on the plot and a teaser is
    judged on whether the audience can see the point without being walked
    through it. A stratifier the run drew no AJ figures for is not a candidate
    at all: the slide would be a table, which is not what this pick is for.

    Ties go to the bundle's own stratifier order, which is a tie-break and not
    a preference. Something better could be said here later, about which
    dimension the audience came to hear about; for a teaser, fewest lines is
    enough.
    """
    fewest = None
    for stratifier in bundle.stratifiers():
        if stratifier == "all" or settings.emphasis_for(stratifier).suppressed:
            continue
        if not requires_aj(bundle, stratifier):
            continue
        if not _aj_figures(bundle, stratifier):
            continue
        count = len(bundle.levels(stratifier))
        if fewest is None or count < fewest[0]:
            fewest = (count, stratifier)
    return None if fewest is None else fewest[1]


def _gathered_section(slides: list[Slide], gather, title: str, note: str,
                      lead: str = "", budget: int | None = None) -> list[Slide]:
    """One closing section, paginated: the shape both of them share.

    Parameterised by an accessor rather than by a field name, so what is
    gathered is decided by the caller and nothing here has to know how a slide
    stores it.

    `lead` heads the section's FIRST page and no other: it qualifies the list
    as a whole, and repeating it on every continuation would be a reader's cue
    that each page is a fresh claim. The renderer is told what the lead costs
    so the first page breaks one bullet earlier rather than running the last
    line off the bottom.
    """
    # De-duplicated, keeping the first appearance. A run of slides that share
    # one set of findings hangs that set on every one of them, so that a
    # presenter reading any panel's notes sees what the run found rather than
    # only the panel that happened to be built first (see `aj_by_stratifier`).
    # Gathering them verbatim would then print each one as many times as there
    # are panels.
    seen = set()
    gathered = []
    for slide in slides:
        for line in gather(slide):
            if line not in seen:
                seen.add(line)
                gathered.append(line)
    return [
        Slide(title=title if index == 0 else f"{title}, continued",
              notes=[note],
              bullets=page,
              lead=lead if index == 0 else "")
        for index, page in enumerate(
            bullet_pages(gathered, lead_height(lead), budget))
    ]


# What the recommendations section is called, and what it is careful to say it
# is not. A generated suggestion is not a work plan: it is what this run's own
# numbers point at, which is worth an analyst's half hour and is not a decision
# anyone has taken.
RECOMMENDATIONS_TITLE = "Where to look next"
RECOMMENDATIONS_NOTE = (
    "Generated from what this run found, by rules that stay silent when they "
    "have nothing to say: each of these fired because a number on an earlier "
    "slide crossed a threshold, and most decks will not carry all of them. "
    "They are suggestions for the next analysis, not a plan anyone has agreed "
    "to, and each names the setting or the data change it would take.")


def recommendations_section(slides: list[Slide],
                            budget: int | None = None) -> list[Slide]:
    """Gather what the section slides recommended, after the findings.

    After rather than among them, because they are a different speech act: a
    finding says what the data said and a recommendation says what to do,
    and an audience reading one list has to be able to tell which is which
    without a tag on every line. Last in the deck, since what happens next is
    where a presentation ends.
    """
    return _gathered_section(slides, lambda slide: slide.recommendations,
                             RECOMMENDATIONS_TITLE, RECOMMENDATIONS_NOTE,
                             budget=budget)


def reserve_section(bundle: Bundle, comparison, vocab: Vocabulary,
                    figures: FigureSet, settings: Settings) -> list[Slide]:
    """The slides kept back for questions, behind one page that says so.

    The robustness check: whether the pooled Cox's hazard ratios survive giving
    every combination of the other splits its own baseline. It is a real
    check with a real answer, and it is not a presentation: it asks a question
    about the estimator rather than about the shelter, and a room that has not
    asked it does not want six minutes on it.

    Nothing here is gathered into the closing sections. What these slides found
    is already in them, carried by the hazard-ratio slides that replaced them,
    and the divider is built after those sections precisely so that a second
    copy cannot creep in.
    """
    built = []
    for stratifier in bundle.stratifiers():
        if stratifier == "all" or settings.emphasis_for(stratifier).suppressed:
            continue
        slide = cox_comparison_by_stratifier(bundle, stratifier, comparison,
                                             vocab, figures)
        if slide is not None:
            # Emptied rather than left as they were: these sentences are on the
            # hazard-ratio slides now, and a slide that carries them here too
            # would print them twice in one deck's notes.
            slide.findings = []
            slide.recommendations = []
            built.append(slide)
    if not built:
        return []

    divider = Slide(
        title="Extra: robustness of the hazard ratios",
        bullets=["Not part of the presentation.",
                 "Kept for questions about whether the model's assumptions "
                 "are doing the work."],
        notes=["The slides after this one ask whether the hazard ratios "
               "survive a freer model, one that gives every combination of "
               "the other splits its own baseline hazard rather than a shared "
               "one. The answer is on the deck's earlier hazard-ratio slides "
               "in one sentence; these are where it is shown.",
               "They are here rather than in the flow because they are a "
               "question about the estimator, not about the shelter. Skip "
               "them unless someone asks."],
        layout="TITLE",
    )
    return [divider] + built


# The two citations the educational opener carries. Written here and checked
# against their sources by the test suite rather than trusted to review:
# CITATION.cff holds the software DOI, and the user guide's reference list
# holds the paper, so a slide naming a DOI neither of them names is a citation
# to something that does not exist.
PAPER_CITATION = ("Mavrovouniotis ML. PLOS ONE. 2026;21(1):e0342102. "
                  "doi:10.1371/journal.pone.0342102")
SOFTWARE_DOI = "10.5281/zenodo.22083814"


def los_overview_slide(bundle: Bundle, vocab: Vocabulary) -> Slide:
    """What length of stay means over a period, before any of it is measured.

    An alternate opening. It asks the question the deck's whole method answers,
    which is not how long stays last but which stays a period is allowed to
    count, and it carries the title slide's own diagram because that picture is
    the answer: a period sees whole stays, and it sees parts of stays that
    began before it or end after it.

    Deliberately not filled. Its right half is the diagram and its left is a
    short list, and the room left over is room a figure drawn from the data can
    take later.

    Built unconditionally. Nothing on it is read from this run except the
    version in the software citation, so there is no bundle that cannot carry
    it.
    """
    version = bundle.value("run", "mlos_version")
    software = f"mLOS {version}. doi:{SOFTWARE_DOI}" if version else \
               f"mLOS. doi:{SOFTWARE_DOI}"

    bullets = [
        Bullet("How do you compute LOS for a specific period?"),
        Bullet("Not just animals with outcomes in that period\u2026", 1),
        Bullet("\u2026 but also animals straddling the beginning or end.", 1),
        Bullet("Method & software"),
        Bullet(PAPER_CITATION, 1),
        Bullet(software, 1),
        Bullet("Aside from this subtlety, what are good ways to look at"),
        Bullet("LOS metrics", 1),
        Bullet("LOS distribution", 1),
        Bullet("Outcomes by tenure", 1),
    ]

    notes = [
        "The question this slide asks is the one the method exists to answer. "
        "A period's length of stay is not the average of the stays that ended "
        "in it: that counts an animal only once it has left, which throws away "
        "everyone still in care and every stay that began earlier, and both "
        "groups are the long ones.",
        "The diagram is the same one the deck opens with. A period sees whole "
        "stays, stays already running when it began, and stays still running "
        "when it ended, and survival analysis is what lets all three "
        "contribute what they know without pretending to know the rest.",
        "The citations are for a room that asks where the method comes from. "
        "The paper is the definition and the worked examples: Mavrovouniotis "
        "ML. Use of Kaplan-Meier and Cox regressions in the distribution of "
        "length of stay in animal shelters for pre-specified calendar "
        "periods: Definition, computation, and examples of dog length of stay "
        "in Orange County California. PLOS ONE. 2026;21(1):e0342102. The "
        "software line names the version that produced these numbers, which "
        "is what says which release a result came from.",
        "The three readings at the foot are what the rest of this section, "
        "and the deck itself, go on to show: summary numbers for how long "
        "stays last, the whole distribution rather than a summary of it, and "
        "where stays end read against how long they had been going.",
    ]

    return Slide(
        title="Looking at Length of Stay (LOS)",
        bullets=bullets,
        figures=[OPENING_DIAGRAM] if OPENING_DIAGRAM.exists() else [],
        notes=notes,
        layout="TITLE",
        # The diagram carries no value anyone reads off it: it is three stays
        # against a period, drawn to be recognized rather than measured. So the
        # room it gives up to a template's artwork costs the slide nothing.
        schematic=True,
    )


def probability_intervals_slide(bundle: Bundle, vocab: Vocabulary) -> Slide | None:
    """How to read a distribution cut into intervals, on the whole sample.

    The two bar figures beside each other rather than above each other, which
    is how they are drawn to be read: R lines their bars up so one sits over
    the other on a page. A slide is wider than it is tall, and two 3:2 panels
    side by side fill it where two stacked panels would each be squeezed to a
    third of the height.

    The tables under them are the two the deck already shows, narrowed and
    retitled. They are here so the picture can be reconciled against the
    numbers the audience has already been given: the median sits inside one of
    these intervals, and the outcome shares are what the right-hand figure
    divides interval by interval.

    Built only where the run drew the figures, which is where
    `probability_mass_width` is set. Nothing here computes a bin; the figures
    and the interval masses come from the analysis.
    """
    figures = [bundle.figure("aj_mass", "all", variant="stack"),
               bundle.figure("aj_fraction", "all", variant="stack")]
    # Both or neither. The slide teaches the pair: one figure says how much
    # falls in each interval, the other what it is made of, and either alone
    # is half the lesson.
    if any(figure is None for figure in figures):
        return None

    outcomes = aj_teaser_table(bundle, vocab)
    tables = [
        sub_table(full_table(bundle, "all"), INTERVAL_SLIDE_MEASURES,
                  title="how long stays last"),
        sub_table(outcomes, list(outcomes.df.columns),
                  title="where stays end"),
    ]

    notes = [
        "Left: the whole distribution of stays cut into intervals of days. "
        "Each bar is how much of the distribution ends inside that interval, "
        "split by outcome type, and the gray bar at the right is the stays "
        "still in care when the analysis window closes. Every bar together "
        "sums to 1, so the picture accounts for every animal.",
        "Right: the same intervals, each divided by its own total. Every bar "
        "is full height, so what varies along the row is the outcome mix "
        "rather than the amount, and the label above each bar is the share of "
        "all stays that bar speaks for. The slot at the cap is left empty "
        "because a normalized remainder would be full height by construction.",
        "Read the bars as amounts, not as rates. The intervals are equal in "
        "days until the last one, which runs from the end of the plotted "
        "range to the stay cap and so covers many more days than its width on "
        "the page suggests. The interval width is a presentation choice: a "
        "wider one collects the early days into a single bar, a narrower one "
        "opens them up, and the same distribution is underneath either way.",
        "These bin what the survival and cumulative-incidence curves already "
        "show. A bar's total height on the left is the fall in the "
        "Kaplan-Meier survival curve across that interval, and the segments "
        "divide that fall the way the Aalen-Johansen curves do. The curves "
        "stay the primary reading: they carry the confidence intervals, they "
        "need no interval chosen for them, and every number the deck quotes "
        "comes from them.",
        "The tables are the ones from the whole-sample slides, so the picture "
        "can be checked against them. Find the interval holding the median "
        "and it is the interval where the running total of the left-hand bars "
        "first passes half. The outcome shares are the totals the right-hand "
        "figure splits interval by interval, which is what makes the drift "
        "across the row visible: the outcome mix among stays ending in the "
        "first days is not the mix among those ending weeks later.",
    ]

    return Slide(
        title="Working with Probabilities in Time Intervals",
        figures=figures,
        tables=tables,
        notes=notes,
    )


# What the educational section is called and what it is for, said once so the
# divider and the guide cannot drift.
EDUCATIONAL_TITLE = "Educational"


def educational_section(bundle: Bundle, vocab: Vocabulary) -> list[Slide]:
    """Slides that teach a way of reading rather than reporting a result.

    At the very back, behind the closing sections and behind the reserve. What
    is here is about how to read the analysis, not about this shelter, so a
    presenter reaches it when a room wants the method rather than the numbers.

    Nothing here is gathered into the closing sections, and that is enforced
    below rather than left to each rule: these slides report no finding of
    their own, and a teaching slide that fed the summary would put a sentence
    about method among sentences about the shelter. A rule added here that
    carries findings has them dropped, which is the behaviour to rely on.
    """
    built = [slide for slide in (los_overview_slide(bundle, vocab),
                                 probability_intervals_slide(bundle, vocab))
             if slide is not None]
    if not built:
        return []
    for slide in built:
        slide.findings = []
        slide.recommendations = []

    divider = Slide(
        title=EDUCATIONAL_TITLE,
        bullets=["Not part of the presentation.",
                 "How to read what the analysis draws, for a room that wants "
                 "the method."],
        notes=["The slides after this one explain a way of reading the "
               "results rather than adding to them. They report nothing about "
               "this shelter that the deck has not already said.",
               "Use them when a question is about how a figure works. Skip "
               "them otherwise."],
        layout="TITLE",
    )
    return [divider] + built


def findings_section(slides: list[Slide],
                     budget: int | None = None) -> list[Slide]:
    """Gather what the section slides found into a closing SECTION.

    The findings are written where the numbers are, then collected here, so
    a summary cannot quietly disagree with the section that produced it. A deck
    whose sections found nothing gets no summary at all rather than an
    empty slide.

    A section rather than one slide because the deck grows: a `FULL` run on OC1
    already fills a page, and a dataset with a fourth stratifier would have run
    off the bottom of it. How much fits on a page is the renderer's judgment,
    asked for here rather than guessed at; the rule's part is that everything
    gathered appears somewhere, in the order the sections produced it.
    """
    note = ("Collected from the section slides; each sentence is generated "
            "beside the numbers it cites.")
    # The automation caveat's second home, and the page it matters most on.
    # Everywhere else in the deck a reader is looking at a number and can judge
    # it; this is the page that tells them what the deck concluded, and it is
    # the one whose selection they cannot check from what is in front of them.
    # It heads the list rather than sitting under it, because a qualification
    # read after the findings is a qualification read too late.
    return _gathered_section(slides, lambda slide: slide.findings,
                             "Findings", note, lead=AUTOMATION_CAVEAT,
                             budget=budget)


def missing_pinned_levels(bundle: Bundle, settings: Settings) -> dict[str, list[str]]:
    """Levels the settings pinned that this dataset does not have.

    Reported rather than raised. A settings file is often written once and
    reused across runs, so a level that is absent today is as likely to be a
    filtered dataset as a typo, and refusing to build the deck over it would be
    the wrong trade. Saying so out loud is not.
    """
    missing = {}
    for stratifier in bundle.stratifiers():
        pinned = settings.emphasis_for(stratifier).levels
        if not pinned:
            continue
        absent = [lvl for lvl in pinned if lvl not in bundle.levels(stratifier)]
        if absent:
            missing[stratifier] = absent
    return missing


def build(results: str | Path | Bundle, out_path: str | Path | None = None,
          settings: Settings | None = None) -> tuple[Path, Path | None]:
    """Write a deck. Returns where it went and what it displaced, if anything.

    The archived path is RETURNED rather than left on the function for a caller
    to pick up afterwards, so two calls cannot report each other's archive.

    `results` may be a results directory or an already-loaded Bundle. Not for
    speed, the bundle is small; it lets a caller that inspected the bundle
    first (as `main` does for its pinned-levels warning) build from the same
    object it inspected.
    """
    settings = settings or Settings()
    bundle = results if isinstance(results, Bundle) else Bundle.load(results)
    # Read against the dataset before anything asks them a question, so every
    # rule below sees one answer: on a run with a single analysis dimension, a
    # stratifier the file said nothing about defaults to ALWAYS rather than to
    # a comparison it has no competitor for.
    settings = settings.for_dataset([s for s in bundle.stratifiers() if s != "all"])
    vocab = Vocabulary(bundle.data)

    # Built once and passed down: three slides read it, and recomputing it per
    # slide would let one of them silently disagree with another. Empty when
    # the run had no Cox regression or no stratified variant, in which case
    # every rule below it declines.
    comparison = cox_comparison(pooled(bundle), stratified(bundle))
    out_path = Path(out_path) if out_path is not None else settings.output_path
    figures = FigureSet(directory=figure_directory(out_path))

    # The opening leads and is not negotiable: what the deck is, then what it
    # was computed over. Everything after it is a finding, and a finding read
    # without knowing the sample it came from is worth less than nothing.
    slides = opening_slides(bundle, vocab)
    for stratifier in bundle.stratifiers():
        # `all` leads, and takes its own rule: the whole sample is the baseline
        # every later slide is read against, so it comes first rather than
        # being skipped for having only one level. Its position is the
        # bundle's, from BASELINE_STRATIFIER, not a separate call sited here.
        #
        # Its second slide is sited here for the same reason a salient
        # stratifier's is below: the remaining-LOS curve is marked at the
        # tenure statistics of the slide before it and has to follow them
        # (see resident_outlook).
        if stratifier == "all":
            built = [los_overall(bundle, vocab), resident_outlook(bundle, vocab)]
        elif settings.emphasis_for(stratifier).suppressed:
            continue
        else:
            # The outlook slide is the salient stratifier's second slide, in
            # the same position the whole sample gives it: immediately after
            # the length-of-stay slide whose rows and tenure figure it carries
            # forward. It declines on its own when the stratifier is not
            # salient, so the order is stated once, here.
            built = [los_by_stratifier(bundle, stratifier, vocab, settings),
                     resident_outlook_by_stratifier(bundle, stratifier, vocab,
                                                    settings)]
        slides.extend(slide for slide in built if slide is not None)

    # The workload run closes the durations: three pages that turn them into a
    # quantity of care, each reading across every stratifier at once, so they
    # can only follow all of them. In order, because each is built on the one
    # before: how many animals, how long each has been here, and the two
    # multiplied.
    slides.extend(slide for slide in
                  (workload_slide(bundle, vocab, section, settings)
                   for section in WORKLOAD_SLIDES)
                  if slide is not None)

    # The two ratio runs close the length-of-stay section rather than opening
    # the deck's methods discussion, because they are about the differences
    # just shown and mean nothing before them. `all` is skipped throughout: the
    # whole sample is one level with nothing to hold a ratio against.
    #
    # Every hazard ratio, then every length-of-stay ratio. See the note above
    # `hazard_ratios_by_stratifier` for why that order is the argument: the
    # first run settles whether the Weibull's form is making the answer, and
    # the second run's leading column is that Weibull in days.
    hr_panel = hazard_ratio_panel(bundle)
    los_panel = los_ratio_panel(bundle)
    wanted = [stratifier for stratifier in panel_stratifiers(hr_panel, HR_SERIES)
              if stratifier != "all"
              and not settings.emphasis_for(stratifier).suppressed]
    for stratifier in wanted:
        label = vocab.stratifier(stratifier).label
        # Two sentences from the retired robustness slide still come from its
        # comparison, which is still computed: what it found rides here, and
        # what it recommends about levels too thin to establish anything rides
        # with it. The parametric-agreement sentence is this slide's own, and
        # it is what the run after this one rests on.
        slide = hazard_ratios_by_stratifier(
            bundle, stratifier, hr_panel, vocab, figures, settings,
            findings=(findings_for_parametric_agreement(hr_panel, stratifier, label)
                      + (findings_for_cox_comparison(comparison, stratifier, label)
                         if requires_cox_comparison(comparison, stratifier) else [])),
            recommendations=unestimable_levels(bundle, stratifier,
                                               comparison, vocab))
        if slide is not None:
            slides.append(slide)

    for stratifier in wanted:
        slide = los_ratios_by_stratifier(bundle, stratifier, los_panel, vocab,
                                         figures, settings)
        if slide is not None:
            slides.append(slide)

    # Competing risks sit after the length-of-stay section: they answer a
    # different question, and the deck earns the right to ask it only once the
    # simpler one has been answered.
    #
    # FULL gives every stratifier its own run of slides. TEASER gives exactly
    # one stratifier's, the most readable, so the audience sees what a
    # breakdown looks like without sitting through all of them. Either way the
    # teaser slide leads, and it is built last so that what it promises is what
    # actually follows it.
    if settings.aj_coverage in ("TEASER", "FULL"):
        if settings.aj_coverage == "FULL":
            wanted = [s for s in bundle.stratifiers()
                      if s != "all" and not settings.emphasis_for(s).suppressed]
        else:
            chosen = aj_teaser_stratifier(bundle, settings)
            wanted = [chosen] if chosen is not None else []

        built = [(s, aj_by_stratifier(bundle, s, vocab, settings)) for s in wanted]
        built = [(s, section) for s, section in built if section]

        teaser = aj_teaser(bundle, vocab,
                           [vocab.stratifier(s).label for s, _ in built])
        if teaser is not None:
            slides.append(teaser)
        # Behind the teaser and ahead of any breakdown: it is still the whole
        # sample, and it answers the teaser's question for the animals in the
        # building rather than for stays from intake.
        destination = resident_destination(bundle, vocab)
        if destination is not None:
            slides.append(destination)
        slides.extend(slide for _, section in built for slide in section)

    # Both closing sections read the same list, the slides built so far, and
    # both are built before either is appended, so neither can gather the
    # other's pages. The order below is the order they appear in the deck.
    # A closing slide carries no figure, so it is one a template decorates and
    # its pages have to break against the band the artwork leaves rather than
    # against the whole slide.
    budget = text_budget(template_band(settings.template))
    closing = (findings_section(slides, budget)
               + recommendations_section(slides, budget))
    slides.extend(closing)

    # After the closing sections, and deliberately: these are not part of the
    # presentation. They are the robustness check the ratio slides replaced,
    # kept where a question from the floor can reach them and nowhere a
    # presenter has to walk through them. Their findings and recommendations
    # were gathered above, from the slides that carry them now, so appending
    # these after the closing sections is also what stops the same sentences
    # being counted twice.
    slides.extend(reserve_section(bundle, comparison, vocab, figures, settings))

    # Last of all. The reserve answers a question about the estimator on this
    # shelter's data; these answer one about how to read a figure at all, which
    # is a step further from the room's own numbers.
    slides.extend(educational_section(bundle, vocab))

    # The workbook and the figure manifest are written from the same bundle and
    # the same blocks as the deck, in the same call, so the three cannot come
    # from different runs. The workbook is archived like the deck, being a
    # deliverable in its own right; the manifest is not, because it describes
    # the figure files beside it, which are overwritten.
    figures.write_manifest()
    sheets = workbook.sheets(bundle, vocab)
    if sheets:
        tables_path, _ = prepare_output(workbook_path(out_path))
        workbook.write(sheets, tables_path, vocab)

    out_path, archived = prepare_output(out_path)
    render(slides, out_path, vocab, flag_style=settings.high_low_flag,
           template=settings.template)
    return out_path, archived


def main(argv: list[str]) -> int:
    from mlos_review.settings import SettingsError

    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a.split("=")[0]: a.partition("=")[2] for a in argv[1:] if a.startswith("--")}

    # The settings module's rule, applied to the command line for the same
    # reason: a silently ignored `--setings=my.yaml` is a settings file the user
    # believes is in force. `--settings` without `=FILE` is the same mistake in
    # a second spelling, most often `--settings my.yaml`, which would also send
    # the file name into the positional arguments.
    known = ("--settings", "--template")
    unknown = sorted(set(flags) - set(known))
    if unknown:
        print(f"error: unrecognized flag(s): {', '.join(unknown)}. "
              f"The flags are {', '.join(f'{flag}=FILE' for flag in known)}.",
              file=sys.stderr)
        return 1
    for flag in known:
        if flag in flags and not flags[flag]:
            print(f"error: {flag} needs a value, as {flag}=FILE.",
                  file=sys.stderr)
            return 1

    try:
        settings = load_settings(flags.get("--settings") or None)
        # After the file, and overriding what it said. A template is the one
        # setting here that belongs to the occasion rather than to the dataset:
        # the same analysis is shown branded to one audience and plain to
        # another, and neither is a reason to edit the settings file.
        if "--template" in flags:
            settings = replace(settings,
                               template=parse_template(flags["--template"]))
    except SettingsError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    results = args[0] if args else "results"
    out = args[1] if len(args) > 1 else None

    bundle = Bundle.load(results)
    for stratifier, absent in missing_pinned_levels(bundle, settings).items():
        print(f"warning: emphasis for {stratifier} names level(s) this dataset "
              f"does not have: {', '.join(absent)}")

    path, archived = build(bundle, out, settings)
    if archived is not None:
        print(f"archived previous deck to {archived}")
    print(f"wrote {path}")
    # The companions are reported too, because a file nobody is told about is a
    # file nobody opens.
    for companion in (workbook_path(path), figure_directory(path) / "manifest.json"):
        if companion.exists():
            print(f"wrote {companion}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
