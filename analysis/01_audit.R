# Run from the repository root. Optional argument overrides the output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
options(digits = 16)
args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args)) args[[1]] else "audit"
for (folder in c("tables", "figures")) {
  dir.create(file.path(out, folder), recursive = TRUE, showWarnings = FALSE)
}
save_table <- function(data, name) {
  write.csv(data, file.path(out, "tables", paste0(name, ".csv")),
            row.names = FALSE, na = "")
}

bands <- seq(460L, 810L, by = 50L)
band_columns <- paste0("W", bands)
files <- sort(list.files("data", pattern = "\\.(xlsx|xls|csv)$", full.names = TRUE,
                         ignore.case = TRUE))
stopifnot(length(files) > 0L)
parse_date <- function(values) {
  if (inherits(values, "POSIXt")) return(as.Date(values, tz = "UTC"))
  text <- trimws(as.character(values))
  result <- as.Date(rep(NA_character_, length(text)))
  iso <- grepl("^\\d{4}-\\d{2}-\\d{2}$", text)
  slash <- grepl("^\\d{1,2}/\\d{1,2}/\\d{4}$", text)
  serial <- grepl("^\\d{5}$", text)
  result[iso] <- as.Date(text[iso], "%Y-%m-%d")
  result[slash] <- as.Date(text[slash], "%m/%d/%Y")
  result[serial] <- as.Date(as.numeric(text[serial]), origin = "1899-12-30")
  stopifnot(all(is.na(text) | !is.na(result)))
  result
}

sources <- list()
inventory <- list()
profiles <- list()
for (file in files) {
  workbook <- !grepl("\\.csv$", file, ignore.case = TRUE)
  sheets <- if (workbook) readxl::excel_sheets(file) else NA_character_
  hash <- digest::digest(file, algo = "sha256", file = TRUE)
  for (sheet in sheets) {
    data <- if (workbook) {
      as.data.frame(readxl::read_excel(file, sheet, guess_max = 100000,
                                      .name_repair = "minimal"))
    } else {
      read.csv(file, check.names = FALSE, na.strings = c("", "NA"))
    }
    source <- if (workbook) paste(basename(file), sheet, sep = " / ") else basename(file)
    date_column <- intersect(c("DATE", "Date", "Doy"), names(data))
    wide_dates <- grep("^\\d{4}-\\d{2}-\\d{2}_(Incidence|Severity)$", names(data), value = TRUE)
    dates <- if (length(date_column)) parse_date(data[[date_column]]) else as.Date(character())
    assessment_dates <- parse_date(sub("_.*", "", wide_dates))
    inventory[[source]] <- tibble(file, sheet, sha256 = hash, bytes = file.size(file),
                                  rows = nrow(data), columns = ncol(data),
                                  missing_cells = sum(is.na(data)),
                                  date_column = paste(date_column, collapse = ""),
                                  date_count = n_distinct(dates, na.rm = TRUE),
                                  dates = paste(sort(unique(dates)), collapse = "|"),
                                  dates_in_headers = paste(sort(unique(assessment_dates)), collapse = "|"))
    profiles[[source]] <- bind_rows(lapply(seq_along(data), function(i) {
      values <- data[[i]]
      observed <- values[!is.na(values)]
      numeric <- is.numeric(values) && length(observed) > 0L
      tibble(file, sheet, column_index = i, variable = names(data)[[i]],
             imported_type = paste(class(values), collapse = "/"),
             missing = sum(is.na(values)), present = length(observed),
             distinct_present = n_distinct(observed),
             numeric_min = if (numeric) min(observed) else NA_real_,
             numeric_max = if (numeric) max(observed) else NA_real_)
    }))
    names(data)[names(data) == ""] <- ".unnamed"
    if (length(date_column)) data[[date_column]] <- dates
    data$.source_row <- seq_len(nrow(data)) + 1L
    data$.source <- source
    sources[[source]] <- data
  }
}
save_table(bind_rows(inventory), "inventory")
save_table(bind_rows(profiles), "column_profiles")
get_source <- function(name) as_tibble(sources[[name]])

