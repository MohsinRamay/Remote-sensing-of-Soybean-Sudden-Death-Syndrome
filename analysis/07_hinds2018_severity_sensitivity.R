# Run after preparing the Hinds cohort with analysis/03_prepare_phase2.R.
# Optional arguments: output directory, then the Phase 2 output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1L]] else "results/hinds_severity"
prepared <- if (length(args) == 2L) args[[2L]] else "results/phase2"
dir.create(file.path(out, "local"), showWarnings = FALSE, recursive = TRUE)
save_csv <- function(data, name, detail = FALSE) {
  directory <- if (detail) file.path(out, "local") else out
  write.csv(data, file.path(directory, paste0(name, ".csv")), row.names = FALSE, na = "")
}
cohort_file <- file.path(prepared, "local", "hinds2018_severity.csv")
if (!file.exists(cohort_file)) {
  stop("Run 03_prepare_phase2.R with the SDS Paper archive argument to prepare the Hinds cohort.")
}
cohort <- read.csv(cohort_file) |> mutate(date = as.Date(date))
dates <- sort(unique(cohort$date))
version_levels <- c("Long sheet", "Field entries")
plots <- distinct(cohort, unit_id, block, variety_code, dose_ml_per_ft, treatment)
stopifnot(nrow(cohort) == 480L, nrow(plots) == 60L, length(dates) == 8L,
          n_distinct(plots$block) == 6L, all(count(plots, block)$n == 10L),
          !anyNA(cohort[c("unit_id", "date", "severity", "entry_severity")]),
          all(between(cohort$severity, 0, 100)), all(between(cohort$entry_severity, 0, 100)),
          !anyDuplicated(cohort[c("unit_id", "date")]),
          !anyDuplicated(plots$unit_id),
          all(count(plots, block, variety_code, dose_ml_per_ft)$n == 1L),
          all(count(plots, variety_code, dose_ml_per_ft)$n == 6L),
          setequal(plots$variety_code, c(1, 2)),
          setequal(plots$dose_ml_per_ft, c(0, 2, 3, 4, 5)))
changed <- cohort |>
  filter(abs(entry_severity - severity) > 1e-7) |>
  select(unit_id, block, treatment, date, severity, entry_severity, field_file,
         rating_sheet, rating_row, entry_sheet, entry_row, entry_column)
save_csv(changed, "rating_disagreements", detail = TRUE)

ratings <- cohort |>
  select(unit_id, block, variety_code, dose_ml_per_ft, treatment, date,
         `Long sheet` = severity, `Field entries` = entry_severity) |>
  pivot_longer(all_of(version_levels), names_to = "version", values_to = "severity") |>
  arrange(unit_id, version, date)
endpoint_dates <- ratings |>
  group_by(unit_id, version) |>
  summarise(final_severity = last(severity),
            audpc = sum(diff(as.integer(date)) *
                          (head(severity, -1L) + tail(severity, -1L)) / 2),
            .groups = "drop") |>
  left_join(plots, by = "unit_id", relationship = "many-to-one")
save_csv(endpoint_dates, "plot_season_summaries", detail = TRUE)

first_detection <- function(events, label) {
  events |>
    group_by(unit_id, version) |>
    summarise(first_detected = first(date[detected], default = as.Date(NA)),
              last_below = last(date[!detected & (is.na(first_detected) | date < first_detected)],
                                default = as.Date(NA)), .groups = "drop") |>
    mutate(censoring = case_when(is.na(first_detected) ~ "right",
                                is.na(last_below) ~ "left", TRUE ~ "interval"),
           threshold = label)
}
detection <- bind_rows(
  first_detection(mutate(ratings, detected = severity > 0), "Above zero"),
  first_detection(mutate(ratings, detected = severity >= 5), "At least 5%")
)
save_csv(detection, "plot_detection_bounds", detail = TRUE)
save_csv(count(detection, version, threshold, censoring), "censoring_counts")

na_equal <- function(left, right) coalesce(left == right, is.na(left) & is.na(right))
paired_detection <- detection |>
  pivot_wider(names_from = version, values_from = c(first_detected, last_below, censoring),
              names_glue = "{.value}_{version}") |>
  mutate(first_visit_changed = !na_equal(`first_detected_Field entries`, `first_detected_Long sheet`),
         bound_changed = first_visit_changed | !na_equal(`last_below_Field entries`, `last_below_Long sheet`),
         censoring_changed = `censoring_Long sheet` != `censoring_Field entries`,
         advance_in_days = as.integer(`first_detected_Long sheet` - `first_detected_Field entries`))
