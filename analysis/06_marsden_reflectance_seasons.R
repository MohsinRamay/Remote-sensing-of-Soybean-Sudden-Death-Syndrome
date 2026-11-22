# Run from the repository root. Optional argument sets the output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
source("analysis/marsden_q4_methods.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
out <- if (length(args)) args[[1]] else "results/phase3_seasons"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name) {
  write.csv(data, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}
bands <- c(660L, 810L)
inventory <- read.csv("audit/tables/inventory.csv")
read_input <- function(path) {
  hash <- unique(inventory$sha256[inventory$file == path])
  stopifnot(identical(digest::digest(path, algo = "sha256", file = TRUE), hash))
  read.csv(path)
}
corrections <- read.csv("audit/evidence/marsden_metadata_correction_candidates.csv",
                        colClasses = c(key_value = "character", original = "character",
                                       preferred = "character"))
disease <- read_input("data/Marsden_SDS.csv") |>
  transmute(year = as.integer(substr(Date, 1, 4)), assessment = as.Date(Date),
            unit_id = as.character(Quadrat), block = Block, plot_id = Plot,
            rotation = Rotation, severity_10pp = Severity / 10)
spectra <- read_input("data/Marsden_RFL.csv") |>
  transmute(year = as.integer(substr(DATE, 1, 4)), acquisition = as.Date(DATE),
            unit_id = as.character(Quadrat), block = Block, plot_id = Plot,
            rotation = Rotation, wavelength_nm = Wavelength, reflectance = Reflectance)
stopifnot(!anyNA(disease), !anyNA(spectra),
          !anyDuplicated(disease[c("year", "unit_id", "assessment")]),
          !anyDuplicated(spectra[c("year", "unit_id", "acquisition", "wavelength_nm")]))
spectra$corrected <- FALSE
field_names <- c(block = "block", plot = "plot_id", rotation = "rotation")
identifier_names <- c(Quadrat = "unit_id", Plot = "plot_id")
corrections$band_cells_updated <- 0L
for (i in seq_len(nrow(corrections))) {
  correction <- corrections[i, ]
  field <- field_names[[correction$field]]
  key <- identifier_names[[correction$key_field]]
  rows <- which(spectra$year == correction$year & spectra$acquisition == as.Date(correction$date) &
                  as.character(spectra[[key]]) == correction$key_value)
  stopifnot(length(rows) > 0L, all(as.character(spectra[[field]][rows]) == correction$original))
  preferred <- correction$preferred
  if (is.numeric(spectra[[field]])) preferred <- as.integer(preferred)
  spectra[[field]][rows] <- preferred
  spectra$corrected[rows] <- TRUE
  corrections$band_cells_updated[i] <- length(rows)
}
save_csv(corrections, "applied_metadata_corrections")

metadata <- distinct(disease, year, unit_id, block, plot_id, rotation)
stopifnot(!anyDuplicated(metadata[c("year", "unit_id")]))
linked <- semi_join(spectra, metadata, by = c("year", "unit_id"))
keys <- c("year", "unit_id", "block", "plot_id", "rotation")
stopifnot(nrow(anti_join(linked, metadata, by = keys)) == 0L)
# Retain all acquisition dates for coverage, then match disease-linked quadrats.
fit_spectra <- filter(spectra, wavelength_nm %in% bands)
valid_keys <- c("unit_id", "assessment", "wavelength_nm")

run_season <- function(season) {
  ratings <- filter(disease, year == season) |> select(-year)
  measurements <- filter(fit_spectra, year == season) |> select(-year)
  pair_dates <- marsden_date_support(ratings, measurements)
  prior <- ratings |>
    inner_join(transmute(filter(pair_dates, use_preceding), assessment, acquisition = previous),
               by = "assessment", relationship = "many-to-one") |>
    inner_join(measurements, by = c("unit_id", "acquisition", "block", "plot_id", "rotation"),
               relationship = "one-to-many")
  stopifnot(!anyDuplicated(prior[valid_keys]), all(count(prior, unit_id, assessment)$n == length(bands)))
  coverage <- pair_dates |>
    left_join(count(ratings, assessment, name = "rated_quadrats"), by = "assessment") |>
    left_join(prior |>
                distinct(assessment, unit_id, corrected) |>
                group_by(assessment) |>
                summarise(paired_quadrats = n(), corrected_quadrats = sum(corrected), .groups = "drop"),
              by = "assessment") |>
    mutate(across(c(paired_quadrats, corrected_quadrats), ~ coalesce(.x, 0L)))
  block_coverage <- prior |>
    group_by(assessment, block, rotation) |>
    summarise(quadrats = n_distinct(unit_id), .groups = "drop") |>
    complete(assessment, nesting(block, rotation), fill = list(quadrats = 0L))

  severity_support <- prior |>
    distinct(assessment, block, unit_id, severity_10pp) |>
    group_by(assessment, block) |>
    summarise(quadrats = n(), rated_positive = sum(severity_10pp > 0),
              mean_severity_percent = mean(severity_10pp * 10),
              max_severity_percent = max(severity_10pp * 10), .groups = "drop")
  slopes <- fit_block_slopes(prior)
  for (band in bands) {
    for (field_block in sort(unique(prior$block))) {
      records <- filter(prior, wavelength_nm == band, block == field_block)
      full <- coef(lm(reflectance ~ severity_10pp + factor(unit_id) +
                       interaction(plot_id, assessment), data = records))[["severity_10pp"]]
      partial <- filter(slopes, wavelength_nm == band, block == field_block,
                        specification == "quadrat_plot_visit")$slope_pp
      stopifnot(isTRUE(all.equal(full, partial, tolerance = 1e-9)))
    }
  }
  estimates <- summarize_blocks(slopes)
  first_last <- sort(unique(prior$assessment))
  latest_two <- tail(first_last, 2L)

  common <- filter(pair_dates, use_preceding, use_interpolation)
  spectra_values <- select(measurements, unit_id, acquisition, wavelength_nm, reflectance)
  brackets <- prior |>
    semi_join(common, by = "assessment") |>
    inner_join(select(common, assessment, following, previous_days, following_days),
               by = "assessment", relationship = "many-to-one") |>
    inner_join(rename(spectra_values, following = acquisition, following_value = reflectance),
               by = c("unit_id", "following", "wavelength_nm"), relationship = "many-to-one")
  stopifnot(n_distinct(brackets$assessment) >= 2L)
  interpolate <- brackets |>
    mutate(reflectance = reflectance + previous_days / pmax(previous_days + following_days, 1) *
             (following_value - reflectance))
  complete_units <- count(prior, unit_id, wavelength_nm) |>
    filter(n == length(first_last)) |> distinct(unit_id)
  subsets <- list("Primary" = prior,
                  "Latest two assessments" = filter(prior, assessment %in% latest_two),
                  "Preceding on interpolation support" = brackets,
                  "Interpolated on common support" = interpolate,
                  "Complete quadrat panels" = semi_join(prior, complete_units, by = "unit_id"))
  if (length(first_last) > 2L) {
    subsets[["Exclude latest assessment"]] <- filter(prior, assessment != max(first_last))
  }
  sensitivity <- bind_rows(lapply(names(subsets), function(label) {
    sample <- subsets[[label]]
    result <- summarize_blocks(fit_block_slopes(sample)) |>
      filter(specification == "quadrat_plot_visit") |>
      mutate(sensitivity = label, assessment_count = n_distinct(sample$assessment),
             first_assessment = min(sample$assessment), last_assessment = max(sample$assessment),
             quadrats = n_distinct(sample$unit_id))
    result
  }))
  outputs <- list(date_support = coverage, block_date_support = block_coverage,
                  severity_support = severity_support,
                  block_slopes = slopes, estimates = estimates, sensitivity = sensitivity)
  lapply(outputs, function(table) mutate(table, year = season, .before = 1))
}
years <- 2016:2018
seasons <- lapply(years, run_season)
for (table in names(seasons[[1L]])) {
  save_csv(bind_rows(lapply(seasons, function(season) season[[table]])), table)
}
comparison <- bind_rows(lapply(seasons, function(season) season$sensitivity))
figure <- comparison |>
  filter(sensitivity %in% c("Primary", "Exclude latest assessment", "Latest two assessments"),
         year != 2017L | sensitivity != "Latest two assessments") |>
  mutate(season = factor(year), band = paste(wavelength_nm, "nm"),
         sensitivity = factor(sensitivity, levels = c("Primary", "Latest two assessments",
                                                       "Exclude latest assessment"))) |>
  ggplot(aes(estimate_pp, season, xmin = lower_pp, xmax = upper_pp,
             colour = sensitivity, shape = sensitivity)) +
  geom_vline(xintercept = 0, colour = "grey55") +
  geom_pointrange(position = position_dodge(width = 0.55), orientation = "y") +
  facet_wrap(vars(band), scales = "free_x", ncol = 2) +
  scale_x_continuous(n.breaks = 5) +
  scale_colour_manual(values = c("#216C60", "#40558F", "#AB4938")) +
  labs(title = "Marsden disease–reflectance associations by season",
       x = "Reflectance difference per 10 percentage points of severity", y = NULL,
       colour = NULL, shape = NULL,
       caption = "Four-block estimates and pointwise intervals. The bands use different horizontal scales.") +
  theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), panel.spacing.x = grid::unit(1.5, "lines"),
        legend.position = "bottom", plot.title.position = "plot",
        plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "seasonal_associations.png"), figure, width = 11, height = 4.6,
       dpi = 180, bg = "white", device = ragg::agg_png)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg", "digest")
save_csv(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                  vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software")
