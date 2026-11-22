# Run from the repository root after analysis/03_prepare_phase2.R.
# Optional arguments: output directory, then the Phase 2 output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("analysis/marsden_q4_methods.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1]] else "results/phase3"
prepared <- if (length(args) == 2L) args[[2]] else "results/phase2"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, filename) {
  write.csv(data, file.path(out, filename), row.names = FALSE, na = "")
}
bands <- c(660L, 810L)
disease <- read.csv(file.path(prepared, "local", "marsden2016_disease.csv")) |>
  transmute(unit_id, plot_id, block, rotation, assessment = as.Date(date),
            severity_10pp = severity / 10)
spectra <- read.csv(file.path(prepared, "local", "marsden2016_reflectance.csv")) |>
  filter(wavelength_nm %in% bands) |>
  transmute(unit_id, acquisition = as.Date(date), wavelength_nm, reflectance)
stopifnot(!anyNA(disease), !anyNA(spectra), !anyDuplicated(disease[c("unit_id", "assessment")]),
          !anyDuplicated(spectra[c("unit_id", "acquisition", "wavelength_nm")]))

pairs <- marsden_date_support(disease, spectra)
save_csv(pairs, "marsden2016_date_support.csv")
same_dates <- filter(pairs, use_preceding, use_interpolation)
prior <- disease |>
  inner_join(transmute(filter(pairs, use_preceding), assessment, acquisition = previous),
             by = "assessment", relationship = "many-to-one") |>
  inner_join(spectra, by = c("unit_id", "acquisition"), relationship = "one-to-many")
interpolated <- disease |>
  inner_join(same_dates, by = "assessment", relationship = "many-to-one") |>
  inner_join(rename(spectra, previous = acquisition, previous_value = reflectance),
             by = c("unit_id", "previous"), relationship = "one-to-many") |>
  inner_join(rename(spectra, following = acquisition, following_value = reflectance),
             by = c("unit_id", "following", "wavelength_nm"), relationship = "many-to-one") |>
  mutate(weight = previous_days / pmax(previous_days + following_days, 1),
         reflectance = previous_value + weight * (following_value - previous_value))
check_panel <- function(data, expected_dates) {
  stopifnot(nrow(data) == 240L * length(bands) * expected_dates,
            n_distinct(data$assessment) == expected_dates,
            n_distinct(data$block) == 4L, n_distinct(data$plot_id) == 12L,
            all(count(data, unit_id, wavelength_nm)$n == expected_dates),
            all(count(data, plot_id, assessment, wavelength_nm)$n == 20L))
}
check_panel(prior, sum(pairs$use_preceding))
check_panel(interpolated, nrow(same_dates))

block_slopes <- fit_block_slopes(prior)
estimates <- summarize_blocks(block_slopes)
save_csv(block_slopes, "marsden2016_reflectance_block_slopes.csv")
save_csv(estimates, "marsden2016_reflectance_estimates.csv")

timing <- bind_rows(
  summarize_blocks(fit_block_slopes(semi_join(prior, same_dates, by = "assessment"))) |>
    mutate(date_alignment = "Preceding on shared dates"),
  summarize_blocks(fit_block_slopes(interpolated)) |>
    mutate(date_alignment = "Interpolated on shared dates")
) |>
  filter(specification == "quadrat_plot_visit")
save_csv(timing, "marsden2016_reflectance_timing_sensitivity.csv")

leave_one <- bind_rows(lapply(sort(unique(prior$assessment)), function(index) {
  omitted <- as.Date(index, origin = "1970-01-01")
  summarize_blocks(fit_block_slopes(filter(prior, assessment != omitted))) |>
    filter(specification == "quadrat_plot_visit") |>
    mutate(omitted_assessment = omitted)
}))
save_csv(leave_one, "marsden2016_reflectance_leave_date_out.csv")

# Check the primary slope against an explicit fixed-effects regression in each block and band.
for (band in bands) {
  for (field_block in sort(unique(prior$block))) {
    data <- filter(prior, wavelength_nm == band, block == field_block)
    reference <- coef(lm(reflectance ~ severity_10pp + factor(unit_id) +
                          interaction(plot_id, assessment), data = data))[["severity_10pp"]]
    fast <- filter(block_slopes, wavelength_nm == band, block == field_block,
                   specification == "quadrat_plot_visit")$slope_pp
    stopifnot(isTRUE(all.equal(fast, reference, tolerance = 1e-9)))
  }
}

figure <- estimates |>
  mutate(band = paste(wavelength_nm, "nm"),
         adjustment = factor(specification, levels = c("quadrat_plot_visit", "plot_visit", "pooled"),
                             labels = c("Plot × visit and quadrat", "Plot × visit", "Pooled within block"))) |>
  ggplot(aes(estimate_pp, adjustment, xmin = lower_pp, xmax = upper_pp)) +
  geom_vline(xintercept = 0, colour = "grey55") +
  geom_pointrange(colour = "#216C60", linewidth = 0.55) +
  facet_wrap(vars(band), ncol = 2, scales = "free_x") +
  scale_x_continuous(n.breaks = 5) +
  labs(title = "Marsden 2016 canopy reflectance and recorded SDS severity",
       x = "Reflectance difference per 10 percentage points of severity",
       y = NULL, caption = "Points average four block slopes. Intervals describe between-block variability. Horizontal scales differ.") +
  theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), panel.spacing.x = grid::unit(1.4, "lines"),
        plot.title.position = "plot",
        plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "marsden2016_reflectance_associations.png"), figure, width = 10,
       height = 4.1, dpi = 180, bg = "white", device = ragg::agg_png)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg")
save_csv(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                  vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software.csv")
