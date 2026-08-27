"""Content blocks: the pieces a slide or a report section is assembled from.

A block is a pure function of the bundle. It selects and arranges values that
the analysis already computed and cross-checked; it does not derive statistics.

Absence is an ordinary answer, which keeps a legitimately absent section
distinguishable from a broken one. A table block says so through a `requires`
predicate a rule calls first, because a rule has to know before it commits a
slide. A notes or findings block says so by returning an empty list, since
its caller is already building a slide and can simply have nothing to add.

Tables carry NUMBERS. Formatting is the renderer's job, flags travel as a
parallel overlay rather than being pasted into the number, and confidence
bounds stay in their own columns. The reason is the same one the workbook
follows: a string cell cannot be sorted, charted, or read by whatever consumes
this next, and the spreadsheet renderer is a named future consumer.
"""

from __future__ import annotations

import itertools
from collections.abc import Sequence
from dataclasses import dataclass, field

import pandas as pd

from mlos_review.bundle import BASELINE_STRATIFIER, Bundle
from mlos_review.names import capitalize_first
from mlos_review.regression import comparable_stratifiers

# The full table's measures, and which bundle matrix each is drawn from. The
# order here is the order they appear in the table: arrivals, then how long a
# stay lasts, then the standing population those stays produce, then what that
# population still owes.
#
# Three trios in the same shape, median then mean then P90, so a reader who has
# learned to scan one has learned to scan the others: the length of stay of an
# arriving animal, the tenure of one already in care, and the further stay that
# one expects. The last column is the odd one and belongs at the end: it is the
# average remaining stay ACROSS residents, which is the thing the trio before it
# is most likely to be mistaken for.
#
# This is the whole table the whole-sample slides divide between them (see
# LOS_SLIDE_MEASURES and OUTLOOK_SLIDE_MEASURES). It is also what the workbook
# writes per stratifier, so nothing on a slide is a number the sheet lacks.
FULL_TABLE_MEASURES: list[tuple[str, str]] = [
    ("mean_daily_intakes", "observations"),
    ("km_median_los", "km"),
    ("km_restricted_mean", "km"),
    ("km_p90_los", "km"),
    ("km_still_in_care_at_cap", "km"),
    ("expected_census", "census"),
    ("per_resident_past_days_restricted_median", "census"),
    ("per_resident_past_days", "census"),
    ("per_resident_past_days_restricted_p90", "census"),
    ("remaining_days_at_median_tenure", "census"),
    ("remaining_days_at_mean_tenure", "census"),
    ("remaining_days_at_p90_tenure", "census"),
    ("per_resident_future_days", "census"),
]

# The three tenure statistics, which both whole-sample slides show because both
# carry the in-care tenure figure they are marked on.
TENURE_MEASURES: list[str] = [
    "per_resident_past_days_restricted_median",
    "per_resident_past_days",
    "per_resident_past_days_restricted_p90",
]

# How the two whole-sample slides divide the table above: arrivals and how long
# a stay lasts on the first, what the standing population still owes on the
# second, the tenure trio on both. Thirteen columns is a spreadsheet, not a
# slide; each half is readable, and the overlap is what lets the second slide be
# read without turning back to the first.
LOS_SLIDE_MEASURES: list[str] = [
    "mean_daily_intakes", "km_median_los", "km_restricted_mean", "km_p90_los",
    "km_still_in_care_at_cap", "expected_census", *TENURE_MEASURES,
]

# Interleaved, tenure then what the curve reads at that tenure, so each pair
# reads as one statement about one animal rather than as two lists to be
# matched up by eye.
OUTLOOK_SLIDE_MEASURES: list[str] = [
    "per_resident_past_days_restricted_median", "remaining_days_at_median_tenure",
    "per_resident_past_days", "remaining_days_at_mean_tenure",
    "per_resident_past_days_restricted_p90", "remaining_days_at_p90_tenure",
    "per_resident_future_days",
]

# The four superlatives that pick highlight rows when a stratifier has more
# levels than a slide can hold. `True` means the largest value wins.
HIGHLIGHT_SELECTORS: list[tuple[str, bool]] = [
    ("mean_daily_intakes", True),
    ("expected_census", True),
    ("km_restricted_mean", False),
    ("km_restricted_mean", True),
]

# Above this many levels, the highlights table selects rather than shows all.
HIGHLIGHT_SHOW_ALL_MAX = 4

# Units live in one footnote rather than in a row under the header. The header
# row is what a reader scans, and a second line of italics under every column
# was costing more attention than it returned, given that most of these
# measures are in days anyway.
UNITS_FOOTNOTE = "LOS and tenure in days."


@dataclass(frozen=True)
class Format:
    """How to write one measure out. `percent` scales only at render time.

    `blank` decides what a missing cell says. The default "n/a" is the right
    answer almost everywhere, because a missing number in these tables means
    the analysis could not produce one: a median the curve never reaches, a
    level whose curve ends early. `blank` is for the other kind of gap, a
    column that only some rows have any business filling at all, where "n/a"
    would report a failure that never happened.
    """

    decimals: int = 1
    percent: bool = False
    blank: bool = False


# How each measure is written out. A content decision, not a styling one: a
# median in whole days and a fraction of stays are different kinds of number,
# and rounding a fraction to zero places would destroy it.
#
# `percent` scales at RENDER time and leaves the stored value alone, so the
# frame still holds the fraction the bundle holds. A spreadsheet renderer can
# then write that fraction into the cell and set a percent number format, which
# is what lets a reader change the display without changing the data.
FORMATS: dict[str, Format] = {
    "mean_daily_intakes": Format(2),
    "km_median_los": Format(0),
    "km_restricted_mean": Format(1),
    "km_p90_los": Format(0),
    "km_still_in_care_at_cap": Format(1, percent=True),
    "expected_census": Format(1),
    "per_resident_past_days": Format(1),
    "per_resident_past_days_restricted_median": Format(0),
    "per_resident_past_days_restricted_p90": Format(0),
    # Whole days for the tenure quantiles, which are whole days by
    # construction, and a decimal for everything read off a curve.
    "remaining_days_at_median_tenure": Format(1),
    "remaining_days_at_mean_tenure": Format(1),
    "remaining_days_at_p90_tenure": Format(1),
    "per_resident_future_days": Format(1),
}


@dataclass
class Table:
    """A table of numbers with everything a renderer needs and nothing more.

    `df` is indexed by stratum level, one column per measure key, holding
    numbers. `flags` is an optional same-shaped frame of "H", "L", "F" or "".
    `formats` is per measure. Measure keys stay machine names; turning them
    into words is the vocabulary's job at render time.

    A column may hold TEXT where the value is genuinely textual: a date, or the
    name of the level that holds an extreme. That is not a breach of the
    numbers rule at the top of this module, which is about a number that has
    been written into a string; a date was never a number, and a renderer that
    can do better with it, like a spreadsheet with a date format, still has the
    value rather than a sentence about it.

    `headers` overrides that translation for one table, per measure, and is
    printed verbatim. It exists for layouts the vocabulary cannot serve: a
    table that puts the same measure in several columns needs the columns to
    say what differs between them, not to repeat the measure's name. Leaving it
    empty is the normal case and keeps every header coming from one place.

    `row_formats` is for the other transposition: a table whose ROWS are the
    measures, where one column holds a share on one line and a day count on the
    next and no single column format can serve both. Keyed by the row label, or
    by its last part where the index has several levels. Empty in the normal
    case, where `formats` alone decides.

    `highlight` names the one column the slide is about, when it is about one:
    the competing-risk slides show a single outcome's figure beside a table of
    all of them. Which column that is, is content; how a renderer says so is
    not, so it is a column key here and a shaded header cell there.
    """

    df: pd.DataFrame
    title: str
    formats: dict[str, Format] = field(default_factory=dict)
    flags: pd.DataFrame | None = None
    footnotes: list[str] = field(default_factory=list)
    headers: dict[str, str] = field(default_factory=dict)
    row_formats: dict[str, Format] = field(default_factory=dict)
    highlight: str = ""


# How a Table's own fields are read on the way to a page. Both renderers need
# the same answers, and a second copy of either would drift the moment one of
# them grew a case: the pptx renderer and the workbook writer must head a
# column the same way and round a cell the same way, or one deliverable
# quietly disagrees with the other about what a run found. They live beside
# Table because they interpret nothing but Table.


def header_text(table: Table, vocab, measure: str, short: bool = True) -> str:
    """What one column is headed by: the table's own word, or the vocabulary's.

    A table may name its own columns; that name is printed as written,
    capitalization included, since a table that overrides the vocabulary has a
    reason the vocabulary does not know about.

    `short` is what a slide needs and a spreadsheet does not. A short form
    leans on its neighbors for context, which is safe in four columns and
    stops being safe in thirteen: the comparison frame has three estimates each
    with an interval, so short forms head it "Lower, Upper" three times over
    with nothing saying which estimate each pair belongs to. The full label
    carries its own base ("hazard ratio, pooled Cox, lower 95% CI"), and a
    sheet has the width for it.
    """
    return table.headers.get(
        measure, capitalize_first(vocab.metric(measure).text(short=short)))


def cell_format(table: Table, row, measure: str) -> Format:
    """How one cell is written: the row's format if it has one, else the column's.

    Nearly every table has one measure per column, and formats follow columns.
    A table that puts its measures in the ROWS cannot: a column holding a share
    on one line and a day count on the next has no single format. Such a table
    fills `row_formats` and it wins here.
    """
    if table.row_formats:
        key = row[-1] if isinstance(row, tuple) else row
        if key in table.row_formats:
            return table.row_formats[key]
    return table.formats.get(measure, Format())


def separates(values: pd.Series) -> bool:
    """Whether a measure can tell the levels apart at all.

    The rule behind every abstention in this module: a column where every level
    ties, or where nothing is recorded, supports no superlative. `idxmax` on
    such a column returns whichever level happens to sort first, which would
    put a row on a slide or a name in a sentence for no reason. What each
    caller does about it differs (a flag says F, a selector picks nothing, a
    finding says nothing at all); the test is the same one.
    """
    values = values.dropna()
    return not values.empty and values.min() != values.max()


# How many levels may share an extreme before naming them stops being a
# finding. Two reads as a result: "LRG and XL have the longest average stay".
# Five is a list of most of the stratifier, and the honest output is silence.
MAX_TIED_LEVELS = 2


def extreme_levels(values: pd.Series, want_max: bool) -> list[str]:
    """EVERY level holding this column's extreme, or none when too many do.

    What `flag_extremes` already does in ink, done in prose. A flagged column
    marks all three levels that hold the maximum; the sentence beside it used
    to say `idxmax`, which is whichever of them sorts first, so a slide could
    mark two levels highest and then name one of them. Nothing in the data ever
    triggered it, floating-point means over hundreds of stays not being equal
    to the last digit, but nothing in the code prevented it either.

    Empty for a column that cannot separate the levels at all, which is
    `separates`' abstention, and empty again past MAX_TIED_LEVELS. Callers
    treat both the same way, because both mean the same thing: there is no
    superlative here worth putting in a sentence.

    Holders come back in the frame's own level order, so two sentences about
    the same stratifier name its levels in the same order.
    """
    values = values.dropna()
    if not separates(values):
        return []
    target = values.max() if want_max else values.min()
    holders = list(values.index[values == target])
    return holders if len(holders) <= MAX_TIED_LEVELS else []


def name_levels(levels: Sequence[str]) -> str:
    """Level names as prose: "LRG", or "LRG and XL"."""
    if len(levels) < 3:
        return " and ".join(str(level) for level in levels)
    return (", ".join(str(level) for level in levels[:-1])
            + f" and {levels[-1]}")


def _agrees(levels: Sequence[str], singular: str, plural: str) -> str:
    """The verb that agrees with however many levels are being named."""
    return singular if len(levels) == 1 else plural


def flag_extremes(df: pd.DataFrame) -> pd.DataFrame:
    """Mark each column's highest and lowest values across EVERY level.

    "H" for the maximum, "L" for the minimum, and "F" for flat when all levels
    tie, so a column where nothing distinguishes the levels says so instead of
    pinning an arbitrary H and L on identical numbers. Ties below that are
    shared: if three levels hold the maximum, all three carry H.

    Because F covers the all-tied case, no level is ever both highest and
    lowest, so there is no combined flag. Judging is always over the full set
    of levels; a highlights table subsets the result rather than recomputing
    it, or "H" would quietly mean "highest of the few I chose".
    """
    flags = pd.DataFrame("", index=df.index, columns=df.columns)
    for column in df.columns:
        values = df[column]
        if values.isna().all():
            continue
        low, high = values.min(), values.max()
        if low == high:
            flags.loc[values.notna(), column] = "F"
        else:
            flags.loc[values == high, column] = "H"
            flags.loc[values == low, column] = "L"
    return flags


def _stratum_table_title(df: pd.DataFrame, stratifier: str, title: str) -> str:
    """`title`, except for the pooled single-level table.

    "all levels by all" is not a title. The whole sample is one level, so there
    is nothing to be "by"; it is the baseline the others are read against.
    Printed wherever a table has to name itself: over each table on a TABLES or
    TITLE slide, and as the heading row of a stacked worksheet.
    """
    return ("the whole sample" if len(df) == 1 and stratifier == "all"
            else title)


# ---------------------------------------------------------------------------
# The opening summary
# ---------------------------------------------------------------------------
#
# What was analyzed, before anything is found from it. These describe the
# INPUT as the run narrowed it: the window it was cut to, how many stays and
# animals survived that cut, how their outcomes were recorded, and how the
# stratifying fields divide them. They are not raw file statistics, which
# belong to data preparation and are not a presentation's business, and they
# are not results, which every slide after them is about.
#
# Counts here are per STAY, from the unified counts, where each stay is counted
# once however many periods it touches. The period-level counts elsewhere in
# the analysis count a stay once per period, which is right for a per-period
# rate and wrong for "how many stays are in this dataset".

# Counts and shares, written the way a summary reads them: no false precision
# on a tally, one decimal on a share. `blank` on the share because most rows of
# the sample table have no share to give and never did, and on TEXT because the
# level a column names is absent when there is no level to name.
COUNT = Format(0)
SHARE = Format(1, percent=True, blank=True)
TEXT = Format(blank=True)

# These tables put their MEASURES in the rows, so their column keys name a role
# rather than a bundle measure and there is nothing for the vocabulary to
# translate. Headed explicitly for that reason: left to the vocabulary they
# would render by the fallback tokenizer, which would put "count" and "share"
# on the awaiting-curation list forever, since neither will ever be a name the
# analysis writes.
COUNT_AND_SHARE_HEADERS = {"count": "Count", "share": "Share"}

# Levels a field may have before its levels are summarized rather than listed.
# The run's own `max_plot_strata` decides, since "how many levels fit on a
# picture" is one judgment and the analysis already made it; this stands in
# only for a bundle that does not say.
MAX_LISTED_LEVELS = 10


def max_listed_levels(bundle: Bundle) -> int:
    return int(bundle.value("settings", "presentation", "max_plot_strata",
                            default=MAX_LISTED_LEVELS))


