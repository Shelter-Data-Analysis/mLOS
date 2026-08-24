# Changelog

What changed between releases, and whether the change moves a number.

Two rules govern entries here.

**Say whether output moved.** A release either changes what a run computes or
it does not, and a reader deciding whether to rerun needs that in the first
line of the section, not inferred from the bullets. A documentation-only
release says so and says that output is byte-identical to the release before.

**The section heading stays `Unreleased` until the tag exists.** The version
number in `CITATION.cff` and `MLOS_VERSION` moves when the work of a release is
done; the heading here moves when the tag is cut. Naming a version in this file
before it is tagged claims an artifact nobody can fetch.

---

## Unreleased

The first release. There is no earlier version to compare against, so this
section describes what 0.1.0 is rather than what moved.

### The analysis

Kaplan-Meier survival, restricted mean length of stay, and median stay, overall
and stratified by period, intake type, or animal group. Cox proportional-hazards
regression with a Weibull shape reading. Aalen-Johansen competing-risks
estimates for the three canonical outcomes. In-care tenure and remaining-stay
curves for the residents present at a moment. Every estimate carries a
confidence interval.

### The outputs

A consolidated Excel workbook, a plot set with the numerical values of each
curve in an identically-named CSV beside it, `results.json` holding every
computed number, a console log, and `data_preparation_stats.csv`, which records
how the input rows were transformed, removed, or kept in the same column layout
as the statistics table ShelterDataPrep writes, so the two stack into one flow
from the raw extract to the rows the models ran on.

The workbook can be rebuilt from a saved `results.json` without repeating the
analysis.

### Release metadata

- `MLOS_VERSION` in `mlos_common.R` is the version of the whole repository, R
  side and Python side alike, because one tag produces one archive with one
  DOI. It is reported in the console log header, in `results.json` under `run`,
  and on the Excel cover sheet. The test suite holds it equal to the version in
  `CITATION.cff` and in `pyproject.toml`.
- `CITATION.cff` names the two data deposits and the preparation tool this
  analysis sits downstream of. It carries no `doi:` field yet, because a
  concept DOI does not exist until a release is archived.
- `PUBLISHING.md` is the runbook for the release itself.

### Experimental

`mlos_review/`, the Python deck builder, ships as experimental and may stay
that way. It reads `results.json` and redoes none of the statistics. Its
caveats are in `README.md` and in full in `presentation_guide.md`.
