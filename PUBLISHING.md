# Publishing mLOS

The runbook for making this repository public and giving it a DOI, together
with the two data deposits that hold what it produces. Written before the first
release, from the ShelterDataPrep publication in August 2026, so each step names
the failure it prevents rather than describing a procedure in the abstract.

The house style in `documentation_rules.md` applies here too.

---

## Contents

- [What gets published](#what-gets-published)
- [Order of operations](#order-of-operations)
- [Which DOI to cite](#which-doi-to-cite)
- [The pre-publication sweep](#the-pre-publication-sweep)
- [Decisions, settled](#decisions-settled)
- [The citable identifiers](#the-citable-identifiers)

---

## What gets published

Three artifacts, one of which arrives on its own and two of which are uploaded
by hand.

| Artifact | Contents | How it gets to Zenodo |
|---|---|---|
| The tool | The `mlos_*.R` sources, `mlos_review/`, the four guides and the Word export of each of the three reader-facing ones, the settings files, the prepared inputs, and the test suite: everything git tracks | Automatic. Zenodo archives the repository tree of each published GitHub release |
| The results | One complete run per dataset: plots, curve CSVs, `results.json`, the Excel workbook, the console log, and the preparation statistics, plus the settings file and provenance sidecar that say how to read them | By hand, from a bundle staged by `tools/make_deposit.py` |
| The deck | The generated PowerPoint decks, their table workbooks, and their figures, plus the deck settings file | By hand, from the same script |

`results/` and `reports/` are not tracked, so neither reaches the software
archive. That is the point of the second and third deposits, not an oversight.

**Why the deck is a separate deposit rather than a folder in the results one.**
The two have different half-lives. The results deposit is what a paper's data
availability statement points at, and it has to stay pinned to the version that
produced it. The deck builder ships as experimental and is expected to keep
moving. Bundling them means either that reworking the deck forces a new version
of the record a paper cites, or that the deck inside that record goes stale.
Separating them costs one more identifier to keep in sync.

Both deposits go up together, after the release is archived and before the
documentation release that catches every DOI in one pass.

## Order of operations

The steps are ordered because several of them cannot be repaired afterward.

### 0. The repository is public

Done, 2026-08-23. Zenodo cannot archive a private repository, so this came
first.

The public repository begins at a single commit, "Initial public release", of
the tree as it then stood. Development before that point is retained
privately and is not part of the published record. Nothing here needs doing
again; the step is kept so the shape of the repository is not a mystery.

### 1. Switch Zenodo on, before any tag

Log in to Zenodo with GitHub and enable `Shelter-Data-Analysis/mLOS` on the
GitHub repositories page.

This is the one ordering constraint with no repair. Zenodo archives releases
published after the switch is on and does not reach back for earlier ones.

### 2. Close out the version

- Rename `## Unreleased` in `CHANGELOG.md` to the version and the date.
- Confirm `MLOS_VERSION` in `mlos_common.R`, `version:` in `CITATION.cff`,
  `version` in `pyproject.toml`, and that heading all agree. The test suite
  checks the first three; the heading is by hand.
- Set `date-released:` in `CITATION.cff` to the day the tag will actually be
  cut, checked in UTC:

  ```bash
  TZ=UTC date +%F
  ```

  GitHub stamps tags in UTC and Zenodo dates records in Geneva local time. An
  evening tag on the United States west coast lands on the following day in
  both, and the release then disagrees with the date written inside it.

- Check that the two data deposits are cited by their **version** DOIs rather
  than their concept DOIs, in `data/OC1_data.md`, `data/OC2_data.md`, and the
  raw-extract comment in `.gitignore`. This belongs here rather than in the
  documentation release, because those deposits already exist and the switch
  depends on nothing minted later. An archived release that names a concept
  DOI names a pointer that can move off the bytes it was run on.

- Bump the version stamp in any guide the release changed, then rebuild the
  Word exports. They are tracked but rebuilt only here, so this is the one
  place the rebuild belongs:

  ```bash
  ./make_docx.sh
  ```

  ```bash
  python3 tests/show_doc_versions.py
  ```

  The second reports nothing outstanding when the first has done its work. A
  release that ships a Word export built from an earlier draft is a release
  whose archive disagrees with itself.

- Run the sweep in [the section below](#the-pre-publication-sweep).
- Run the test suite, and validate the citation file:

  ```bash
  Rscript tests/run_tests.R
  ```

  ```bash
  cffconvert --validate -i CITATION.cff
  ```

### 3. Regenerate every run under the version being tagged

A results deposit whose run logs name several versions cannot say what produced
it, and a deposit whose logs name a version that was never released points at
nothing. Regenerate in one pass, after the version is stamped and before the
bundle is staged:

```bash
Rscript mlos_run_complete.R --settings data/OC2_settings.yaml --data data/OC2_data.csv --results results
```

```bash
Rscript mlos_run_complete.R --settings data/OC1_settings.yaml --data data/OC1_data.csv --results results/OC1
```

Then rebuild both decks, in the same pass and from those runs. A deck shows
numbers it did not compute, so one built before the run it displays is showing
an earlier shelter:

```bash
python3 -m mlos_review.deck
```

```bash
python3 -m mlos_review.deck results/OC1 reports/mlos_deck_OC1.pptx
```

`tools/make_deposit.py` refuses to stage a bundle whose runs disagree about the
version, and refuses a deck older than the run it claims to show. Both are the
paragraphs above stated as code. Staging each bundle to a throwaway directory
is the cheap way to find out now rather than at upload time:

```bash
python3 tools/make_deposit.py /tmp/check_results && python3 tools/make_deposit.py --deck /tmp/check_deck
```

### 4. Tag and publish the GitHub release

The tag alone does nothing. Zenodo hooks the published-release event.

```bash
git tag -a v0.1.0 -m "0.1.0" && git push origin main && git push origin v0.1.0
```

Then publish the release from the existing tag, titled with the bare version
number. `CITATION.cff` supplies the title and authors, so a release titled
`mLOS 0.1.0` would produce a Zenodo record reading
`Shelter-Data-Analysis/mLOS: mLOS 0.1.0`.

### 5. Collect the software DOIs, and fix the version field

Zenodo mints two DOIs within a minute or two: one for the release, one concept
DOI for all releases. Keep both; the concept DOI is the one `CITATION.cff`
wants.

Then edit the Zenodo record's `version` field to drop the leading `v`. Zenodo
takes it from the tag name rather than from `CITATION.cff`, so the record reads
`v0.1.0` where a run log reads `0.1.0`, and the pair a reader checks is the DOI
and the version.

### 6. Stage and upload the results deposit

Set the software concept DOI at the top of `tools/make_deposit.py`, re-run it,
and upload the staged bundle as a new Zenodo upload.

- **Type** Dataset, **License** CC BY 4.0, matching the prepared-data deposit
  it derives from.
- **Title** naming the tool version, because the deposit is a snapshot of one
  version by construction.
- **Related identifiers**, which are what make the deposits a chain rather than
  a set of orphans:
  - *is derived from* the prepared data, `10.5281/zenodo.22051368`
  - *is compiled by* mLOS, the concept DOI from step 5

Do this before the documentation release, so that release catches every DOI in
one pass.

### 7. Stage and upload the deck deposit

Same metadata shape as step 6, with *is derived from* pointing at the results
deposit rather than at the prepared data. Do this in the same sitting: the
deck bundle records the analysis version and run timestamp of the run behind
it, so the two deposits describe the same run.

### 8. Cut the documentation release that catches the DOIs

None of the DOIs can be inside the release that produced them, so a second
release carries them:

- The software concept DOI into `CITATION.cff`'s `doi:` field.
- The results deposit, and the deck deposit if it exists, wherever they belong
  in `README.md` and the guides.

Output stays byte-identical, so the results deposit stays valid and pinned at
the earlier version. Do not regenerate it.

## Which DOI to cite

One rule applied twice, in opposite directions, because precision has to live
somewhere.

**Software: the concept DOI.** It resolves to the newest release, and the
version number beside it says which release was run. This is why `CITATION.cff`
carries a concept DOI and why a run log has to report the version.

**Data: the version DOI.** A run log pins its source by digest, so only the
version DOI is guaranteed to still hold the bytes that produced a result.

The two data sidecars and the raw-extract comment in `.gitignore` follow the
data rule and name version DOIs. The one concept DOI in the documents is
ShelterDataPrep's own, which is right: it is software, and the version a
preparation log reports sits beside it.

## The pre-publication sweep

Passages that are accurate now and wrong once a DOI exists.

| Where | What it says now | What it becomes |
|---|---|---|
| `README.md`, "Citing" | `CITATION.cff` carries no DOI yet | Names the concept DOI and the version beside it |
| The three guides | Version stamp `20260823_001` or later, Word export possibly behind it | Stamps bumped and exports rebuilt, per step 2 |
| `data/OC1_data.md`, `data/OC2_data.md` | Raw extract at `…091`, prepared files at `…368`, both version DOIs | Correct as it stands; switched from concept DOIs at 0.1.0 |
| `.gitignore`, raw-extract comment | Raw extract deposited at `…091` | Correct as it stands |
| `mlos_user_guide.md`, screening-ledger section | ShelterDataPrep at `10.5281/zenodo.22051338` | Correct as it stands; a concept DOI is right for software |
| `presentation_guide.md` | Deck builder documented with no deposit named | Names the deck deposit |

Check this list against the files rather than trusting it. It was written
before the first release and the documents have moved since.

## Decisions, settled

Recorded so they are not reopened by accident.

**The deck deposit goes up**, alongside the results deposit and at the same
time, as its own record rather than a folder inside that one. The two are
separated because they have different half-lives: the results deposit is what
a paper's data availability statement points at and has to stay pinned to the
version that produced it, while the deck builder is experimental and is
expected to keep moving. Bundling them would mean either that reworking the
deck forces a new version of the record a paper cites, or that the deck inside
that record goes stale.

**The repository is public**, and begins at the release snapshot. See
[step 0](#0-the-repository-is-public).

**The Word exports are tracked**, and rebuilt for a release rather than on
every edit. Zenodo archives the repository tree and not the release assets, so
a Word file offered only as a release asset would not be in the record at all.
What makes tracking them affordable is the rebuild rule, and what makes the
rule safe is the version stamp each guide carries: nothing has to remember
whether an export is current, because comparing two stamps says so.

**The results deposit covers two runs**, OC2 and OC1.
`data/OC2_largecut_settings.yaml` is a variant that adds one filter, cutting
the LARGE animal size, to make a single point about the shape floor; it is an
illustration rather than a core example. It stays in the repository because
`tests/README_TESTS.md` names it as an input to `scan_shape_floor.R`, and no
run of it is deposited.

## The citable identifiers

Filled in as they are minted. The concept DOIs of the two ShelterDataPrep
deposits and of ShelterDataPrep itself are already known.

| # | What it names | DOI |
|---|---|---|
| 1 | Raw extracts, all versions | `10.5281/zenodo.22051090` |
| 2 | Raw extracts, version 1 | `10.5281/zenodo.22051091` |
| 3 | ShelterDataPrep, all releases | `10.5281/zenodo.22051338` |
| 4 | Prepared data, all versions | `10.5281/zenodo.22051367` |
| 5 | Prepared data, version 1 | `10.5281/zenodo.22051368` |
| 6 | mLOS, all releases | not yet minted |
| 7 | mLOS, this release | not yet minted |
| 8 | mLOS results, all versions | not yet minted |
| 9 | mLOS results, version 1 | not yet minted |
| 10 | mLOS deck, all versions | not yet minted |
| 11 | mLOS deck, version 1 | not yet minted |

A paper cites five of these: the raw extracts by version DOI if the preparation
is part of what is reported, the prepared data by version DOI, ShelterDataPrep
by concept DOI with its version, mLOS by concept DOI with its version, and the
results by version DOI.