def _unified_stays(bundle: Bundle, stratifier: str) -> pd.Series:
    """Stays per level of one stratifier, each stay counted once.

    The column is called `period_label` whatever the stratifier is, because R
    builds these counts for every field through the helper it wrote for
    periods. The rows arrive in the stratifier's own level order, from the same
    labels vector `bundle.levels` reads, so they are taken as they come.
    """
    counts = bundle.table("strata", stratifier, "unified_stay_counts")
    return pd.Series(list(counts["total_stays"]),
                     index=[str(v) for v in counts["period_label"]])


def requires_study_window(bundle: Bundle) -> bool:
    return bundle.has("unified", "study_start") or bundle.has("settings", "periods")


def study_window_table(bundle: Bundle) -> Table:
    """The stretch of calendar the analysis was cut to, and its periods.

    The whole window leads, then the periods inside it, which is the order
    every other table in the deck uses for the same reason: the pooled figure
    is the baseline and the splits are read against it.

    Periods DEFINED but never reached by any stay are left out, because the
    rest of the deck leaves them out: a stratifier's levels are the levels
    present, so a period listed here and absent everywhere else would read as a
    stretch of time the analysis lost rather than one the data never filled.

    With exactly one period the pooled row is dropped instead, because it would
    be the period row again under a different name. What is kept is the period,
    since its label is what the reader meets on every other slide.
    """
    periods: dict[str, dict] = {}
    if bundle.has("settings", "periods"):
        strata = bundle.data.get("strata", {})
        present = set(bundle.levels("period")) if "period" in strata else None
        for _, period in bundle.table("settings", "periods").iterrows():
            label = str(period["period_label"])
            if present is not None and label not in present:
                continue
            periods[label] = {
                "start_date": str(period["start_date"]),
                "end_date": str(period["end_date"]),
                "duration_days": period["duration_days"],
            }

    rows: dict[str, dict] = {}
    start = bundle.value("unified", "study_start")
    end = bundle.value("unified", "study_end")
    if start and end and len(periods) != 1:
        pooled = bundle.levels("all")[0] if bundle.has("strata", "all") else "All"
        rows[str(pooled)] = {
            "start_date": str(start),
            "end_date": str(end),
            "duration_days": bundle.value("settings", "window_days"),
        }
    rows.update(periods)

    df = pd.DataFrame.from_dict(
        rows, orient="index",
        columns=["start_date", "end_date", "duration_days"])
    return Table(
        df=df,
        title="study window",
        formats={"duration_days": COUNT},
        headers={"start_date": "From", "end_date": "To", "duration_days": "Days"},
        footnotes=["A period includes its start date but excludes its end date."],
    )


# The sample rows, in reading order: how many stays there are, how many animals
# they belong to, how many arrived inside the window, then the cap and the stays
# that ran past it. A measure the bundle does not offer drops out.
SAMPLE_ROWS = ["total_stays", "n_animals", "total_intakes",
               "restricted_stay_cap", "n_capped"]

# The one sample row the bundle also gives a share for.
SAMPLE_SHARES = {"n_capped": ("unified", "fraction_capped")}

# The pooled pseudo-outcome, which leads the outcome rows as their total. It is
# not a state the data can record, so it has no count of its own and takes the
# tally the analysis already sums: every stay with an observed outcome.
ANY_OUTCOME = "Any"

# The two halves of the sample table, named in an outer index level. Not
# decoration: the footnote below governs the second half only, and without the
# grouping it reads as governing the table, which would say the stay count
# excludes stays with no outcome. It does not. The three totals differ, by the
# left-truncated stays and then by the right-censored ones, and a reader is
# entitled to see which rows the caveat is about.
SAMPLE_GROUP = "Sample"
OUTCOME_GROUP = "Outcomes"

SAMPLE_FOOTNOTE = ("Outcome counts are only outcomes observed before the stay "
                   "cap and within the study window.")


def requires_sample(bundle: Bundle) -> bool:
    return bundle.has("strata", "all", "unified_stay_counts")


def _sample_counts(bundle: Bundle) -> dict:
    """Every sample count this bundle offers, keyed by its measure name.

    The animal count is dropped when the data carried no animal identifier. The
    run invents one per row in that case, so "distinct animals" would be the
    stay count again under a name that claims more than it knows.
    """
    stays = bundle.table("strata", "all", "unified_stay_counts")
    found = {"total_stays": stays["total_stays"].iloc[0]}
    if bundle.value("data_preparation", "animal_ids_supplied", default=False):
        found["n_animals"] = bundle.value("data_preparation", "n_animals")
    if bundle.has("strata", "all", "observations"):
        observed = bundle.stratum("all", "observations")
        if "total_intakes" in observed.columns:
            found["total_intakes"] = observed["total_intakes"].iloc[0]
    found["restricted_stay_cap"] = bundle.value("settings", "restricted_stay_cap")
    found["n_capped"] = bundle.value("unified", "n_capped")
    return {name: value for name, value in found.items() if value is not None}


def _sample_row_label(measure: str, vocab) -> str:
    """One sample row's label, with its unit where the row is not a tally.

    Every other row in this table is a count and the column says so. The stay
    cap is a duration sitting in the same column, so it carries the unit the
    vocabulary already holds for it rather than leaving the reader to guess
    whether 365 is a number of animals.
    """
    name = vocab.metric(measure)
    label = capitalize_first(name.label)
    return f"{label} ({name.unit})" if name.unit else label


def _outcome_codes(bundle: Bundle, counts: pd.DataFrame) -> list[str]:
    """The recorded outcome codes, in the order the run's plots draw them.

    Palette order first, so a reader coming from a figure legend finds the rows
    where they expect them, then anything the palette does not mention.
    """
    found = [column[len("outcome_"):-len("_events")] for column in counts.columns
             if column.startswith("outcome_") and column.endswith("_events")]
    order = bundle.value("palette", "outcome_order", default=[])
    order = [order] if isinstance(order, str) else list(order)
    codes = [code for code in order if code in found]
    return codes + [code for code in found if code not in codes]


def _outcome_rows(bundle: Bundle, vocab) -> dict:
    """The outcome tallies: the pooled total, then one row per outcome code.

    Counts, not the competing-risk analysis: these are the tallies the data
    carries, and the slides much later in the deck are what the analysis makes
    of them. The row label carries the code AND its words, which is how the
    configuration writes it and how every plot legend in the run reads.

    Shares come from the bundle's own outcome mix rather than from dividing
    here, so a reader comparing this slide against the workbook finds the same
    number rather than one rounded differently. `Any` is the exception that
    proves it: its share would be one by construction, so it is left blank
    rather than being the single figure on the slide that no run computed.
    """
    counts = bundle.stratum("all", "outcomes")
    level = counts.index[0]
    mix = bundle.stratum("all", "mix") if bundle.has("strata", "all", "mix") else None

    rows = {}
    if "completed_outcomes_total" in counts.columns:
        rows[ANY_OUTCOME] = {
            "count": counts.loc[level, "completed_outcomes_total"],
            "share": None,
        }
    for code in _outcome_codes(bundle, counts):
        share = None
        if mix is not None and f"outcome_mix_{code}" in mix.columns:
            share = mix.loc[level, f"outcome_mix_{code}"]
        rows[f"{code} {vocab.outcome_labels.get(code, code)}"] = {
            "count": counts.loc[level, f"outcome_{code}_events"],
            "share": share,
        }
    return rows


def sample_table(bundle: Bundle, vocab) -> Table:
    """How much data there is, and how the stays in it were recorded as ending.

    One table rather than two, because the outcome tallies are counts over the
    same sample and a reader checking that they add up should not have to look
    across a gutter to do it. One row per measure, because the measures are of
    different things and a row of nine columns headed by nine different nouns
    is not a table anyone reads.

    Two GROUPS in an outer index level, though, because the footnote is about
    the second of them: see SAMPLE_GROUP. The renderer writes a repeated outer
    label once, so the grouping costs one narrow column and no repetition.

    The share column is filled where the bundle gives a share and is blank
    rather than "n/a" elsewhere: those rows have no share, as opposed to a
    share the analysis failed to produce.
    """
    found = _sample_counts(bundle)
    rows = {
        (SAMPLE_GROUP, _sample_row_label(measure, vocab)): {
            "count": found[measure],
            "share": bundle.value(*SAMPLE_SHARES[measure])
                     if measure in SAMPLE_SHARES else None,
        }
        for measure in SAMPLE_ROWS if measure in found
    }
    if bundle.has("strata", "all", "outcomes"):
        rows.update({(OUTCOME_GROUP, label): values
                     for label, values in _outcome_rows(bundle, vocab).items()})

    df = pd.DataFrame(
        list(rows.values()),
        index=pd.MultiIndex.from_tuples(rows) if rows else None,
        columns=["count", "share"])
    return Table(
        df=df,
        title="the sample and its outcomes",
        formats={"count": COUNT, "share": SHARE},
        headers=dict(COUNT_AND_SHARE_HEADERS),
        footnotes=[SAMPLE_FOOTNOTE],
    )


def summary_fields(bundle: Bundle) -> list[str]:
    """Stratifiers that came from a FIELD of the data, in bundle order.

    Every one of them, and only them, carries unified stay counts: a field
    divides the stays, so each stay belongs to exactly one of its levels and
    counting them once is meaningful. Periods divide the calendar instead, a
    stay can touch several, and R writes no unified counts for them. So asking
    for the counts is also the test for which stratifiers this section is
    about, rather than a list of field names kept in step by hand.
    """
    return [stratifier for stratifier in bundle.stratifiers()
            if stratifier != "all"
            and bundle.has("strata", stratifier, "unified_stay_counts")]


def requires_field_summary(bundle: Bundle) -> bool:
    return bool(summary_fields(bundle))


def field_summary_table(bundle: Bundle, vocab) -> Table:
    """One row per stratifying field: how many levels, and the two extremes.

    NOT USED BY ANY RULE TODAY, and kept deliberately, the way QUADRANTS is
    kept in the renderer. It is the shape that holds however many levels a
    field has, so a field with fifty categories still says something on a
    slide, where every field the analysis carries today is small enough for
    `level_counts_table` to list level by level. A dataset that outgrows the
    listing is what this is for. The fixture tests exercise it directly so it
    cannot rot in the meantime.

    The named levels are the smallest and largest by stay count, from
    `extreme_levels`, so a shared extreme names both holders and too many
    holders names none. The two ends abstain independently: a field can have a
    single largest level and a five-way tie at the bottom, and the largest is
    still worth reporting.
    """
    rows: dict[str, dict] = {}
    for stratifier in summary_fields(bundle):
        counts = _unified_stays(bundle, stratifier)
        row: dict = {"categories": len(counts)}
        smallest = extreme_levels(counts, want_max=False)
        largest = extreme_levels(counts, want_max=True)
        if smallest:
            row.update(smallest=name_levels(smallest),
                       smallest_stays=counts.min())
        if largest:
            row.update(largest=name_levels(largest), largest_stays=counts.max())
        rows[capitalize_first(vocab.stratifier(stratifier).label)] = row

    df = pd.DataFrame.from_dict(
        rows, orient="index",
        columns=["categories", "smallest", "smallest_stays",
                 "largest", "largest_stays"])
    return Table(
        df=df,
        title="fields the analysis splits by",
        formats={"categories": COUNT,
                 "smallest": TEXT, "largest": TEXT,
                 "smallest_stays": COUNT, "largest_stays": COUNT},
        headers={"categories": "Levels", "smallest": "Smallest",
                 "smallest_stays": "Stays", "largest": "Largest",
                 "largest_stays": "Stays"},
        footnotes=["Smallest and largest by stay count; a field whose levels "
                   "all tie names neither."],
    )


def requires_level_counts(bundle: Bundle, stratifier: str) -> bool:
    return (bundle.has("strata", stratifier, "unified_stay_counts")
            and len(bundle.levels(stratifier)) <= max_listed_levels(bundle))


def level_counts_table(bundle: Bundle, stratifier: str, vocab) -> Table:
    """Every level of one field, with its stays.

    Built only when the field has few enough levels to plot, which is the same
    threshold as fitting on a slide and is already a setting. Past it the field
    still appears in the summary table beside this one, so a field is never
    silently missing; it is described rather than enumerated.
    """
    counts = _unified_stays(bundle, stratifier)
    df = pd.DataFrame({"total_stays": list(counts)}, index=list(counts.index))
    return Table(
        df=df,
        title=f"stays by {vocab.stratifier(stratifier).label}",
        formats={"total_stays": COUNT},
        headers={"total_stays": "Stays"},
    )


# ---------------------------------------------------------------------------
# Observation gaps
# ---------------------------------------------------------------------------

# How R names an analysis in the gaps table (see mlos_results.R): the pooled
# fit under one fixed name, and every stratified fit as "KM by " and the
# stratifier's label. That label is the join key the bundle carries, and R
# writes it from two lists that agree on the words but not always on their case
# (the registry in mlos_common.R, the coverage block in mlos_results.R), so the
# match ignores case. An analysis this cannot place is NOT dropped: it falls to
# the pooled slide, so a stratifier added on the R side and unknown here reports
# its gaps in the less specific place rather than silently reporting none.
POOLED_GAP_ANALYSIS = "Unified KM"
STRATUM_GAP_PREFIX = "KM by "


def _gap_analysis_ids(bundle: Bundle) -> dict[str, str]:
    """Every analysis name the gaps table can hold, against its stratifier id."""
    ids = {POOLED_GAP_ANALYSIS.lower(): BASELINE_STRATIFIER}
    coverage = bundle.value("settings", "coverage", default={})
    if isinstance(coverage, dict):
        for stratifier, entry in coverage.items():
            label = entry.get("label") if isinstance(entry, dict) else None
            if label:
                ids[f"{STRATUM_GAP_PREFIX}{label}".lower()] = stratifier
    return ids


def observation_gaps(bundle: Bundle, stratifiers: Sequence[str]) -> pd.DataFrame:
    """The gaps R recorded for some stratifiers, one row each.

    A gap is a stretch of days below the stay cap with no stay under
    observation at all. R scans for them and records what it found without
    adjusting anything, which is what lets a report say so.

    The bundle's own columns, plus `stratifier`: the id the analysis name
    resolved to, which is what a caller filters and labels by.
    """
    columns = ["analysis", "stratum", "gap_start_day", "gap_end_day", "stratifier"]
    if not bundle.has("unified", "gaps"):
        return pd.DataFrame(columns=columns)
    gaps = bundle.table("unified", "gaps")
    ids = _gap_analysis_ids(bundle)
    gaps = gaps.assign(stratifier=[ids.get(str(name).lower(), BASELINE_STRATIFIER)
                                   for name in gaps["analysis"]])
    return gaps[gaps["stratifier"].isin(list(stratifiers))]


def _gap_day(value) -> str:
    """A gap boundary as it reads in a sentence, without a false decimal."""
    return f"{float(value):g}"


def _gap_subject(row, vocab) -> str:
    """What one gap is a gap IN, named for prose."""
    if row["stratifier"] == BASELINE_STRATIFIER:
        return "the pooled data"
    return f"{row['stratum']} ({vocab.stratifier(row['stratifier']).label})"


