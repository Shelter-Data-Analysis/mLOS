"""Display names for the machine vocabulary of the mLOS results bundle.

The analysis vocabulary is deliberately uniform and machine-shaped: lowercase
snake_case, the same spelling in the bundle, the workbook, and the CSVs, so a
value can be looked up by name anywhere it appears. That is the right choice
for the analysis and the wrong one for a slide. This module is the single place
where `km_median_los` becomes "median LOS", and it lives here rather than in
the R writers so the machine names stay machine names everywhere upstream.

Three conventions, and each has a reason.

Labels begin lowercase ("mean daily intakes", not "Mean daily intakes") because
a label is as likely to land mid-sentence in a bullet as at the head of a
column. Renderers that need a capital call `capitalize_first`, which is not
`str.capitalize`: that method lowercases everything after the first character
and would turn "median LOS" into "Median los".

Acronyms the reader is assumed to know stay capitalized and unexpanded: CI, KM,
AJ, Cox, LOS. Spelling out length of stay in every column header doubles the
width of a table to tell the reader something they knew. Acronyms the reader
may NOT know carry a `plain` alternative, which the low-mathematics profile
will select once profiles exist; RMST is the motivating case. Nothing passes
`plain=True` yet, so those entries are written and unused on purpose rather
than by oversight.

Entries carry a `short` for narrow table columns and a `unit` kept separate
from the label, so a renderer can print units once per header instead of in
every cell. Most entries fill only `label`; the other fields exist from the
start because retrofitting them means rewriting every entry.

A `short` must stand on its own. The first draft assumed the table title
would supply the context, so `km_median_los` was just "median" -- which was
fine until a table put it beside the resident-tenure median and the two
columns both read "median". A table that spans the arriving-cohort and
resident views cannot lend context it does not have.

Resolution is by explicit table first, with three structural rules underneath,
and a token-based fallback last. The fallback is a safety net, not a strategy:
it guarantees no raw snake_case ever reaches a slide, including names added to
the bundle after this table was last touched, and it records every name it had
to handle so `report_fallbacks` can list what is waiting to be curated.
"""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Acronyms that survive the fallback tokenizer intact. Anything not listed
# gets ordinary lowercase treatment.
ACRONYMS = {
    "aj": "AJ",
    "ci": "CI",
    "cif": "CIF",
    "cox": "Cox",
    "df": "df",
    "hr": "HR",
    "km": "KM",
    "los": "LOS",
    "p90": "P90",
    "rmst": "RMST",
    "rmtl": "RMTL",
    "se": "SE",
}


@dataclass(frozen=True)
class Name:
    """One display name. Only `label` is required."""

    label: str
    short: str | None = None
    unit: str | None = None
    plain: str | None = None

    def text(self, *, plain: bool = False, short: bool = False) -> str:
        """The label to print, honouring the profile's register and width.

        `plain` selects the low-mathematics wording where one exists; `short`
        selects the narrow-column form. Both fall back to `label`, so a caller
        never has to check which fields an entry happens to fill.
        """
        if plain and self.plain:
            return self.plain
        if short and self.short:
            return self.short
        return self.label


def capitalize_first(text: str) -> str:
    """Capitalize the first character and touch nothing else.

    `str.capitalize` lowercases the remainder, which destroys every acronym in
    this module. This is the only capitalization renderers should use.
    """
    return text[:1].upper() + text[1:] if text else text


# ---------------------------------------------------------------------------
# Metric names
# ---------------------------------------------------------------------------

