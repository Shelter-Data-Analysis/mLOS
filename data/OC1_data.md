# `OC1_data.csv` — Orange County Animal Care (California)

Provenance sidecar for `OC1_data.csv`; this file travels with the dataset. (Each
real-shelter dataset used with mLOS gets its own `<name>_data.md` sidecar like
this one.)

> **Superseded by `OC2_data.csv`, the default since 2026-08-01.** This dataset
> is frozen: nothing regenerates it, and it is kept tracked so a later result
> that looks wrong can be checked against a known one. It was called
> `OC_data.csv` until that date. Run it by naming it explicitly —
> `Rscript mlos_run_complete.R --settings data/OC1_settings.yaml --data data/OC1_data.csv`.
> For what changed and why, see `OC2_data.md`.

- **Coverage:** intakes and outcomes, **January 1, 2018 – October 3, 2025**
- **Rows:** 36,567 stays, 29,746 distinct animals — dogs only
- **Source:** Orange County Animal Care, a government shelter whose records are
  subject to California public-records law
- **Companion settings:** `OC1_settings.yaml` (period boundaries and outcome-code
  mappings specific to this dataset)

## How this file is produced

`OC1_data.csv` is generated from the raw extract by **ShelterDataPrep**, a
separate tool in its own repository
([`Shelter-Data-Analysis/ShelterDataPrep`](https://github.com/Shelter-Data-Analysis/ShelterDataPrep),
archived at [10.5281/zenodo.22051338](https://doi.org/10.5281/zenodo.22051338)).
It reads a YAML settings file and writes the prepared CSV together with a
statistics table recording what every filtering and mapping step removed or
changed:

```bash
python3 -m shelterprep configs/orange_county1.yaml
```

| input | |
|---|---|
| raw extract | `25-5969 Intakes and Outcomes 2018 to 20251002 1.csv` (66.8 MB) |
| SHA-256 of its contents | `fbc5fa4959fe5e76f543497118717673f0c5f03ca546a28189e656e77307c3ae` |
| rows in | 192,149 (all species) |
| config | `ShelterDataPrep/configs/orange_county1.yaml` |

The raw extract was obtained from Orange County Animal Care under public-records
request **25-5969**, dated 2025-10-02.

`OC1_data.csv` is deposited, with its statistics table, its run log, and the
settings file that produced it, at
[10.5281/zenodo.22051368](https://doi.org/10.5281/zenodo.22051368), under CC BY
4.0. That is the DOI of version 1 of the deposit, which is the one holding the
bytes described above.

### Preparation summary

Dogs only. Administrative records that are not shelter stays are removed
(disposal, body-disposal outcomes, expired found/lost/home records, deceased-on-
intake, euthanasia-request and wildlife intakes), site labels are mapped to the
canonical mLOS codes, and rows with an outcome date before the intake date or an
age above the top cutoff are dropped. A final deduplication removes the earlier
of two rows identical in every output column covering a stay of at least one
night; same-day repeats are left for mLOS's own duplicate-stay and
overlapping-stay screens.

**`OC1_data_stats.csv`, tracked alongside this file, is the full accounting** —
one row per step, in order, with rows in, rows affected, rows out, and the same
three counts for distinct animals. It is the source for any exclusion table in a
paper. (`OC1_data_run.txt` carries the same ledger plus machine-specific paths
and versions, and is deliberately not tracked.)

The study window is set to the full span of the extract, so nothing is excluded
by date. Narrowing it is a one-line change in the config, and the cost in rows
is then reported in the statistics table like any other step.

## Where the raw extract lives

**Not in this repository.** Raw extracts are large and are published data; they
belong in a deposit with their own DOI rather than in git history, where every
version of them would live forever. `/data/*_raw.csv.gz` is gitignored so one
cannot be committed here by accident.

> **Zenodo DOI:
> [10.5281/zenodo.22051091](https://doi.org/10.5281/zenodo.22051091).** The
> 25-5969 extract is deposited there as `OC_raw.csv.gz`, under CC BY 4.0. Cite
> it as the data source for anything computed from `OC1_data.csv`. That is the
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