def _gap_subjects(rows: pd.DataFrame, vocab) -> str:
    """The same for several gaps at once, a clause per stratifier.

    Grouped rather than listed one by one because the parenthesis is there to
    say what KIND of level the name is, and two levels of one stratifier said
    in a row would answer that twice.
    """
    holders: dict[str, list[str]] = {}
    for _, row in rows.iterrows():
        strata = holders.setdefault(row["stratifier"], [])
        if str(row["stratum"]) not in strata:
            strata.append(str(row["stratum"]))
    named = ["the pooled data" if stratifier == BASELINE_STRATIFIER
             else f"{name_levels(strata)} ({vocab.stratifier(stratifier).label})"
             for stratifier, strata in holders.items()]
    return name_levels(named)


def _gap_notes(bundle: Bundle, stratifiers: Sequence[str], vocab) -> list[str]:
    """What the gap scan found among some analyses, in detail or in passing.

    Unlike every other caveat in this module, this one speaks when it has
    nothing to report (see `cap_sensitivity_notes` for the usual rule). A gap
    does not qualify a curve, it invalidates it from that day on, so "there are
    none" is a finding a presenter is entitled to have been told rather than an
    absence they are left to infer from silence.

    What it will not do is claim a check that did not happen. R scans a
    stratifier only where it fitted one, so an analysis with a single level is
    left out of the reassurance rather than counted into it, and a slide with
    nothing checked says nothing. The pooled scan always runs, and with one
    period it IS the period's scan, over the same rows.

    Detail is spent where it can be acted on. A gap inside the plotted range is
    a hole in a curve the audience is looking at, so it is named with its days;
    a gap past the plot cap is in no figure here and is reported briefly, since
    what it still costs is the restricted means, which run to the stay cap.
    """
    checked = []
    for stratifier in stratifiers:
        if stratifier == BASELINE_STRATIFIER:
            checked.append("the pooled data")
        elif bundle.value("settings", "coverage", stratifier, "included",
                          default=False):
            checked.append(f"every {vocab.stratifier(stratifier).label}")
    if not checked:
        return []

    cap = bundle.value("settings", "restricted_stay_cap")
    horizon = f"the {cap}-day stay cap" if cap else "the stay cap"
    gaps = observation_gaps(bundle, stratifiers)
    if gaps.empty:
        return [f"Observation gaps: none. The scan covers {name_levels(checked)}, "
                f"and every day up to {horizon} has at least one stay under "
                f"observation there, so no curve on the slides that follow is "
                f"drawn across a stretch where the risk set had emptied."]

    plot_cap = bundle.value("settings", "presentation", "plot_stay_cap")
    in_view = gaps if plot_cap is None else gaps[gaps["gap_start_day"] < plot_cap]
    beyond = gaps.drop(index=in_view.index)

    notes = []
    if not in_view.empty:
        found = [f"{_gap_subject(row, vocab)}, day {_gap_day(row['gap_start_day'])} "
                 f"to day {_gap_day(row['gap_end_day'])}"
                 for _, row in in_view.iterrows()]
        notes.append(
            f"Observation gaps, inside the plotted range: {name_levels(found)}. A "
            f"gap is a stretch of days with no stay under observation at all, "
            f"which left truncation makes possible: every stay at risk resolved "
            f"before the next entrant's tenure reached it. Nothing in the "
            f"analysis is adjusted for one, so each curve named here, its "
            f"restricted mean and everything drawn from it are unreliable from "
            f"that day onward.")
    if not beyond.empty:
        earliest = _gap_day(beyond["gap_start_day"].min())
        alone = len(beyond) == 1
        count = "one" if alone else str(len(beyond))
        lead = (f"Further gaps sit past the plotted range, {count} in"
                if not in_view.empty else
                f"Observation gaps: none inside the plotted range, but {count} "
                f"past it, in")
        notes.append(
            f"{lead} {_gap_subjects(beyond, vocab)}, "
            f"{'starting' if alone else 'the earliest starting'} at day "
            f"{earliest}. No figure here reaches {'it' if alone else 'them'}, "
            f"since the plots stop at the {plot_cap}-day plot cap, but the "
            f"restricted means run to {horizon} and do, so read those for the "
            f"named {'level' if alone else 'levels'} as unreliable from day "
            f"{earliest} onward.")
    return notes


def window_gap_notes(bundle: Bundle, vocab) -> list[str]:
    """The gap scan over the calendar, for the slide that lists the periods.

    The stratifiers here are the ones the opening summary does NOT tally, which
    on every dataset so far means the periods. Taken as the complement rather
    than by name so that the two opening slides between them account for every
    analysis R scanned, whatever stratifiers a future bundle carries.
    """
    fields = set(summary_fields(bundle))
    return _gap_notes(bundle, [stratifier for stratifier in bundle.stratifiers()
                               if stratifier != BASELINE_STRATIFIER
                               and stratifier not in fields], vocab)


def sample_gap_notes(bundle: Bundle, vocab) -> list[str]:
    """The gap scan over the whole sample and the fields that divide it."""
    return _gap_notes(bundle, [BASELINE_STRATIFIER] + summary_fields(bundle), vocab)


# ---------------------------------------------------------------------------
# Care days
# ---------------------------------------------------------------------------

# The three workload tables, in the order the slides ask their questions: how
# many animals are in care, how long each has been here, and what those two
# multiply to in animal-days.
#
# The multiplication is exact and is the spine of the run. Counted,
# daily_mean_total_in_care_days = mean_census_inventory x
# per_resident_in_care_days; fitted, expected_past_animal_days =
# expected_census x per_resident_past_days, both by construction (see
# .census_aggregate_matrix in mlos_km.R). So the third table is the first two
# multiplied, on each side, and a discrepancy visible there is the two
# discrepancies before it compounded rather than a third piece of evidence.
#
# Every table pairs a COUNTED column with a FITTED one, which is where the
# model is held against the data. They measure the
# same thing and normally agree closely, which is most of the point: a reader
# who has taken four slides of KM-implied figures on trust gets to see the
# implication checked.
#
# The animal-day TOTAL over the study window is not here. It is the same
# quantity as the counted census times the window length, so on a slide it
# added a second scale of the same fact and invited "we are nearly done" when
# read against the days owed, which is one average day's. It keeps its place in
# the workbook, where width is free.
WORKLOAD_INTAKES = "mean_daily_intakes"
WORKLOAD_RESIDENTS = "mean_census_inventory"
WORKLOAD_RESIDENTS_FITTED = "expected_census"
WORKLOAD_TENURE = "per_resident_in_care_days"
WORKLOAD_TENURE_FITTED = "per_resident_past_days"
WORKLOAD_REMAINING_FITTED = "per_resident_future_days"
WORKLOAD_DAYS = "daily_mean_total_in_care_days"
WORKLOAD_DAYS_FITTED = "expected_past_animal_days"
WORKLOAD_DAYS_OWED = "expected_future_animal_days"
CARE_DAYS_DELIVERED = "total_animal_days"

# Headed by what each column IS rather than by the measure's usual name: on
# these three slides the reader's question is always counted-or-fitted, and a
# header that answered it in a parenthesis after five other words would be
# answering it last.
# A share is headed by the quantity it divides, not by a bare "Pct". On the
# slides the neighbouring column supplies that, but a sheet is read a column at
# a time and its order is not fixed, so a heading that leans on its neighbour
# is one column move away from being wrong. It was: the intake share sat beside
# the study-window day total for want of the intakes column, and read as a
# share of those days.
WORKLOAD_HEADERS = {
    WORKLOAD_INTAKES: "Intakes/day",
    "intake_share": "Intakes, pct",
    WORKLOAD_RESIDENTS: "Census, counted",
    "resident_share": "Census counted, pct",
    WORKLOAD_RESIDENTS_FITTED: "Census, fitted",
    "fitted_share": "Census fitted, pct",
    WORKLOAD_TENURE: "Tenure, counted",
    WORKLOAD_TENURE_FITTED: "Tenure, fitted",
    WORKLOAD_REMAINING_FITTED: "Remaining, fitted",
    WORKLOAD_DAYS: "Animal-days, counted",
    WORKLOAD_DAYS_FITTED: "Animal-days, fitted",
    WORKLOAD_DAYS_OWED: "Days owed, fitted",
    "owed_share": "Days owed, pct",
    CARE_DAYS_DELIVERED: "Days given, whole window",
}

# A level carries a stratifier's future workload when it holds a majority of
# the days still owed AND holds a larger share of them than of the residents
# who owe them. Both conditions, because either alone says nothing worth a
# sentence: a majority on its own is usually just the biggest level being
# biggest, and a disproportion on its own can be a level holding 3% of the
# residents and 5% of the days.
CARE_DAYS_MAJORITY = 0.50
CARE_DAYS_DISPROPORTION = 0.05


def burden_carrier(bundle: Bundle,
                   stratifier: str) -> tuple[str, float, float] | None:
    """The level carrying a stratifier's future workload, where one does.

    Returns the level, its share of the care days still owed, and its share of
    the residents who owe them. None where no level meets both conditions.

    One definition, used by the finding that reports the finding and by the
    recommendation that acts on it, so the deck cannot suggest narrowing to a
    level it did not name as the carrier.
    """
    owed = _care_days_owed(bundle, stratifier)
    if owed is None or owed.sum() <= 0 or len(owed) < 2:
        return None
    if not bundle.has("strata", stratifier, "census"):
        return None
    # Both shares below divide one level by the levels' total, which only means
    # something where the levels partition the standing population. Periods do
    # not, so they are excluded here even though they now carry an owed column.
    if not _levels_partition_census(bundle, stratifier):
        return None
    census = bundle.stratum(stratifier, "census")["expected_census"]
    if census.sum() <= 0:
        return None

    owed_share = owed / owed.sum()
    resident_share = census / census.sum()
    carrier = owed_share.idxmax()
    if owed_share[carrier] <= CARE_DAYS_MAJORITY:
        return None
    if owed_share[carrier] - resident_share[carrier] < CARE_DAYS_DISPROPORTION:
        return None
    return str(carrier), float(owed_share[carrier]), float(resident_share[carrier])


def requires_care_days(bundle: Bundle, stratifier: str) -> bool:
    return (bundle.has("strata", stratifier, "observations")
            and CARE_DAYS_DELIVERED
            in bundle.stratum(stratifier, "observations").columns)


def _care_days_owed(bundle: Bundle, stratifier: str) -> pd.Series | None:
    """Days of care each level's current residents are still committed to.

    Read from the bundle rather than formed here. It is the census times what
    each resident still owes, and R publishes exactly that product as
    `expected_future_animal_days`; multiplying the two columns back together on
    this side would be a second route to a number the file already holds, which
    is the one thing the blocks are not for.

    Present for every stratifier, PERIODS INCLUDED. A period's census is an
    average over its own stretch of calendar rather than a slice of one
    standing population, so the periods cannot divide a workload between them
    and get no share column; but each period's own figure is a real quantity,
    the commitment an average day's residents carried under that regime. The
    share is what needed the partition test, and `_workload_frame` and
    `burden_carrier` are what apply it.
    """
    if not bundle.has("strata", stratifier, "census"):
        return None
    census = bundle.stratum(stratifier, "census")
    if WORKLOAD_DAYS_OWED not in census.columns:
        return None
    return census[WORKLOAD_DAYS_OWED]


# What each of the three workload tables holds, in slide order: the columns, a
# format per column, and the sheet-and-slide title. The share columns are named
# here and filled only where the levels divide the standing population, which
# periods do not.
# HOW MANY COLUMNS FIT IS MEASURED, NOT CHOSEN. Three tables sit side by side
# on these slides and each pays for its own column of level names, so the row
# has about 12.5 inches for everything. Where a set asks for more, the renderer
# floors each column at its longest word and lets the row hang off the slide
# (see `_squeezed` in render_pptx), which is loud rather than silent: the
# failure it replaced was a percentage column squeezed to a third of an inch
# with its heading broken one letter to a line.
#
# What each of these three costs, at the widths this run's numbers need:
#
#   census       12.5in of 12.5   percentage of intakes, counted census with
#                                 its percentage, fitted census
#   tenure       12.2in of 12.5   counted, fitted, and what is still to come
#   animal-days  11.7in of 12.5   counted, fitted, owed
#
# The animal-days slide has no room for a fourth column and the reason is the
# numbers rather than the headings: five and six digits with a thousands
# separator need about an inch a column whatever they are called, so a share of
# the days owed asks for 13.9 inches of a 12.5-inch slide. That share is in the
# workbook and in the slide's findings, which is the standing rule when a
# column will not fit.
#
# Column headings carry no commas. A comma in a heading is a two-part label
# wearing a disguise, and the second part is always the one that gets wrapped
# onto a line of its own; the table's TITLE is where a phrase belongs.
WORKLOAD_SECTIONS = {
    "census": (
        ["intake_share", WORKLOAD_RESIDENTS, "resident_share",
         WORKLOAD_RESIDENTS_FITTED],
        "census",
    ),
    "tenure": (
        [WORKLOAD_TENURE, WORKLOAD_TENURE_FITTED, WORKLOAD_REMAINING_FITTED],
        "days per resident",
    ),
    "animal_days": (
        [WORKLOAD_DAYS, WORKLOAD_DAYS_FITTED, WORKLOAD_DAYS_OWED],
        "animal-days (average)",
    ),
}

# Headings for the slide, where the table's TITLE names the quantity and the
# column has only to say which side of the comparison it is. One word each,
# because a header two words long is a header that wraps, and three tables of
# wrapped headers is the row that would not fit in the first place.
WORKLOAD_SLIDE_HEADERS = {
    "intake_share": "Intake Pct",
    WORKLOAD_RESIDENTS: "Counted",
    "resident_share": "Pct",
    WORKLOAD_RESIDENTS_FITTED: "Fitted",
    WORKLOAD_TENURE: "Counted",
    WORKLOAD_TENURE_FITTED: "Fitted",
    WORKLOAD_REMAINING_FITTED: "Future",
    WORKLOAD_DAYS: "Counted",
    WORKLOAD_DAYS_FITTED: "Fitted",
    WORKLOAD_DAYS_OWED: "Owed",
}

# The workbook's reading order, which is its own rather than the slides'.
# Deriving it from WORKLOAD_SECTIONS made the sheet inherit the slides' budget:
# a column no slide had room for was dropped from the workbook too, against
# what `workload_full_table` promises. Two went that way, the intakes per day
# and the share of the days owed, and losing the first stranded the intake
# share beside the study-window day total. Each share now follows the column it
# divides, which is also the order WORKLOAD_SHARE_OF states.
WORKLOAD_WORKBOOK_ORDER = [
    CARE_DAYS_DELIVERED,
    WORKLOAD_INTAKES, "intake_share",
    WORKLOAD_RESIDENTS, "resident_share",
    WORKLOAD_RESIDENTS_FITTED, "fitted_share",
    WORKLOAD_TENURE, WORKLOAD_TENURE_FITTED, WORKLOAD_REMAINING_FITTED,
    WORKLOAD_DAYS, WORKLOAD_DAYS_FITTED,
    WORKLOAD_DAYS_OWED, "owed_share",
]