# Stratum-table rows, unified-node scalars, and the columns of the regression
# and AJ tables. Grouped the way the workbook groups them so a missing entry is
# easy to spot against the sheet it came from.
METRICS: dict[str, Name] = {
    # -- observation counts -------------------------------------------------
    "duration_days": Name("observation window", "window", "days"),
    "total_observations": Name("stays observed", "stays"),
    "events": Name("completed stays", "completed"),
    "censored": Name("censored stays", "censored"),
    "left_truncated": Name("left-truncated stays", "left-truncated"),
    "right_censored": Name("right-censored stays", "right-censored"),
    # "Exceeded cap" rather than "still in care at the stay cap", which is what
    # this said and is a longer way of saying the same thing: a stay counted
    # here ran past the cap, which is why its recorded duration was truncated
    # to it. The fitted figure below keeps the fuller wording, because it is a
    # different quantity and the two appear on different slides.
    "capped_at_restricted_stay_cap": Name("exceeded cap", "at cap"),
    "mean_days_at_risk": Name("mean days at risk", "days at risk", "days"),
    "total_animal_days": Name("total animal-days", "animal-days", "animal-days"),
    "n_animals": Name("distinct animals", "animals"),
    "total_intakes": Name("intakes"),
    "total_outcomes": Name("outcomes"),
    "mean_daily_intakes": Name("mean daily intakes", "intakes/day", "per day"),
    "mean_daily_outcomes": Name("mean daily outcomes", "outcomes/day", "per day"),
    "fraction_capped": Name("fraction that exceeded the cap", "at cap", "fraction"),
    # -- outcome counts and mix --------------------------------------------
    "completed_outcomes_total": Name("completed outcomes", "outcomes"),
    "incidence_overall_per_100_animal_days": Name(
        "overall exit rate", "exit rate", "per 100 animal-days"
    ),
    # -- Kaplan-Meier, the intake-cohort view -------------------------------
    "km_median_los": Name("median LOS", "median LOS", "days"),
    "km_p90_los": Name("90th percentile LOS", "P90 LOS", "days"),
    "km_restricted_mean": Name(
        "restricted mean LOS", "mean LOS", "days", plain="average LOS within the stay cap"
    ),
    "km_restricted_mean_ratio": Name(
        "restricted mean LOS against the reference level", "LOS ratio (KM)",
        "times", plain="how many times as long this level's average stay is"
    ),
    "km_still_in_care_at_cap": Name(
        "fitted fraction still in care at the stay cap", "at cap (fitted)",
        "fraction"
    ),
    "km_past_days_per_intake": Name(
        "elapsed animal-days per intake", "elapsed/intake", "days"
    ),
    "km_future_days_per_intake": Name(
        "future animal-days per intake", "future/intake", "days"
    ),
    "max_time": Name("longest observed stay", "longest", "days"),
    "restricted_stay_cap": Name("stay cap", "cap", "days"),
    "study_start": Name("study start"),
    "study_end": Name("study end"),
    # -- census aggregates, the resident view -------------------------------
    "mean_census_inventory": Name("mean census", "census", "animals"),
    "total_in_care_days_sum": Name("total in-care days accrued", "in-care days", "days"),
    "daily_mean_total_in_care_days": Name(
        "mean in-care days accrued per night", "in-care days/night", "days"
    ),
    "expected_census": Name("expected census", "expected census", "animals"),
    "expected_past_animal_days": Name(
        "expected elapsed animal-days", "animal-days", "animal-days"
    ),
    "expected_future_animal_days": Name(
        "expected future animal-days", "future", "animal-days"
    ),
    "per_resident_in_care_days": Name(
        "observed tenure per resident", "observed tenure", "days"
    ),
    "per_resident_past_days": Name("mean tenure per resident", "mean tenure", "days"),
    "per_resident_future_days": Name(
        "expected remaining stay per resident", "remaining", "days"
    ),
    "per_resident_past_days_restricted_median": Name(
        "median tenure per resident", "median tenure", "days"
    ),
    "per_resident_past_days_restricted_p90": Name(
        "90th percentile tenure per resident", "P90 tenure", "days"
    ),
    # The remaining-LOS curve read at each of the three tenures above. Every
    # label begins "at", because the whole point of these three is the tenure
    # they are read AT: drop the preposition and "mean remaining stay" is what
    # a reader takes away, which is per_resident_future_days and a different
    # number. The short forms keep it for the same reason, and lean on the
    # tenure columns beside them for the rest.
    "remaining_days_at_mean_tenure": Name(
        "remaining stay at mean tenure", "at mean tenure", "days",
        plain="days still to come for an animal of average tenure"
    ),
    "remaining_days_at_median_tenure": Name(
        "remaining stay at median tenure", "at median tenure", "days",
        plain="days still to come for the middle animal in care"
    ),
    "remaining_days_at_p90_tenure": Name(
        "remaining stay at P90 tenure", "at P90 tenure", "days",
        plain="days still to come for a long-staying animal in care"
    ),
    # -- Aalen-Johansen -----------------------------------------------------
    "aj_rmst_stay": Name(
        "RMST", "RMST", "days", plain="restricted mean stay within the cap"
    ),
    "aj_analysis_window_days": Name("AJ analysis window", "window", "days"),
    # Stems, used as column keys where a table puts the outcome in the row
    # instead of in the measure name.
    "aj_final_cif": Name("share of stays", "share", "fraction"),
    # `short` is bare "days" because it heads a row in a table whose other row
    # says "share": the mean is what the footnote is for, and the column beside
    # it is paying for every character this label spends.
    "aj_restricted_mean": Name(
        "mean days to this outcome", "days", "days",
        plain="average days it takes, among stays that end this way"
    ),
    # -- regression and AJ table columns ------------------------------------
    "variable": Name("term"),
    "hr": Name("hazard ratio", "HR"),
    # The two Cox fits held against each other, and how close they are shown to
    # be. "pooled" and "stratified" are the words the methods document uses for
    # them, so a reader who goes looking finds the same pair of names there.
    "hr_pooled": Name("hazard ratio, pooled Cox", "pooled HR",
                      plain="hazard ratio from the main model"),
    "hr_stratified": Name("hazard ratio, stratified Cox", "stratified HR",
                          plain="hazard ratio with the other splits given their own baselines"),
    "hr_ratio": Name("ratio of the two hazard ratios", "HR ratio"),
    # Not "p-value": the bare word would let a reader take it for the hazard
    # ratio's own p-value, which is in the same table's neighborhood and
    # answers an entirely different question. The name says what is being
    # tested for a difference.
    # "diff p" and not "p diff" so that the p is never the first character: a
    # renderer capitalises a header's first letter, and p is the symbol rather
    # than a word. Ordering the short around that is what lets this name go
    # through the vocabulary like every other one, instead of needing a table
    # to spell its own header and putting the case of a p beyond the reach of
    # the one place names are decided.
    "p_difference": Name("p-value for a difference between the two", "diff p",
                         plain="evidence the two models disagree"),
    # The label is phrased as the reading, since the cell says 8% and "agree
    # within" is what turns that into a sentence. The short drops the phrasing
    # and names the quantity, because a column header sits above six cells and
    # a header that completes each of their sentences reads as an instruction
    # by the third row.
    "agreement_margin": Name("the two agree within", "agreement",
                             plain="how close the two models are shown to be"),
    "los_ratio": Name("LOS ratio", "ratio"),
    # The six readings the two ratio panels lay side by side. A panel puts three
    # estimates of ONE quantity in three columns, so each name has to say which
    # fit it came from and what that fit assumed; the slide overrides these with
    # the two-word series labels, which lean on the column beside them, and the
    # sheet cannot, since it heads nine columns at once.
    #
    # The Weibull pair is one estimate under two link functions, HR being the
    # time ratio to the power of minus the fitted shape. The labels say pooled
    # Weibull on both sides so a reader meeting them on two sheets can see that,
    # rather than taking them for two fits that happened to agree.
    "hr_cox_pooled": Name("hazard ratio, pooled Cox", "Cox pooled",
                          plain="hazard ratio with every dimension in one model"),
    "hr_cox_stratified": Name("hazard ratio, stratified Cox", "Cox stratified",
                              plain="hazard ratio with the other dimensions given "
                                    "their own baselines"),
    "hr_weibull_pooled": Name("hazard ratio, pooled Weibull", "Weibull pooled",
                              plain="hazard ratio from the same model with a "
                                    "Weibull baseline imposed"),
    "los_weibull_pooled": Name("LOS ratio, pooled Weibull", "Weibull pooled",
                               plain="times as long, adjusted, under one shape"),
    "los_weibull_stratified": Name("LOS ratio, freed-shape Weibull",
                                   "Weibull freed shape",
                                   plain="times as long, adjusted, with the other "
                                         "dimensions' shapes free"),
    "los_km_ratio": Name("LOS ratio, unadjusted Kaplan-Meier", "KM unadjusted",
                         plain="times as long by each level's own curve, "
                               "adjusted for nothing"),
    "p_value": Name("p-value", "p"),
    "test": Name("test"),
    "statistic": Name("statistic", "stat"),
    "df": Name("degrees of freedom", "df"),
    "state": Name("outcome"),
    "rmean": Name("restricted mean", "mean", "days"),
    # -- unified stay counts ------------------------------------------------
    "period_label": Name("period"),
    "total_stays": Name("stays"),
    "left_truncated_stays": Name("left-truncated stays", "left-truncated"),
    "right_censored_stays": Name("right-censored stays", "right-censored"),
}