marsden_metadata <- c("block", "plot", "rotation")
hinds_metadata <- c("block", "plot", "treatment", "variety", "concentration")
unit_key <- c("site", "year", "unit")
visit_key <- c(unit_key, "date")
band_key <- c(visit_key, "band")
normalize <- function(data, site, disease = FALSE, raw = FALSE) {
  date_field <- if (disease) if (site == "Marsden") "Date" else "Doy" else "DATE"
  result <- data |>
    mutate(across(any_of(c("Block", "Plot", "Quadrat", "Variety")), as.character)) |>
    mutate(date = .data[[date_field]], year = as.integer(format(date, "%Y")),
           site = .env$site, block = as.character(Block), plot = as.character(Plot))
  if (site == "Marsden") {
    result <- result |> mutate(unit = as.character(Quadrat), rotation = Rotation)
  } else {
    result <- result |>
      mutate(unit = if (raw) substr(as.character(Reading), 1L, 3L) else plot,
             treatment = Treatment, concentration = if (raw) Conc else Concentration,
             variety = recode(as.character(Variety), "1" = "Pioneer P20T79R2",
                              "2" = "Syngenta NK Soybean S24-K2"))
  }
  if ("Wavelength" %in% names(result)) {
    result <- result |> mutate(band = as.integer(Wavelength), value = Reflectance)
  }
  stopifnot(!anyNA(result[c(visit_key)]))
  if ("band" %in% names(result)) stopifnot(all(result$band %in% bands))
  result
}
retain <- function(data, fields) select(data, all_of(fields), .source, .source_row)

workbooks <- setNames(lapply(c("Marsden", "Hinds"), function(site) {
  years <- if (site == "Marsden") 2016:2019 else 2018:2019
  setNames(lapply(years, function(year) {
    sheet <- if (year == 2018) "Sheet1" else "Sheet 1"
    name <- paste0(site, " RFL ", year, ".xlsx / ", sheet)
    normalize(get_source(name), site, raw = year == 2018)
  }), years)
}), c("Marsden", "Hinds"))
raw_csv <- setNames(lapply(names(workbooks), function(site) {
  normalize(get_source(paste(site, "RFL 2018.csv")), site, raw = TRUE)
}), names(workbooks))
rfl_csv <- setNames(lapply(names(workbooks), function(site) {
  normalize(get_source(paste0(site, "_RFL.csv")), site)
}), names(workbooks))
disease <- bind_rows(lapply(names(workbooks), function(site) {
  normalize(get_source(paste0(site, "_SDS.csv")), site, disease = TRUE)
}))
exports <- bind_rows(lapply(c("MRS_2016", "MRS_2017", "MRS_2018", "HRS_2018"), function(name) {
  normalize(get_source(paste0(name, ".csv")), if (startsWith(name, "M")) "Marsden" else "Hinds")
}))
rfl <- bind_rows(unname(rfl_csv), workbooks$Marsden[["2019"]], workbooks$Hinds[["2019"]]) |>
  retain(c(band_key, "value", union(marsden_metadata, hinds_metadata)))

