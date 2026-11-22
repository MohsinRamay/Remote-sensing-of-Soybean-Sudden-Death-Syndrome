# Marsden 2016 disease and reflectance protocol

## Question and date support

For Q4, estimate how canopy reflectance varies with foliar severity after accounting for stable quadrat differences and the shared changes in each plot over time. Use the audited Marsden 2016 cohort. Analyze the red band at 660 nm and the near-infrared band at 810 nm. They represent different canopy responses to disease and seasonal development. Earlier SDS spectroscopy also identifies associations in the red and near-infrared regions. [Herrmann et al. 2018](https://www.mdpi.com/2072-4292/10/3/426)

There are no same-day acquisitions and ratings. Pair each rating with the latest available spectrum on or before the rating date, within four calendar days. Use the same date rule for every quadrat and band. Keep the original dates and report which visits the rule drops. The result links reflectance to a later rating of recorded severity. The actual symptom state at acquisition is unobserved.

For a date-alignment sensitivity check, linearly interpolate between observed spectra bracketing a rating, with each bracket endpoint at most seven days away. Compare interpolation to the earlier-spectrum rule on the assessment dates eligible under both. Interpolation is retrospective and can use later observations. It assumes locally linear change across the bracket and serves only as a sensitivity check.

## Estimand and comparison

Report reflectance percentage points per 10 percentage points of recorded severity. Fit separate slopes in each of four field blocks and average them with equal block weights. Fit three descriptive specifications using the same observations. The first pools dates and plots within each block. The second absorbs plot-by-assessment-pair fixed effects. These account for all observed differences shared by quadrats of the same plot at a visit pair, including cropping system, common seasonal change and plot-specific seasonal trends. The primary specification adds quadrat fixed effects to remove stable differences among quadrats.

The repeated observations identify changes relative to other quadrats in the same plot over time. They leave local, time-varying canopy condition as a possible explanation. Use pointwise 95% t intervals across the four block slopes as descriptive precision summaries. The small number of blocks limits precision. The associations are observational and one-season estimates. Compare them across blocks and exclude each assessment in turn to check dependence on particular dates. These analyses do not estimate onset prediction or an SDS-specific causal effect.
