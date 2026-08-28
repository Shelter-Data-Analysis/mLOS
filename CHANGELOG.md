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

## 0.1.2 (2026-08-28)

Deck workbook correction, and a documentation pass on terminology. **No
analysis number changed**: the R analysis sources are untouched, and every
value a run computes is identical. What moved is the
`Workload_By_Stratum` sheet of the deck builder's workbook, which now carries
three columns it had been dropping and heads its share columns unambiguously,
and the wording of the three guides.

- The workbook's column order was derived from the three workload slides'
  sections, so a column no slide had room for was dropped from the sheet as
  well, against what `workload_full_table` documents. Three went that way:
  `Intakes/day`, the share of the fitted census, and the share of the days
  owed. All three are now present, from a workbook order of its own
  (`WORKLOAD_WORKBOOK_ORDER`).
- Losing `Intakes/day` left the intake share sitting beside `Days given, whole
  window`, headed only `Pct`, where it read as a share of those days. It is not:
  it is the share of intakes, and for the large dogs of **OC2** the two differ
  by nearly a factor of two, 38.4% against 69.7%. The value was always correct;
  the header and its neighbor were not.
- The four share headers now name what they divide (`Intakes, pct`,
  `Census counted, pct`, `Census fitted, pct`, `Days owed, pct`) instead of a
  bare `Pct` or `Share`, so a share does not depend on its neighbor to be read.

Slides are unaffected: they use their own header map and their own column
sections, neither of which changed. Anyone who read a share out of the deposited
deck workbook should recheck it against the corrected column.

Documentation, in the same window:

- **One name for the fit that carries every factor at once.** It had answered to
  "general Weibull", "main Cox" and "unified Cox" depending on the page, while
  `pooled` was separately naming four different things. Four words are now
  reserved, each already matching an identifier so no code was renamed:
  `unified` for the whole sample, `pooled` for the all-factor fully adjusted
  fit, `crude` for that fit with covariate terms dropped, `all-cause` for every
  outcome type together, plus `marginal` for a curve `unified` would overstate.
  27 sites across the four guides. Recorded in `documentation_rules.md` §5.
- **A contradiction fixed.** The user guide said the per-predictor stratified
  Cox fits were "in `results.json` but on no worksheet", and forty lines later
  said the workbook shows their hazard ratios. The second is right, and
  `mlos_excel_export.R` writes them.
- **Section 6 of the math methods document retitled** to "Regressions on the
  Three Factors", which is what it holds, with a roadmap paragraph saying why
  the stratified Cox sits after the Weibull rather than beside the other Cox
  material. No section renumbered.
- **`PUBLISHING.md` gained "Decisions, deferred"**, listing terminology and
  results-JSON names worth changing later, and saying plainly that nothing in
  it is a commitment.

---

## 0.1.1 (2026-08-24)

Documentation. **No number changed**: the analysis sources are untouched apart
from the version string, and every value a run computes is identical to 0.1.0.
The version moves because what a citation points at has changed.

Output is not byte-identical, because a run records which version made it.
Measured against the deposited 0.1.0 run rather than assumed: all 37 curve
CSVs are identical, and `results.json` is identical except for the
`mlos_version` line. The version string also appears in the console log header
and on the Excel cover sheet. So the deposit stays valid and stays pinned at
0.1.0, and rerunning under 0.1.1 reproduces its numbers exactly.

### Added

- mLOS has a DOI: [10.5281/zenodo.22083814](https://doi.org/10.5281/zenodo.22083814),
  the concept DOI, which resolves to the newest release. It is in
  `CITATION.cff`, so the rendered citation now carries it.
- What the shipped OC2 settings produce is deposited at
  [10.5281/zenodo.22084231](https://doi.org/10.5281/zenodo.22084231), CC BY 4.0,
  and is a `references` entry: cite it instead of the prepared input if you
  used those results as they are rather than recomputing them.
- The slide deck built from that run is deposited at
  [10.5281/zenodo.22085157](https://doi.org/10.5281/zenodo.22085157), CC BY 4.0.
  `README.md` and `presentation_guide.md` name it. `CITATION.cff` does not: the
  deck builder is experimental, the results deposit is the record, and a
  citation file should not point a reader at the rendering instead.

### Changed

- `README.md`'s citing section names the three deposits and says which to cite
  when, rather than saying no DOI exists yet.
- The deposit each record names as its parent is its direct one. The results
  deposit is derived from the prepared input rather than from the raw extract,
  because mLOS never reads the raw extract, and the ancestry stays walkable
  because the prepared deposit points at the raw one itself.

## 0.1.0 (2026-08-24)

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
- The two data deposits this analysis reads are cited by their version DOIs,
  `10.5281/zenodo.22051091` for the raw extract and `10.5281/zenodo.22051368`
  for the prepared files, rather than by the concept DOIs that follow the
  newest version. A run log pins its source by digest, so only a version
  record is guaranteed to still hold those bytes.

### Experimental

`mlos_review/`, the Python deck builder, ships as experimental and may stay
that way. It reads `results.json` and redoes none of the statistics. Its
caveats are in `README.md` and in full in `presentation_guide.md`.