# Reconcile multisets under the indicated key, including repeated records.
# Sort comparable values inside each key before matching occurrence indices.
comparison_summary <- list()
comparison_details <- list()
compare <- function(label, left, right, key, fields) {
  pack <- function(data) {
    data |>
      select(all_of(c(key, fields)), any_of(c(".source", ".source_row"))) |>
      arrange(across(all_of(c(key, fields)))) |>
      group_by(across(all_of(key))) |>
      mutate(occurrence = row_number(), present = TRUE) |>
      ungroup()
  }
  paired <- full_join(pack(left), pack(right), by = c(key, "occurrence"),
                      suffix = c(".expected", ".observed"), relationship = "one-to-one") |>
    mutate(status = case_when(is.na(present.expected) ~ "observed_only",
                              is.na(present.observed) ~ "expected_only",
                              TRUE ~ "match"))
  both <- paired$status == "match"
  equal <- function(a, b) {
    same <- if (is.numeric(a) && is.numeric(b)) abs(a - b) <= 1e-9 else a == b
    coalesce(same, is.na(a) & is.na(b))
  }
  differences <- lapply(fields, function(field) {
    a <- paired[[paste0(field, ".expected")]]
    b <- paired[[paste0(field, ".observed")]]
    !equal(a, b)
  })
  paired$fields_differing <- vapply(seq_len(nrow(paired)), function(i) {
    paste(fields[vapply(differences, function(x) x[[i]], logical(1))], collapse = "|")
  }, character(1))
  paired$status[both & nzchar(paired$fields_differing)] <- "different_values"
  comparison_summary[[label]] <<- tibble(
    comparison = label, expected_rows = nrow(left), observed_rows = nrow(right),
    matched = sum(paired$status == "match"), expected_only = sum(paired$status == "expected_only"),
    observed_only = sum(paired$status == "observed_only"),
    different_values = sum(paired$status == "different_values")
  )
  discrepancy <- filter(paired, status != "match")
  if (nrow(discrepancy)) comparison_details[[label]] <<- mutate(discrepancy, comparison = label, .before = 1)
}

aggregate_replicates <- function(data, metadata) {
  data |>
    group_by(across(all_of(unique(c(visit_key, metadata))))) |>
    summarise(across(all_of(band_columns), ~ mean(.x, na.rm = TRUE)), .groups = "drop") |>
    pivot_longer(all_of(band_columns), names_to = "band", names_prefix = "W",
                 names_transform = list(band = as.integer), values_to = "value",
                 values_drop_na = TRUE)
}

for (site in names(workbooks)) {
  metadata <- if (site == "Marsden") marsden_metadata else hinds_metadata
  raw_metadata <- metadata
  workbook <- workbooks[[site]][["2018"]]
  raw <- raw_csv[[site]]
  compare(paste(site, "2018 workbook to replicate CSV"), workbook, raw,
          c(visit_key, "Reading"), c(raw_metadata, band_columns))
  if (site == "Hinds") {
    # The legacy notebook takes the plot from the first three characters of Reading.
    raw <- mutate(raw, plot = unit)
  }
  compare(paste(site, "2018 replicate means to intermediate"), aggregate_replicates(raw, metadata),
          filter(rfl_csv[[site]], year == 2018),
          unique(c(band_key, metadata)), "value")
}
for (year in 2016:2017) {
  workbook <- workbooks$Marsden[[as.character(year)]]
  compare(paste("Marsden", year, "workbook to intermediate"), workbook,
          filter(rfl_csv$Marsden, .data$year == .env$year), band_key, c(marsden_metadata, "value"))
}

