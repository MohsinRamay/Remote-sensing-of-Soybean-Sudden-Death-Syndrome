# Run from the repository root:
# Rscript analysis/03_prepare_phase2.R [output directory] [SDS Paper root]
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1]] else "results/phase2"
local <- file.path(out, "local")
dir.create(local, recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name, detail = FALSE) {
  write.csv(data, file.path(if (detail) local else out, paste0(name, ".csv")),
            row.names = FALSE, na = "")
}
assert_key <- function(data, keys) {
  stopifnot(nrow(data) > 0, !anyNA(data[keys]), !anyDuplicated(data[keys]))
}
assert_rating <- function(values) {
  stopifnot(all(is.na(values) | is.finite(values) & values >= 0 & values <= 100))
}
repos <- read.csv("audit/tables/inventory.csv")
manifest <- read.csv("audit/evidence/sds_paper_source_manifest.csv")
verify_hash <- function(path, relative, inventory) {
  expected <- unique(inventory$sha256[inventory$file == relative])
  sha256 <- digest::digest(path, algo = "sha256", file = TRUE)
  stopifnot(length(expected) == 1L, sha256 == expected)
  sha256
}
read_repo <- function(path) {
  verify_hash(path, path, repos)
  read.csv(path) |> mutate(source_row = row_number() + 1L)
}
plot_key <- function(site, year, block, plot) paste(site, year, block, plot, sep = "/")
unit_key <- function(site, year, unit) paste(site, year, unit, sep = "/")

disease_file <- "data/Marsden_SDS.csv"
m_disease <- read_repo(disease_file) |>
  filter(ID == "SDS_2016") |>
  transmute(date = as.Date(Date), block = Block, plot = Plot, quadrat = Quadrat, rotation = Rotation,
            plot_id = plot_key("Marsden", 2016L, block, plot),
            unit_id = unit_key("Marsden", 2016L, quadrat),
            severity = Severity, incidence = Incidence, source_file = disease_file, source_row)
m_units <- distinct(m_disease, unit_id, quadrat, plot_id, plot, block, rotation)
assert_key(m_disease, c("unit_id", "date"))
assert_key(m_units, "unit_id")
assert_rating(m_disease$severity)
assert_rating(m_disease$incidence)
m_plot_visits <- count(m_disease, block, plot, rotation, date)
stopifnot(nrow(m_units) == 240L, n_distinct(m_units$plot_id) == 12L,
          nrow(m_plot_visits) == 72L, all(m_plot_visits$n == 20L),
          all(count(m_units, block, rotation)$n == 20L))

reflectance_file <- "data/Marsden_RFL.csv"
m_reflectance <- read_repo(reflectance_file) |>
  filter(startsWith(DATE, "2016-")) |>
  transmute(unit_id = unit_key("Marsden", 2016L, Quadrat), date = as.Date(DATE),
            block = Block, plot = Plot, rotation = Rotation, wavelength_nm = Wavelength,
            reflectance = Reflectance, source_file = reflectance_file, source_row)
assert_key(m_reflectance, c("unit_id", "date", "wavelength_nm"))
stopifnot(nrow(m_reflectance) == 23040L,
          all(count(m_reflectance, unit_id, date)$n == 8L),
          nrow(anti_join(m_reflectance, m_units, by = c("unit_id", "block", "plot", "rotation"))) == 0L)
save_csv(m_units, "marsden2016_units", TRUE)
save_csv(m_disease, "marsden2016_disease", TRUE)
save_csv(m_reflectance, "marsden2016_reflectance", TRUE)

marsden_coverage <- tibble(cohort = "Marsden 2016", blocks = n_distinct(m_units$block),
                   plots = n_distinct(m_units$plot_id), units = nrow(m_units),
                   severity_visits = n_distinct(m_disease$date), severity_rows = nrow(m_disease),
                   spectra_visits = n_distinct(m_reflectance$date), spectral_band_rows = nrow(m_reflectance),
                   excluded_band_rows = 0L, linked_yield_units = NA_integer_)

save_csv(marsden_coverage, "marsden2016_cohort_coverage")

