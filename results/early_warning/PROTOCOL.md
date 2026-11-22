# Marsden early-warning eligibility and baseline

## Prediction target and inputs

A landmark is a recorded scouting assessment. Score a quadrat immediately after its rating is available if it has had no positive rating through that visit and has a next scheduled rating within ten days. Predict whether that next rating is the first positive. Use severity above zero for the primary endpoint, with incidence above zero and first severity of at least 5% as sensitivity definitions. Predict first *recorded* detection at the next assessment. The elapsed time can vary across visits, and the biological onset time within the interval is unknown.

Maintain one record per quadrat, landmark, and endpoint, including ineligible records. Mark earlier or concurrent detections before checking follow-up availability. Treat a missing or out-of-window next visit as unscored. Keep all eligible repeat observations in the same block fold. The resulting estimand is risk per eligible scouting opportunity within a season.

Define a second eligibility flag for the future matched spectral comparison. Require both 660 and 810 nm at a single acquisition strictly before the landmark and no more than seven days earlier. Take the latest eligible acquisition per quadrat. Same-day spectra are outside this flag because acquisition order is unknown. Match spectra by audited quadrat and season, and obtain cropping system and block from the verified disease registry. This phase measures spectral coverage and runs the baseline on both denominators.

## Validation and baselines

Within each season, hold out one entire block at a time. For each endpoint and denominator, compare constant risk, cropping-system-only risk, visit-only risk, and visit-by-cropping-system risk. The latter two control for the known scouting date and are additional comparators for the later spectral analysis. Estimate rates in training using `(events + 0.5) / (observations + 1)`. Where a group is absent in training, use the training overall rate for the single-factor models. For the interaction, fall back to the training visit rate where available. Record fallback use.

Report out-of-fold prevalence, Brier score, AUROC, and average precision separately by season, endpoint and denominator. Rank scores with tied values handled together. In addition to pooled out-of-fold AUROC, report a within-block AUROC weighted by the number of positive–negative pairs in each held-out block. This avoids ranking scores from different fitted models against one another. Give each eligible scouting opportunity equal weight. Report the number of mixed-outcome plot-by-landmark groups to show support for future within-plot discrimination. Whole-block validation targets other blocks in the same observed season. Cross-season transfer, threshold selection, and a spectral model are separate analyses.

## Latest-spectrum comparison

Use the spectrum-matched eligibility and held-out baseline tables defined at revision `f76c160`. Join percent reflectance at 660 and 810 nm by season, audited quadrat and the frozen acquisition date. Verify that it is the latest strictly prior date with both bands. Use the verified disease-registry labels for block and cropping system.

Within each season, endpoint and training fold, center and scale each band by its training mean and sample standard deviation. Fit a two-slope logistic model with the smoothed visit-by-cropping-system log-odds as a fixed offset, including its documented fallbacks. The offset uses the same training blocks as the slopes. Use no additional intercept and fix the ridge penalty to one half the sum of the squared standardized slopes on the summed log-loss scale. This stabilizes the fit without tuning and isolates the addition of the two bands. Apply the training estimates to the held-out block and verify that its offset probabilities reproduce the corresponding frozen baseline predictions.

Compare held-out Brier score, pair-weighted within-block AUROC and pooled average precision across all five models, with prevalence reported for context. Compute within-plot-visit AUROC by comparing positive–negative quadrat pairs sharing a block, plot and landmark, giving ties half credit and each pair equal weight. Only mixed-outcome plot-visits contribute. Report the number of contributing plot-visits and pairs. Use the same procedure on the separately defined 5% severity and positive-incidence risk sets. Interpret within-season comparisons descriptively given four blocks and repeated scouting opportunities.