join_counts <- list()
excluded <- list()
disputed <- c("4811", "4812", "4911", "4912", "4913")
for (export in split(exports, exports$.source)) {
  site <- unique(export$site)
  year <- unique(export$year)
  label <- unique(export$.source)
  metadata <- if (site == "Marsden") marsden_metadata else hinds_metadata
  ratings <- filter(disease, .data$site == .env$site, .data$year == .env$year)
  reflectance <- filter(rfl_csv[[site]], .data$year == .env$year)
  selected <- reflectance
  if (site == "Marsden" && year == 2018) {
    selected <- reflectance |> filter(!unit %in% disputed) |> semi_join(ratings, by = unit_key)
  }
  rating_fields <- c("Incidence", "Severity")
  disease_wide <- ratings |>
    select(all_of(c(unit_key, metadata, "date", rating_fields)),
           any_of(if (site == "Marsden") "ID" else "Yield")) |>
    pivot_wider(names_from = date, values_from = all_of(rating_fields),
                names_glue = "{date}_{.value}")
  expected <- left_join(selected, select(disease_wide, -all_of(metadata)),
                        by = unit_key, relationship = "many-to-many")
  fields <- c("value", grep("_(Incidence|Severity)$", names(disease_wide), value = TRUE),
              if (site == "Marsden") "ID" else "Yield")
  compare(paste("Reconstructed join to", label), expected, export,
          unique(c(band_key, metadata)), fields)
  removed <- anti_join(reflectance, export, by = band_key) |>
    group_by(across(all_of(c(unit_key, metadata)))) |>
    summarise(removed_dates = paste(sort(unique(date)), collapse = "|"),
              removed_band_rows = n(), .groups = "drop") |>
    mutate(in_legacy_explicit_exclusions = site == "Marsden" & year == 2018 & unit %in% disputed,
           disease_unit_present = !is.na(match(unit, ratings$unit)))
  excluded[[label]] <- removed
  join_counts[[label]] <- tibble(
    site, year, intermediate_rows = nrow(reflectance),
    intermediate_units = n_distinct(reflectance$unit), disease_units = n_distinct(ratings$unit),
    intermediate_only_units = n_distinct(anti_join(reflectance, ratings, by = unit_key)$unit),
    disease_only_units = n_distinct(anti_join(ratings, reflectance, by = unit_key)$unit),
    explicitly_excluded_rows = sum(reflectance$unit %in% disputed & site == "Marsden" & year == 2018),
    selected_rows = nrow(selected), reconstructed_rows = nrow(expected),
    rows_added_by_join = nrow(expected) - nrow(selected), export_rows = nrow(export),
    export_units = n_distinct(export$unit),
    export_only_units = n_distinct(anti_join(export, reflectance, by = unit_key)$unit),
    export_without_disease_units = n_distinct(anti_join(export, ratings, by = unit_key)$unit),
    disease_without_export_units = n_distinct(anti_join(ratings, export, by = unit_key)$unit),
    export = label) |> relocate(export)
}
save_table(bind_rows(comparison_summary), "lineage_summary")
export_ratings <- exports |>
  select(all_of(unit_key), matches("_(Incidence|Severity)$")) |>
  pivot_longer(matches("_(Incidence|Severity)$"), names_to = c("assessment", "rating"),
               names_sep = "_", values_to = "exported") |>
  filter(as.integer(substr(assessment, 1L, 4L)) == year) |>
  group_by(across(all_of(unit_key)), assessment, rating) |>
  summarise(exported_min = min(exported), exported_max = max(exported),
            distinct_exported = n_distinct(exported), .groups = "drop")
rating_differences <- disease |>
  mutate(assessment = as.character(date)) |>
  select(all_of(unit_key), assessment, Incidence, Severity) |>
  pivot_longer(c(Incidence, Severity), names_to = "rating", values_to = "source_rating") |>
  inner_join(export_ratings, by = c(unit_key, "assessment", "rating"),
             relationship = "one-to-one") |>
  mutate(largest_absolute_difference = pmax(abs(source_rating - exported_min),
                                            abs(source_rating - exported_max))) |>
  filter(largest_absolute_difference > 1e-9 | distinct_exported > 1L)
save_table(rating_differences, "export_rating_differences")
save_table(if (length(comparison_details)) bind_rows(comparison_details)
           else tibble(comparison = character(), status = character()), "lineage_discrepancies")
save_table(bind_rows(join_counts), "join_integrity")
save_table(bind_rows(excluded), "join_omissions")

duplicate_rows <- function(data, key) {
  data |>
    add_count(across(all_of(key)), name = "key_rows") |>
    filter(key_rows > 1L) |>
    relocate(all_of(key), key_rows, .source, .source_row)
}
all_raw <- bind_rows(unname(raw_csv), workbooks$Marsden[["2018"]], workbooks$Hinds[["2018"]])
all_long_reflectance <- bind_rows(unname(rfl_csv), exports, unname(workbooks$Marsden[c("2016", "2017", "2019")]),
                                  workbooks$Hinds[["2019"]])
duplicate_reflectance <- duplicate_rows(all_long_reflectance, c(".source", band_key))
duplicate_disease <- duplicate_rows(disease, c(".source", visit_key))
duplicate_readings <- duplicate_rows(all_raw, c(".source", visit_key, "Reading"))
save_table(retain(duplicate_reflectance, c(band_key, "key_rows", "value", union(marsden_metadata, hinds_metadata))),
           "duplicate_reflectance_keys")
