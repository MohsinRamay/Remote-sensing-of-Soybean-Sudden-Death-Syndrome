# Phase 1 data audit

November 22, 2026. Repository data revision `a9db68a6de8327c57d0f755ca8a554f7886b7d25`. Planning base `aa05890b55021707da68aa0176572e7d82601260`.

The repository audit is complete. Field reconciliation remains open, especially for Hinds 2018 plot linkage. Original inputs were left intact. [Audit decisions and evidence needed](ISSUE_REGISTER.md) records the proposed analysis restrictions and their release criteria.

## Sampling and join integrity

| Trial | Reflectance units | Disease units | Both streams | Reflectance / disease dates |
|---|---:|---:|---:|---:|
| Marsden 2016 | 240 | 240 | 240 | 12 / 6 |
| Marsden 2017 | 120 | 240 | 120 | 10 / 5 |
| Marsden 2018 | 127 | 115 | 115 | 8 / 5 |
| Hinds 2018 | 60 | 60 | 60 by recorded ID, linkage disputed | 7 / 8 |
| Marsden 2019 | 240 workbook identifier pairs | — | — | 8 / — |
| Hinds 2019 | 60 | — | — | 10 / — |

All 10 CSVs and six workbook sheets are inventoried. The only parsed missing input cells are 2,050 blanks in a trailing unnamed column of the Marsden 2018 replicate CSV. Missing **visits** remain a separate issue. The four historical joins add zero rows by multiplication, and their reflectance keys and values reproduce. Wide disease columns repeat each unit's ratings on its spectral rows, including ratings collected later than the reflectance date. Use the individual measurement streams for modeling and use only ratings and measurements available by the prediction landmark.

The 2016 and 2017 Marsden workbook records match the combined intermediate. The 2018 Marsden workbook and replicate CSV agree. In Hinds, 45 values in the raw `Plot` field change between workbook and CSV, including fractional workbook labels. The reading labels and band values agree. Re-averaging the replicate CSVs with the notebook's metadata-aware grouping reproduces both 2018 reflectance intermediates. The Hinds grouping uses the three-digit reading prefix. The numerical comparison uses absolute tolerance `1e-9`. [Lineage counts](tables/lineage_summary.csv) · [Detailed lineage differences](tables/lineage_discrepancies.csv) · [Join integrity](tables/join_integrity.csv).

The Marsden 2018 join excludes five named IDs in the code. Only 4811 and 4812 occur in the intermediate, accounting for 24 band rows. Ten additional IDs, 4901–4910, have reflectance and no disease entry, accounting for 80 band rows. All 115 disease units occur in the export. Of these, 108 have a June 29 spectrum and 99 have an August 23 spectrum. The Marsden 2018 replicate file contains four readings per unit on August 31 for all 115 sampled IDs, with repeated reading labels. The intermediate averages all four. The 2018 joined export mixes full and rounded incidence values in 265 quadrat–assessment cells spanning 92 quadrats, affecting 1,750 spectral rows. The largest absolute incidence difference is 0.00000492 percentage points. Use the long disease table at its native precision. [Join omissions](tables/join_omissions.csv) · [Missing visits](tables/unit_visits_without_record.csv) · [Replicates](tables/replicate_count_or_label_flags.csv) · [Export ratings](tables/export_rating_differences.csv).

## Conflicting identities and labels

- **Marsden 2017, June 30.** The source workbook has six plot conflicts for quadrats 1316, 1601, 1711, 2201, 2411 and 2511. Five also differ in rotation and two in block. Other reflectance dates agree with the disease metadata for these IDs, and all 1,200 repository disease rows match the archived long ratings. The pattern is consistent with a shifted metadata range. Acquisition identity still needs the original sequence or field map.
- **Marsden 2018.** The first reflectance visit agrees with disease on rotation for all overlapping records. Each of the seven later visits has 60 conflicts in plots 11, 14, 19, 23, 27 and 29. Plot and block agree. The two affected blocks exhibit opposite three-way label cycles. Both archived disease workbooks reproduce all 575 repository rating rows and their recorded labels. Verify assignments against the plot-year field map.
- **Hinds 2018, August 3.** Plot 508's field assignment is block 5, T4, cultivar code 1, dose 5. Raw reading 5081 carries the plot 507 label (T6, cultivar code 2, dose 2). The same file has two different spectra both labeled 5082. The reading-prefix transformation creates eight duplicated plot-date-band keys for 508 and leaves one reading assigned to 507. Assignment evidence supports the treatment key. Acquisition identity and replication remain open for both plots on that date.
- **Marsden 2019.** Each of 120 distinct `Quadrat` values appears with two `Plot` values, producing 7,680 duplicate date-band keys under the earlier quadrat-only convention. Using the stable workbook pair gives 240 complete spectral trajectories and unique keys. Keep this display identifier provisional until the 2019 field crosswalk is recovered. The archive calendar lists four visual visits at Hinds and one at Marsden in 2019. No labeled outcomes were recovered from those calendar entries.

[Direct label comparisons](tables/reflectance_vs_disease_labels.csv) · [Duplicate spectral keys](tables/duplicate_reflectance_keys.csv) · [Hinds reading-prefix disagreements](tables/hinds_reading_plot_disagreements.csv) · [Marsden 2019 identifier pairs](tables/marsden2019_identifier_pairs.csv).

## Hinds plot linkage

The repository rating and yield values reproduce the archived `Hinds SDS Yield.xlsx` summary within `1e-7`. The archive field workbook `SDS Hinds.xlsx` long table matches the separate remote-sensing rating workbook on all 480 plot-date records. Compared by recorded plot, this second version differs from the repository at 387 incidence and 339 severity cells, including 98 and 81 differences in positive status, respectively.

