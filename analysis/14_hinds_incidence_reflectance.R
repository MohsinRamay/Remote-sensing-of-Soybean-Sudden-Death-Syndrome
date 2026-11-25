# Usage: Rscript analysis/14_hinds_incidence_reflectance.R <archive root> [output dir] [phase2 dir]
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% 1:3)
archive <- normalizePath(args[[1]], mustWork = TRUE)
out <- if (length(args) >= 2L) args[[2]] else "results/exploration"
phase2 <- if (length(args) == 3L) args[[3]] else "results/phase2"
dir.create(out, recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name) write.csv(data, file.path(out, paste0("hinds_", name, ".csv")),
                                            row.names = FALSE, na = "")
manifest <- read.csv("audit/evidence/sds_paper_source_manifest.csv")
read_archive <- function(file, sheet) {
  relative <- file.path("04_source_data/2018 Research/Hinds", file)
  path <- file.path(archive, relative)
  expected <- unique(manifest$sha256[manifest$file == relative & manifest$root_scope == "SDS Paper"])
  stopifnot(identical(digest::digest(path, algo = "sha256", file = TRUE), expected))
  readxl::read_excel(path, sheet, .name_repair = "unique_quiet")
}
severity <- read.csv(file.path(phase2, "local", "hinds2018_severity.csv")) |>
  mutate(date = as.Date(date))
entry <- read_archive("SDS Hinds.xlsx", "Reproductive Stage")
long <- read_archive("SDS Hinds.xlsx", "SDS") |>
  transmute(plot = Plot, date = as.Date(Date, tz = "UTC"), long_incidence = Incidence)
stand <- read_archive("Stand Count.xlsx", "Sheet1") |>
  transmute(plot = Plot, register_denominator = `Avg Std Count`)
first_columns <- grep("^[0-9]{5}$", names(entry))
wide <- bind_rows(lapply(first_columns, function(i) {
  stopifnot(identical(as.character(entry[1, i + 1:2]), c("Incidence", "Severity")))
  tibble(plot = entry$Plot[-1L],
         date = as.Date(as.integer(names(entry)[i]), origin = "1899-12-30"),
         symptomatic_plants = as.numeric(entry[[i]][-1L]),
         recorded_incidence = as.numeric(entry[[i + 1L]][-1L]),
         workbook_denominator = entry[["Avg Std Count"]][-1L])
}))
incidence <- severity |>
  inner_join(wide, by = c("plot", "date"), relationship = "one-to-one") |>
  inner_join(long, by = c("plot", "date"), relationship = "one-to-one") |>
  inner_join(stand, by = "plot", relationship = "many-to-one") |>
  mutate(workbook_recalculation = 100 * symptomatic_plants / workbook_denominator,
         register_recalculation = 100 * symptomatic_plants / register_denominator)
stopifnot(nrow(incidence) == 480L, !anyNA(incidence[c("recorded_incidence", "long_incidence")]),
          all(incidence$workbook_denominator > 0), all(incidence$register_denominator > 0))
save_csv(incidence |>
           group_by(date) |>
           summarise(counts_available = sum(is.finite(symptomatic_plants)),
                     incidence_field_long_disagreements = sum(abs(long_incidence - recorded_incidence) > 1e-7),
                     workbook_reproduced = sum(abs(recorded_incidence - workbook_recalculation) < 1e-7, na.rm = TRUE),
                     register_reproduced = sum(abs(recorded_incidence - register_recalculation) < 1e-7, na.rm = TRUE),
                     register_above_100 = sum(register_recalculation > 100, na.rm = TRUE),
                     median_abs_change_pp = if (any(is.finite(register_recalculation))) {
                       median(abs(register_recalculation - workbook_recalculation), na.rm = TRUE)
                     } else NA_real_, .groups = "drop"), "incidence_reconstruction")

# Compare recorded percentages on identical rows, including later visual ratings.
# Remove block and assigned treatment means before describing plot-level correlation.
partial_cor <- function(x, y, design) {
  r <- lm.fit(design, cbind(x, y))$residuals
  if (any(apply(r, 2L, sd) < 1e-12)) return(NA_real_)
  cor(r[, 1L], r[, 2L])
}
save_csv(incidence |>
           group_by(date) |>
           group_modify(function(data, key) {
             design <- model.matrix(~ factor(block) + treatment, data)
             tibble(plots = nrow(data),
                    entry_correlation = partial_cor(data$recorded_incidence, data$entry_severity, design),
                    long_correlation = partial_cor(data$long_incidence, data$severity, design))
           }) |>
           ungroup(), "joint_correlation")

spectra <- read.csv(file.path(phase2, "local", "hinds2018_reflectance.csv")) |>
  filter(eligible, wavelength_nm %in% c(660, 810)) |>
  mutate(acquisition = as.Date(date)) |>
  select(unit_id, acquisition, wavelength_nm, reflectance) |>
  pivot_wider(names_from = wavelength_nm, names_prefix = "nm", values_from = reflectance)
stopifnot(!anyNA(spectra[c("nm660", "nm810")]), !anyDuplicated(spectra[c("unit_id", "acquisition")]))
paired <- severity |>
  left_join(spectra, by = join_by(unit_id, closest(date >= acquisition)), relationship = "many-to-one") |>
  mutate(lag_days = as.integer(date - acquisition)) |>
  filter(lag_days %in% 0:4)
save_csv(paired |> count(date, acquisition, lag_days, name = "plot_visits"), "reflectance_coverage")

# Fit separate slopes for each block, adjusting jointly for plot and visit.
# Sensitivity removes the last supported date, and uses the entry severity version.
spectral_slopes <- function(data) {
  data |>
    pivot_longer(c(nm660, nm810), names_to = "band", values_to = "reflectance") |>
    group_by(block, band) |>
    group_modify(function(data, key) {
      x <- data$severity / 10
      y <- data$reflectance
      r <- lm.fit(model.matrix(~ factor(plot) + factor(date), data), cbind(x, y))$residuals
      tibble(pooled = cov(x, y) / var(x),
             adjusted = sum(r[, 1L] * r[, 2L]) / sum(r[, 1L]^2),
             plot_visits = nrow(data), dates = n_distinct(data$date))
    }) |>
    ungroup() |>
    pivot_longer(c(pooled, adjusted), names_to = "model", values_to = "slope") |>
    filter(is.finite(slope))
}
bind_rows(
  mutate(spectral_slopes(paired), scenario = "Long reference"),
  mutate(spectral_slopes(mutate(paired, severity = entry_severity)), scenario = "Entry sheet"),
  mutate(spectral_slopes(filter(paired, date < max(date))), scenario = "Drop latest assessment"),
  mutate(spectral_slopes(filter(paired, lag_days > 0)), scenario = "Strictly prior"),
  mutate(spectral_slopes(filter(paired, acquisition != as.Date("2018-08-03"))),
         scenario = "Drop disputed acquisition date")
) |>
  group_by(scenario, band, model) |>
  summarise(blocks = n(), plot_visits = sum(plot_visits), dates = max(dates),
            estimate = mean(slope), minimum = min(slope), maximum = max(slope), .groups = "drop") |>
  save_csv("reflectance_slopes")