save_table(retain(duplicate_disease, c(visit_key, "key_rows", "Incidence", "Severity",
                                       union(marsden_metadata, hinds_metadata))), "duplicate_disease_keys")
save_table(retain(duplicate_readings, c(visit_key, "key_rows", "Reading", union(marsden_metadata, hinds_metadata))),
           "duplicate_reading_keys")

raw_visits <- all_raw |>
  group_by(.source, across(all_of(visit_key))) |>
  summarise(rows = n(), reading_ids = paste(Reading, collapse = "|"),
            source_rows = paste(.source_row, collapse = "|"),
            plot_values = paste(sort(unique(plot)), collapse = "|"),
            labels = n_distinct(block, plot, rotation, treatment, variety, concentration),
            .groups = "drop")
save_table(filter(raw_visits, rows != 2 | labels != 1), "replicate_count_or_label_flags")
save_table(all_raw |> filter(site == "Hinds", plot != unit) |>
             retain(c(visit_key, "Reading", hinds_metadata)), "hinds_reading_plot_disagreements")

label_fields <- union(marsden_metadata, hinds_metadata)
label_observations <- bind_rows(
  rfl |> retain(c(visit_key, label_fields)) |> mutate(stream = "reflectance"),
  disease |> retain(c(visit_key, label_fields)) |> mutate(stream = "disease")
) |>
  group_by(stream, .source, across(all_of(c(visit_key, label_fields)))) |>
  summarise(rows = n(), first_source_row = min(.source_row), .groups = "drop")
label_comparison <- label_observations |>
  pivot_longer(all_of(label_fields), names_to = "field", values_transform = as.character,
               values_drop_na = TRUE)
label_disagreements <- label_comparison |>
  group_by(across(all_of(unit_key)), field) |>
  filter(n_distinct(value) > 1L) |>
  ungroup() |>
  arrange(site, year, unit, field, stream, date, value)
save_table(label_disagreements, "metadata_disagreements")
disease_labels <- label_comparison |>
  filter(stream == "disease") |>
  distinct(across(all_of(unit_key)), field, disease_value = value)
save_table(label_comparison |>
             filter(stream == "reflectance") |>
             inner_join(disease_labels, by = c(unit_key, "field"), relationship = "many-to-many") |>
             filter(value != disease_value) |>
             rename(reflectance_value = value), "reflectance_vs_disease_labels")
save_table(label_disagreements |>
             count(site, year, stream, date, field, name = "label_records") |>
             left_join(label_disagreements |>
                         distinct(site, year, stream, date, field, unit) |>
                         count(site, year, stream, date, field, name = "units"),
                       by = c("site", "year", "stream", "date", "field")),
           "metadata_disagreement_counts")

collapse_labels <- function(values) paste(sort(unique(values[!is.na(values)])), collapse = "|")
registry <- label_observations |>
  group_by(across(all_of(unit_key))) |>
  summarise(reported_plot_keys = collapse_labels(if_else(is.na(block) | is.na(plot), NA_character_,
                                                          paste(site, year, block, plot, sep = "/"))),
            across(all_of(label_fields), collapse_labels),
            reflectance_visits = n_distinct(date[stream == "reflectance"]),
            disease_visits = n_distinct(date[stream == "disease"]),
            .groups = "drop") |>
  mutate(candidate_id = paste(site, year, unit, sep = "/"),
         unit_field = if_else(site == "Marsden", "Quadrat", "Plot"),
         unresolved_metadata = candidate_id %in% with(label_disagreements, paste(site, year, unit, sep = "/")))
save_table(registry, "candidate_units")
save_table(label_observations |>
             filter(site != "Marsden" | year < 2019L) |>
             distinct(site, year, block, plot, rotation, treatment, variety, concentration) |>
             group_by(site, block, plot) |>
             filter(n_distinct(year) > 1L) |>
             ungroup() |>
             arrange(site, block, plot, year),
           "reused_plot_labels")
save_table(label_observations |>
             distinct(site, year, stream, unit, across(all_of(label_fields))) |>
             count(site, year, stream, across(all_of(label_fields)), name = "candidate_units"),
           "reported_plot_labels")

