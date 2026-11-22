# Functional analysis of soybean sudden death syndrome

This project investigates how soybean sudden death syndrome (SDS) develops through time and how its epidemic trajectories relate to multispectral canopy reflectance. It builds on Muhammad Mohsin Raza's doctoral field research at Iowa State University's Marsden and Hinds farms.

The research uses functional data analysis (FDA), functional mixed models, and suitable longitudinal comparators to study epidemic timing, progression, treatment differences, disease–reflectance relationships, yield associations, and early warning.

## Current status

Updated November 22, 2026. The Phase 1 audit, archive checks, and exploratory Marsden 2016 longitudinal and disease–reflectance analyses are complete. The source-keyed Hinds severity cohort is prepared for sensitivity analysis. The Marsden slides corroborate the 2017–2018 main-plot labels, and the Hinds combine sequence verifies the archived harvest keys. Remaining work includes acquisition-level checks and formal FDA analyses.

Read the [2016–2018 disease–reflectance comparison](results/phase3_seasons/REPORT.md), [Marsden 2016 disease–reflectance results](results/phase3/REPORT.md), [Phase 2 results](results/phase2/REPORT.md), [analysis protocol](results/phase2/PROTOCOL.md), [audit report](audit/REPORT.md), [data dictionary](audit/DATA_DICTIONARY.md), [issue register](audit/ISSUE_REGISTER.md), and [research plan](RESEARCH_PLAN.md). Run `Rscript analysis/01_audit.R` from the repository root to regenerate the inventory, discrepancy tables and observed trajectory figures.

The most consequential new finding is that the Hinds 2018 repository rating and yield values appear under different plot IDs in the field and harvest workbook lineage. The Marsden 2017 disease table also contains twice as many quadrats as the reflectance table. Archived Marsden yield records have been located for 2016–2018. The preliminary prediction pilot remains exploratory.

## Research questions

| ID | Question | Initial priority |
|---|---|---|
| Q1 | How do crop rotation and other verified experimental treatments change the whole SDS epidemic trajectory? | Core |
| Q2 | How much of the treatment difference reflects epidemic timing versus progression after symptom onset? | Core |
| Q3 | Are there reproducible epidemic phenotypes that final severity and AUDPC incompletely describe? | Core |
| Q4 | How do multispectral canopy trajectories relate to disease development after accounting for treatment, year, and canopy development? | Core |
| Q5 | How do incidence and severity develop together, and when do their trajectories diverge? | Supporting |
| Q6 | Does the timing and shape of disease development explain yield beyond conventional disease summaries? | Conditional on yield coverage |
| Q7 | Can partial reflectance trajectories improve prediction of subsequent visible SDS? | Secondary |
| Q8 | Which trajectory features and treatment contrasts are consistent across seasons or sites? | Cross-cutting |

Each question remains in scope. The sequence follows data availability and the strength of the evidence for each endpoint.

## Available field data

| Site and year | Reflectance units | Disease units | Reflectance / disease dates |
|---|---:|---:|---:|
| Marsden 2016 | 240 | 240 | 12 / 6 |
| Marsden 2017 | 120 | 240 | 10 / 5 |
| Marsden 2018 | 127, of which 115 appear in the join | 115 | 8 / 5 |
| Hinds 2018 | 60 | 60, with linkage disputed | 7 / 8 |
| Marsden 2019 | 120 quadrats | No outcome file found | 8 / — |
| Hinds 2019 | 60 | No outcome file found | 10 / — |

Units are within-season recorded identifiers or candidate identifier pairs. See the [sampling figure](audit/figures/sampling_coverage.png) and [join counts](audit/tables/join_integrity.csv).

Eight recorded bands are centered at 460, 510, 560, 610, 660, 710, 760, and 810 nm. Time is the principal functional domain. Bands will initially be represented as separate channels.

Treatment replication occurs at the experimental unit established by the field design. Quadrats are subsamples within Marsden plots, and dates and bands are repeated observations. Verify the design before treatment inference.

## Existing repository contents

| Path | Purpose |
|---|---|
| `data/` | Original workbooks, CSV exports, and existing joined datasets |
| `Data.Rmd` | Earlier cleaning and joining workflow |
| `Joined data.Rmd` | Overview of the joined datasets |
| `Quantification of SDS Intenisity.Rmd` | Study description, original FDA proposal, and exploratory plots |
| `images/` | Field photographs, experimental layouts, and illustrative trajectories |
| `Remote-sensing-of-Soybean-Sudden-Death-Syndrome.Rproj` | RStudio project |
| `RESEARCH_PLAN.md` | Living research plan and progress record |
| `analysis/` | Reproducible R audit and optional archive checks |
| `audit/` | Audit report, documentation, tables and figures |
| `results/phase2/` | Cohort summaries, longitudinal baseline and observed symptom detection figures |
| `results/phase3/` | Marsden 2016 disease–reflectance estimates and date sensitivity |
| `results/phase3_seasons/` | Marsden 2016–2018 comparison and correction provenance |

The earlier notebooks document the original workflow. Check their input paths, package versions, and metadata handling before execution.

## Immediate work

1. Check Hinds severity and onset results across the two archived rating versions. Continue incidence denominator reconciliation.
2. Extend the Marsden disease-only treatment and symptom timing analyses to 2017–2018.
3. Define eligibility, prediction windows and validation for any future early-warning comparison.

## Updating this project

At the end of each work session, update the phase tracker, affected question status, data issue register, and dated progress log in `RESEARCH_PLAN.md`. Link the code commit and outputs supporting each finding. Record changes in endpoints, exclusions, or model choices before presenting the associated results.

Maintain source data and record corrections in a separate, reproducible transformation with the evidence used. Add R scripts, derived data and reports as the next phases begin.

## Related research

- [Raza et al. 2020, Exploring the Potential of High-Resolution Satellite Imagery for the Detection of Soybean Sudden Death Syndrome](https://doi.org/10.3390/rs12071213)
- [Raza et al., Time of Soybean Sudden Death Syndrome Foliar Symptom Onset Influences Final Disease Intensity, Yield, and Yield Components](https://doi.org/10.1094/PDIS-07-21-1551-RE)
- [2017 conference abstract collection, including the original handheld canopy reflectance study](https://doi.org/10.1094/PHYTO-107-12-S5.165)
- [Functional analysis of plant disease progress curves, r4pde documentation](https://emdelponte.github.io/r4pde/articles/functional-analysis.html)

The research plan contains additional methodological references and the novelty assessment.