# The unified node spells several quantities differently from the stratum
# tables that hold the same measure: it drops the `km_` prefix, which the
# stratum rows carry to separate the fitted figures from the observed counts
# beside them. Aliasing rather than duplicating keeps one wording per concept,
# so a slide comparing the whole sample against its strata cannot label the two
# halves inconsistently.
ALIASES: dict[str, str] = {
    "n_total": "total_observations",
    "n_events": "events",
    "n_censored": "censored",
    "n_capped": "capped_at_restricted_stay_cap",
    "median_los": "km_median_los",
    "still_in_care_at_cap": "km_still_in_care_at_cap",
    "percentile_90": "km_p90_los",
    "restricted_mean": "km_restricted_mean",
}


# ---------------------------------------------------------------------------
# Figure kinds and stratifiers
# ---------------------------------------------------------------------------

# The `kind` field of the outputs manifest. These name a figure, so they read
# as titles rather than as measures, and they double as the filename stem, so
# `km_in_care_tenure` is also `km_in_care_tenure_by_period.png`.
KINDS: dict[str, Name] = {
    "km_survival": Name("Kaplan-Meier survival curve", "survival curve"),
    "km_remaining_los": Name("remaining LOS by tenure", "remaining LOS"),
    "km_census_by_tenure": Name("census by tenure", "census profile"),
    "km_in_care_tenure": Name("in-care tenure profile", "tenure profile"),
    "aj_cif": Name("cumulative incidence", "incidence"),
    "aj_conditional": Name("conditional outcome mix by day", "outcome mix"),
    "aj_mass": Name("probability mass by interval", "exit timing"),
}