visit_coverage <- function(data, stream_name) {
  observed <- distinct(data, across(all_of(visit_key)))
  observed |>
    select(all_of(unit_key)) |>
    distinct() |>
    inner_join(distinct(observed, site, year, date), by = c("site", "year"),
               relationship = "many-to-many") |>
    left_join(mutate(observed, observed = TRUE), by = visit_key, relationship = "one-to-one") |>
    mutate(stream = stream_name, observed = coalesce(observed, FALSE))
}
# Use the workbook's two identifier fields together for 2019 Marsden displays.
# These pairs distinguish spectra without assigning treatment plots.
marsden2019 <- filter(rfl, site == "Marsden", year == 2019L)
save_table(marsden2019 |>
             group_by(site, year, unit, plot, block, rotation) |>
             summarise(visits = n_distinct(date), band_rows = n(), .groups = "drop") |>
             rename(quadrat_field = unit, plot_field = plot), "marsden2019_identifier_pairs")
rfl_trajectories <- rfl |>
  mutate(unit = if_else(site == "Marsden" & year == 2019L, paste(unit, plot, sep = "/"), unit))
coverage <- bind_rows(visit_coverage(rfl_trajectories, "Reflectance"), visit_coverage(disease, "Disease"),
                      visit_coverage(exports, "Joined reflectance"))
visit_counts <- coverage |>
  group_by(site, year, stream, date) |>
  summarise(season_units = n(), observed_units = sum(observed),
            units_without_record = sum(!observed), .groups = "drop")
save_table(visit_counts, "visit_coverage")
save_table(filter(coverage, !observed), "unit_visits_without_record")
save_table(rfl |>
             group_by(across(all_of(visit_key))) |>
             summarise(rows = n(), present_bands = n_distinct(band[!is.na(value)]),
                       missing_bands = paste(setdiff(bands, band[!is.na(value)]), collapse = "|"),
                       .groups = "drop") |>
             filter(present_bands != length(bands) | rows != length(bands)),
           "spectrum_coverage_flags")

symptom_flags <- disease |>
  filter(!is.na(Incidence), !is.na(Severity), (Incidence > 0) != (Severity > 0)) |>
  mutate(disagreement = if_else(Incidence > 0, "incidence_positive_only", "severity_positive_only"))
save_table(retain(symptom_flags, c(visit_key, label_fields, "Incidence", "Severity", "disagreement")),
           "symptom_disagreements")
save_table(count(symptom_flags, site, year, date, disagreement), "symptom_disagreement_counts")

# Bounds describe the first recorded positive under each reading of the ratings.
# Missing readings do not supply a negative bound.
onset <- disease |>
  filter(!is.na(Incidence) | !is.na(Severity)) |>
  mutate(incidence = Incidence > 0, severity = Severity > 0,
         either = incidence | severity, both = incidence & severity) |>
  pivot_longer(c(incidence, severity, either, both),
               names_to = "definition", values_to = "positive", values_drop_na = TRUE) |>
  group_by(across(all_of(unit_key)), definition) |>
  summarise(first_positive = first(sort(date[positive]), default = as.Date(NA)),
            last_negative = first(sort(date[!positive & (is.na(first_positive) | date < first_positive)],
                                       decreasing = TRUE), default = as.Date(NA)),
            censoring = case_when(is.na(first_positive) ~ "right",
                                  is.na(last_negative) ~ "left",
                                  TRUE ~ "interval"),
            .groups = "drop")
save_table(onset, "candidate_onset_intervals")
save_table(count(onset, site, year, definition, censoring), "onset_counts")
save_table(disease |>
             filter(site == "Hinds") |>
             group_by(across(all_of(unit_key))) |>
             summarise(rating_rows = n(), distinct_yields = n_distinct(Yield, na.rm = TRUE),
                       yield_values = collapse_labels(Yield), .groups = "drop"),
           "hinds_yield_repetition")

