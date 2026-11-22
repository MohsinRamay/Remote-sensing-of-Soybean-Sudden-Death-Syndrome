# Living research plan for functional analysis of SDS

Version 0.3. Updated November 22, 2026.

Research owner and field-design lead — Muhammad Mohsin Raza.

Audited source revision — `a9db68a6de8327c57d0f755ca8a554f7886b7d25`.

## 1. Scientific purpose

Determine what the time-dependent behavior of SDS incidence, severity, and multispectral canopy reflectance reveals about epidemic development, experimental treatments, canopy response, and subsequent disease or yield outcomes.

The initial manuscript direction is treatment-dependent SDS epidemic trajectories and their association with canopy reflectance. Early warning is a secondary analysis. Final manuscript scope will follow the data audit and the evidence for each hypothesis.

The full set of questions remains available for exploration. Select a small primary hypothesis family before formal inference. Identify later additions and result-informed choices as exploratory.

## 2. What is established and what remains provisional

| Item | Evidence and status |
|---|---|
| Marsden and Hinds data exist | Verified through repository files and study notebooks |
| Eight bands and repeated disease ratings exist | Verified in existing CSV files |
| Both experiments used RCBD | Stated in the study notebook. Exact treatment allocation, randomization, and subsampling hierarchy require verification |
| Marsden treatment is represented by rotation codes | Verified. Crop sequence definitions and stable plot assignments require documentation |
| Hinds includes treatment, variety, concentration, and yield fields | Verified. Treatment definitions, concentration units, and factor structure require documentation |
| 2019 disease data are unavailable | Repository notebook describes very few symptomatic units. Reflectance workbooks exist. Search original records before deciding their analytical role |
| Pilot prediction performance varies across seasons | Exploratory Python analysis used linear levels and slopes, fixed model settings, and preliminary metadata reconciliation. A formal FDA model and inferential validation are pending |
| Broader epidemiological FDA analyses have potential | Research hypotheses. Formal results are pending |
| Dissertation context | Full dissertation located in the SDS Paper archive. Chapters 2–4 inform rating definitions, design, yield methods and overlap with earlier work. Formal novelty review remains pending |

The earlier pilot values depend on endpoint definition, metadata assumptions, exclusions, and model representation. Reproduce them in version-controlled code before using them in a report. The planning documents carry forward their qualitative findings only.

## 3. Research questions and estimands

| ID | Question and proposed estimand | Analysis and comparator | Main qualification |
|---|---|---|---|
| Q1 | Do treatments differ in disease trajectory? Estimate treatment-specific mean curves and pairwise difference functions over a common observed period | Functional mixed model or GAMM. Compare with repeated measures treatment-by-time and parsimonious nonlinear mixed models | Experimental-unit replication and valid response distribution |
| Q2 | Do treatment differences reflect onset timing, progression after onset, or both? Estimate onset intervals and supported differences in onset-aligned curves | Compare chronological and onset-relative representations. Use an interval-censored onset model where feasible | Alignment is outcome-informed and changes the estimand. It can remove a biologically important treatment effect |
| Q3 | What epidemic phenotypes recur? Estimate leading functional modes and assess whether curves with similar AUDPC have distinct timing or shape | Low-rank FPCA and cautious clustering, compared with final severity, AUDPC, onset, and simple progression summaries | Components and clusters require stability checks. Largest variance may reflect year or treatment |
| Q4 | How are disease and canopy trajectories associated? Estimate time-varying or low-rank joint associations, within treatment and year | Begin with concurrent smooth associations, then multivariate FDA or joint functional models. Compare with simple longitudinal regression | Seasonal development, senescence, measurement timing, and calibration can create shared trends |
| Q5 | How do incidence and severity trajectories correspond? Estimate their joint modes and time-varying association | Joint curve analysis, compared with assessment-specific association and AUDPC correlations | Verify rating denominators and scales. Their ratio has no assumed biological interpretation |
| Q6 | Which aspects of disease history are associated with yield? Estimate a regularized temporal association with final yield | Scalar-on-function regression, compared with treatment plus final severity, AUDPC, and onset | Marsden harvest records are located and linkage review is pending. Hinds has 60 source-keyed plot yields. Timing effects may be weakly identifiable |
| Q7 | Do partial reflectance trajectories improve early warning? Estimate risk of first positive foliar rating within a defined future window among eligible symptom-free units | Low-rank functional regression, compared with treatment alone, latest spectrum, and simple trajectory summaries | Use information available at prediction time. Account for interval-censored onset and limited pre-onset visits |
| Q8 | Which effects persist across environments? Estimate treatment-by-season trajectory differences and assess feature stability or transfer | Year-specific contrasts and interaction models. Hold out years or sites for predictive claims | Three Marsden seasons and one disease-labeled Hinds season limit broad environmental generalization |

