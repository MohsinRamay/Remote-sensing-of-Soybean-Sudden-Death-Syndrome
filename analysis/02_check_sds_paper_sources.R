# Optional corroboration using the separately held SDS Paper project.
# Usage: Rscript analysis/02_check_sds_paper_sources.R <project-root> <output-directory>
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L, dir.exists(args[[1]]))
project <- normalizePath(args[[1]], mustWork = TRUE)
out <- args[[2]]
dir.create(out, recursive = TRUE, showWarnings = FALSE)
save_table <- function(data, name) {
  write.csv(data, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}

manifest <- list()
record_source <- function(relative, section, data) {
  full <- file.path(project, relative)
  manifest[[length(manifest) + 1L]] <<- tibble(
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
h18_harvest <- read_evidence("2018 Research/Hinds/Yield/Hinds Yield.xlsx", "Sheet1") |>
  select(Plot, Yield = `Adj. Plot Yield (bu/Ac)`)
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
save_table(bind_rows(manifest), "sds_paper_source_manifest")

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
