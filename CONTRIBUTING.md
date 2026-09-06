# Contributing

Everything happens in the open, on the
[issue tracker](https://github.com/Shelter-Data-Analysis/mLOS/issues).

## If you have run mLOS on a shelter

This is the contribution the project most wants, and it has two halves.

**Deposit the run** in a data repository that mints a persistent identifier:
Figshare, Zenodo, Dryad, or an institutional repository. Four things travel
together.

1. **The prepared CSV**, as mLOS read it.
2. **The YAML settings file** that produced the run.
3. **The results**: the Excel workbook, `results.json`, the plots with their
   companion CSVs, `analysis_log.txt`, and `data_preparation_stats.csv`.
4. **The report written from them**, in whatever form it took: a memo, a board
   presentation, a slide deck, a paper.

Then **cite mLOS by its DOI, naming the version actually used**, rather than by
a link to the repository. A GitHub URL is not archival: the repository can be
rewritten or deleted, and "the GitHub repository" and a named version are
different claims, of which only the second is checkable.
[10.5281/zenodo.22083814](https://doi.org/10.5281/zenodo.22083814) is the DOI,
and the console log, the `run` block of `results.json`, and the Excel cover
sheet each report the version to name it with.

Where the extract is not yours to release, deposit the settings and the results
without it, and say which file is withheld and why. What is lost is
recomputation; the workbook, the plots, and the two statistics records still
stand on their own.

**Then say how it went**, in an issue linking the deposit: what was most
useful, what was least useful or actively misleading, and what analysis or
feature was missing. Say how many stays over what span, and which version,
since that is what makes the other three interpretable. An issue rather than a
section of the deposit, because an issue can be answered and closed against a
release that acts on it.

## If you have found a bug

Open an issue with the settings file, `analysis_log.txt`, and
`data_preparation_stats.csv`. Those three usually locate a bug without the
data, which is just as well, since the data is generally not yours to send.
Name the mLOS and R versions, and say what the expected result was. If it also
happens on the shipped Orange County data, which is what a bare `Rscript
mlos_run_complete.R` runs, say so: that makes it a test fixture.

## If you need help

Questions about reading an output, choosing settings, or whether a method suits
a particular shelter's data are welcome as issues. There is no private support
channel; answers are public so the next person with the question finds one.
[`mlos_user_guide.md`](mlos_user_guide.md) opens with a section for
practitioners that assumes no statistics background, and
[`mlos_math_methods.md`](mlos_math_methods.md) holds every estimator and
convention.

## If you want to change the code

Pull requests go to `main`, one change to a pull request.

- Read [`documentation_rules.md`](documentation_rules.md) before editing any of
  the guides, and [`tests/README_TESTS.md`](tests/README_TESTS.md) before
  changing code that moves a number: the suite compares against committed
  golden outputs, and a change that moves one is reviewed by reading that diff.
- `Rscript tests/run_tests.R --generate-outputs` passes before a pull request
  is opened, and `python3 tests/run_review_tests.py` too if the change touches
  `mlos_review/`.
- Every claim the guides make about a worked example is marked with the run it
  came from, OC1 or OC2, and `python3 tests/show_guide_examples.py` recomputes
  them from a real run. A change that moves a quoted figure updates the guide
  and that checker together.

For a new estimator or a change in statistical convention, open an issue first:
`mlos_math_methods.md` has to grow with it, and the shape of that section is
worth settling before the code.

Contributions are accepted under the licenses the repository already uses: MIT
for code, CC BY 4.0 for the guides.