Q1, Q2, and Q4 form the proposed core. Q3 and Q5 support interpretation. Q6 depends on yield coverage. Q7 remains a distinct prediction objective. Q8 governs how far each finding generalizes.

## 4. Phase tracker

| Phase | Status | Deliverables | Completion criterion |
|---|---|---|---|
| 0. Feasibility and planning | Initial review complete | Repository overview, preliminary literature map, questions, issue register | Living documents available in version control |
| 1. Data reconstruction and quality control | Repository audit complete. Field reconciliation open | [Inventory](audit/tables/inventory.csv), [dictionary and hierarchy](audit/DATA_DICTIONARY.md), [candidate registry](audit/tables/candidate_units.csv), [issue and decision register](audit/ISSUE_REGISTER.md) | Freeze field-verified identifiers, treatment allocation and eligible cohorts. Keep discrepancies and exclusions auditable |
| 2. Temporal exploration and protocol | Marsden 2016 exploratory protocol and Hinds source preparation complete | [Protocol](results/phase2/PROTOCOL.md), [cohort and baseline report](results/phase2/REPORT.md) | Common support and model complexity justified by observed data |
| 3. Core epidemiological models | First Marsden 2016 comparator fitted. Core inference pending | Q1–Q5 models, design-aware contrasts, uncertainty bands, sensitivity analyses | Findings supported by diagnostics and appropriate experimental replication |
| 4. Yield, early warning, and transfer | Conditional | Q6–Q8 analyses and comparisons | Dependencies satisfied and validation matches each claim |
| 5. Evidence synthesis and manuscript | Pending | Decision memo, figures, tables, manuscript, reproducibility supplement | Claims match evidence, scope is coherent, and analysis reruns from a documented environment |

## 5. Phase 1 — reconstruct the data

### File inventory and dictionary

Inventory every workbook sheet and CSV. Record source revision, file hash, dimensions, column types, date ranges, units, missingness, and transformation provenance. Compare raw workbooks, intermediate reflectance tables, disease tables, and joined exports.

Verify the instrument model, band widths, reflectance scale, calibration/reference procedure, number of replicate readings, sensor height and field of view, acquisition conditions, and replicate averaging. Recover planting dates, cultivar assignments, growth stages, and harvest details where available.

Document Marsden rotation codes and plot-year assignments. Document Hinds treatment names, concentration meaning and units, cultivar allocation, and randomization. Identify which physical plots recur across years and how crop phases affect soybean plot availability.

### Canonical tables to create during implementation

| Table | One row per | Essential fields |
|---|---|---|
| Unit registry | Site × year × observational unit | Stable physical plot ID, block, quadrat or plot ID, treatment, cultivar, verified design role |
| Reflectance | Unit × actual date × band × replicate where available | Measurement, scale, source, QA flag |
| Disease | Unit × actual assessment date | Incidence, severity, rating scales, plant denominator where available, source, QA flag |
| Yield | Unit × harvest | Yield, units, sampled area, moisture adjustment, source |
| Correction ledger | Proposed or applied correction | Original value, replacement, evidence, decision, date, affected rows |

