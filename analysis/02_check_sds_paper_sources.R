# Optional corroboration using the separately held SDS Paper project.
# Usage: Rscript analysis/02_check_sds_paper_sources.R <project-root> <output-directory> [ISU Work root]
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% c(2L, 3L), dir.exists(args[[1]]))
project <- normalizePath(args[[1]], mustWork = TRUE)
out <- args[[2]]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
save_table <- function(data, name) {
  write.csv(data, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}

manifest <- list()
record_source <- function(relative, section, data, root = project) {
  full <- file.path(root, relative)
  manifest[[length(manifest) + 1L]] <<- tibble(
    root_scope = if (identical(root, project)) "SDS Paper" else "ISU Work",
    file = relative, sheet = as.character(section), rows = nrow(data), columns = ncol(data),
    sha256 = digest::digest(full, algo = "sha256", file = TRUE)
  )
}
read_evidence <- function(relative, sheet) {
  relative <- file.path("04_source_data", relative)
  data <- readxl::read_excel(file.path(project, relative), sheet, guess_max = 100000,
                            .name_repair = "unique_quiet")
  record_source(relative, sheet, data)
  data
}
check <- function(label, repo, archive, key, fields) {
  stopifnot(!anyDuplicated(repo[key]), !anyDuplicated(archive[key]))
  paired <- full_join(mutate(repo, in_repo = TRUE), mutate(archive, in_archive = TRUE),
                      by = key, suffix = c(".repo", ".archive"), relationship = "one-to-one")
  paired_fields <- paired |> filter(in_repo, in_archive)
  discrepancies <- list()
  rows <- lapply(fields, function(field) {
    x <- paired_fields[[paste0(field, ".repo")]]
    y <- paired_fields[[paste0(field, ".archive")]]
    equal <- if (is.numeric(x) && is.numeric(y)) abs(x - y) <= 1e-7 else x == y
    same <- coalesce(equal, is.na(x) & is.na(y))
    discrepancies[[field]] <<- bind_cols(paired_fields[!same, key, drop = FALSE],
                                        tibble(field, repository = as.character(x[!same]),
                                               archive = as.character(y[!same])))
    tibble(comparison = label, field, repo_rows = nrow(repo), archive_rows = nrow(archive),
           shared_keys = nrow(paired_fields), repo_only = sum(is.na(paired$in_archive)),
           archive_only = sum(is.na(paired$in_repo)), different_values = sum(!same),
           max_abs_difference = if (is.numeric(x) && is.numeric(y) && length(x)) {
             max(abs(x - y), na.rm = TRUE)
           } else NA_real_,
           different_positive_status = if (field %in% c("Incidence", "Severity")) {
             sum((x > 0) != (y > 0), na.rm = TRUE)
           } else NA_integer_)
  })
  save_table(paired |> filter(is.na(in_repo) | is.na(in_archive)),
             paste0(label, "_unmatched_keys"))
  save_table(bind_rows(discrepancies), paste0(label, "_value_differences"))
  bind_rows(rows)
}

marsden <- read.csv("data/Marsden_SDS.csv")
hinds <- read.csv("data/Hinds_SDS.csv")
m17 <- read_evidence("2017 Research/2017 Research/Marsden Visuals/All Visuals.xlsx", "Sheet1")
remote <- "2018 Research/Analysis/Remote Sensing Paper"
m18 <- read_evidence(file.path(remote, "Marsden SDS 2018.xlsx"), "All")
m18_visuals <- read_evidence("2018 Research/Marsden/Visuals/SDS 2018.xlsx", "All")
h18 <- read_evidence(file.path(remote, "Hinds SDS 2018.xlsx"), "SDS") |>
  rename(Variety = Varirty, Treatment = Trt, Concentration = Conc)
hinds_field_book <- "2018 Research/Hinds/SDS Hinds.xlsx"
h18_field_long <- read_evidence(hinds_field_book, "SDS") |>
  rename(Variety = Varirty, Treatment = Trt, Concentration = Conc)
h18_field_wide <- read_evidence(hinds_field_book, "Reproductive Stage")
design <- read_evidence("2018 Research/Hinds/Hinds Experiment Sheet.xlsx", "Sheet1") |>
  select(Block, Plot, Variety = Varirty, Treatment = Trt, Concentration = Conc)
hinds_fields <- c("Block", "Variety", "Treatment", "Concentration")
marsden_fields <- c("Block", "Plot", "Rotation", "Incidence", "Severity")
m_date <- c("Date", "Quadrat")
h_date <- c("Date", "Plot")
date_text <- function(data) mutate(data, Date = as.character(as.Date(Date, tz = "UTC")))

m16_yield <- read_evidence("2016 Research/Marsden/Marsden SDS Yield.xlsx", "Specific Date") |>
  select(Quadrat = Canopy, Yield)
m17_yield <- read_evidence("2017 Research/Marsden/Marsden SDS Yield.xlsx", "Specific Date") |>
  select(Quadrat, Yield)
m17_harvest <- read_evidence("2017 Research/Marsden Yield/Marsden Yield.xlsx", "Quadrats") |>
  select(Quadrat = Quadrat...9, Yield = buacA)
m18_yield <- read_evidence("2018 Research/Marsden/Visuals/Marsden SDS Yield.xlsx", "Sheet1") |>
  select(Quadrat, Yield)
m18_harvest <- read_evidence("2018 Research/Marsden/Yield/Yield Correction.xlsx", "Sheet1") |>
  select(Quadrat, Yield = `Adj. Plot Yield (bu/Ac)`)
h18_joined <- read_evidence("2018 Research/Hinds/Hinds SDS Yield.xlsx", "Sheet1")
h18_yield <- select(h18_joined, Plot, Yield)
h18_consolidated <- read_evidence("2018 Research/Marsden/Quadrat scale AUDPC and Yield.xlsx",
                                  "Hinds 2018")
ratings_by_doy <- function(data) {
  data |>
    select(Plot, matches("^(Inc|Sev)[0-9]{3}$")) |>
    pivot_longer(-Plot, names_pattern = "(Inc|Sev)([0-9]{3})",
                 names_to = c(".value", "doy")) |>
    transmute(Plot, Date = as.character(as.Date("2018-01-01") + as.integer(doy) - 1L),
              Incidence = Inc, Severity = Sev)
}
h18_combine <- read_evidence("2018 Research/Hinds/Yield/Hinds Yield.xlsx", "Sheet1")
h18_harvest <- select(h18_combine, Plot, Yield = `Adj. Plot Yield (bu/Ac)`)
stand <- read_evidence("2018 Research/Hinds/Stand Count.xlsx", "Sheet1") |>
  select(Plot, count_total = Total, scaled_stand = `Avg Std Count`)
calendar <- read_evidence("additional_source_records_2026-10-11/Marsden and Hinds assessment dates 2016-2019 (2).xlsx",
                          "Sheet1")
relative <- "04_source_data/2018 Research/Hinds/Randomization.csv"
randomization <- read.csv(file.path(project, relative))
record_source(relative, NA, randomization)
randomization <- randomization |>
  transmute(Plot = plots, Block = block, Variety = A,
            Concentration = c(0, 2, 3, 4, 5)[B])
design_fields <- setdiff(hinds_fields, "Treatment")

summary <- bind_rows(
  check("marsden2017_disease", filter(marsden, ID == "SDS_2017"), date_text(m17),
        m_date, marsden_fields),
  check("marsden2018_remote_sensing_disease", filter(marsden, ID == "SDS_2018"),
        date_text(m18), m_date, marsden_fields),
  check("marsden2018_visuals_disease", filter(marsden, ID == "SDS_2018"),
        date_text(m18_visuals), m_date, marsden_fields),
  check("hinds2018_disease", rename(hinds, Date = Doy), date_text(h18), h_date,
        c(hinds_fields, "Incidence", "Severity")),
  check("hinds2018_field_vs_remote_disease", date_text(h18), date_text(h18_field_long),
        h_date, c(hinds_fields, "Incidence", "Severity")),
  check("hinds2018_disease_yield_summary", rename(hinds, Date = Doy),
        ratings_by_doy(h18_joined), h_date, c("Incidence", "Severity")),
  check("hinds2018_disease_consolidated", rename(hinds, Date = Doy),
        ratings_by_doy(h18_consolidated), h_date, c("Incidence", "Severity")),
  check("hinds2018_design", distinct(hinds, Plot, across(all_of(hinds_fields))),
        design, "Plot", hinds_fields),
  check("hinds2018_randomization", design, randomization, "Plot", design_fields),
  check("hinds2018_yield_summary", distinct(hinds, Plot, Yield), h18_yield, "Plot", "Yield"),
  check("hinds2018_yield_harvest", distinct(hinds, Plot, Yield), h18_harvest, "Plot", "Yield"),
  check("hinds2018_consolidated_yield_harvest", select(h18_consolidated, Plot, Yield),
        h18_harvest, "Plot", "Yield"),
  check("marsden2017_yield_harvest", m17_yield, m17_harvest, "Quadrat", "Yield"),
  check("marsden2018_yield_harvest", m18_yield, m18_harvest, "Quadrat", "Yield")
)

yield_overlap <- function(year, source) {
  ratings <- filter(marsden, ID == paste0("SDS_", year))
  spectra <- read.csv(sprintf("data/MRS_%d.csv", year))
  tibble(year, archive_units = n_distinct(source$Quadrat),
         archive_with_yield = n_distinct(source$Quadrat[!is.na(source$Yield)]),
         units_also_in_repo_disease = n_distinct(intersect(source$Quadrat, ratings$Quadrat)),
         units_also_in_repo_joined = n_distinct(intersect(source$Quadrat, spectra$Quadrat)))
}
save_table(bind_rows(yield_overlap(2016, m16_yield), yield_overlap(2017, m17_yield),
                     yield_overlap(2018, m18_yield)), "marsden_yield_overlap")
save_table(filter(design, Plot == 508), "hinds_508_experiment_assignment")
save_table(tibble(
  plots_with_stand_totals = sum(!is.na(stand$count_total)),
  plots_with_scaled_stand = sum(!is.na(stand$scaled_stand)),
  repository_plot_matches = n_distinct(intersect(stand$Plot, hinds$Plot))
), "hinds_stand_count_coverage")
serial <- suppressWarnings(as.numeric(calendar$date))
calendar$calendar_date <- as.Date(serial, origin = "1899-12-30")
save_table(calendar |> filter(format(calendar_date, "%Y") == "2019",
                             grepl("visual rating", task, ignore.case = TRUE)) |>
             select(study, calendar_date, task, GS, `complete/n ratings`), "calendar_2019_visual_visits")

# Test whether the same measurements appear under different plot labels.
# A numerical match alone does not establish the correct field label.
repo_wide <- hinds |>
  select(Plot, Doy, Incidence, Severity) |>
  pivot_wider(names_from = Doy, values_from = c(Incidence, Severity))
rated_archive <- date_text(h18) |>
  select(Plot, Date, Incidence, Severity) |>
  pivot_wider(names_from = Date, values_from = c(Incidence, Severity))
features <- setdiff(names(repo_wide), "Plot")
a <- as.matrix(repo_wide[features])
b <- as.matrix(rated_archive[features])
rating_matches <- lapply(seq_len(nrow(a)), function(i) {
  which(rowSums(abs(sweep(b, 2L, a[i, ], "-")) > 1e-7) == 0L)
})
unique_rating_plot <- vapply(rating_matches, function(indices) {
  if (length(indices) == 1L) rated_archive$Plot[indices] else NA_real_
}, numeric(1))
repo_yield <- distinct(hinds, Plot, Yield)
yield_matches <- lapply(repo_yield$Yield, function(value) {
  which(abs(value - h18_harvest$Yield) <= 1e-7)
})
unique_harvest_plot <- vapply(yield_matches, function(indices) {
  if (length(indices) == 1L) h18_harvest$Plot[indices] else NA_real_
}, numeric(1))
mapping <- tibble(plot = repo_wide$Plot, matching_ratings_plot = unique_rating_plot,
                  rating_matches = lengths(rating_matches)) |>
  left_join(tibble(plot = repo_yield$Plot, matching_harvest_plot = unique_harvest_plot,
                   yield_matches = lengths(yield_matches)), by = "plot")
save_table(mapping, "hinds_value_mapping_review")
candidate_remap <- hinds |>
  inner_join(select(mapping, plot, matching_harvest_plot), by = c("Plot" = "plot"),
             relationship = "many-to-one") |>
  transmute(Plot = matching_harvest_plot, Date = Doy, Incidence, Severity)
remap_counts <- check("hinds2018_test_yield_implied_rating_mapping", candidate_remap,
                     date_text(h18_field_long), h_date, c("Incidence", "Severity"))
save_table(bind_rows(summary, remap_counts), "source_comparison_counts")
save_table(summarise(mapping, plots = n(), unique_rating_matches = sum(rating_matches == 1),
                     rating_matches_same_plot = sum(matching_ratings_plot == plot, na.rm = TRUE),
                     unique_yield_matches = sum(yield_matches == 1),
                     yield_matches_same_plot = sum(matching_harvest_plot == plot, na.rm = TRUE),
                     rating_and_yield_match_same_plot = sum(matching_ratings_plot ==
                                                             matching_harvest_plot, na.rm = TRUE)),
           "hinds_value_mapping_counts")

# Each date in the reproductive-stage workbook spans three columns.
# The first data row labels them Plants, Incidence, and Severity.
first_columns <- grep("^[0-9]{5}$", names(h18_field_wide))
count_checks <- bind_rows(lapply(first_columns, function(i) {
  stopifnot(identical(as.character(h18_field_wide[1, i + 1:2]), c("Incidence", "Severity")))
  records <- h18_field_wide[-1, ]
  plants <- as.numeric(records[[i]])
  incidence <- as.numeric(records[[i + 1L]])
  severity <- as.numeric(records[[i + 2L]])
  denominator <- records[["Avg Std Count"]]
  evaluated <- complete.cases(plants, incidence, denominator) & denominator > 0
  dates <- as.Date(as.integer(names(h18_field_wide)[i]), origin = "1899-12-30")
  compared <- inner_join(
    tibble(Plot = records$Plot, Date = as.character(dates), Incidence = incidence, Severity = severity),
    date_text(h18_field_long), by = h_date, suffix = c(".field", ".long"), relationship = "one-to-one")
  tibble(date = dates, plots = nrow(records), plots_with_plant_counts = sum(!is.na(plants)),
         comparable_incidence = sum(evaluated),
         incidence_reproduced = sum(abs(100 * plants[evaluated] / denominator[evaluated] -
                                          incidence[evaluated]) <= 1e-7),
         field_long_matches = nrow(compared),
         field_long_incidence_differences = sum(abs(compared$Incidence.field - compared$Incidence.long) > 1e-7),
         field_long_severity_differences = sum(abs(compared$Severity.field - compared$Severity.long) > 1e-7))
}))
save_table(count_checks, "hinds_reproductive_count_checks")

# Cross-check recorded Hinds plot IDs against the combine sequence and stand sheet.
combine_path <- "04_source_data/2018 Research/Hinds/Yield/MRHSDS.csv"
combine_records <- tibble(Plot = as.integer(readLines(file.path(project, combine_path))))
record_source(combine_path, NA, combine_records)
sequence <- filter(combine_records, Plot != 999L)
sorted_harvest <- arrange(h18_combine, Sr)
stopifnot(nrow(sequence) == nrow(sorted_harvest), !anyDuplicated(sequence$Plot))
stand_links <- h18_field_wide[-1, ] |>
  select(Plot, recorded_denominator = `Avg Std Count`) |>
  inner_join(stand, by = "Plot", relationship = "one-to-one")
save_table(tibble(
  sequence_positions = nrow(sequence),
  sequence_positions_matching_harvest = sum(sequence$Plot == sorted_harvest$Plot),
  first_sequence_id = first(sequence$Plot), last_sequence_id = last(sequence$Plot),
  field_stand_shared_plots = nrow(stand_links),
  field_denominator_matches_plot_stand = sum(stand_links$recorded_denominator ==
                                               stand_links$scaled_stand),
  field_slots_eventually_incidence_positive = sum(tapply(h18_field_long$Incidence,
                                                          h18_field_long$Plot,
                                                          function(x) any(x > 0)))
), "hinds_anchor_checks")

# Manual transcription of soybean plots from Marsden Schemes slides 3 and 4.
# The numbered Marsden 2017 Layout slide establishes panel and column order.
map_plots <- bind_rows(
  tibble(year = 2017L, plot = c(13, 16, 17, 22, 24, 25, 33, 34, 39, 41, 42, 44),
         slide_rotation = c("S2", "S3", "S4", "S4", "S2", "S3",
                            "S3", "S2", "S4", "S4", "S3", "S2")),
  tibble(year = 2018L, plot = c(11, 14, 19, 23, 27, 29, 32, 35, 38, 45, 48, 49),
         slide_rotation = c("S3", "S4", "S2", "S3", "S2", "S4",
                            "S4", "S2", "S3", "S2", "S3", "S4"))
) |>
  mutate(block = plot %/% 10L, slide = year - 2014L)
history <- "04_source_data/additional_historical_references"
for (name in c("Marsden Schemes.pptx", "Marsden 2017 Layout.pptx", "Blocks 2017.pptx")) {
  record_source(file.path(history, name), NA, NULL)
}
m_rfl <- read.csv("data/Marsden_RFL.csv")
metadata_sources <- bind_rows(
  marsden |> transmute(year = as.integer(substr(Date, 1L, 4L)), plot = Plot,
                       block = Block, rotation = Rotation, date = Date, stream = "Disease"),
  m_rfl |> transmute(year = as.integer(substr(DATE, 1L, 4L)), plot = Plot,
                    block = Block, rotation = Rotation, date = DATE, stream = "Reflectance")
) |>
  distinct() |>
  inner_join(map_plots, by = c("year", "plot", "block"), relationship = "many-to-one")
save_table(metadata_sources |>
             group_by(year, plot, block, slide, slide_rotation, stream) |>
             summarise(recorded_rotations = paste(sort(unique(rotation)), collapse = "|"),
                       dates = n_distinct(date),
                       conflicting_dates = paste(sort(unique(date[rotation != slide_rotation])),
                                                 collapse = "|"),
                       .groups = "drop"),
           "marsden_year_map_checks")

# In Blocks 2017 slides 1 and 2, six printed tags sit under the following plots.
quadrat_map <- tibble(Quadrat = c(1316, 1601, 1711, 2201, 2411, 2511),
                      slide = c(1L, 1L, 1L, 2L, 2L, 2L),
                      slide_plot = c(13, 16, 17, 22, 24, 25))
quadrat_check <- m_rfl |>
  filter(DATE == "2017-06-30") |>
  distinct(Quadrat, recorded_block = Block, recorded_plot = Plot, recorded_rotation = Rotation) |>
  inner_join(quadrat_map, by = "Quadrat", relationship = "one-to-one") |>
  left_join(distinct(filter(marsden, ID == "SDS_2017"), Quadrat, disease_plot = Plot,
                     disease_block = Block, disease_rotation = Rotation),
            by = "Quadrat", relationship = "one-to-one") |>
  left_join(select(filter(map_plots, year == 2017L), slide_plot = plot, slide_rotation),
            by = "slide_plot", relationship = "many-to-one")
save_table(quadrat_check, "marsden_2017_quadrat_map_checks")
quadrat_changes <- bind_rows(lapply(c("block", "plot", "rotation"), function(field) {
  recorded <- as.character(quadrat_check[[paste0("recorded_", field)]])
  proposed <- as.character(quadrat_check[[paste0("disease_", field)]])
  tibble(issue = "D01", year = 2017L, date = "2017-06-30",
         key_field = "Quadrat", key_value = as.character(quadrat_check$Quadrat),
         field, original = recorded, preferred = proposed,
         evidence = "Blocks 2017 slides 1–2, Marsden Schemes slide 3, and archived disease ratings")
})) |>
  filter(original != preferred)
rotation_changes <- metadata_sources |>
  filter(year == 2018L, stream == "Reflectance", rotation != slide_rotation) |>
  transmute(issue = "D02", year, date, key_field = "Plot", key_value = as.character(plot),
            field = "rotation", original = rotation, preferred = slide_rotation,
            evidence = "Marsden Schemes slide 4 and two archived disease tables")
save_table(bind_rows(quadrat_changes, rotation_changes) |>
             arrange(year, date, key_value, field), "marsden_metadata_correction_candidates")

w810_path <- "05_analysis/working_datasets_2026-10-12/data/Marsden_additional_measurements.csv"
dates_path <- "05_analysis/working_datasets_2026-10-12/data/Marsden_radiometer_field_metadata.csv"
w810 <- read.csv(file.path(project, w810_path))
w810_dates <- read.csv(file.path(project, dates_path))
record_source(w810_path, NA, w810)
record_source(dates_path, NA, w810_dates)
w810_check <- w810 |>
  transmute(field, Quadrat = as.integer(sub(".*quadrat", "", sample_key)), value) |>
  inner_join(select(w810_dates, field, DATE = date), by = "field", relationship = "many-to-one") |>
  inner_join(filter(m_rfl, Wavelength == 810, startsWith(DATE, "2017")),
             by = c("Quadrat", "DATE"), relationship = "one-to-one")
save_table(tibble(archive_values = nrow(w810), shared_values = nrow(w810_check),
                  distinct_quadrats = n_distinct(w810_check$Quadrat), dates = n_distinct(w810_check$DATE),
                  differences = sum(abs(w810_check$value - w810_check$Reflectance) > 1e-7),
                  disputed_june30_values = sum(w810_check$DATE == "2017-06-30" &
                                                w810_check$Quadrat %in% quadrat_map$Quadrat)),
           "marsden_2017_w810_checks")

if (length(args) == 3L) {
  isu <- normalizePath(args[[3]], mustWork = TRUE)
  read_isu <- function(relative, sheet) {
    data <- readxl::read_excel(file.path(isu, relative), sheet, guess_max = 100000,
                              .name_repair = "unique_quiet")
    record_source(relative, sheet, data, root = isu)
    data
  }
  read_logger <- function(relative, pattern, separator, columns) {
    lines <- readLines(file.path(isu, relative))
    data <- read.table(text = grep(pattern, lines, value = TRUE), sep = separator,
                       col.names = columns, strip.white = TRUE)
    record_source(relative, NA, data, root = isu)
    data
  }
  band_columns <- paste0("W", seq(460L, 810L, by = 50L))
  logger_columns <- c("date", "time", "angle", "irr", "logger_id", "ss", band_columns)
  m17_logger <- "2017 Research/2017 Research/Reflectance/June-30/06302017.RFL"
  m17_original <- read_logger(m17_logger, "^\t6/30/2017\t", "\t", c("empty", logger_columns))
  m17_tag_sequence <- m17_original |>
    mutate(previous_tag = lag(logger_id), next_tag = lead(logger_id),
           candidate_quadrat = if_else(logger_id == 3116 & previous_tag == 1315 & next_tag == 1317,
                                       1316L, logger_id))
  m17_match <- m17_tag_sequence |>
    pivot_longer(all_of(band_columns), names_to = "band", names_prefix = "W",
                 names_transform = list(band = as.integer), values_to = "logger_value") |>
    inner_join(filter(m_rfl, DATE == "2017-06-30"), by = c("candidate_quadrat" = "Quadrat",
                                                         "band" = "Wavelength"),
               relationship = "one-to-one")
  save_table(m17_match |>
               group_by(candidate_quadrat, logger_id, time, previous_tag, next_tag) |>
               summarise(bands_compared = n(),
                         mismatching_bands = sum(abs(logger_value - Reflectance) > 1e-9),
                         .groups = "drop") |>
               mutate(map_flag = candidate_quadrat %in% quadrat_map$Quadrat),
             "marsden_2017_logger_checks")

  h18_logger <- "2018 Research/Reflectance/August 03/08032018.RFL"
  h18_visit <- read_logger(h18_logger, "^ *8/0?3/2018,", ",", logger_columns)
  logger_headers <- function(relative) {
    lines <- readLines(file.path(isu, relative), n = 10L)
    tibble(file = relative, metadata = trimws(gsub("\t+", " ", grep("REFLECTANCE.*FILE|CALIBRATION",
                                                                     lines, value = TRUE))))
  }
  save_table(bind_rows(logger_headers(m17_logger), logger_headers(h18_logger)),
             "logger_instrument_headers")
  h18_day <- read_isu("2018 Research/Reflectance/Hinds/August 3.xlsx", "08032018")
  signature <- function(data) do.call(paste, c(data[band_columns], sep = "|"))
  logger_row <- match(signature(h18_day), signature(h18_visit))
  stopifnot(!anyNA(logger_row), !anyDuplicated(logger_row))
  h18_acquisition <- bind_cols(select(h18_day, Plot, Reading),
                               select(h18_visit[logger_row, ], time, logger_id)) |>
    mutate(reading_prefix = Reading %/% 10L)
  pairs <- h18_acquisition |>
    group_by(reading_prefix) |>
    summarise(readings = n(), logger_number_gap = max(logger_id) - min(logger_id), .groups = "drop")
  save_table(tibble(logger_rows = nrow(h18_visit), worksheet_rows = nrow(h18_day),
                    worksheet_spectra_matched = length(logger_row),
                    plots_with_two_consecutive_readings = sum(pairs$readings == 2L &
                                                               pairs$logger_number_gap == 1L)),
             "hinds_august3_logger_checks")
  save_table(h18_acquisition |>
               filter(logger_id %in% 89:92) |>
               arrange(logger_id) |>
               mutate(sequence_implied_plot = c(507L, 507L, 508L, 508L),
                      sequence_implied_reading = c(5071L, 5072L, 5081L, 5082L)),
             "hinds_august3_candidate_sequence")

  root19 <- "2019 Reserach"
  m19 <- read_isu(file.path(root19, "Marsden/Reflectance/Canopy Reflectance Marsden 2019.xlsx"),
                  "Sheet1")
  h19 <- read_isu(file.path(root19, "Hinds/Reflectance/Canopy Reflectance Hinds 2019.xlsx"),
                  "Sheet1")
  long_bands <- function(data) {
    pivot_longer(data, matches("^[0-9]{3}\\.0$"), names_to = "Wavelength",
                 names_transform = list(Wavelength = as.integer), values_to = "archived_value")
  }
  m19_repo <- readxl::read_excel("data/Marsden RFL 2019.xlsx", "Sheet 1") |>
    mutate(across(c(Plot, Quadrat), as.integer))
  m19_compared <- inner_join(m19_repo, long_bands(m19), by = c("DATE", "Wavelength", "Plot" = "PLOT"),
                             relationship = "one-to-one")
  m19_counts <- count(m19, DATE, Quadrat)
  h19_means <- long_bands(h19) |>
    group_by(DATE, Plot, Wavelength, Block, Treatment, Variety, Concentration) |>
    summarise(archive_replicates = n(), archived_value = mean(archived_value), .groups = "drop")
  h19_repo <- readxl::read_excel("data/Hinds RFL 2019.xlsx", "Sheet 1")
  h19_compared <- inner_join(h19_repo, h19_means, by = c("DATE", "Plot", "Wavelength"),
                             relationship = "one-to-one")
  save_table(bind_rows(
    tibble(site = "Marsden", archive_reading_rows = nrow(m19), actual_units = n_distinct(m19$Quadrat),
           field_plots = n_distinct(m19$Plot), visits = n_distinct(m19$DATE),
           unit_visits = nrow(m19_counts), unit_visits_with_two_readings = sum(m19_counts$n == 2L),
           workbook_band_rows = nrow(m19_repo), shared_band_rows = nrow(m19_compared),
           matched_band_values = sum(abs(m19_compared$Reflectance - m19_compared$archived_value) <= 1e-9),
           matching_archive_ids = sum(m19_compared$Quadrat.x == m19_compared$Quadrat.y &
                                        m19_compared$Block.x == m19_compared$Block.y &
                                        m19_compared$Rotation.x == m19_compared$Rotation.y)),
    tibble(site = "Hinds", archive_reading_rows = nrow(h19), actual_units = n_distinct(h19$Plot),
           field_plots = n_distinct(h19$Plot), visits = n_distinct(h19$DATE),
           unit_visits = nrow(distinct(h19, DATE, Plot)),
           unit_visits_with_two_readings = sum(count(h19, DATE, Plot)$n == 2L),
           workbook_band_rows = nrow(h19_repo), shared_band_rows = nrow(h19_compared),
           matched_band_values = sum(abs(h19_compared$Reflectance - h19_compared$archived_value) <= 1e-9),
           matching_archive_ids = sum(h19_compared$Block.x == h19_compared$Block.y &
                                        h19_compared$Treatment.x == h19_compared$Treatment.y &
                                        h19_compared$Variety.x == h19_compared$Variety.y &
                                        h19_compared$Concentration.x == h19_compared$Concentration.y))
  ), "reflectance_2019_archive_checks")
  stopifnot(all(m19$Plot == as.integer(substr(as.character(m19$Quadrat), 1L, 2L))))
  save_table(distinct(m19, Quadrat, block = Block, field_plot = Plot, rotation = Rotation) |>
               arrange(Quadrat), "marsden_2019_field_units")
  h19_sds <- read_isu(file.path(root19, "Hinds/Quadrat scale/SDS Hinds.xlsx"), "SDS")
  m19_sds <- read_isu(file.path(root19, "Marsden/Visual/SDS.xlsx"), "Sheet1")
  h19_gis <- read_isu(file.path(root19, "Hinds/Quadrat scale/Hinds For GIS.xlsx"), "Sheet1")
  h18_gis <- read_evidence("2018 Research/Hinds/Hinds For GIS.xlsx", "Sheet1")
  rating_columns <- grep("^(Inc|Sev)", names(h19_gis), value = TRUE)
  gis <- inner_join(select(h19_gis, Plot, all_of(rating_columns)),
                    select(h18_gis, Plot, all_of(rating_columns)), by = "Plot",
                    suffix = c(".2019_folder", ".2018_folder"), relationship = "one-to-one")
  gis_matches <- sum(vapply(rating_columns, function(field) {
    sum(abs(gis[[paste0(field, ".2019_folder")]] - gis[[paste0(field, ".2018_folder")]]) <= 1e-7)
  }, integer(1)))
  save_table(tibble(hinds_slots = nrow(h19_sds),
                    hinds_slots_with_any_date_or_rating = sum(!is.na(h19_sds$Date) |
                                      !is.na(h19_sds$Incidence) | !is.na(h19_sds$Severity)),
                    marsden_roster_rows = nrow(m19_sds),
                    marsden_roster_rating_columns = sum(grepl("Incid|Sever", names(m19_sds))),
                    hinds_gis_cells_compared = nrow(gis) * length(rating_columns),
                    hinds_gis_cells_equal_to_2018 = gis_matches),
             "disease_2019_archive_checks")

  methods <- "My Thesis/My Thesis/Remote Sensing Paper/Radiometer Paper/Materials and Methods.docx"
  record_source(methods, NA, NULL, root = isu)
}
dissertation <- paste0("02_dissertation_and_earlier_drafts/",
                       "Modeling yield loss due to soybean sudden death syndrome at different spatial scales.pdf")
record_source(dissertation, NA, NULL)
save_table(bind_rows(manifest), "sds_paper_source_manifest")