if (length(args) == 2L) {
  archive <- normalizePath(args[[2]], mustWork = TRUE)
  source_folder <- "04_source_data/2018 Research/Hinds"
  read_hinds <- function(file, sheet) {
    relative <- file.path(source_folder, file)
    path <- file.path(archive, relative)
    verify_hash(path, relative, filter(manifest, root_scope == "SDS Paper"))
    readxl::read_excel(path, sheet, .name_repair = "unique_quiet", guess_max = 100000) |>
      mutate(source_row = row_number() + 1L)
  }
  field_file <- "SDS Hinds.xlsx"
  design_file <- "Hinds Experiment Sheet.xlsx"
  combined_file <- "Yield/Hinds Yield.xlsx"
  cultivar_key <- c("1" = "Pioneer P20T79R2", "2" = "Syngenta NK Soybean S24-K2")
  h_design <- read_hinds(design_file, "Sheet1") |>
    transmute(block = Block, plot = Plot, treatment = Trt, variety_code = Varirty,
              variety = unname(cultivar_key[as.character(Varirty)]),
              dose_ml_per_ft = Conc, design_file, design_sheet = "Sheet1",
              design_row = source_row, plot_id = plot_key("Hinds", 2018L, block, plot),
              unit_id = unit_key("Hinds", 2018L, plot))
  assert_key(h_design, "plot")
  stopifnot(nrow(h_design) == 60L, all(count(h_design, block)$n == 10L),
            all(count(h_design, variety_code, dose_ml_per_ft)$n == 6L),
            all(count(h_design, block, variety_code, dose_ml_per_ft)$n == 1L),
            !anyNA(h_design$variety))
  h_disease <- read_hinds(field_file, "SDS") |>
    transmute(date = as.Date(Date, tz = "UTC"), block = Block, plot = Plot, treatment = Trt,
              variety_code = Varirty, dose_ml_per_ft = Conc, severity = Severity,
              field_file, rating_sheet = "SDS", rating_row = source_row)
  assert_key(h_disease, c("plot", "date"))
  assert_rating(h_disease$severity)
  h_disease <- inner_join(h_disease, h_design,
                          by = c("block", "plot", "treatment", "variety_code", "dose_ml_per_ft"),
                          relationship = "many-to-one")
  stopifnot(nrow(h_disease) == 480L, all(count(h_disease, date)$n == 60L))

  entry <- read_hinds(field_file, "Reproductive Stage")
  first_columns <- grep("^[0-9]{5}$", names(entry))
  h_entry <- bind_rows(lapply(first_columns, function(i) {
    severity_column <- i + 2L
    stopifnot(entry[[severity_column]][[1]] == "Severity")
    tibble(plot = entry$Plot[-1], date = as.Date(as.integer(names(entry)[[i]]), origin = "1899-12-30"),
           entry_severity = as.numeric(entry[[severity_column]][-1]),
           entry_sheet = "Reproductive Stage", entry_row = entry$source_row[-1],
           entry_column = severity_column)
  }))
  assert_key(h_entry, c("plot", "date"))
  assert_rating(h_entry$entry_severity)
  h_disease <- left_join(h_disease, h_entry, by = c("plot", "date"), relationship = "one-to-one") |>
    mutate(severity_versions_agree = coalesce(abs(severity - entry_severity) <= 1e-7, FALSE))

  h_yield <- read_hinds(combined_file, "Sheet1") |>
    transmute(plot = Plot, sequence = Sr, area_sq_ft = `H. Area (sq ft)`,
              yield_bu_per_ac = `Adj. Plot Yield (bu/Ac)`, yield_file = combined_file,
              yield_sheet = "Sheet1", yield_row = source_row)
  assert_key(h_yield, "plot")
  sequence_file <- file.path(source_folder, "Yield/MRHSDS.csv")
  sequence_path <- file.path(archive, sequence_file)
  verify_hash(sequence_path, sequence_file, filter(manifest, root_scope == "SDS Paper"))
  sequence <- as.integer(readLines(sequence_path))
  stopifnot(identical(as.numeric(sequence[sequence != 999L]), arrange(h_yield, sequence)$plot),
            !anyNA(h_yield[c("yield_bu_per_ac", "area_sq_ft")]),
            all(h_yield$area_sq_ft > 0))
  h_yield <- inner_join(h_yield, select(h_design, plot, unit_id, plot_id), by = "plot",
                        relationship = "one-to-one")
  stopifnot(nrow(h_yield) == 60L)
  h_file <- "data/Hinds_RFL.csv"
  h_reflectance <- read_repo(h_file) |>
    transmute(unit_id = unit_key("Hinds", 2018L, Plot), block = Block, plot = Plot, date = as.Date(DATE),
              observed_treatment = Treatment, observed_variety = Variety,
              observed_dose_ml_per_ft = Concentration, wavelength_nm = Wavelength,
              reflectance = Reflectance, source_file = h_file, source_row,
              eligible = !(date == as.Date("2018-08-03") & plot %in% c(507L, 508L)),
              eligibility_note = if_else(eligible, "eligible", "disputed August 3 reading identities"))
  assert_key(filter(h_reflectance, eligible), c("unit_id", "date", "wavelength_nm"))
  stopifnot(nrow(anti_join(h_reflectance, h_design, by = "unit_id")) == 0L,
            all(count(filter(h_reflectance, eligible), unit_id, date)$n == 8L),
            nrow(anti_join(filter(h_reflectance, eligible), h_design,
                           by = c("unit_id", "block", "observed_treatment" = "treatment",
                                  "observed_variety" = "variety",
                                  "observed_dose_ml_per_ft" = "dose_ml_per_ft"))) == 0L)
  save_csv(h_design, "hinds2018_units", TRUE)
  save_csv(h_disease, "hinds2018_severity", TRUE)
  save_csv(h_yield, "hinds2018_yield", TRUE)
  save_csv(h_reflectance, "hinds2018_reflectance", TRUE)
  save_csv(summarise(h_disease, comparable = sum(!is.na(entry_severity) & !is.na(severity)),
                     disagreements = sum(!severity_versions_agree),
                     any_positive_disagreements = sum((entry_severity > 0) != (severity > 0),
                                                     na.rm = TRUE),
                     max_disagreement_pp = max(abs(entry_severity - severity), na.rm = TRUE)),
           "hinds_severity_version_check")
  hinds_coverage <- tibble(
    cohort = "Hinds 2018", blocks = n_distinct(h_design$block), plots = nrow(h_design),
    units = nrow(h_design), severity_visits = n_distinct(h_disease$date),
    severity_rows = nrow(h_disease), spectra_visits = n_distinct(h_reflectance$date),
    spectral_band_rows = sum(h_reflectance$eligible), excluded_band_rows = sum(!h_reflectance$eligible),
    linked_yield_units = nrow(h_yield))
  save_csv(hinds_coverage, "hinds2018_cohort_coverage")
}