Keep disease and reflectance observations at their actual dates. Construct analysis-specific joins from these tables. Future disease ratings belong in endpoint construction, and their availability must be tracked separately from prediction inputs.

### Known issue register

The [audit issue register](audit/ISSUE_REGISTER.md) documents D01–D13, the source evidence, proposed handling, and the field records needed. The main analysis decisions are below.

| Scope | Current decision |
|---|---|
| Q1–Q2, Q5 · Disease trajectories and timing | Start with within-season Marsden 2016 and descriptive Marsden 2017–2018 disease streams. Use actual assessment dates and compare candidate onset definitions. Prepare Hinds severity from the dated field lineage with independent design and harvest keys. Check rating versions and incidence denominators. |
| Q3–Q4 · Shape and spectral associations | Start with observed support and simple longitudinal comparators. Pair Marsden 2016 on eligible IDs after the registry is frozen. Use the slide-backed Marsden 2018 assignments. Flag the unresolved acquisition IDs and prepare Hinds linkage from the dated field lineage. |
| Q6 · Yield | Marsden harvest files now identified for 2016–2018. Verify units, crosswalks and sampling coverage. Use the sequence-verified Hinds combine workbook. Keep the legacy join quarantined. |
| Q7–Q8 · Prediction and transfer | Pilot unreproduced. Design eligible landmarks and validation after freezing endpoints and physical plot linkage. Treat 2019 as reflectance-only pending recovery of labeled ratings. |

Keep original design assignments and observation-level metadata traceable. A reproducible candidate match remains provisional until the corresponding field evidence supports it.

## 6. Phase 2 — exploration and protocol

Plot observed incidence, severity, and each reflectance band for individual units, with plot-level and treatment-level summaries. Show actual visits and distinguish missing observations from zero ratings. Examine disease reversals, ceiling effects, senescence, date-wide shifts, and implausible spectral changes.

Report the number of blocks, plots, observational units, dates, and measurements separately. Compare epidemic summaries with curve shapes and identify examples of similar AUDPC with different timing. Inspect year effects before pooling seasons or interpreting FPCA.

Use calendar date as an initial within-year domain. Assess days after planting or growth stage if verified metadata exist. Analyze the shared observed period for between-treatment contrasts and report effects of alternate domains. Onset-relative time is a separate secondary representation.

Before formal testing, document the primary response, contrast family, time domain, link and response distribution, hierarchy, smoothing complexity, missing-data assumptions, exclusion rules, and sensitivity analyses. Label analyses already informed by the preliminary pilot as exploratory.

## 7. Phase 3 — modeling principles

### Experimental structure

Represent block, treatment plot, quadrat, and repeated measurements according to the confirmed design. Treatment degrees of freedom and resampling units must reflect treatment randomization. Account for recurring physical plots across seasons and consider residual spatial structure if coordinates or adjacency are available.

With only three Marsden disease-labeled seasons, begin with year-specific descriptions and fixed year interactions. Estimate broad between-environment variation only if supported by the available replication. Analyze the two sites according to their distinct designs and treatment definitions.

### Response models and comparators

Use count-based incidence models if numerators and denominators are recovered. For visual percentages, select an appropriate bounded-response model that accommodates observed zeros and ones. Verify whether severity is continuous, ordinal, or transformed. Apply suitable links and measurement-error assumptions before functional modeling.

Compare a design-aware repeated measures model, a parsimonious nonlinear epidemic model where suitable, and a low-complexity GAMM or functional mixed model. Use the same observations, estimand, and assessment period for comparisons. FDA model choice follows the scientific question and data resolution.

Begin with a small smooth basis for each band and epidemic response. Sparse-data FPCA can borrow strength across units, but shared sampling dates constrain temporal detail. Check whether fitted features are supported by observations. Derivatives amplify uncertainty, particularly near boundaries. Report symptom progress rate on its defined response scale. Relate it to mechanistic infection parameters only with an appropriate epidemic model and assumptions.