# Report-only graphics. A dated gap breaks a line, and duplicate band keys are omitted.
plot_theme <- theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        plot.title.position = "plot", plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
save_plot <- function(plot, name, width, height) {
  ggsave(file.path(out, "figures", paste0(name, ".png")), plot, width = width,
         height = height, dpi = 180, bg = "white", device = ragg::agg_png)
}
coverage_plot <- visit_counts |>
  mutate(season = paste(site, year),
         stream = factor(stream, levels = c("Disease", "Reflectance", "Joined reflectance"))) |>
  ggplot(aes(date, observed_units, colour = stream, shape = stream)) +
  geom_segment(aes(xend = date, y = 0, yend = observed_units), linewidth = 0.3,
               alpha = 0.5, show.legend = FALSE) +
  geom_point(size = 2.3) +
  facet_wrap(vars(season), scales = "free_x", ncol = 2) +
  scale_x_date(date_labels = "%b %d", breaks = scales::breaks_pretty(n = 5), expand = expansion(mult = 0.08)) +
  scale_colour_manual(values = c("#B74638", "#176C61", "#364F80")) +
  scale_shape_manual(values = c(17, 1, 4)) +
  labs(title = "Sampling coverage by visit", x = "Calendar date", y = "Candidate units with a record",
       colour = NULL, shape = NULL,
       caption = "Marsden 2019 uses the two workbook identifier fields together. Other panels use the recorded quadrat or plot ID.") +
  plot_theme
save_plot(coverage_plot, "sampling_coverage", 11, 8)

# Draw all disease records on their recorded assessment dates.
disease_season <- coverage |> filter(stream == "Disease")
disease_plot <- disease_season |>
  left_join(disease |> select(all_of(visit_key), Incidence, Severity), by = visit_key,
            relationship = "one-to-one") |>
  pivot_longer(c(Incidence, Severity), names_to = "rating") |>
  mutate(season = paste(site, year)) |>
  ggplot(aes(date, value, group = unit, colour = rating)) +
  geom_line(alpha = 0.16, linewidth = 0.32, na.rm = TRUE) +
  geom_point(alpha = 0.17, size = 0.55, na.rm = TRUE) +
  facet_grid(rating ~ season, scales = "free_x") +
  scale_x_date(date_labels = "%b %d", breaks = scales::breaks_pretty(n = 3)) +
  scale_colour_manual(values = c("#A14838", "#733A59"), guide = "none") +
  labs(title = "Observed foliar disease trajectories", x = "Assessment date", y = "Recorded rating",
       caption = "One line per candidate unit. Incidence is recorded in percent. Severity uses the source scores.") +
  plot_theme
save_plot(disease_plot, "observed_disease", 13, 6)

rfl_plot <- coverage |>
  filter(stream == "Reflectance") |>
  crossing(band = c(660L, 810L)) |>
  left_join(rfl_trajectories |>
              filter(band %in% c(660L, 810L)) |>
              add_count(across(all_of(band_key))) |>
              filter(n == 1L) |>
              select(all_of(band_key), value),
            by = band_key, relationship = "one-to-one") |>
  mutate(season = paste(site, year), wavelength = paste(band, "nm")) |>
  ggplot(aes(date, value, group = unit, colour = wavelength)) +
  geom_line(alpha = 0.15, linewidth = 0.32, na.rm = TRUE) +
  geom_point(alpha = 0.16, size = 0.55, na.rm = TRUE) +
  facet_grid(wavelength ~ season, scales = "free") +
  scale_x_date(date_labels = "%b %d", breaks = scales::breaks_pretty(n = 3)) +
  scale_colour_manual(values = c("#AA4934", "#216C60"), guide = "none") +
  labs(title = "Observed red and near-infrared reflectance", x = "Acquisition date",
       y = "Recorded reflectance",
       caption = "One line per candidate unit. Duplicate unit-date-band records are omitted from this figure.") +
  plot_theme
save_plot(rfl_plot, "observed_reflectance", 15, 6)

packages <- c("dplyr", "tidyr", "ggplot2", "readxl", "digest", "ragg", "scales")
save_table(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                   vapply(packages, function(p) as.character(packageVersion(p)), character(1)))),
           "software")