All 60 repository yield values each match exactly one archived harvest value within `1e-7`. Only one matches under the same plot ID. Fifty-six repository disease trajectories each match one full trajectory in the field workbook lineage, and all 56 point to the same plot as their corresponding yield match. The remaining repository IDs are 209, 305, 503 and 601. Under the plot mapping suggested by yield, their ratings differ from the field lineage at two incidence values and five severity values across five plot–date records. The consolidated `Hinds 2018` sheet agrees with the combine harvest workbook by plot for all 60 yields. These checks support a plot-label permutation in the repository lineage as a likely explanation. Preserve both versions until the original field and harvest linkage is established. Use the assignment sheet for design evidence. The archived generated randomization CSV uses sequential IDs after block 1, and its assignments already disagree on the 10 shared plot keys.

The repository also carries the same yield value on eight rating rows for each plot. The replicated values convey one endpoint per plot. [Archive comparison counts](evidence/source_comparison_counts.csv) · [Trajectory and yield mapping counts](evidence/hinds_value_mapping_counts.csv) · [Repository yield repetition](tables/hinds_yield_repetition.csv).

## Ratings, onset and harvest

The repository contains 27 rating records with incidence and severity on opposite sides of zero, comprising 19 at Hinds 2018, seven at Marsden 2016 and one at Marsden 2018. Choosing incidence, severity, either, or both changes the first positive date for 17 Hinds plots, five Marsden 2016 quadrats and one Marsden 2018 quadrat. The audit retains last recorded negative and first recorded positive dates. Under recorded incidence, the interval/left/right-censored counts are 181/12/47 for Marsden 2016, 131/3/106 for Marsden 2017, 97/2/16 for Marsden 2018 and 54/6/0 for Hinds 2018. All Hinds repository plots are eventually incidence-positive. These are bounds on first recorded symptoms under each endpoint definition. [Rating disagreements](tables/symptom_disagreements.csv) · [Candidate onset intervals](tables/candidate_onset_intervals.csv).

At Hinds, the reproductive-stage field sheet records symptomatic plant counts for all 60 plots on the first five visits, for 29 plots on August 18, and for zero plots on the last two visits. The stored stand estimate reproduces 328 of the 329 percentages that can be checked from counts in that sheet. The long table differs from the same workbook's field sheet at three incidence and three severity cells. These data support auditing the early calculation and distinguish later ratings that lack a count. [Hinds count checks](evidence/hinds_reproductive_count_checks.csv).

The dissertation verifies the quadrat rating definitions and documents the randomized design, planting dates and harvest protocol. Chapters 2 and 3 overlap directly with the proposed yield and onset questions. Chapter 4 uses satellite data and its own sampling coverage. The dissertation does not establish the handheld instrument's calibration or resolve the repository label assignments.

Marsden harvest records were located for all three disease-linked seasons. The archive contains yield for 240, 103 and 115 quadrats in 2016, 2017 and 2018, respectively. They overlap the repository disease files at all of those IDs and the historical joined reflectance exports at 240, 95 and 115 IDs. The 2017 and 2018 analysis yields match the labeled harvest columns for 103/103 and 115/115 IDs. The 2016 workbook stores both yield and kg/ha values. Preserve harvest coverage and review selection, moisture and area assumptions before Q6. [Marsden yield overlap](evidence/marsden_yield_overlap.csv) · [Data dictionary](DATA_DICTIONARY.md).

## Observed trajectories and next analysis

- [Sampling coverage](figures/sampling_coverage.png) shows actual reflectance and disease visits and the effect of the 2018 Marsden filter.
- [Disease trajectories](figures/observed_disease.png) show source ratings, including the disputed Hinds repository version. These figures describe the observed seasonal distributions.
- [660 nm and 810 nm trajectories](figures/observed_reflectance.png) show selected recorded channels. The Hinds duplicate band keys are omitted from the curves. No interpolation or smoothing was used.

Proceed with Marsden 2016 design-aware descriptive exploration and a draft within-season protocol. Use the full Marsden 2017 disease cohort for disease-only exploration. At Marsden 2018, disease-only trajectory descriptions and metadata-independent reflectance summaries can proceed separately. Keep label-conflicted acquisitions out of treatment-aligned and paired work pending reconciliation. At Hinds, summarize source versions separately and defer plot-linked treatment, yield, onset and reflectance analyses until the archive permutation is resolved. Use 2019 for reflectance coverage and seasonal exploration. The next step is to freeze a provenance-bearing unit registry and eligible cohorts against the field records, then compare simple longitudinal models with FDA on shared time support.

## Reproduce

From the repository root, run `Rscript analysis/01_audit.R`. It requires `readxl`, `digest`, `dplyr`, `tidyr`, `ggplot2`, `ragg` and `scales`. It writes CSVs and figures under `audit/`. Pass a different output directory as an optional argument. [Code](../analysis/01_audit.R) · [Software versions](tables/software.csv) · [File inventory](tables/inventory.csv) · [Column profiles](tables/column_profiles.csv).

The optional source comparison takes the separate SDS Paper project root and a writable output directory as positional arguments. For example, `Rscript analysis/02_check_sds_paper_sources.R "$SDS_PAPER_ROOT" /tmp/sds-paper-check`. The archive inputs and detailed plot mappings are held separately. [Archive comparison code](../analysis/02_check_sds_paper_sources.R) · [Source fingerprint manifest](evidence/sds_paper_source_manifest.csv).