For retrospective Q1–Q5 analyses, full observed trajectories are available. For Q7 predictions, fit smoothing, FPCA, scaling, selection, and tuning using training data and truncate test trajectories at prediction time.

### Inference and robustness

Estimate whole-curve treatment contrasts with global tests and simultaneous bands where feasible. Account for the selected family of treatment, band, and response comparisons. Use design-respecting resampling or permutation, with blocks or plots as required, and report limitations from small replication.

Carry uncertainty from fitted curves into derivatives, scores, downstream associations, and yield models through joint estimation or suitable resampling. Evaluate sensitivity to curve complexity, time alignment, metadata resolution, missingness, onset definition, senescence period, and selected bands. Check stability of FPCA components and clusters under resampling.

Use simple effect sizes alongside curve plots. Examples include severity differences on a stated date, differences in time to a supported threshold, and integrated differences over an explicitly defined interval. Adjust interpretation when thresholds are never reached.

## 8. Phase 4 — conditional extensions

### Yield

Verify harvest coverage and units before Q6. Begin with treatment-adjusted associations and a small number of curve summaries. Compare a low-rank scalar-on-function model with AUDPC, final severity, and onset models using common samples. Evaluate incremental explanatory or predictive value and coefficient stability. Highly correlated disease values across time limit identification of narrow critical periods. Observational disease–yield associations require care in causal interpretation.

### Early warning

Define the target as first positive foliar rating within a prespecified future window. Require a documented symptom-free state appropriate to each landmark. Treat first-visit positives as left-censored onset, units remaining negative as right-censored, and first detection between visits as interval-censored.

Compare treatment alone, latest spectrum, simple levels/slopes, and a low-rank FDA model using identical eligible units and folds. Separate identification of upcoming onset from eventual season-end disease status. Hinds can support onset-window analyses despite all plots eventually becoming positive.

For predictive evaluation, hold out complete plots or blocks as required. Hold out complete years for seasonal transfer, and exclude recurring physical plots from training where the target is new-plot transfer. Use nested tuning when tuning is undertaken. Report AUROC, precision–recall performance with prevalence, calibration, Brier score, and sensitivity at a fixed scouting burden. Include plot-stratified discrimination where enough mixed-outcome plots exist, with uncertainty and the number of contributing plots.

### Cross-environment interpretation

Treatment inference within the observed trial can be supported by randomization-aware models without requiring successful prediction in a held-out year. Seasonal transfer and new-site deployment are distinct claims requiring matching validation. Test whether any common spectral associations survive adjustment for treatment and normal seasonal development.

## 9. Manuscript decisions and outputs

| Evidence available | Potential manuscript direction |
|---|---|
| Stable treatment differences in timing or progression, with informative canopy associations | Functional epidemiology and canopy response paper |
| Trajectory summaries add clear, reproducible information beyond final severity and AUDPC | Epidemic phenotyping and functional methods application |
| Partial curves improve useful scouting decisions across independent test groups | Early warning paper or a focused secondary section |
| Findings depend strongly on season, calibration, or treatment structure | Validation and limitations paper if the sources of failure can be demonstrated rigorously |
| Identity or design conflicts prevent trustworthy inference, or curves add little supported information | Document the evidence and narrow the scope. Reassess feasibility before manuscript drafting |

Treat these as evidence-based scope decisions. Publication value depends on biological insight, credible inference, and reproducibility. Multiple papers would require distinct contributions and sufficient evidence for each.

Planned figures are the verified design and sampling coverage, observed and fitted treatment curves, contrast functions with uncertainty, supported onset/progression differences, interpretable functional modes, and disease–reflectance associations. Yield and prediction figures are conditional. Planned tables cover data provenance, issue resolution, experimental replication, model comparisons, and sensitivity results.

Compare the contribution with the existing SDS papers, including the original handheld abstract and published satellite and onset–yield studies. Use the recovered dissertation chapters and source crosswalks when finalizing novelty. Map data overlap, established results, and genuinely new questions in the manuscript record.