# Stratifier ids, which appear inside titles ("LOS by animal group") rather
# than standing alone, so they stay lowercase even by title conventions.
STRATIFIERS: dict[str, Name] = {
    "period": Name("period"),
    "intake": Name("intake type"),
    "group": Name("animal group"),
    "all": Name("whole sample", "all"),
}


# ---------------------------------------------------------------------------
# Structural rules
# ---------------------------------------------------------------------------

# An estimate's interval bounds and standard error are a role attached to a
# base measure, not measures of their own. Parsing them out rather than naming
# every `_ci_lower`, `_ci_upper` and `_se` spelling is what keeps METRICS to
# roughly half the machine names a bundle carries, and it hands the renderer
# what it actually wants: one header over three numeric columns.
ROLE_SUFFIXES = {
    "_ci_lower": "ci_lower",
    "_ci_upper": "ci_upper",
    "_se": "se",
}

ROLE_LABELS = {
    "ci_lower": "lower 95% CI",
    "ci_upper": "upper 95% CI",
    "se": "standard error",
}

ROLE_SHORT = {"ci_lower": "lower", "ci_upper": "upper", "se": "SE"}

# Measures that exist once per competing-risk outcome. The code in the slot is
# resolved against the bundle's own `palette.outcome_labels`, which is user
# configuration and so genuinely belongs in the JSON, unlike the fixed metric
# vocabulary this module translates.
#
# The labels arrive lowercase ("community live"), which .outcome_label in
# mlos_common.R now guarantees precisely so this module does not have to
# choose between breaking the lowercase-initial rule and rewriting text it did
# not author. The templates still keep the slot out of first position, because
# "share of outcomes that are community live" reads better than the same words
# reversed. Short forms keep the bare code, which ties a narrow column back to
# the plot legend.
OUTCOME_TEMPLATES = [
    (
        re.compile(r"^outcome_(\w+)_events$"),
        "outcomes recorded as {outcome}",
        "{code} outcomes",
    ),
    (
        re.compile(r"^outcome_mix_(\w+)$"),
        "share of outcomes that are {outcome}",
        "{code} share",
    ),
    (
        re.compile(r"^incidence_(\w+)_per_100_animal_days$"),
        "exit rate to {outcome}",
        "{code} rate",
    ),
    (
        re.compile(r"^aj_final_cif_(\w+)$"),
        "cumulative incidence of {outcome} at the cap",
        "{code} CIF",
    ),
    (
        re.compile(r"^aj_restricted_mean_(\w+)$"),
        "restricted mean time to {outcome}",
        "{code} RMT",
    ),
    (re.compile(r"^aj_rmtl_(\w+)$"), "RMTL for {outcome}", "{code} RMTL"),
]

