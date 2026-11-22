# Marsden latest-spectrum early warning

November 22, 2026. Adding red and near-infrared reflectance to visit-by-cropping-system risk improved ranking among quadrats in the same plot and visit in 2018. Within-plot-visit AUROC was near 0.50 in 2016 and 2017. The augmented model lowered Brier score against the best non-spectral baseline by 0.0013 in 2017 and increased it in 2016 and 2018. [Protocol](PROTOCOL.md)

## First positive severity at the next visit

The target was first recorded severity above zero at the next assessment within ten days. The matched rows and whole-block folds came from the [eligibility and baseline analysis](REPORT.md) at `f76c160`. Each spectrum used 660 and 810 nm from the same latest acquisition 1–7 days before the landmark. The model added two standardized reflectance terms to the fixed visit-by-cropping-system log odds. Scaling, baseline rates, and ridge logistic slopes were estimated on the training blocks for each fold and season.

| Season | Model | Brier ↓ | Within-block AUROC ↑ | Average precision ↑ | Within-plot-visit AUROC ↑ |
|---|---|---:|---:|---:|---:|
| 2016 | Cropping system | 0.1596 | 0.647 | 0.282 | 0.500 |
| | Visit | 0.1497 | 0.726 | 0.323 | 0.500 |
| | Visit × cropping system | 0.1360 | 0.808 | 0.483 | 0.500 |
| | Visit × cropping system + spectrum | 0.1364 | 0.806 | 0.481 | 0.503 |
| 2017 | Cropping system | 0.1759 | 0.816 | 0.395 | 0.500 |
| | Visit | 0.1553 | 0.781 | 0.408 | 0.500 |
| | Visit × cropping system | 0.1399 | 0.832 | 0.506 | 0.500 |
| | Visit × cropping system + spectrum | 0.1386 | 0.826 | 0.503 | 0.510 |
| 2018 | Cropping system | 0.2531 | 0.571 | 0.442 | 0.500 |
| | Visit | 0.2472 | 0.478 | 0.353 | 0.500 |
| | Visit × cropping system | 0.2682 | 0.560 | 0.394 | 0.500 |
| | Visit × cropping system + spectrum | 0.2643 | 0.595 | 0.410 | 0.702 |

In 2017, within-block AUROC and average precision both decreased slightly relative to the offset baseline.

There were 153/731 detections in 2016 (20.9%), 70/281 in 2017 (24.9%), and 79/199 in 2018 (39.7%). Average precision pools held-out scores by season. The two stratified AUROCs weight by the number of positive–negative pairs. Within-plot-visit AUROC uses 30, 16, and 22 mixed-outcome plot-visits and 1,276, 200, and 265 pairs, respectively. All non-spectral models assign equal scores within each plot-visit. [All models and denominators](latest_spectrum_metrics.csv)

In 2018, within-plot-visit AUROC ranged from 0.653 to 0.865 across the four held-out blocks. The spectrum improved within-block AUROC and average precision relative to the interaction baseline. Visit alone still had the lowest Brier score and cropping system alone had the highest average precision. The 2018 primary Brier change relative to the interaction varied across held-out blocks, with three improvements and one worsening. [Block metrics](latest_spectrum_block_metrics.csv)

## Endpoint sensitivity

Changes below are relative to visit × cropping system on the same endpoint-specific rows. Positive Brier gains indicate lower error with spectra. The within-plot-visit baseline is 0.500 throughout.

| Endpoint | Season | Detections / opportunities | Mixed plot-visits | Brier gain | Δ within-block AUROC | Δ average precision | Spectral within-plot-visit AUROC |
|---|---:|---:|---:|---:|---:|---:|---:|
| Severity ≥5% | 2016 | 160/758 | 31 | +0.0005 | −0.003 | +0.011 | 0.509 |
| | 2017 | 70/291 | 17 | −0.0018 | −0.011 | −0.004 | 0.489 |
| | 2018 | 34/280 | 12 | −0.0094 | +0.006 | −0.014 | 0.642 |
| Incidence >0 | 2016 | 148/731 | 30 | −0.0011 | −0.003 | +0.001 | 0.506 |
| | 2017 | 70/281 | 16 | +0.0013 | −0.006 | −0.003 | 0.510 |
| | 2018 | 80/198 | 22 | +0.0018 | +0.042 | +0.017 | 0.696 |

The 2018 within-plot-visit ranking gain persisted for incidence and was smaller at 5% severity, where probability accuracy worsened. In 2017 the matched incidence and primary severity rows and outcomes were identical. The 2017 matched cohort covers 48% of primary-eligible opportunities, and all estimates reflect four blocks per season with repeated observations. The findings support a descriptive 2018 within-plot signal and limited incremental performance across the observed seasons. Trajectory models and cross-season transfer remain separate milestones.

## Reproduce

Run from the repository root. The first two scripts regenerate the eligibility and baseline predictions from audited inputs. The third validates the acquisition and row keys, then fits and scores the spectral model.

```sh
Rscript --vanilla analysis/08_marsden_disease_seasons.R
Rscript --vanilla analysis/09_marsden_early_warning.R
Rscript --vanilla analysis/10_marsden_latest_spectrum.R
```

Use fresh output directories via the scripts' optional directory arguments to check reproducibility. Detailed predictions and plot-visit metrics are written under the ignored `local/` directory. [R code](../../analysis/10_marsden_latest_spectrum.R) · [Software versions](latest_spectrum_software.csv)