## 10. Reproducibility and implementation

Use R for the analysis, consistent with the existing project. Evaluate `mgcv`, suitable mixed-model tools, and FDA implementations such as `refund`, `fdapace`, or `r4pde` for the chosen estimands after checking current documentation. The audit records the R and package versions used. Add an environment lockfile for the modeling workflow.

Create numbered audit, preparation, exploration, model, and report scripts as those phases begin. Keep source inputs intact, place generated tables and figures in documented output paths, and record software versions, random seeds, model settings, and source revision. A documented command should regenerate each reported result from verified inputs. Store field-record corrections separately with their evidence and merge them reproducibly.

## 11. Updating and resuming work

At the start of a session, read this plan and the latest log entry, inspect the repository revision, and confirm which data issues affect the intended analysis. Continue the earliest actionable task in the current phase.

At the end of a session, update the phase tracker and issue register, then append a log entry with the work performed, evidence and file links, decisions, unresolved items, and next concrete action. Keep earlier decisions visible. If a decision changes, record the replacement and reason.

### Decision record

| Date | Decision | Rationale | Status |
|---|---|---|---|
| 2026-11-21 | Explore the epidemiological questions with FDA, including full-season analyses | Repeated disease and reflectance measurements support questions about epidemic dynamics and canopy response | Agreed research direction |
| 2026-11-21 | Proposed core is Q1, Q2, and Q4. R is the intended implementation language | A coherent first analysis can build on the existing project and use the full-season data | Proposed working choice |
| 2026-11-21 | Preliminary metadata substitutions and pilot estimates need a reproducible audit before interpretation | Original field assignments remain partly unresolved | Working requirement |

### Progress log

#### 2026-11-21 — initial review and planning

- Inspected repository files at the source revision stated above and read the study notebooks.
- Inventoried disease-linked datasets and identified Hinds 2018 plus both 2019 reflectance workbooks.
- Audited temporal coverage and distinct observational units. Identified metadata and endpoint issues recorded as D01–D11.
- Ran exploratory trajectory prediction checks in a temporary analysis using linear levels/slopes and preliminary metadata assumptions. Performance varied across seasons, rotation alone was informative, and within-plot findings were inconsistent. Formal FDA analyses remain pending.
- Reviewed methodological and plant pathology literature. FDA has precedents in disease progress analysis and crop phenotyping. The novelty assessment remains specific to the biological questions and joint disease–reflectance evidence.
- Prepared the README and this living plan. The source data and earlier analysis notebooks remain the inputs for Phase 1.
- Next action is a version-controlled inventory and identifier reconciliation report, beginning with D01–D03 and D11.

#### 2026-11-22 — Phase 1 audit and archive corroboration

- Based `codex/sds-fda-phase1-audit` on the verified open draft PR #1 planning revision `aa05890b55021707da68aa0176572e7d82601260`. Repository input data remain at the audited source revision.
- Created the [R audit](analysis/01_audit.R), [audit report](audit/REPORT.md), [candidate unit registry](audit/tables/candidate_units.csv), [sampling coverage](audit/figures/sampling_coverage.png), and detailed evidence linked from the report. Preserved all source observations and flagged unresolved records without applying corrections.
- Cross-checked the separate SDS Paper project with a [reproducible archive script](analysis/02_check_sds_paper_sources.R). Located the full dissertation and Marsden yield files for all three seasons. Observed that the Hinds repository rating and yield values point to a different field-to-plot mapping, with 56 full trajectory and yield matches jointly pointing to the same archive plot.
- Kept 2019 reflectance descriptive. Verified 120 Marsden 2019 quadrats with two readings each and determined that the Hinds 2019 GIS sheet duplicates 2018 ratings. Retained actual assessment dates and provisional onset bounds.
- Followed up in the archive on the original layout and linkage. The 2017 tag map corroborates all six intended assignments, the phase diagram corroborates all 12 soybean plot rotations in 2018, and the Hinds combine sequence reproduces all 60 harvest plot keys. The original logger resolves the six Marsden spectra with one acquisition tag typo, and gives a candidate sequential pairing for Hinds 507/508. The archived radiometer draft and logger headers document CROPSCAN MSR87 and percent reflectance. See [audit evidence](audit/REPORT.md).
- Next action is to build the provenance-bearing registry, prepare the original-source Hinds severity cohort, and draft the Marsden 2016 within-season protocol. Check the remaining unresolved acquisition identities and rating or denominator differences.