# Units for the outcome-templated measures, keyed by the template's index.
OUTCOME_UNITS = [None, "fraction", "per 100 animal-days", "probability", "days", "days"]


def _tokenize(name: str) -> str:
    """Last-resort rendering: split on underscores and expand known acronyms.

    Deliberately dumb. Its job is to keep a raw `snake_case` string off a slide
    when the table has no entry, not to produce good wording; a name that
    reaches this path should be promoted into METRICS once anyone cares about
    how it reads.
    """
    words = [ACRONYMS.get(tok, tok) for tok in name.split("_")]
    return " ".join(words).replace("in care", "in-care")


class Vocabulary:
    """Resolves machine names to display names for one results bundle.

    Holds the bundle's outcome labels, which are configuration rather than
    fixed vocabulary, and records every name that fell through to the
    tokenizer so a build can report what still needs curating.
    """

    def __init__(self, bundle: dict | None = None):
        self.outcome_labels: dict[str, str] = {}
        if bundle:
            palette = bundle.get("palette", {}).get("outcome_labels", {})
            names = palette.get("names", [])
            values = palette.get("values", [])
            # The configured label repeats the code as a prefix ("L Community
            # live") so the workbook legend ties to the plot colors. Prose
            # wants the words alone; a renderer that needs the code has the
            # key.
            for code, label in zip(names, values):
                self.outcome_labels[code] = re.sub(rf"^{re.escape(code)}\s+", "", label)
        # "Any" is the pooled pseudo-outcome; it is not in the configured
        # labels because it is not a state the data can record.
        self.outcome_labels.setdefault("Any", "any outcome")
        self._fallbacks: set[str] = set()

    # -- lookup -------------------------------------------------------------

    def metric(self, name: str) -> Name:
        """The display name for a metric, including CI/SE and outcome forms."""
        base, role = self.split_role(name)
        entry = self._base_metric(base)
        if role is None:
            return entry
        return Name(
            label=f"{entry.label}, {ROLE_LABELS[role]}",
            short=ROLE_SHORT[role],
            unit=entry.unit,
            plain=f"{entry.plain}, {ROLE_LABELS[role]}" if entry.plain else None,
        )

    def kind(self, name: str) -> Name:
        return self._lookup(KINDS, name)

    def stratifier(self, name: str) -> Name:
        return self._lookup(STRATIFIERS, name)

    def split_role(self, name: str) -> tuple[str, str | None]:
        """Split a name into its base measure and its CI/SE role, if any."""
        for suffix, role in ROLE_SUFFIXES.items():
            if name.endswith(suffix):
                return name[: -len(suffix)], role
        return name, None

    # -- internals ----------------------------------------------------------

    def _base_metric(self, base: str) -> Name:
        canonical = ALIASES.get(base, base)
        if canonical in METRICS:
            return METRICS[canonical]
        templated = self._outcome_metric(canonical)
        if templated is not None:
            return templated
        self._fallbacks.add(base)
        return Name(_tokenize(base))

    def _outcome_metric(self, name: str) -> Name | None:
        for index, (pattern, label, short) in enumerate(OUTCOME_TEMPLATES):
            match = pattern.match(name)
            if not match:
                continue
            code = match.group(1)
            if code not in self.outcome_labels:
                continue
            return Name(
                label=label.format(outcome=self.outcome_labels[code]),
                short=short.format(code=code),
                unit=OUTCOME_UNITS[index],
            )
        return None

    def _lookup(self, table: dict[str, Name], name: str) -> Name:
        if name in table:
            return table[name]
        self._fallbacks.add(name)
        return Name(_tokenize(name))

    # -- reporting ----------------------------------------------------------

    @property
    def fallbacks(self) -> list[str]:
        """Names rendered by the tokenizer, sorted; the curation to-do list."""
        return sorted(self._fallbacks)