WORKLOAD_FORMATS = {
    WORKLOAD_INTAKES: Format(1),
    WORKLOAD_RESIDENTS: COUNT,
    WORKLOAD_RESIDENTS_FITTED: COUNT,
    WORKLOAD_TENURE: Format(1),
    WORKLOAD_TENURE_FITTED: Format(1),
    WORKLOAD_REMAINING_FITTED: Format(1),
    WORKLOAD_DAYS: COUNT,
    WORKLOAD_DAYS_FITTED: COUNT,
    WORKLOAD_DAYS_OWED: COUNT,
    CARE_DAYS_DELIVERED: COUNT,
    "intake_share": SHARE, "resident_share": SHARE, "fitted_share": SHARE,
    "owed_share": SHARE,
}

# Percentages on the WORKLOAD SLIDES only. A tenth of a percentage point is
# nothing an audience can act on and it is two characters of width in a table
# that was wrapping its headings; the workbook keeps the decimal, because a
# sheet is where a reader goes to check a number rather than to take an
# impression of it.
WORKLOAD_SLIDE_SHARE = Format(0, percent=True, blank=True)

# Which counted column each share divides, so a share is always of its own
# side of the table: the counted shares out of the counted total, the fitted
# out of the fitted. Sharing one denominator would put the gap between the two
# sides into the shares as well, where it would read as a difference between
# the levels.
WORKLOAD_SHARE_OF = {
    "intake_share": WORKLOAD_INTAKES,
    "resident_share": WORKLOAD_RESIDENTS,
    "fitted_share": WORKLOAD_RESIDENTS_FITTED,
    "owed_share": WORKLOAD_DAYS_OWED,
}


def _workload_frame(bundle: Bundle, stratifier: str) -> pd.DataFrame:
    """Every workload column one stratifier has, counted and fitted together.

    Assembled once and sliced by the three slides and by the workbook, so a
    column cannot be computed one way for a slide and another for the sheet it
    is checked against.
    """
    frame = pd.DataFrame()
    if bundle.has("strata", stratifier, "observations"):
        observations = bundle.stratum(stratifier, "observations")
        for name in (WORKLOAD_INTAKES, WORKLOAD_RESIDENTS, WORKLOAD_DAYS,
                     CARE_DAYS_DELIVERED):
            if name in observations.columns:
                frame[name] = observations[name]
    if bundle.has("strata", stratifier, "census"):
        census = bundle.stratum(stratifier, "census")
        for name in (WORKLOAD_RESIDENTS_FITTED, WORKLOAD_TENURE,
                     WORKLOAD_TENURE_FITTED, WORKLOAD_REMAINING_FITTED,
                     WORKLOAD_DAYS_FITTED, WORKLOAD_DAYS_OWED):
            if name in census.columns:
                frame[name] = census[name]

    if _levels_partition_census(bundle, stratifier):
        for share, column in WORKLOAD_SHARE_OF.items():
            if column not in frame.columns:
                continue
            total = frame[column].sum()
            if total:
                frame[share] = frame[column] / total
    return frame


def requires_workload(bundle: Bundle, stratifier: str, section: str) -> bool:
    """Whether one stratifier can fill one of the three tables.

    Both sides are required, counted and fitted. A table with one of them is
    not a smaller version of this table, it is a different table: the whole
    reading is the comparison, and a column standing alone would be read as an
    answer rather than as half of one.
    """
    columns, _ = WORKLOAD_SECTIONS[section]
    frame = _workload_frame(bundle, stratifier)
    wanted = [name for name in columns if name in WORKLOAD_FORMATS
              and name not in WORKLOAD_SHARE_OF]
    return all(name in frame.columns and frame[name].notna().any()
               for name in wanted)


# Levels a workload table may show before it starts selecting. Three of these
# tables sit on one slide under a subtitle, and the deepest of them sets the
# row: at eleven levels the last footnote fell off the foot of the page. Ten
# rows and a header is what the body holds.
#
# Unlike the LOS slides, which select four rows by four superlatives, this
# keeps the largest levels by the counted column, because the question these
# slides ask is where the animals and the days actually are. The shares are
# still each level's share of the WHOLE, so they no longer sum to one when a
# level has been left out, and the footnote says how many were.
WORKLOAD_MAX_ROWS = 10


def workload_table(bundle: Bundle, stratifier: str, vocab, section: str) -> Table:
    """One stratifier's rows for one of the three workload questions."""
    columns, subject = WORKLOAD_SECTIONS[section]
    frame = _workload_frame(bundle, stratifier)
    present = [name for name in columns if name in frame.columns]
    label = vocab.stratifier(stratifier).label

    hidden = 0
    if len(frame) > WORKLOAD_MAX_ROWS and present:
        size = frame[present[0]] if present[0] not in WORKLOAD_SHARE_OF else frame[present[1]]
        keep = set(size.nlargest(WORKLOAD_MAX_ROWS).index)
        hidden = len(frame) - len(keep)
        frame = frame[frame.index.isin(keep)]

    footnotes = ["Counted from the data; fitted from the survival curves."]
    if hidden:
        footnotes.append(
            f"The {WORKLOAD_MAX_ROWS} largest levels; {hidden} more are in the "
            f"workbook. Shares are of the whole, so they do not add to 100%.")
    if section == "census" and "resident_share" not in present:
        footnotes.append(
            f"No share: {label} levels divide the calendar rather than the "
            f"animals in care, so each figure is that level's own rather than "
            f"a part of one total.")
    # The days-owed slide has no room for a share column, so the one number
    # anyone would read off it is written under the table instead: which level
    # holds most of what is owed, and how much of it. Small type, but a reader
    # who wants it can find it, and the alternative was a column that does not
    # fit.
    if section == "animal_days":
        footnotes.append(_owed_share_footnote(bundle, stratifier, label))
    return Table(
        df=frame[present].copy(),
        title=f"{subject}, by {label}",
        formats={name: (WORKLOAD_SLIDE_SHARE if name in WORKLOAD_SHARE_OF
                        else WORKLOAD_FORMATS[name])
                 for name in present},
        headers=dict(WORKLOAD_SLIDE_HEADERS),
        footnotes=footnotes,
    )


def _owed_share_footnote(bundle: Bundle, stratifier: str, label: str) -> str:
    """Which level holds most of the days owed, for the foot of the table.

    Silent about the size of the share where the levels do not divide the
    standing population, since there is no whole for a share to be of: what a
    period holds is its own commitment under its own regime, and that is what
    the sentence says instead.
    """
    owed = _care_days_owed(bundle, stratifier)
    if owed is None or owed.dropna().empty:
        return "Days owed is what an average day's residents still have to come."
    if not _levels_partition_census(bundle, stratifier):
        return (f"Each {label}'s days owed is its own commitment under its own "
                f"regime, not a part of one total, so no share is given.")
    total = owed.sum()
    if not total:
        return "Days owed is what an average day's residents still have to come."
    top = owed.idxmax()
    return f"{top} holds {owed[top] / total:.0%} of the days owed."


def workload_full_table(bundle: Bundle, stratifier: str, vocab,
                        columns: Sequence[str] | None = None) -> Table:
    """Every workload column at once, for the workbook.

    The slides take three slices of this and leave out the study-window
    animal-day total entirely. Nothing is dropped here: a column not worth a
    third of a slide is still worth a cell to a reader checking the arithmetic,
    and the width that made it a poor slide column costs nothing on a sheet.

    `columns` forces a column set the caller has agreed across a family of
    these, so they can be stacked on one sheet under one row of headings. A
    stratifier that has no share columns, periods being the case, then carries
    them empty rather than dropping them and breaking the stack. Empty is the
    honest rendering: the footnote says why, and a share of a population the
    levels do not divide has no value to put there.
    """
    frame = _workload_frame(bundle, stratifier)
    if columns is None:
        columns = [name for name in WORKLOAD_WORKBOOK_ORDER
                   if name in frame.columns]
    frame = frame.reindex(columns=list(columns))

    footnotes = []
    if not _levels_partition_census(bundle, stratifier):
        footnotes.append(
            f"No shares: {vocab.stratifier(stratifier).label} levels divide the "
            f"calendar rather than the animals in care, so each figure is that "
            f"level's own rather than a part of one total.")
    return Table(
        df=frame,
        title=f"workload by {vocab.stratifier(stratifier).label}",
        formats={name: WORKLOAD_FORMATS[name] for name in columns
                 if name in WORKLOAD_FORMATS},
        headers=dict(WORKLOAD_HEADERS),
        footnotes=footnotes,
    )


def workload_columns(bundle: Bundle, stratifiers: Sequence[str]) -> list[str]:
    """The columns a family of workload tables agrees on, in reading order.

    The union of what the stratifiers have rather than the full catalogue, so a
    measure this run does not carry at all never appears, while one that only
    some stratifiers can fill appears for all of them and is empty where it
    cannot be filled.
    """
    present = set()
    for stratifier in stratifiers:
        present.update(_workload_frame(bundle, stratifier).columns)
    return [name for name in WORKLOAD_WORKBOOK_ORDER if name in present]


def requires_full_table(bundle: Bundle, stratifier: str) -> bool:
    blocks = {block for _, block in FULL_TABLE_MEASURES}
    return all(bundle.has("strata", stratifier, block) for block in blocks)


def full_table(bundle: Bundle, stratifier: str) -> Table:
    """Every level of one stratifier, on the measures the deck leads with.

    The whole sample is not a special case: `all` is a stratifier with a single
    level, so it comes through here unchanged and its row cannot drift from the
    stratified ones. Flags are suppressed for a single level, where "highest of
    one" would be noise.
    """
    frames = {}
    for measure, block in FULL_TABLE_MEASURES:
        source = bundle.stratum(stratifier, block)
        frames[measure] = source[measure]
    df = pd.DataFrame(frames, index=bundle.levels(stratifier))

    flags = flag_extremes(df) if len(df) > 1 else None
    return Table(
        df=df,
        title=_stratum_table_title(df, stratifier, f"all levels by {stratifier}"),
        formats=dict(FORMATS),
        flags=flags,
        footnotes=[UNITS_FOOTNOTE],
    )


def sub_table(table: Table, measures: Sequence[str], title: str = "") -> Table:
    """The same table, narrowed to some of its columns.

    A column view, not a new table: the numbers, the flags and the formats come
    from the table passed in, so two slides built from one table cannot disagree
    about a value or about which level holds an extreme. Flags in particular
    must be inherited rather than recomputed, for the reason `flag_extremes`
    gives about `highlights_table`: judged over the columns that survived, "H"
    would quietly mean "highest of the ones I kept".

    Measures the table does not have are dropped rather than raising, so a run
    whose bundle predates a measure narrows to what it has instead of failing.
    """
    kept = [measure for measure in measures if measure in table.df.columns]
    return Table(
        df=table.df[kept],
        title=title or table.title,
        formats={k: v for k, v in table.formats.items() if k in kept},
        flags=None if table.flags is None else table.flags[kept],
        footnotes=list(table.footnotes),
        headers={k: v for k, v in table.headers.items() if k in kept},
        row_formats=dict(table.row_formats),
        highlight=table.highlight if table.highlight in kept else "",
    )


def selected_levels(table: Table, selectors: Sequence[tuple[str, bool]],
                    show_all_max: int, pinned: Sequence[str] = ()) -> list[str]:
    """Which levels a short table shows: all of them, or the remarkable ones.

    Up to `show_all_max` levels everything is shown. Beyond that the levels
    holding the selectors' superlatives are taken as a UNION, which routinely
    yields fewer rows than there are selectors because the superlatives
    collide: a group that fills the kennels is usually also the one that stays
    longest. Fewer rows is the intended outcome, not a shortfall to backfill,
    and which selector won a row is deliberately not shown.

    Ties are broken ARBITRARILY here, by `idxmax`, which is allowed because
    this picks rows and asserts nothing about them. This picks which rows fit on a slide; it
    asserts nothing. Choosing one of two identical rows costs the reader a row
    they can look up in the workbook, where naming one of two identical levels
    in a sentence would tell them something untrue. The sentences use
    `extreme_levels` for exactly that reason.

    `pinned` names levels the settings file insisted on. They join the union
    rather than replacing it, so asking for a level you care about does not
    silently drop the one the data says is remarkable. A pinned level that this
    stratifier does not have is ignored here and reported by the caller, which
    is the layer that knows whether the name was a typo or a level this
    particular dataset happens to lack.

    Shared by the LOS and competing-risk tables because the mechanism is one
    decision, not two. What differs between them is which columns select and
    how many rows are worth showing, and those are arguments.
    """
    levels = list(table.df.index)
    if len(levels) <= show_all_max:
        return levels

    picked: list[str] = [lvl for lvl in pinned if lvl in levels]
    for measure, want_max in selectors:
        values = table.df[measure].dropna()
        if not separates(values):
            continue
        level = values.idxmax() if want_max else values.idxmin()
        if level not in picked:
            picked.append(level)
    # Rows always appear in the stratifier's canonical level order, never in
    # the order the selectors happened to fire. The reader is comparing rows
    # against each other and against the same stratifier elsewhere in the deck;
    # a table whose order encoded the selection criteria would read as a
    # ranking it is not.
    return [lvl for lvl in levels if lvl in picked]


def _shown(source: Table, chosen: Sequence[str], title: str,
           criterion: str = "") -> Table:
    """`source` cut down to `chosen` rows, keeping everything that describes it.

    Formats, headers and flags travel with the rows. Flags in particular are
    SUBSET rather than recomputed: they were judged across every level, and
    recomputing them here would quietly turn "highest" into "highest of the few
    I chose". The footnote says so, and says how the rows were picked; what the
    marks look like is the renderer's legend, appended there, since a letter
    and a color need different words for the same fact.
    """
    footnotes = list(source.footnotes)
    if len(chosen) < len(source.df):
        footnotes.insert(0, f"{len(chosen)} of {len(source.df)} levels shown"
                            f"{criterion}; marks are judged across all "
                            f"{len(source.df)}, not across the rows shown here.")
    return Table(
        df=source.df.loc[list(chosen)],
        title=title,
        formats=dict(source.formats),
        flags=None if source.flags is None else source.flags.loc[list(chosen)],
        footnotes=footnotes,
        headers=dict(source.headers),
        row_formats=dict(source.row_formats),
        highlight=source.highlight,
    )


def highlights_table(bundle: Bundle, stratifier: str,
                     full: Table | None = None,
                     pinned: Sequence[str] = ()) -> Table:
    """A short LOS table meant to send the reader to the full one.

    Selects on the four superlatives in HIGHLIGHT_SELECTORS: who arrives most,
    who fills the most kennels, and the longest and shortest average stay.
    """
    # Explicit None check rather than a truthiness test: Table wraps a
    # DataFrame, and anything that later gives it a __len__ would silently turn
    # an empty table into "build me a fresh one".
    if full is None:
        full = full_table(bundle, stratifier)
    chosen = selected_levels(full, HIGHLIGHT_SELECTORS, HIGHLIGHT_SHOW_ALL_MAX,
                             pinned)
    return _shown(full, chosen, f"LOS highlights by {stratifier}")


# ---------------------------------------------------------------------------
# Cap sensitivity
# ---------------------------------------------------------------------------

