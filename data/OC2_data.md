# `OC2_data.csv` — Orange County Animal Care (California)

Provenance sidecar for `OC2_data.csv`; this file travels with the dataset. (Each
real-shelter dataset used with mLOS gets its own `<name>_data.md` sidecar like
this one.)

- **Coverage:** intakes and outcomes, **June 1, 2018 – October 2, 2025**
- **Rows:** 34,718 stays, 28,230 distinct animals — dogs only
- **Source:** Orange County Animal Care, a government shelter whose records are
  subject to California public-records law
- **Companion settings:** `OC2_settings.yaml` (period boundaries and outcome-code
  mappings specific to this dataset)

`OC2_data.csv` is the second definition of this dataset and **the mLOS default
since 2026-08-01**. A bare run uses it:

```bash
Rscript mlos_run_complete.R
```

It supersedes `OC1_data.csv`, which is retained rather than deleted: the two are
built from the same raw extract and differ only in which rows count as shelter
stays, in the study window, and in the outcome vocabulary, so OC1 stays useful
as a frozen baseline to check against if a later result looks wrong. Nothing
regenerates it. See `OC1_data.md`.

## How this file is produced

`OC2_data.csv` is generated from the raw extract by **ShelterDataPrep**, a
separate tool in its own repository
([`Shelter-Data-Analysis/ShelterDataPrep`](https://github.com/Shelter-Data-Analysis/ShelterDataPrep),
archived at [10.5281/zenodo.22051338](https://doi.org/10.5281/zenodo.22051338)).
It reads a YAML settings file and writes the prepared CSV together with a
statistics table recording what every filtering and mapping step removed or
changed:

```bash
python3 -m shelterprep configs/orange_county2.yaml
```

| input | |
|---|---|
| raw extract | `25-5969 Intakes and Outcomes 2018 to 20251002 1.csv` (66.8 MB) |
| SHA-256 of its contents | `fbc5fa4959fe5e76f543497118717673f0c5f03ca546a28189e656e77307c3ae` |
| rows in | 192,149 (all species) |
| config | `ShelterDataPrep/configs/orange_county2.yaml` |

The raw extract was obtained from Orange County Animal Care under public-records
request **25-5969**, dated 2025-10-02. It is the same extract `OC1_data.csv` was
built from, and the digest above is identical: the two datasets differ only in
their preparation.

`OC2_data.csv` is deposited, with its statistics table, its run log, and the
settings file that produced it, at
[10.5281/zenodo.22051368](https://doi.org/10.5281/zenodo.22051368), under CC BY
4.0. That is the DOI of version 1 of the deposit, which is the one holding the
bytes described above.

### Preparation summary

Dogs only. Administrative records that are not shelter stays are removed
(expired found/lost/home records, deceased-on-intake, euthanasia-request,
disposal-request, surgery, disaster and boarding intakes), together with rows
whose kennel number marks an animal that was never actually kenneled — a field
return-to-owner or a found/lost report. Site labels are then mapped to the
canonical mLOS codes, and rows with an outcome date before the intake date or an
age above the top cutoff are dropped. A final deduplication removes the earlier
of two rows identical in every output column covering a stay of at least one
night; same-day repeats are left for mLOS's own duplicate-stay and
overlapping-stay screens.

Body disposal and dead-on-arrival are **kept**, as non-live outcomes, rather
than cut. `age_group` is carried into the output alongside `animal_size`, though
`OC2_settings.yaml` uses only `animal_size` as the animal grouping.

**`OC2_data_stats.csv`, tracked alongside this file, is the full accounting** —
one row per step, in order, with rows in, rows affected, rows out, and the same
three counts for distinct animals. It is the source for any exclusion table in a
paper. (`OC2_data_run.txt` carries the same ledger plus machine-specific paths
and versions, and is deliberately not tracked.)

### The study window

The window runs **2018-06-01 to 2025-10-02**, and its start is set by left
truncation rather than by a policy decision. The extract is drawn *by intake
date* and begins 2018-01-01, so an animal admitted in 2017 and still resident in
April 2018 does not appear in it at all. Early 2018 therefore under-counts
exactly the population a length-of-stay study cares about most — the long stays.
That bias decays as the pre-2018 admissions leave, and the shelter's move to a
new facility in spring 2018, when it almost emptied out, flushed most of them.
June 1, 2018 is the first date from which the resident population is one the
extract can fully account for.

The window is an *overlap* rule: a stay is kept if it was in progress at any
point inside it. So 162 rows carry intake dates before June 1, 2018, the
earliest 2018-01-22 — correctly, because those stays are in the file and were
resident during the window. What the start date removes is the period whose
denominator is incomplete, not those rows.

The end date stops one day short of the extract's last intake (2025-10-03),
dropping 11 same-day admissions that carry no usable follow-up.

Narrowing further is a one-line change in the config, and the cost in rows is
then reported in the statistics table like any other step. `OC2_settings.yaml`
also applies its own `period_dates` on this side.

## Where the raw extract lives

**Not in this repository.** Raw extracts are large and are published data; they
belong in a deposit with their own DOI rather than in git history, where every
version of them would live forever. `/data/*_raw.csv.gz` is gitignored so one
cannot be committed here by accident.

> **Zenodo DOI:
> [10.5281/zenodo.22051091](https://doi.org/10.5281/zenodo.22051091).** The
> 25-5969 extract is deposited there as `OC_raw.csv.gz`, under CC BY 4.0. Cite
> it as the data source for anything computed from `OC2_data.csv`. That is the
> version DOI rather than the concept DOI
> [10.5281/zenodo.22051090](https://doi.org/10.5281/zenodo.22051090), which
> follows the newest version: a run log pins its source by digest, so only the
> version record is guaranteed to still hold those bytes.

A gzipped working copy is kept locally, outside any repository, at the path the
config points to. ShelterDataPrep resolves that path relative to the settings
file rather than to the working directory, so `../../_shelter_raw/OC_raw.csv.gz`
means a `_shelter_raw` directory sitting beside the two repositories; adjust
`source_dir` for your own machine. pandas reads `.csv.gz` directly, so nothing
needs unpacking.

The digest above is of the **uncompressed** contents, so it identifies the data
rather than any particular archive of it: it is unchanged by compressing,
recompressing, or moving the file. To check a copy:

```bash
gunzip -c OC_raw.csv.gz | shasum -a 256
```

The same arrangement covers the other shelters — `IR_raw.csv.gz`,
`CIall_raw.csv.gz`, `LB_raw.csv.gz`, `MV_raw.csv.gz` and `LA_raw.csv.gz`, the
last shared by the LA County dogs and cats configs.