# ---------------------------------------------------------------------------
# Coverage check
# ---------------------------------------------------------------------------


def bundle_names(bundle: dict) -> dict[str, set[str]]:
    """Every machine name a renderer could ask this bundle about.

    The measure names are the rows of the `matrix` nodes and the unified
    node's scalars, which between them are what a block reads by name. The
    `table` nodes' columns are deliberately not swept: they are record fields
    rather than measures, and most of them (the attrition steps, the per-day
    CIF grids, the gap boundaries) are never printed anywhere. Sweeping them
    would put four dozen names that will never be curated onto a report whose
    whole use is that an entry on it means something.
    """
    metrics: set[str] = set()
    kinds: set[str] = set()

    def walk(node):
        if isinstance(node, dict):
            if node.get("type") == "matrix":
                metrics.update(node.get("rows", []))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(bundle)
    metrics.update(k for k in bundle.get("unified", {}) if k != "gaps")
    kinds.update(entry["kind"] for entry in bundle.get("outputs", []))
    # Keep only names shaped like machine vocabulary: underscore-joined tokens,
    # each either lowercase snake_case or an outcome code, which is user
    # configuration and uppercase-initial (L, T, N, Any). A stricter
    # all-lowercase filter used to drop every per-outcome measure from the
    # sweep, so a per-outcome family added without a template would have
    # rendered by tokenizer on slides without ever reaching the
    # awaiting-curation list this sweep exists to feed.
    token = r"(?:[a-z0-9]+|[A-Z][A-Za-z0-9]*)"
    name_shape = re.compile(rf"{token}(?:_{token})*")
    return {
        "metrics": {n for n in metrics if name_shape.fullmatch(n)},
        "kinds": kinds,
        "stratifiers": set(bundle.get("strata", {}).keys()),
    }


def report_fallbacks(bundle: dict) -> tuple[Vocabulary, list[str], dict[str, set[str]]]:
    """Resolve every name in the bundle and return what needed the tokenizer.

    Also returns the names that were checked, from `bundle_names`, so a caller
    reporting coverage counts does not walk the bundle a second time.
    """
    vocab = Vocabulary(bundle)
    found = bundle_names(bundle)
    for name in sorted(found["metrics"]):
        vocab.metric(name)
    for name in sorted(found["kinds"]):
        vocab.kind(name)
    for name in sorted(found["stratifiers"]):
        vocab.stratifier(name)
    return vocab, vocab.fallbacks, found


def main(argv: list[str]) -> int:
    path = Path(argv[1] if len(argv) > 1 else "results/results.json")
    if not path.exists():
        print(f"No results bundle at {path}", file=sys.stderr)
        return 1
    bundle = json.loads(path.read_text())
    vocab, fallbacks, found = report_fallbacks(bundle)
    total = sum(len(v) for v in found.values())
    print(f"{path}: {total} names ({len(found['metrics'])} metrics, "
          f"{len(found['kinds'])} kinds, {len(found['stratifiers'])} stratifiers)")
    print(f"covered by table: {total - len(fallbacks)}    by fallback: {len(fallbacks)}")
    if fallbacks:
        print("\nawaiting curation:")
        for name in fallbacks:
            print(f"  {name:52s} -> {vocab.metric(name).label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