save_csv(filter(paired_detection, bound_changed), "changed_detection_bounds", detail = TRUE)
save_csv(paired_detection |>
           group_by(threshold) |>
           summarise(plots = n(), first_visit_changed = sum(first_visit_changed),
                     interval_changed = sum(bound_changed), censoring_changed = sum(censoring_changed),
                     max_days_earlier = max(c(0, advance_in_days), na.rm = TRUE),
                     .groups = "drop"),
         "detection_version_comparison")

endpoints <- endpoint_dates |>
  pivot_longer(c(final_severity, audpc), names_to = "outcome", values_to = "value")
save_csv(endpoints |>
           pivot_wider(id_cols = c(unit_id, outcome), names_from = version, values_from = value) |>
           mutate(delta = `Field entries` - `Long sheet`) |>
           group_by(outcome) |>
           summarise(plots = n(), changed_plots = sum(abs(delta) > 1e-7),
                     mean_change = mean(delta), max_abs_change = max(abs(delta)), .groups = "drop"),
         "season_endpoint_version_comparison")

trajectory <- ratings |>
  left_join(select(filter(detection, threshold == "Above zero"), -threshold, -censoring, -last_below),
            by = c("unit_id", "version"), relationship = "many-to-one") |>
  mutate(detected_percent = 100 * (!is.na(first_detected) & first_detected <= date))
save_csv(trajectory |>
           group_by(version, treatment, variety_code, dose_ml_per_ft, date) |>
           summarise(plots = n(), severity_percent = mean(severity),
                     cumulative_detection_percent = mean(detected_percent), .groups = "drop"),
         "treatment_visit_means")
trial_means <- trajectory |>
  group_by(version, date) |>
  summarise(plots = n(), severity_percent = mean(severity),
            cumulative_detection_percent = mean(detected_percent), .groups = "drop")
save_csv(trial_means, "trial_visit_means")

# Complete factorial blocks allow equal weights over the other factor.
contrasts <- function(data, time_columns) {
  levels <- c("P20T79R2 minus S24-K2", "Nonzero dose minus zero")
  split_contrast <- function(active, label) {
    data |>
      mutate(active = active) |>
      group_by(version, outcome, across(all_of(time_columns)), block) |>
      summarise(difference = mean(value[active]) - mean(value[!active]), .groups = "drop") |>
      group_by(version, outcome, across(all_of(time_columns))) |>
      summarise(blocks = n(), estimate = mean(difference),
                margin = qt(0.975, blocks - 1L) * sd(difference) / sqrt(blocks), .groups = "drop") |>
      mutate(contrast = label, lower = estimate - margin, upper = estimate + margin) |>
      select(-margin)
  }
  bind_rows(split_contrast(data$variety_code == 1, levels[[1L]]),
            split_contrast(data$dose_ml_per_ft > 0, levels[[2L]]))
}
visit_contrasts <- trajectory |>
  pivot_longer(c(severity, detected_percent), names_to = "outcome", values_to = "value") |>
  contrasts("date")
season_contrasts <- contrasts(endpoints, character())
save_csv(visit_contrasts, "visit_contrasts")
save_csv(season_contrasts, "season_contrasts")

compare_contrasts <- function(data, dates) {
  data |>
    select(outcome, contrast, all_of(dates), version, estimate) |>
    pivot_wider(names_from = version, values_from = estimate) |>
    mutate(change = `Field entries` - `Long sheet`)
}
save_csv(compare_contrasts(visit_contrasts, "date"), "visit_contrast_version_comparison")
save_csv(compare_contrasts(season_contrasts, character()), "season_contrast_version_comparison")

early <- filter(trial_means, date <= dates[[4L]])
figure <- ggplot(early, aes(date, cumulative_detection_percent, colour = version,
                            shape = version, linetype = version)) +
  geom_step(linewidth = 0.9) +
  geom_point(size = 2.5) +
  scale_colour_manual(values = c("Long sheet" = "#216C60", "Field entries" = "#AA4934")) +
  scale_x_date(date_labels = "%b %d", breaks = dates[1:4]) +
  labs(title = "Hinds 2018 first detection by severity source",
       x = "Assessment date", y = "Plots detected by this date (%)",
       colour = NULL, shape = NULL, linetype = NULL,
       caption = "Early assessment window. Each plot represents 1.67 percentage points.") +
  theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        plot.title.position = "plot", plot.caption.position = "plot",
        plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "early_detection_versions.png"), figure, width = 9.5, height = 4.8,
       bg = "white", dpi = 180, device = ragg::agg_png)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg")
save_csv(tibble(component = c("R", packages),
                version = c(as.character(getRversion()),
                            vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software")