#### 2026-11-22 — phase 2 cohorts and Marsden 2016 baseline

- Rebuilt the [Marsden 2016 and Hinds 2018 cohorts](analysis/03_prepare_phase2.R) using input fingerprints and source-specific keys. Hinds has 60 sequence-verified harvest records and 480 dated severities. Three severity ratings differ across archived versions. Twenty-four band rows from the two disputed August 3 acquisitions are flagged. Archive-derived records stay local.
- Wrote the [exploratory protocol](results/phase2/PROTOCOL.md) and fitted the visit-factor baseline and spline comparison at the main-plot level. The four-block paired S2 minus S3 difference was 33.0 percentage points at the final assessment. The conditional curve and AUDPC tests had the same tail area. Leave-one-block-out RMSE was essentially unchanged by smoothing, which generated small negative early predictions. Retain the visit-factor baseline for this cohort.
- Used last-negative and first-positive bounds for recorded onset, with incidence as a sensitivity definition. The timing descriptions are exploratory. Read the [baseline report](results/phase2/REPORT.md) for the differences, held-out metrics and remaining uncertainties.
- Next analysis is a Marsden 2016 disease–reflectance association protocol using the separate dates, followed by severity-version sensitivity checks at Hinds and extension of the Marsden cohort.

### Template for the next entry

```text
Date and phase
Research question or issue IDs addressed
Repository revision and source files
Work completed and output links
Findings and uncertainty
Decisions and changes to endpoints, exclusions, or models
Unresolved items and exact information needed
Next concrete action
```

## 12. Initial references and novelty map

| Reference | Relevance |
|---|---|
| [Raza et al., original handheld study in the 2017 APS abstract collection](https://doi.org/10.1094/PHYTO-107-12-S5.165) | Prior use and findings from Marsden 2016 canopy reflectance |
| [Raza et al. 2020, satellite SDS detection](https://doi.org/10.3390/rs12071213) | Established SDS remote-sensing contribution and overlapping field context |
| [Bi et al. 2020, GRU time-series satellite SDS detection](https://doi.org/10.3390/rs12213621) | Temporal prediction precedent using Marsden satellite data |
| [Herrmann et al. 2018, leaf and canopy SDS spectroscopy](https://doi.org/10.3390/rs10030426) | Prior pre-visual detection using spectroscopy |
| [Raza et al., SDS onset and yield](https://doi.org/10.1094/PDIS-07-21-1551-RE) | Existing onset–yield contribution that the functional analysis must extend |
| [From Scalar Summaries to Functional Comparisons, 2026](https://doi.org/10.1094/PHYTO-01-26-0009-LE) | Direct precedent for functional disease progress comparisons |
| [r4pde functional analysis documentation](https://emdelponte.github.io/r4pde/articles/functional-analysis.html) | Implementation and examples of design-adjusted disease curves and functional summaries |
| [Yao, Müller, and Wang 2005, sparse longitudinal FDA](https://doi.org/10.1198/016214504000001745) | Sparse curve estimation, covariance, and uncertainty |
| [Joint modelling of paired sparse functional data using principal components](https://pmc.ncbi.nlm.nih.gov/articles/PMC2672432/) | Joint disease–reflectance modeling framework |

Expand this map before manuscript commitment. Record each study's sensing platform, disease endpoint, sampling frequency, experimental design, FDA formulation, and validation. Keep prospective data-driven choices distinguishable from results established in earlier studies.
