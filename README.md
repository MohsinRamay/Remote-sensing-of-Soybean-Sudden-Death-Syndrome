# Functional analysis of soybean sudden death syndrome

This project investigates how soybean sudden death syndrome (SDS) develops through time and how its epidemic trajectories relate to multispectral canopy reflectance. It builds on Muhammad Mohsin Raza's doctoral field research at Iowa State University's Marsden and Hinds farms.

The research uses functional data analysis (FDA), functional mixed models, and suitable longitudinal comparators to study epidemic timing, progression, treatment differences, disease–reflectance relationships, yield associations, and early warning.

## Current status

Updated November 21, 2026. Planning and preliminary audit are complete. Data reconciliation, reproducible analysis, formal FDA model fitting, uncertainty estimation, and manuscript development are pending.

The initial analysis identified potential metadata conflicts and inconsistent performance across seasons in a simple trajectory prediction pilot. Its results are exploratory. Publication feasibility remains under evaluation.

Read [RESEARCH_PLAN.md](RESEARCH_PLAN.md) for the hypotheses, analysis sequence, data issue register, completion criteria, and dated progress log. That document is the working record for this project.

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

| Site and year | Disease-linked observational units in existing CSV files | Reflectance visits | Disease-rating visits | Notes |
|---|---|---|---|---|
| Marsden 2016 | 240 distinct quadrat IDs | 12 | 6 | Four blocks and 12 distinct plot IDs in the joined file |
| Marsden 2017 | 120 distinct quadrat IDs | 10 | 5 | Some reflectance metadata conflict on June 30 |
| Marsden 2018 | 115 distinct quadrat IDs | 8 | 5 | Visit coverage varies among quadrats. Rotation labels require reconciliation |
| Hinds 2018 | 60 distinct plot IDs | 7 | 8 | All plots eventually had positive recorded incidence. Yield is present |
| Marsden and Hinds 2019 | Reflectance workbooks present | To inventory | Disease labels unavailable in the repository | Notebook describes very few symptomatic units |

Counts describe the files audited at commit `a9db68a6de8327c57d0f755ca8a554f7886b7d25`. They require reproduction in the audit pipeline. The 2017 file produces additional apparent groups if inconsistent plot metadata are included in the key. Counts are based on distinct quadrat IDs within year.

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

The earlier notebooks document the original workflow. Check their input paths, package versions, and metadata handling before execution.

## Immediate work

1. Build a reproducible inventory and data dictionary from all original and derived files.
2. Reconcile unit identifiers and treatment labels against field layouts and original records.
3. Produce observed disease and reflectance trajectories with sampling coverage visible.
4. Specify a core protocol for treatment curves and disease–reflectance associations.
5. Fit design-aware longitudinal baselines and FDA models, then evaluate uncertainty and robustness.

## Updating this project

At the end of each work session, update the phase tracker, affected question status, data issue register, and dated progress log in `RESEARCH_PLAN.md`. Link the code commit and outputs supporting each finding. Record changes in endpoints, exclusions, or model choices before presenting the associated results.

Maintain source data and record corrections in a separate, reproducible transformation with the evidence used. Future analysis work will add scripts, derived data, and reports as their phases begin. The intended implementation language is R, matching the existing project.

## Related research

- [Raza et al. 2020, Exploring the Potential of High-Resolution Satellite Imagery for the Detection of Soybean Sudden Death Syndrome](https://doi.org/10.3390/rs12071213)
- [Raza et al., Time of Soybean Sudden Death Syndrome Foliar Symptom Onset Influences Final Disease Intensity, Yield, and Yield Components](https://doi.org/10.1094/PDIS-07-21-1551-RE)
- [2017 conference abstract collection, including the original handheld canopy reflectance study](https://doi.org/10.1094/PHYTO-107-12-S5.165)
- [Functional analysis of plant disease progress curves, r4pde documentation](https://emdelponte.github.io/r4pde/articles/functional-analysis.html)

The research plan contains additional methodological references and the novelty assessment.