# Above this share of a level's stays still in care at the cap, that level's
# tenure and census figures get called out in the speaker notes. Half a percent
# reads as negligible and is not, for a reason worth stating: a stay that
# reaches the cap is present on every one of those days, so it counts in full
# up to the cap (it is never dropped from the curve), but the days it would
# have gone on to spend past the cap are excluded from every tenure figure, and
# the standing population feels those missing days far more than the arriving
# cohort does. On OC2, LARGE's 0.9% at the cap contributes about a tenth of
# that group's whole restricted mean.
CAP_SENSITIVITY_THRESHOLD = 0.005

# The measures the excluded days beyond the cap distort, worst first. An
# ordering of exposure, not a list of everything the cap touches. A percentile
# of the tenure profile moves furthest because the profile is nearly flat far
# out in its tail, where a small change in the excluded mass buys many days;
# the means move least because a mean spreads that mass over the whole range.
CAP_EXPOSED_MEASURES = [
    ("per_resident_past_days_restricted_p90", "census"),
    ("per_resident_past_days_restricted_median", "census"),
    ("per_resident_past_days", "census"),
    ("expected_census", "census"),
    ("km_restricted_mean", "km"),
]


def cap_sensitivity_notes(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """Name the levels whose tenure figures the cap is holding back.

    Judged across EVERY level of the stratifier, like the H/L/F flags and for
    the same reason: whether the cap binds is a property of the level's own
    curve, not of whichever rows a highlights table chose to show. A level that
    is flagged but not displayed still belongs in the notes, because the
    workbook and the CSVs carry its numbers.

    Returns no notes when nothing crosses the threshold, rather than a note
    saying so. A caveat that fires on every deck stops being read.
    """
    if not bundle.has("strata", stratifier, "km"):
        return []
    km = bundle.stratum(stratifier, "km")
    if "km_still_in_care_at_cap" not in km.columns:
        return []

    at_cap = km["km_still_in_care_at_cap"].dropna()
    flagged = at_cap[at_cap > CAP_SENSITIVITY_THRESHOLD].sort_values(ascending=False)
    if flagged.empty:
        return []

    cap = bundle.data.get("settings", {}).get("restricted_stay_cap")
    horizon = f"{cap}-day cap" if cap else "stay cap"
    listing = ", ".join(f"{level} {value * 100:.1f}%"
                        for level, value in flagged.items())

    exposed = [vocab.metric(measure).label
               for measure, block in CAP_EXPOSED_MEASURES
               if bundle.has("strata", stratifier, block)
               and measure in bundle.stratum(stratifier, block).columns]

    notes = [
        f"Cap sensitivity. The KM curve still has stays in care at the "
        f"{horizon} for {listing}, above the "
        f"{CAP_SENSITIVITY_THRESHOLD * 100:.1f}% mark at which the cap starts "
        f"to shape the answer. Those stays count in full up to the cap, but "
        f"the days they would have gone on to spend beyond it are excluded, so "
        f"read every tenure and census figure for those levels as a lower "
        f"bound rather than an estimate."
    ]
    if exposed:
        notes.append(
            "Most exposed first: " + ", ".join(exposed) + ". The percentile "
            "moves furthest because the tenure profile is nearly flat far out "
            "in its tail, so a small change in the excluded mass buys many "
            "days. Median LOS is barely affected, and the 90th percentile of "
            "LOS reports no value at all rather than a capped one when the "
            "curve never reaches it."
        )
    return notes


# ---------------------------------------------------------------------------
# Order shifts
# ---------------------------------------------------------------------------

# Two levels shift order when one is ahead of the other on one of a figure's
# three marks and behind it on another. A difference smaller than this counts
# as no difference at all, in days.
#
# One day, for two reasons that meet at the same number. The median and the P90
# are read off a step function on a grid of whole days, so anything under a day
# there IS a tie, and the threshold is what permitting ties amounts to. The
# restricted mean is an integral over that same grid and moves continuously,
# where a fraction of a day is the kind of difference one long stay produces,
# so the same number serves as its noise margin.
#
# Applied to each difference before any sign is read, which is what stops a
# marginal difference on one mark from being reported as a reversal of a real
# difference on another.
ORDER_SHIFT_TOLERANCE = 1.0

# The trio of marks each figure on an LOS slide carries, in the order the deck
# explains them everywhere else, with what to call the figure and what a
# sentence about it would be claiming. Both trios are on the slide's table, so
# a reader can check any pair this names.
ORDER_SHIFT_TRIOS: list[tuple[str, str, list[str]]] = [
    ("length-of-stay curves", "has the longer stays",
     ["km_median_los", "km_restricted_mean", "km_p90_los"]),
    ("in-care tenure profiles", "has the longer-standing residents",
     TENURE_MEASURES),
]


def _pair_days(first: float, second: float) -> tuple[str, str]:
    """Two day counts, at the coarsest precision that keeps them apart.

    Whole days everywhere else in the deck's prose, but two values a day apart
    can round to the same integer, and "the higher mean (30 against 30)" reads
    as a bug rather than as a rounding convention. A decimal is added only when
    that happens.
    """
    for places in (0, 1, 2):
        shown = (f"{first:.{places}f}", f"{second:.{places}f}")
        if shown[0] != shown[1]:
            return shown
    return shown


def order_shifts(df: pd.DataFrame,
                 measures: Sequence[str]) -> list[tuple[str, str, dict]]:
    """Every pair of levels these measures do not rank the same way.

    For each pair, the difference on each measure, with anything under
    `ORDER_SHIFT_TOLERANCE` flattened to zero. A pair is returned only when
    what survives holds both a positive and a negative difference: a tie plus
    one direction is agreement as far as it goes, not a shift.

    A measure one of the two levels has no value for is dropped from that
    pair rather than dropping the pair, since an unreached P90 leaves the
    median and the mean perfectly comparable.

    Most substantial first, and "substantial" is the SMALLER side of the
    reversal: a pair three days ahead on one mark and forty behind on another
    has crossed by three days, however far apart the two are otherwise. It is
    the leading pair that gets spelled out with numbers, so it should be the
    one least likely to be an artefact.
    """
    found = []
    for first, second in itertools.combinations(df.index, 2):
        gaps = {}
        for measure in measures:
            ahead, behind = df.loc[first, measure], df.loc[second, measure]
            if ahead != ahead or behind != behind:
                continue
            gap = float(ahead) - float(behind)
            gaps[measure] = 0.0 if abs(gap) < ORDER_SHIFT_TOLERANCE else gap
        forward = [gap for gap in gaps.values() if gap > 0]
        backward = [-gap for gap in gaps.values() if gap < 0]
        if not forward or not backward:
            continue
        found.append((str(first), str(second), gaps,
                      min(max(forward), max(backward))))
    found.sort(key=lambda shift: shift[3], reverse=True)
    return [(first, second, gaps) for first, second, gaps, _ in found]


def _order_shift_marks(measures: Sequence[str], df: pd.DataFrame,
                       first: str, second: str, vocab) -> str:
    """One side of a worked example: the marks that run one way, with values."""
    named = []
    for measure in measures:
        ahead, behind = _pair_days(df.loc[first, measure], df.loc[second, measure])
        named.append(f"{vocab.metric(measure).short} ({ahead} against {behind})")
    return name_levels(named)


def order_shift_notes(full: Table, label: str, vocab) -> list[str]:
    """Which pairs of levels the three marks on a figure disagree about.

    A note per figure, and none for a figure whose marks rank the levels alike.
    The deck leads its stratified slides with a level's average stay, and the
    audience will carry that ranking to the other two marks unless told that it
    does not hold: a level can have the higher median and the lower P90, which
    is not an inconsistency but a heavier tail, and it means "this level stays
    longer" is only ever true of one mark at a time.

    Judged over every level of the stratifier rather than the rows the
    highlights table kept, like the cap caveat and the H/L/F flags, since the
    workbook and the figures carry the undisplayed levels too.
    """
    notes = []
    if len(full.df) < 2:
        return notes
    for figure, claim, measures in ORDER_SHIFT_TRIOS:
        present = [measure for measure in measures if measure in full.df.columns]
        if len(present) < 2:
            continue
        shifts = order_shifts(full.df, present)
        if not shifts:
            continue
        pairs = name_levels([f"{first} with {second}"
                             for first, second, _ in shifts])
        first, second, gaps = shifts[0]
        ahead = [measure for measure in present if gaps.get(measure, 0) > 0]
        behind = [measure for measure in present if gaps.get(measure, 0) < 0]
        # A mark the tolerance flattened is named without its values. Printing
        # them would show two numbers a reader can see are not equal, in a
        # clause saying they are level, and the point of the clause is to
        # account for the third mark rather than to quantify it.
        level = [measure for measure in present if gaps.get(measure, 1) == 0]
        example = (f"Take {first} with {second}, in days. {first} has the "
                   f"higher {_order_shift_marks(ahead, full.df, first, second, vocab)} "
                   f"but the lower "
                   f"{_order_shift_marks(behind, full.df, first, second, vocab)}")
        if level:
            example += (f"; the {name_levels([vocab.metric(m).short for m in level])} "
                        f"{_agrees(level, 'separates', 'separate')} them by less "
                        f"than a day")
        notes.append(
            f"Order shifts on the {figure}. "
            f"{'One pair' if len(shifts) == 1 else f'{len(shifts)} pairs'} of "
            f"levels {_agrees(shifts, 'is', 'are')} ranked one way by one of "
            f"the three marks and the other way by another: {pairs}. {example}. "
            f"So a claim about which {label} {claim} has to name the mark it "
            f"rests on. Differences under a day are counted as ties, so nothing "
            f"here turns on rounding.")
    return notes


def los_standing_notes(bundle: Bundle, stratifier: str, vocab) -> list[str]:
    """The note tail every LOS slide carries, whole-sample or by level.

    Three things that are true of any slide built from the KM block, in one
    place because the ORDER is a single decision and not one per rule: the cap
    that bounds every figure, then the caveat that fires when that cap is doing
    visible work (which reads as a qualification of the sentence before it, so
    it must follow), then how the numbers were arrived at, which holds whether
    the cap binds or not and so comes last.

    A rule supplies whatever is particular to its slide and appends this.
    """
    notes = []
    cap = bundle.data.get("settings", {}).get("restricted_stay_cap")
    if cap:
        notes.append(f"Stay cap is at {cap} days. Every LOS and tenure figure "
                     f"on this slide is restricted to it.")
    notes.extend(cap_sensitivity_notes(bundle, stratifier, vocab))
    # True without exceptions now that the at-cap column is the KM curve's
    # terminal value rather than the observed count. Daily intakes are the one
    # tally on these slides, which is why the note names them.
    notes.append("All values other than the daily intakes are based on the KM "
                 "curve, not on direct summation in the data sample.")
    return notes


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

# A finding is a finished sentence with the numbers already in it. Slides
# carry them without displaying them, and the deck gathers them onto a closing
# slide, so the summary is assembled from what each section actually found
# rather than written separately and left to drift.
#
# Plain strings for now. They will want structure once the planner has to rank
# or drop them, but inventing that structure before anything ranks would be
# guessing at the fields.


def _census_shares(bundle: Bundle, stratifier: str,
                   census: pd.Series) -> pd.Series | None:
    """Each level's share of the standing population, when that is meaningful.

    It is meaningful only when the levels partition the population at a moment
    in time. Animal group and intake type do: every resident has exactly one
    size and one intake type, and the level censuses sum to the whole-sample
    census. PERIODS DO NOT. Periods partition the calendar, so their censuses
    are averages over disjoint stretches and sum to roughly the number of
    periods times the true census. On OC2 that sum is 571 against a real census
    of 191, so a "share of residents" by period would be nonsense.

    Rather than hardcode which stratifiers are safe, this checks: the shares
    are returned only if the levels actually add up to the pooled census. The
    tolerance is not pedantry. These are KM-implied censuses fitted per
    stratum, so they agree with the pooled figure closely but not exactly.
    """
    if not bundle.has("strata", "all", "census"):
        return None
    total = float(bundle.stratum("all", "census")["expected_census"].iloc[0])
    if not total or total != total:
        return None
    if abs(census.sum() - total) > 0.01 * total:
        return None
    return census / total


def _levels_partition_census(bundle: Bundle, stratifier: str) -> bool:
    """Whether this stratifier's levels divide the standing population.

    The question `_census_shares` answers on the way to answering another one,
    asked on its own by everything that needs to know whether ANY share of the
    residents is meaningful here, rather than a share of one particular
    quantity. Asked of the fitted census, which is the series the rule was
    written against, so a caller cannot get a different answer by holding a
    different column.
    """
    if not bundle.has("strata", stratifier, "census"):
        return False
    census = bundle.stratum(stratifier, "census").get("expected_census")
    if census is None:
        return False
    return _census_shares(bundle, stratifier, census.dropna()) is not None


def findings_for_overall(full: Table) -> list[str]:
    """What the whole-sample slide contributes: the length-bias contrast.

    Every other finding compares levels, which a single-level table cannot
    do. What it can do instead is set the arriving cohort against the standing
    population, the one comparison that needs no second level and the reason
    the slide carries two figures. Silent unless both medians are available: a
    median LOS the curve never reaches arrives as NA.
    """
    if len(full.df) != 1:
        return []
    row = full.df.iloc[0]
    arrival = row.get("km_median_los")
    resident = row.get("per_resident_past_days_restricted_median")
    if arrival is None or resident is None:
        return []
    if arrival != arrival or resident != resident:
        return []
    return [f"A typical arriving animal leaves in {arrival:.0f} days, while a "
            f"typical animal already in care has been here {resident:.0f}, "
            f"the same shelter read two ways."]


def findings_for_stratifier(bundle: Bundle, stratifier: str, full: Table,
                               label: str) -> list[str]:
    """What this stratifier's slide contributes to the closing summary.

    Usually one sentence, sometimes none. Nothing is said when there is a
    single level, when length of stay is flat across the levels, or when more
    levels share the longest stay than `extreme_levels` will name, because
    "the longest of several identical values" is not a finding.

    Levels that tie are named together and take a plural verb. The share clause
    reads "and" when the same levels hold both extremes and "while" when they
    do not, which is a comparison of the two SETS rather than of two names, so
    a two-way tie holding both still reads as one group.
    """
    if len(full.df) < 2:
        return []

    stays = full.df["km_restricted_mean"].dropna()
    longest = extreme_levels(stays, want_max=True)
    if not longest:
        return []

    sentence = (f"Among {label} levels, {name_levels(longest)} "
                f"{_agrees(longest, 'has', 'have')} the longest average stay "
                f"at {stays[longest[0]]:.0f} days")

    census = full.df["expected_census"].dropna()
    shares = _census_shares(bundle, stratifier, census) if not census.empty else None
    biggest = extreme_levels(shares, want_max=True) if shares is not None else []
    if biggest and shares[biggest[0]] > 0:
        share = shares[biggest[0]] * 100
        if biggest == longest:
            sentence += f", and the largest share of residents at {share:.0f}%"
        else:
            sentence += (f", while {name_levels(biggest)} "
                         f"{_agrees(biggest, 'holds', 'hold')} the largest "
                         f"share of residents at {share:.0f}%")
    return [sentence + "."]


def findings_for_outlook(full: Table) -> list[str]:
    """What the whole-sample outlook slide contributes: the resident's own view.

    The slide before it says how long an arriving animal stays and how long a
    resident has been here. The number this adds is the one nobody guesses from
    those two, and the one on the slide that looks forward.
    """
    if len(full.df) != 1:
        return []
    row = full.df.iloc[0]
    tenure = row.get("per_resident_past_days_restricted_median")
    remaining = row.get("remaining_days_at_median_tenure")
    if tenure is None or remaining is None:
        return []
    if tenure != tenure or remaining != remaining:
        return []
    return [f"The animal in the middle of an average day's population has "
            f"been here {tenure:.0f} days and expects {remaining:.0f} more."]


def findings_for_outlook_stratifier(full: Table, label: str) -> list[str]:
    """Which levels' residents are furthest from leaving, and which nearest.

    Both ends, because the sentence is a contrast and one end alone would read
    as a fact about a level rather than as a range across them. Silent where
    either end has too many holders to name, the rule `extreme_levels` applies
    everywhere: "the furthest of five identical values" is not a finding.
    """
    if len(full.df) < 2:
        return []
    if "remaining_days_at_median_tenure" not in full.df.columns:
        return []
    if "per_resident_past_days_restricted_median" not in full.df.columns:
        return []

    remaining = full.df["remaining_days_at_median_tenure"].dropna()
    tenure = full.df["per_resident_past_days_restricted_median"]
    furthest = extreme_levels(remaining, want_max=True)
    nearest = extreme_levels(remaining, want_max=False)
    if not furthest or not nearest or set(furthest) & set(nearest):
        return []

    def described(levels):
        held = levels[0]
        return (f"{name_levels(levels)}, whose median resident has been here "
                f"{tenure[held]:.0f} days and expects {remaining[held]:.0f} more")

    return [f"Among {label} levels, the residents furthest from leaving are "
            f"{described(furthest)}; the nearest are {described(nearest)}."]


def findings_for_order_shifts(full: Table, label: str) -> list[str]:
    """That the levels have no single ranking, where they do not.

    A qualification of the finding beside it rather than a finding of its
    own: the slide finds which level has the longest average stay, and this
    says how far that sentence generalizes to the other two marks. Silent when
    the marks agree, which is the ordinary case and needs no sentence.
    """
    measures = [measure for measure in ORDER_SHIFT_TRIOS[0][2]
                if measure in full.df.columns]
    if len(full.df) < 2 or len(measures) < 2:
        return []
    shifts = order_shifts(full.df, measures)
    if not shifts:
        return []
    pairs = len(list(itertools.combinations(full.df.index, 2)))
    if len(shifts) == 1:
        first, second, _ = shifts[0]
        return [f"The {label} levels have no single ranking by length of stay: "
                f"{first} and {second} swap places between the median, the mean "
                f"and the 90th percentile."]
    return [f"The {label} levels have no single ranking by length of stay: "
            f"{len(shifts)} of the {pairs} pairs swap places between the "
            f"median, the mean and the 90th percentile."]


def findings_for_care_days(bundle: Bundle) -> list[str]:
    """The shelter's committed workload, and who is carrying it.

    Two sentences at most, and the second only where a level actually carries
    the load (see CARE_DAYS_MAJORITY and CARE_DAYS_DISPROPORTION). A stratifier
    whose levels each owe about what their size suggests has nothing to say
    here, and saying it anyway would bury the stratifier where it is true.
    """
    lines = []
    owed_all = _care_days_owed(bundle, BASELINE_STRATIFIER)
    if owed_all is not None and len(owed_all) and owed_all.iloc[0] == owed_all.iloc[0]:
        total = float(owed_all.iloc[0])
        census = float(bundle.stratum(BASELINE_STRATIFIER, "census")
                       ["expected_census"].iloc[0])
        cap = bundle.value("settings", "restricted_stay_cap")
        horizon = f", within the {cap}-day cap" if cap else ""
        # Both figures are fitted, so a small enough dataset produces a real
        # census of 0.4 animals owing 1.2 days. Rounded into a sentence that is
        # a claim about a shelter, that reads as nonsense rather than as a
        # small number, so the sentence is not made at all below what it can
        # state. The animal-years clause goes the same way on its own account:
        # it is there to make a large number graspable, and "some 0
        # animal-years" makes a small one absurd.
        if census >= 0.5 and total >= 1:
            years = (f", some {total / 365:.0f} animal-years"
                     if total >= 365 / 2 else "")
            lines.append(
                f"The {census:.0f} "
                f"{'animal' if round(census) == 1 else 'animals'} in care on "
                f"an average day {'is' if round(census) == 1 else 'are'} "
                f"committed to about "
                f"{total:,.0f} more {'day' if round(total) == 1 else 'days'} "
                f"of care{years}{horizon}.")

    for stratifier in summary_fields(bundle):
        found = burden_carrier(bundle, stratifier)
        if found is None:
            continue
        carrier, owed_share, resident_share = found
        owed = _care_days_owed(bundle, stratifier)
        lines.append(
            f"{carrier} is {resident_share * 100:.0f}% of the animals in care "
            f"but {owed_share * 100:.0f}% of the care days still owed: "
            f"{owed[carrier]:,.0f} days of {owed.sum():,.0f}.")
    return lines


# A level is over- or under-represented in the standing population when its
# share of the residents differs from its share of the arrivals by more than
# this. Below it, the two shares are the same share as far as an audience is
# concerned and the sentence would be reporting rounding.
REPRESENTATION_GAP = 0.05

# How far a level's counted census may sit from its fitted one before the gap
# is worth a sentence. Both are estimates of the same thing over the same
# window, so a few percent is the ordinary noise of a KM fit; past this, the
# level was carrying a population its own intake and length of stay would not
# sustain in a steady state.
DRIFT_GAP = 0.05


def findings_for_representation(bundle: Bundle, vocab) -> list[str]:
    """Levels that fill the building out of proportion to how they arrive.

    The exact statement, and the reason it is a finding rather than an
    arithmetic curiosity: a level's share of the census over its share of the
    intakes is its mean length of stay over the shelter's. So the gap between
    the two shares IS the length-of-stay difference, seen from the population
    rather than from the animal, and it is a statement about heterogeneity
    BETWEEN levels rather than about the shape of any one level's curve.

    Named for the largest gap in each direction, and only where the levels
    divide the standing population: a share of the residents by period would
    be a share of several different populations.
    """
    lines = []
    for stratifier in summary_fields(bundle):
        frame = _workload_frame(bundle, stratifier)
        if not {"intake_share", "resident_share"} <= set(frame.columns):
            continue
        gap = (frame["resident_share"] - frame["intake_share"]).dropna()
        if gap.empty:
            continue
        label = vocab.stratifier(stratifier).label
        over = gap.idxmax()
        if gap[over] < REPRESENTATION_GAP:
            continue
        lines.append(
            f"By {label}, {over} is {frame.at[over, 'intake_share'] * 100:.0f}% "
            f"of the arrivals but {frame.at[over, 'resident_share'] * 100:.0f}% "
            f"of the animals in care on an average day, because its stays run "
            f"longer than the shelter's average.")
    return lines


# What each workload slide's counted-against-fitted sentence is about, keyed by
# section: the two columns, and how to say the quantity in a sentence.
WORKLOAD_DRIFT = {
    "census": (WORKLOAD_RESIDENTS, WORKLOAD_RESIDENTS_FITTED,
               "animals in care", "{value:,.0f}"),
    "tenure": (WORKLOAD_TENURE, WORKLOAD_TENURE_FITTED,
               "days of tenure per resident", "{value:,.1f}"),
    "animal_days": (WORKLOAD_DAYS, WORKLOAD_DAYS_FITTED,
                    "animal-days on an average day", "{value:,.0f}"),
}


def findings_for_model_drift(bundle: Bundle, vocab, section: str) -> list[str]:
    """Where the counted population parts from the one the curve implies.

    The one dynamic reading in a deck of steady-state figures, and it is stated
    as what it is: the fitted side assumes intakes have been arriving at the
    observed average rate for long enough, and where they have not, the counted
    side remembers what the fitted side has forgotten.

    Silence would be the wrong answer when the two agree, which is why the
    agreement gets a sentence of its own. A reader who has taken four slides of
    KM-implied numbers on trust has just been shown the implication checked
    against a count, and that it passed is the most useful thing on the slide.
    """
    counted_name, fitted_name, subject, form = WORKLOAD_DRIFT[section]
    lines = []
    for stratifier in bundle.stratifiers():
        if stratifier == BASELINE_STRATIFIER:
            continue
        frame = _workload_frame(bundle, stratifier)
        if not {counted_name, fitted_name} <= set(frame.columns):
            continue
        counted, fitted = frame[counted_name], frame[fitted_name]
        drift = ((counted - fitted) / fitted.where(fitted > 0)).dropna()
        if drift.empty:
            continue
        label = vocab.stratifier(stratifier).label
        level = drift.abs().idxmax()
        if drift.abs().max() < DRIFT_GAP:
            lines.append(
                f"By {label}, the fitted {subject} match the counted ones to "
                f"within {drift.abs().max() * 100:.0f}% at every level, so the "
                f"survival curves reproduce the population the data actually "
                f"held.")
            continue
        direction = "more" if drift[level] > 0 else "fewer"
        carried = ("the long stays of a busier past, still in the building"
                   if drift[level] > 0 else
                   "a population still filling up behind a rise in intakes")
        lines.append(
            f"By {label}, {level} held {abs(drift[level]) * 100:.0f}% "
            f"{direction} {subject} than its own intake rate and length of "
            f"stay imply: {form.format(value=counted[level])} counted against "
            f"{form.format(value=fitted[level])} fitted, which is "
            f"{carried}.")
    return lines


# How far the parametric hazard ratio may sit from the semiparametric one
# before the deck says the Weibull form is doing work of its own. Read as a
# proportion of the Cox estimate, so it is the same test on a ratio of 0.4 as
# on one of 1.2.
PARAMETRIC_GAP = 0.10


def findings_for_parametric_agreement(panel, stratifier: str,
                                      label: str) -> list[str]:
    """Whether the Weibull's hazard ratios track the Cox's on this stratifier.

    The bridge between the two runs of ratio slides, and the reason the hazard
    ratios come first: the length-of-stay slides are read off a Weibull, and a
    Weibull is worth reading only where its parametric form is not making the
    answer. So the deck asks that question here, level by level, and says which
    answer it got instead of assuming the flattering one.

    Two things have to agree for the finding to be a clean yes: the estimates
    within `PARAMETRIC_GAP`, and the intervals overlapping. Intervals that miss
    each other say the two models are estimating different numbers and the
    sample is large enough to tell, which is a different and stronger statement
    than a wide gap on a thin level.
    """
    if stratifier not in panel.index.get_level_values("stratifier"):
        return []
    rows = panel.loc[stratifier]
    if not {"hr_cox_pooled", "hr_weibull_pooled"} <= set(rows.columns):
        return []

    worst_level, worst_gap, disjoint = None, 0.0, []
    for level in rows.index:
        cox, weibull = rows.at[level, "hr_cox_pooled"], rows.at[level, "hr_weibull_pooled"]
        if pd.isna(cox) or pd.isna(weibull) or cox <= 0:
            continue
        gap = abs(weibull / cox - 1)
        if gap > worst_gap:
            worst_level, worst_gap = level, gap
        bounds = [rows.at[level, f"{key}_ci_{side}"]
                  for key in ("hr_cox_pooled", "hr_weibull_pooled")
                  for side in ("lower", "upper")]
        if any(pd.isna(bound) for bound in bounds):
            continue
        cox_lo, cox_hi, weibull_lo, weibull_hi = bounds
        if cox_hi < weibull_lo or weibull_hi < cox_lo:
            disjoint.append(level)
    if worst_level is None:
        return []

    if worst_gap < PARAMETRIC_GAP and not disjoint:
        return [f"By {label}, the Weibull hazard ratios track the Cox ones to "
                f"within {worst_gap:.0%} at every level, so the parametric "
                f"form is not making the answer and the length-of-stay ratios "
                f"that follow can be read as the same comparison in days."]

    detail = (f"{worst_level} by {worst_gap:.0%}" if worst_level not in disjoint
              else f"{worst_level} by {worst_gap:.0%}, far enough that the two "
                   f"intervals do not overlap")
    return [f"By {label}, the Weibull and Cox hazard ratios part company on "
            f"{detail}. The Weibull's length-of-stay ratio for that level is a "
            f"statement about a fitted shape as much as about the level, and "
            f"the unadjusted Kaplan-Meier column beside it is the check to "
            f"read it against."]


def findings_for_gaps(bundle: Bundle, vocab) -> list[str]:
    """Curves the audience can see that stop being estimable inside the plot.

    Only gaps starting below the plot cap, which is the deck's own reading of
    which gaps a reader can act on: past the cap no figure here crosses one, and
    the notes on the opening slides carry those. A gap inside the plotted range
    invalidates a curve the deck is showing, which is a finding in the
    strongest sense, so it is stated whatever else the deck found.
    """
    gaps = observation_gaps(bundle, bundle.stratifiers())
    if gaps.empty:
        return []
    plot_cap = bundle.value("settings", "presentation", "plot_stay_cap")
    if plot_cap is not None:
        gaps = gaps[gaps["gap_start_day"] < plot_cap]
    if gaps.empty:
        return []

    earliest = gaps["gap_start_day"].min()
    subjects = _gap_subjects(gaps, vocab)
    verb = "is" if len(gaps) == 1 else "are"
    return [f"Observation of {subjects} has a gap inside the plotted range, "
            f"from day {_gap_day(earliest)}, so {'that curve' if len(gaps) == 1 else 'those curves'} "
            f"and everything drawn from {'it' if len(gaps) == 1 else 'them'} "
            f"{verb} unreliable from there on."]


# ---------------------------------------------------------------------------
# Competing risks
# ---------------------------------------------------------------------------

# The two measures the competing-risk tables report. Both are per-outcome in
# the bundle (aj_final_cif_L, aj_restricted_mean_L and so on), which the two
# tables below arrange two different ways.
AJ_OUTCOME_MEASURES = ["aj_final_cif", "aj_restricted_mean"]

AJ_OUTCOME_FORMATS: dict[str, Format] = {
    "aj_final_cif": Format(1, percent=True),
    "aj_restricted_mean": Format(1),
}


# Up to this many levels, the AJ table shows all of them. Higher than the LOS
# tables' four because these rows are shorter to read: six numbers in two kinds
# rather than eight in five, and the reader is comparing them against the
# figures beside the table rather than against each other alone.
AJ_SHOW_ALL_MAX = 6


def requires_aj(bundle: Bundle, stratifier: str) -> bool:
    """Whether one stratifier has competing-risk numbers to put on a slide."""
    return (bundle.has("aj", "has_analysis") and bool(bundle.data["aj"]["has_analysis"])
            and bundle.has("strata", stratifier, "aj_final_cif")
            and bundle.has("strata", stratifier, "aj_restricted_mean"))


def requires_aj_teaser(bundle: Bundle) -> bool:
    return requires_aj(bundle, "all")


# A slide footnote and a speaker note are not the same length of sentence. The
# footnote is read in the two seconds an audience spends looking away from the
# figure, so it says the thing that would be MISREAD without it and stops. The
# note is read by whoever is talking, who has time for the careful version and
# needs it, because "conditional on the outcome" is the whole distinction.
SHARE_AND_DAYS_FOOTNOTE = (
    "Share is the cumulative incidence at the stay cap. Mean days is the "
    "average duration of stays with that specific outcome, not across all "
    "stays."
)

SHARE_AND_DAYS_NOTE = (
    "Mean days is conditional on that outcome: the average time it takes "
    "among the stays that end that way, not across all stays. Read as an "
    "unconditional mean it is badly wrong."
)


def aj_window_notes(bundle: Bundle, stratifier: str) -> list[str]:
    """How long the competing-risk fit ran, and for whom it ran less long.

    The window is the last fitted time, capped at the stay cap, so it is a
    property of a level's own data: a level whose last stay resolves early gets
    a shorter one. That is not a distortion and the note says so. Beyond its
    window a level has nobody left under observation, so its shares are final
    rather than cut short, and they compare with a longer-running level's on
    the same terms. A window-sensitive quantity like RMTL would be a different
    matter; the deck does not report one.

    The note exists because an audience that notices two panels ending at
    different days will ask, and the answer is short.
    """
    if not bundle.has("strata", stratifier, "aj_window"):
        return []
    source = bundle.stratum(stratifier, "aj_window")
    if "aj_analysis_window_days" not in source.columns:
        return []
    windows = source["aj_analysis_window_days"].dropna()
    if windows.empty:
        return []

    longest = int(windows.max())
    shorter = windows[windows < longest].sort_values()
    if shorter.empty:
        return [f"Measured over a {longest}-day window."]

    listing = ", ".join(f"{level} {int(value)}" for level, value in shorter.items())
    return [f"Measured over a {longest}-day window, except where a level's own "
            f"curve ends sooner: {listing} days. That is where its last stay "
            f"resolves, not a horizon imposed on it, and past that point it "
            f"has nobody left under observation, so its shares are final and "
            f"still compare with the rest."]


def aj_outcome_codes(bundle: Bundle, stratifier: str) -> list[str]:
    """The competing outcomes, in the bundle's own order, "Any" excluded.

    "Any" is left out of every competing-risk block: the cumulative incidences
    already sum to it, and its restricted mean is a mean over a mixture of
    outcomes that answers no question anyone asks. It stays in the bundle,
    where a caller that wants the pooled figure can still ask for it.
    """
    cif = bundle.stratum(stratifier, "aj_final_cif")
    return [c[len("aj_final_cif_"):] for c in cif.columns
            if c.startswith("aj_final_cif_") and not c.endswith("_Any")]


def _aj_column_parts(column: str) -> tuple[str, str]:
    """Split an AJ table column into its measure and its outcome code.

    By known measure prefix, never by underscore position: the codes come from
    the user's palette configuration, so a code containing an underscore is
    legal, and splitting at the last underscore would quietly cut it in half.
    A column no known measure explains is a programming error, not data.
    """
    for measure in AJ_OUTCOME_MEASURES:
        prefix = measure + "_"
        if column.startswith(prefix):
            return measure, column[len(prefix):]
    raise ValueError(f"{column} is not an AJ outcome column")


def _aj_sources(bundle: Bundle, stratifier: str) -> tuple[list[str], dict]:
    """The outcome codes and the two matrices every AJ table is built from."""
    return aj_outcome_codes(bundle, stratifier), {
        "aj_final_cif": bundle.stratum(stratifier, "aj_final_cif"),
        "aj_restricted_mean": bundle.stratum(stratifier, "aj_restricted_mean"),
    }


def aj_outcome_table(bundle: Bundle, vocab) -> Table:
    """Where each stay ends up, and how long it takes to get there.

    One row per competing outcome, over the whole sample, one column per
    measure. The upright arrangement: a reader comparing outcomes gets them
    stacked under each other rather than spread across a header row, and the
    table grows downward as a dataset gains outcome codes.

    Nothing on a slide uses this today. It is kept because it is the shape a
    reader wants wherever outcomes are the subject and levels are not, which
    the flat arrangement below is deliberately not.

    No flags. Marking the largest cumulative incidence would be pointing at
    something a three-row table already shows.
    """
    codes, sources = _aj_sources(bundle, "all")
    level = sources["aj_final_cif"].index[0]

    rows = {
        capitalize_first(vocab.outcome_labels.get(code, code)): {
            measure: sources[measure].loc[level, f"{measure}_{code}"]
            for measure in AJ_OUTCOME_MEASURES
        }
        for code in codes
    }
    df = pd.DataFrame.from_dict(rows, orient="index", columns=AJ_OUTCOME_MEASURES)
    return Table(
        df=df,
        title="where stays end, and when",
        formats=dict(AJ_OUTCOME_FORMATS),
        flags=None,
        footnotes=[SHARE_AND_DAYS_FOOTNOTE],
    )


def aj_levels_table(bundle: Bundle, stratifier: str, vocab) -> Table:
    """Every level of one stratifier: each outcome's share, then its mean days.

    THE MASTER TABLE for competing risks, in two senses that are worth keeping
    straight.

    It is where the flags are judged. Every column here holds one measure, so
    an extreme compares shares with shares and days with days. Everything
    downstream, `aj_highlights_table` selecting rows and `stacked_by_measure`
    turning the frame on its side, is extract and reshape: it may drop rows or
    move them, and it must never recompute a flag, because "highest" would
    then mean highest of whatever survived rather than highest of the levels.

    It is also the shape the companion **Excel** sheets will be built from,
    when they are. A worksheet wants every level and every measure, one row per
    level, with the numbers as numbers; the slide arrangements are subsets and
    transpositions of exactly this. Keep it complete even where a slide only
    ever shows part of it.

    The flat arrangement, one row per level and one column per outcome per
    measure, which is what lets these numbers sit under figures: a row per
    level is what a reader comparing levels wants, and the whole sample is one
    row of it rather than a special case.

    Columns keep their real bundle names (`aj_final_cif_L` and so on), so the
    frame is still addressable by measure and outcome; the printed header is
    the outcome code with the vocabulary's short name for the measure, so a
    column says both what it is about and which of it: `L share`, `L days`.
    An earlier draft headed the columns with the bare code and left a footnote
    to say which half was which, on the grounds that six repetitions of a word
    would spend width this arrangement exists to save. On the slide that
    actually uses it, the whole sample under two figures, that width was there
    all along, and a header that says what it is beats a header that needs a
    sentence to be read.

    Flags are judged across every level, and suppressed for a single level
    where "highest of one" would be noise, exactly as in `full_table`.
    """
    codes, sources = _aj_sources(bundle, stratifier)

    columns, formats, headers = {}, {}, {}
    for measure in AJ_OUTCOME_MEASURES:
        for code in codes:
            key = f"{measure}_{code}"
            columns[key] = sources[measure][key]
            formats[key] = AJ_OUTCOME_FORMATS[measure]
            headers[key] = f"{code} {vocab.metric(measure).text(short=True)}"

    df = pd.DataFrame(columns, index=bundle.levels(stratifier))
    flags = flag_extremes(df) if len(df) > 1 else None
    return Table(
        df=df,
        title=_stratum_table_title(df, stratifier,
                                   f"where stays end by {stratifier}"),
        formats=formats,
        flags=flags,
        footnotes=[SHARE_AND_DAYS_FOOTNOTE],
        headers=headers,
    )


def aj_teaser_table(bundle: Bundle, vocab) -> Table:
    """The whole sample as one flat row, for the teaser slide.

    The same block as every stratified AJ table, asked for the one stratifier
    that has a single level, so the teaser's numbers cannot drift from the
    ones the stratified slides show. It carries no flags because a single
    level has no highest and lowest, which `aj_levels_table` already decides.
    """
    return aj_levels_table(bundle, "all", vocab)


def _sole_extreme(values: pd.Series, want_max: bool) -> str | None:
    """The level holding this column's extreme, when exactly ONE level does.

    Stricter than `extreme_levels`, which the per-outcome sentences use, and
    deliberately. Those sentences name every level that shares an extreme and
    print the number beside them, so a reader sees the tie. The sweep says a
    level is the slowest in EVERY outcome type, with no numbers anywhere in it;
    with two levels tied in one outcome that sentence is simply false, and
    nothing on the slide would show it.
    """
    holders = extreme_levels(values, want_max)
    return holders[0] if len(holders) == 1 else None


def _outcome_sweep(per_outcome: dict, label: str) -> str | None:
    """A level that is slowest, or fastest, to EVERY outcome. Usually neither.

    The finding a run of competing-risk slides makes and none of its panels
    shows: a reader looking at one outcome at a time cannot see that the same
    level sits at the same end of all of them. It is also the strongest thing
    the section can say, which is why it leads the stratifier's findings and
    why the test for it is the strict one.

    Silent unless every outcome has a sole holder and it is the same level in
    all of them. An outcome whose levels tie at that end has no sole holder, so
    "every outcome type" cannot be asserted over it; a single outcome is not
    "every" in any useful sense and would only restate the sentence below.
    """
    if len(per_outcome) < 2:
        return None

    ends = []
    for word, want_max in (("slowest", True), ("fastest", False)):
        holders = {_sole_extreme(values, want_max)
                   for values in per_outcome.values()}
        if len(holders) == 1 and None not in holders:
            ends.append(f"{holders.pop()} is the {word} in every outcome type")
    if not ends:
        return None
    return f"By {label}, " + " and ".join(ends) + "."


# How far apart two levels' mean times to an outcome have to be before the gap
# is worth stating as a multiple rather than left as two numbers a reader could
# divide. Doubling is the point at which "somewhat longer" stops describing it.
OUTCOME_SPREAD_MULTIPLE = 2.0

# How many outcomes of a kind a level needs before its mean time to that
# outcome anchors a headline multiple. A mean over ten events is not a mean
# anyone should build a twentyfold claim on, and the smallest levels are
# exactly where the widest ratios come from: on OC2 the widest gap of all is
# _UNKNOWN_'s time to a non-live outcome, over twenty of them.
OUTCOME_SPREAD_MINIMUM_EVENTS = 30


def _outcome_timings(bundle: Bundle, stratifier: str) -> pd.DataFrame | None:
    """Mean time to each outcome, per level, with the thin cells removed.

    The AJ restricted means as a level-by-outcome frame, blanked wherever the
    level had fewer than `OUTCOME_SPREAD_MINIMUM_EVENTS` of that outcome. One
    place, because both spread findings read the same frame along different
    axes and a cell too thin to average is too thin either way.
    """
    if not (bundle.has("strata", stratifier, "aj_restricted_mean")
            and bundle.has("strata", stratifier, "outcomes")):
        return None
    means = bundle.stratum(stratifier, "aj_restricted_mean")
    events = bundle.stratum(stratifier, "outcomes")

    columns = {}
    for code in aj_outcome_codes(bundle, stratifier):
        column, counted = f"aj_restricted_mean_{code}", f"outcome_{code}_events"
        if column not in means.columns or counted not in events.columns:
            continue
        # An outcome a level never saw is written as null, which arrives as
        # None in a column of object dtype. Coerced rather than compared as it
        # comes: every step below assumes numbers, and object-dtype comparison
        # against None is pandas' business rather than something to rely on.
        values = pd.to_numeric(means[column], errors="coerce")
        values = values.where(values > 0)
        enough = events[counted].fillna(0).reindex(values.index).fillna(0)
        columns[code] = values.where(enough >= OUTCOME_SPREAD_MINIMUM_EVENTS)
    if not columns:
        return None
    return pd.DataFrame(columns)


def findings_for_outcome_spread(bundle: Bundle, stratifier: str,
                                label: str, vocab) -> list[str]:
    """Down a column: the outcome whose timing separates the LEVELS most.

    ONE finding per stratifier, naming the outcome with the widest ratio rather
    than one per outcome, because the sentence beside it already names the
    slowest and fastest level of every outcome and three more bullets restating
    those as multiples would be the same slide twice. What this adds is the
    multiple itself, and which outcome carries it.
    """
    timings = _outcome_timings(bundle, stratifier)
    if timings is None or len(timings) < 2:
        return []

    widest = None
    for code in timings.columns:
        values = timings[code].dropna()
        if len(values) < 2:
            continue
        ratio = float(values.max() / values.min())
        if ratio < OUTCOME_SPREAD_MULTIPLE:
            continue
        if widest is None or ratio > widest[0]:
            widest = (ratio, code, values)

    if widest is None:
        return []
    ratio, code, values = widest
    slowest, fastest = values.idxmax(), values.idxmin()
    # Plural rather than "a {outcome} outcome", which would need an article
    # chosen for a label the run supplies: "a other live outcome".
    outcome = vocab.outcome_labels.get(code, code)
    return [f"By {label}, the levels differ most in how long {outcome} "
            f"outcomes take: {slowest} at {values[slowest]:.0f} days against "
            f"{fastest} at {values[fastest]:.0f}, a {ratio:.1f}-fold gap."]


def findings_for_outcome_contrast(bundle: Bundle, stratifier: str,
                                  label: str, vocab) -> list[str]:
    """Across a row: the level whose own OUTCOMES differ most in timing.

    The other axis of the same table, and a different statement. The spread
    finding compares levels against each other on one outcome; this compares
    one level's outcomes against each other, which is what an audience is
    really asking when it wants to know why a level's stays are long. A level
    can leave quickly by one route and slowly by another, and the average over
    its stays hides that completely.

    One finding per stratifier, naming the level with the widest internal gap,
    for the reason the spread finding is one per stratifier: the closing
    section takes a bullet per contribution, and one per level would give a
    seven-level stratifier seven of them.

    Thin cells are blanked before anything is compared (see
    `_outcome_timings`), so a level's widest gap is never anchored on an
    outcome it barely had. On OC2 that is what keeps `_UNKNOWN_` out of it: ten
    other-live outcomes against a hundred and thirty community-live ones would
    otherwise make it the widest gap in the animal groups.
    """
    timings = _outcome_timings(bundle, stratifier)
    if timings is None or len(timings.columns) < 2:
        return []

    widest = None
    for level in timings.index:
        values = timings.loc[level].dropna()
        if len(values) < 2:
            continue
        ratio = float(values.max() / values.min())
        if ratio < OUTCOME_SPREAD_MULTIPLE:
            continue
        if widest is None or ratio > widest[0]:
            widest = (ratio, str(level), values)

    if widest is None:
        return []
    ratio, level, values = widest
    slow, fast = values.idxmax(), values.idxmin()
    slow_label = vocab.outcome_labels.get(slow, slow)
    fast_label = vocab.outcome_labels.get(fast, fast)
    # "Within a single {label}" rather than "a {label} level", which would need
    # an article chosen for a label this cannot see: "a intake type level".
    return [f"Within a single {label} the outcomes differ too, most of all for "
            f"{level}: its {slow_label} outcomes take {values[slow]:.0f} days "
            f"against {values[fast]:.0f} for its {fast_label} ones, "
            f"{ratio:.1f} times as long. An average over {level}'s stays "
            f"describes neither."]


def findings_for_aj(levels: Table, label: str, vocab) -> list[str]:
    """Which levels are slowest and fastest to each outcome.

    Up to two findings. First the sweep, when one level sits at the same end
    of every outcome, because it is the finding no single panel shows and it
    frames the detail that follows. Then one sentence per outcome, gathered
    into a SINGLE finding, because the closing slide takes a bullet per
    contribution and three bullets about one stratifier would crowd out the
    stratifiers either side of it.

    Time again, not share. Where a level's stays end up is the panel above; how
    long they take to get there is the part of the same figure a reader cannot
    measure by eye, and it is what the table was ordered around.

    Judged across every level, including levels the highlights table did not
    show, for the reason the flags are: an extreme is a property of the
    stratifier, not of the rows that fitted on the slide. An outcome whose
    levels all tie says nothing, the same abstention the selectors make, and
    with nothing to say about any outcome there is no finding at all.

    The two ends of an outcome abstain independently, through `extreme_levels`,
    so an outcome with a clear fastest level and a four-way tie for slowest
    reports the fastest and stops. Both ends spell out their unit rather than
    letting the second borrow the first's, because with either end able to go
    missing there is no reliable first to borrow from.
    """
    if len(levels.df) < 2:
        return []

    per_outcome = {column[len("aj_restricted_mean_"):]: levels.df[column].dropna()
                   for column in levels.df.columns
                   if column.startswith("aj_restricted_mean_")}

    parts = []
    for code, values in per_outcome.items():
        ends = []
        for word, want_max in (("slowest", True), ("fastest", False)):
            holders = extreme_levels(values, want_max)
            if holders:
                ends.append(f"{name_levels(holders)} "
                            f"{_agrees(holders, 'is', 'are')} {word} "
                            f"({values[holders[0]]:.1f} days)")
        if not ends:
            continue
        outcome = vocab.outcome_labels.get(code, code)
        parts.append(f"for {outcome} outcomes, " + " and ".join(ends))

    findings = []
    sweep = _outcome_sweep(per_outcome, label)
    if sweep is not None:
        findings.append(sweep)
    if parts:
        sentences = "".join(f". {capitalize_first(part)}" for part in parts[1:])
        findings.append(f"Time to outcome by {label}: {parts[0]}{sentences}.")
    return findings


def stacked_by_measure(table: Table, vocab, highlight: str = "") -> Table:
    """Turn a flat AJ table on its side: outcomes across, measures down.

    From one row per level and a column per outcome per measure, to one column
    per OUTCOME and two rows per level, a share and a mean days. Same numbers,
    same flags, a table that is half as wide and twice as tall.

    That shape is what a split slide wants: the table's width is the figure's
    loss, and this one gives back nearly an inch and a half of it. It says the
    same thing in half the width: the flat arrangement spells the measure out
    once per outcome across six headers, where here the outcome is named once
    at the head of its column and the measure once at the head of its row.

    Flags are RESHAPED, never recomputed. In the flat table each column holds
    one measure, so its extremes compare shares with shares and days with days.
    Recomputing down a column of this table would compare 80.8% against 20.5
    days and mark whichever happened to be larger.

    `highlight` names an outcome to point the reader at, for a slide whose
    figure shows that outcome alone. It travels as the column key, not as a
    mark: the renderer shades that header. A glyph in the header text would sit
    on the same table as the high and low marks and be read as one of them,
    which is the whole problem those marks were changed to avoid.
    """
    codes, measures = [], []
    for column in table.df.columns:
        measure, code = _aj_column_parts(column)
        if code not in codes:
            codes.append(code)
        if measure not in measures:
            measures.append(measure)

    labels = {measure: vocab.metric(measure).text(short=True) for measure in measures}
    rows = [(level, labels[measure])
            for level in table.df.index for measure in measures]
    index = pd.MultiIndex.from_tuples(rows)

    def reshaped(source):
        return pd.DataFrame(
            [[source.loc[level, f"{measure}_{code}"] for code in codes]
             for level in table.df.index for measure in measures],
            index=index, columns=codes)

    return Table(
        df=reshaped(table.df),
        title=table.title,
        formats={},
        flags=None if table.flags is None else reshaped(table.flags),
        footnotes=list(table.footnotes),
        headers={code: code for code in codes},
        highlight=highlight,
        row_formats={labels[measure]: AJ_OUTCOME_FORMATS[measure]
                     for measure in measures},
    )


def aj_highlights_table(bundle: Bundle, stratifier: str, vocab,
                        full: Table | None = None,
                        pinned: Sequence[str] = ()) -> Table:
    """The levels worth showing, chosen by TIME rather than by share.

    Selects on the longest and the shortest mean time to each outcome, so a
    dataset with three outcomes has six selectors and, after the usual
    collisions, fewer rows than that.

    Time selects and share does not, deliberately. The figures above the table
    are cumulative incidence curves, so a level with a remarkable share is
    already the line the eye goes to; how LONG that share takes to accumulate
    is what the reader cannot get off the plot at a glance, and it is what
    picks the rows.
    """
    if full is None:
        full = aj_levels_table(bundle, stratifier, vocab)
    selectors = [(column, want_max)
                 for column in full.df.columns
                 if column.startswith("aj_restricted_mean_")
                 for want_max in (True, False)]
    chosen = selected_levels(full, selectors, AJ_SHOW_ALL_MAX, pinned)
    return _shown(full, chosen, f"where stays end, highlights by {stratifier}",
                  criterion=", by longest and shortest mean days")


# ---------------------------------------------------------------------------
# The two Cox fits, held against each other
# ---------------------------------------------------------------------------

# Hazard ratios sit in a narrow band around 1 and the whole point of the table
# is that two of them are close, so two decimals is the floor: at one, 1.10 and
# 1.12 would print the same and the table would show agreement it had not
# earned. The margin is a percentage of a ratio and blanks on the reference
# level, where no comparison exists to be uncertain about.
HR_FORMAT = Format(2)
# The same ratios on a sheet, at the Cox sheets' three places and for their
# reason: a spreadsheet is where a number is checked rather than taken an
# impression of, and the cell holds full precision whatever this says.
RATIO_SHEET_FORMAT = Format(3)
MARGIN_FORMAT = Format(1, percent=True, blank=True)
# Three places, not two: these p-values sit high, and rounding 0.534 to 0.53
# would be fine while rounding a genuinely small one to 0.00 would not.
P_FORMAT = Format(3, blank=True)

# The two HRs, then the two readings of how they compare, in the order the
# question arises: is there evidence they differ, and how close are they shown
# to be. The p comes first because it is the familiar one and the reader will
# look for it; the margin comes last because it is the one that can conclude.
COX_COMPARISON_COLUMNS = ["hr_pooled", "hr_stratified", "p_difference",
                          "agreement_margin"]

# Short enough for the foot of a slide. The full reading of both columns, and
# the independence caveat they share, are in the speaker notes: a footnote long
# enough to explain an equivalence margin properly is no longer a footnote, and
# a presenter needs the explanation more than the audience does.
COMPARISON_FOOTNOTES = [
    "Diff p: evidence the two differ; large means none was found.",
    "Agreement: how close they are shown to be, at 95% confidence. "
    "Smaller is stronger.",
]


def ratio_panel_table(panel: pd.DataFrame, series, stratifier: str,
                      title: str, footnotes: list[str]) -> Table:
    """One stratifier's levels against the three readings of one ratio.

    Estimates only. Each reading's 95% interval is on the figure beside it,
    where a whisker shows an interval better than two more numeric columns
    would, and nine columns of numbers is a sheet rather than a slide.

    No flags. `flag_extremes` marks a measure's highest and lowest level, which
    would be exactly the wrong emphasis: the reading to take off this table is
    how far the three columns of one ROW sit from each other, and a mark on the
    biggest level of a column invites reading down instead.
    """
    keys = [key for key, _, _ in series]
    df = panel.loc[stratifier, keys].copy()
    return Table(
        df=df,
        title=title,
        formats={key: HR_FORMAT for key in keys},
        headers={key: label for key, label, _ in series},
        footnotes=list(footnotes),
    )


def ratio_panel_full_table(panel: pd.DataFrame, series, title: str) -> Table:
    """Every stratifier, every level, all three readings WITH their intervals.

    The sheet form of what `ratio_panel_table` shows one stratifier and three
    estimate columns of. That one is a view of this: it drops the six interval
    columns, which are on the figure beside it as whiskers, and takes one
    stratifier's rows. Here the whiskers have nowhere to be, and a reader who
    came to a spreadsheet to check whether two readings really part company
    needs the bounds, since two estimates a decimal apart is either a
    disagreement or a rounding difference depending entirely on them.

    This is where the Weibull fits reach a reader in numbers at all. The hazard
    panel is where `hr_weibull_pooled` reaches a reader, and the length-of-stay
    panel is where the two time ratios and the Kaplan-Meier ratio do; the Cox
    sheets carry neither.

    Not a view of the two Cox sheets either, on the hazard side. It puts three
    fits over one index, and two of them are elsewhere, but the third is not,
    and the arrangement that makes the three comparable row by row is the thing
    being written.

    No flags, for `ratio_panel_table`'s reason: the reading is across a row,
    not down a column.
    """
    keys = [key for key, _, _ in series]
    columns = [column for key in keys
               for column in (key, f"{key}_ci_lower", f"{key}_ci_upper")]
    return Table(
        df=panel.reindex(columns=columns).copy(),
        title=title,
        formats={column: RATIO_SHEET_FORMAT for column in columns},
    )


def requires_cox_comparison(comparison: pd.DataFrame, stratifier: str) -> bool:
    """Whether one stratifier has both fits and so has something to compare.

    Asks the comparison frame rather than the bundle, because the condition is
    not "the bundle has a stratified variant" but "that variant produced usable
    rows for this stratifier": a variant whose fit failed is present in the
    bundle and empty here.
    """
    return stratifier in comparable_stratifiers(comparison)


def cox_comparison_table(comparison: pd.DataFrame, stratifier: str) -> Table:
    """One stratifier's levels, both hazard ratios, and the two ways they compare.

    Four columns and no more. The intervals behind each hazard ratio are on the
    figure this table sits beside, where a whisker shows an interval better
    than two more numeric columns would, and the ratio of the two hazard ratios
    is in the frame for whoever wants it but says nothing here that the p-value
    and the margin do not say between them.

    Both comparison columns are shown because they fail differently. The
    p-value is the familiar question, whether there is evidence the two part
    company, and a reader will look for it whether or not it is here; but a
    large one is equally consistent with real agreement and with a level too
    thin to establish anything, and cannot separate them. The margin can. Shown
    alone, either invites the reader to supply the other's meaning.

    No flags. `flag_extremes` marks the highest and lowest level of a measure,
    which is exactly the wrong emphasis here: the largest margin belongs to the
    smallest level and marking it would read as a finding about that level
    rather than about how few stays it has.
    """
    df = comparison.loc[stratifier, COX_COMPARISON_COLUMNS].copy()
    return Table(
        df=df,
        title=f"pooled against stratified Cox, by {stratifier}",
        formats={"hr_pooled": HR_FORMAT,
                 "hr_stratified": HR_FORMAT,
                 "p_difference": P_FORMAT,
                 "agreement_margin": MARGIN_FORMAT},
        footnotes=list(COMPARISON_FOOTNOTES),
    )


# Above this, the interval for the ratio of the two hazard ratios is so wide
# that the level established almost nothing either way, and saying "they agree
# within 25%" without saying why would credit the check with a result it did
# not produce. The threshold is a presentation judgment, not a statistical
# one: there is no margin at which a level stops counting, only one past which
# the sentence has to explain itself.
WIDE_MARGIN = 0.20


def findings_for_cox_comparison(comparison: pd.DataFrame, stratifier: str,
                                   label: str) -> list[str]:
    """What the robustness check found, for the closing section.

    One sentence, phrased around the WIDEST margin rather than a typical one.
    The claim is "every level agrees at least this closely", and the weakest
    level is what that claim rests on; an average would let one badly
    established level hide behind five well established ones.
    """
    margins = comparison.loc[stratifier, "agreement_margin"].dropna()
    if margins.empty:
        return []

    widest = margins.max()
    tight = margins[margins < WIDE_MARGIN]
    if widest < WIDE_MARGIN or tight.empty:
        return [f"The {label} hazard ratios hold when every other split is given "
                f"its own baseline hazard: the two models agree within "
                f"{widest:.0%} at every level."]

    # Some levels are well established and some are not, which is a statement
    # about how many stays they hold, so the sentence separates them rather
    # than reporting the worst case as if it described the check as a whole.
    thin = margins[margins >= WIDE_MARGIN]
    return [f"The {label} hazard ratios hold when every other split is given its "
            f"own baseline hazard, agreeing within {tight.max():.0%} on "
            f"{name_levels(list(tight.index))}. {capitalize_first(name_levels(list(thin.index)))} "
            f"{'hold' if len(thin) > 1 else 'holds'} too few stays to establish "
            f"more than {widest:.0%}."]


# How the regression frames are written out in the workbook. More decimals
# than the slide's, because a sheet is where a reader goes to check a number
# rather than to take an impression of it, and the cell holds full precision
# either way; these only decide what shows without widening a column.
COX_SHEET_FORMATS: dict[str, Format] = {
    "hr": Format(3),
    "hr_ci_lower": Format(3),
    "hr_ci_upper": Format(3),
    "p_value": Format(4),
    "hr_pooled": Format(3),
    "hr_pooled_ci_lower": Format(3),
    "hr_pooled_ci_upper": Format(3),
    "hr_stratified": Format(3),
    "hr_stratified_ci_lower": Format(3),
    "hr_stratified_ci_upper": Format(3),
    "hr_ratio": Format(4),
    "hr_ratio_ci_lower": Format(4),
    "hr_ratio_ci_upper": Format(4),
    "p_difference": Format(4, blank=True),
    "agreement_margin": Format(1, percent=True, blank=True),
}


def cox_fit_table(frame: pd.DataFrame, title: str) -> Table:
    """One Cox regression's hazard ratios, every column, for the workbook.

    Takes a `regression.pooled` or `regression.stratified` frame as it stands:
    both carry the same four columns and the same (stratifier, level) index, so
    one function serves both and the two sheets cannot come out shaped
    differently.

    Every level of every stratifier, reference rows included, in contrast with
    the slide tables, which show what fits. A sheet has room, and a reference
    row omitted from a spreadsheet is the row a reader needs to see to know
    what the others are ratios OF.
    """
    return Table(df=frame.copy(), title=title, formats=dict(COX_SHEET_FORMATS))


def cox_full_comparison_table(comparison: pd.DataFrame) -> Table:
    """Both fits and both comparisons, every column, for the workbook.

    The wide form of what `cox_comparison_table` shows four columns of. That
    one is a view of this and is not written to the workbook; this one is not a
    view of the two fit sheets, because the ratio, its interval, the p-value
    and the margin exist in neither of them.
    """
    return Table(df=comparison.copy(), title="pooled against stratified Cox",
                 formats=dict(COX_SHEET_FORMATS),
                 footnotes=list(COMPARISON_FOOTNOTES))
