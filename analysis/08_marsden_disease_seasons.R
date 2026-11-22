# Run from the repository root. Optional argument sets the output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
source("analysis/marsden_disease_methods.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
out <- if (length(args)) args[[1L]] else "results/marsden_disease"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name, detail = FALSE) {
  directory <- if (detail) file.path(out, "local") else out
  write.csv(data, file.path(directory, paste0(name, ".csv")), row.names = FALSE, na = "")
}
source_file <- "data/Marsden_SDS.csv"
inventory <- read.csv("audit/tables/inventory.csv")
expected <- inventory$sha256[inventory$file == source_file]
stopifnot(identical(digest::digest(source_file, file = TRUE, algo = "sha256"), expected))
disease <- read.csv(source_file) |>
  mutate(source_row = row_number() + 1L) |>
  transmute(year = as.integer(substr(Date, 1L, 4L)), date = as.Date(Date),
            block = Block, plot = Plot, rotation = Rotation, quadrat = Quadrat,
            unit_id = paste("Marsden", year, Quadrat, sep = "/"), severity = Severity,
            incidence = Incidence, source_file, source_row)
registry <- distinct(disease, year, block, plot, rotation, quadrat, unit_id)
design <- distinct(registry, year, block, plot, rotation)
map <- read.csv("audit/evidence/marsden_year_map_checks.csv") |>
  filter(stream == "Disease") |>
  transmute(year, block, plot, rotation = slide_rotation)
stopifnot(!anyNA(disease), all(between(disease$severity, 0, 100)),
          all(between(disease$incidence, 0, 100)), !anyDuplicated(registry$unit_id),
          !anyDuplicated(disease[c("unit_id", "date")]),
          nrow(anti_join(filter(design, year %in% 2017:2018), map,
                         by = c("year", "block", "plot", "rotation"))) == 0L,
          nrow(anti_join(map, design, by = c("year", "block", "plot", "rotation"))) == 0L,
          all(count(design, year, block)$n == 3L),
          all(count(design, year, block, rotation)$n == 1L),
          all(count(design, year)$n == 12L))
save_csv(registry, "unit_registry", detail = TRUE)
save_csv(count(registry, year, block, plot, rotation, name = "quadrats"), "plot_sizes")

summarize_pair <- function(data, pair, group_columns, outcome) {
  differences <- data |>
    filter(rotation %in% pair) |>
    select(all_of(c(group_columns, outcome, "block", "rotation"))) |>
    pivot_wider(names_from = rotation, values_from = all_of(outcome)) |>
    mutate(difference = .data[[pair[[1L]]]] - .data[[pair[[2L]]]])
  differences |>
    group_by(across(all_of(group_columns))) |>
    summarise(blocks = n(), estimate = mean(difference),
              margin = qt(0.975, df = blocks - 1L) * sd(difference) / sqrt(blocks),
              .groups = "drop") |>
    mutate(contrast = paste(pair, collapse = " minus "), outcome = .env$outcome,
           lower = estimate - margin, upper = estimate + margin) |>
    select(-margin)
}
contrasts <- combn(sort(unique(disease$rotation)), 2, simplify = FALSE)
plot_dates <- disease |>
  group_by(year, block, plot, rotation, date) |>
  summarise(quadrats = n(), severity = mean(severity), .groups = "drop")
visits <- distinct(disease, year, date) |> count(year, name = "visits")
unit_visits <- count(disease, unit_id, year) |>
  inner_join(visits, by = "year", relationship = "many-to-one")
stopifnot(all(count(plot_dates, year, date)$n == 12L),
          all(unit_visits$n == unit_visits$visits))
season_fit <- function(season) {
  profiles <- filter(plot_dates, year == season)
  dates <- sort(unique(profiles$date))
  gaps <- diff(as.integer(dates))
  duration <- sum(gaps)
  weights <- (c(0, gaps) + c(gaps, 0)) / (2 * duration)
  tests <- marsden_permutation(profiles, dates, weights, duration) |> mutate(year = season, .before = 1)
  endpoints <- profiles |>
    group_by(year, block, plot, rotation) |>
    arrange(date, .by_group = TRUE) |>
    summarise(final_severity = last(severity), window_mean_severity = sum(severity * weights),
              audpc = window_mean_severity * duration, .groups = "drop")
  list(tests = tests, endpoints = endpoints)
}
fits <- lapply(sort(unique(disease$year)), season_fit)
save_csv(bind_rows(lapply(fits, function(fit) fit$tests)), "permutation")
endpoints <- bind_rows(lapply(fits, function(fit) fit$endpoints))
save_csv(endpoints, "plot_endpoints")
save_csv(plot_dates, "plot_visit_severity")
means <- plot_dates |>
  group_by(year, rotation, date) |>
  summarise(blocks = n(), mean_severity = mean(severity), .groups = "drop")
save_csv(means, "rotation_visit_means")
save_csv(bind_rows(lapply(contrasts, function(pair) {
  summarize_pair(plot_dates, pair, c("year", "date"), "severity")
})), "dated_severity_contrasts")
season_endpoints <- bind_rows(lapply(contrasts, function(pair) {
  bind_rows(lapply(c("final_severity", "window_mean_severity", "audpc"), function(endpoint) {
    summarize_pair(endpoints, pair, "year", endpoint)
  }))
}))
save_csv(season_endpoints, "season_endpoint_contrasts")
full_2018 <- filter(season_endpoints, year == 2018L) |> mutate(panel = "All four blocks")
balanced_2018 <- bind_rows(lapply(contrasts, function(pair) {
  bind_rows(lapply(c("final_severity", "window_mean_severity"), function(endpoint) {
    summarize_pair(filter(endpoints, year == 2018L, block != 4L), pair, "year", endpoint)
  }))
})) |> mutate(panel = "Three blocks with 10 quadrats per plot")
save_csv(bind_rows(filter(full_2018, outcome != "audpc"), balanced_2018), "marsden2018_block_sensitivity")

detect <- function(records, definition) {
  records |>
    arrange(unit_id, date) |>
    group_by(year, block, plot, rotation, unit_id) |>
    summarise(first_positive = first(date[positive], default = as.Date(NA)),
              last_negative = last(date[!positive & (is.na(first_positive) | date < first_positive)],
                                   default = as.Date(NA)), .groups = "drop") |>
    mutate(censoring = case_when(is.na(first_positive) ~ "right",
                                is.na(last_negative) ~ "left", TRUE ~ "interval"),
           definition = .env$definition)
}
bounds <- bind_rows(detect(mutate(disease, positive = severity > 0), "Severity above zero"),
                    detect(mutate(disease, positive = severity >= 5), "Severity at least 5%"),
                    detect(mutate(disease, positive = incidence > 0), "Incidence above zero"))
save_csv(bounds, "detection_bounds", detail = TRUE)
save_csv(count(bounds, year, rotation, definition, censoring), "censoring_counts")
detection <- disease |>
  inner_join(select(bounds, unit_id, definition, first_positive, censoring), by = "unit_id",
             relationship = "many-to-many") |>
  mutate(ever_detected = !is.na(first_positive) & first_positive <= date)
stopifnot(nrow(detection) == 3L * nrow(disease))
plot_detection <- detection |>
  group_by(year, block, plot, rotation, date, definition) |>
  summarise(percent_detected = 100 * mean(ever_detected), .groups = "drop")
save_csv(plot_detection |>
           group_by(year, rotation, date, definition) |>
           summarise(blocks = n(), percent_detected = mean(percent_detected), .groups = "drop"),
         "rotation_detection")

pair_bounds <- bounds |>
  select(year, rotation, unit_id, definition, first_positive, censoring) |>
  pivot_wider(names_from = definition, values_from = c(first_positive, censoring))
different <- function(a, b) coalesce(a != b, xor(is.na(a), is.na(b)))
save_csv(pair_bounds |>
           group_by(year, rotation) |>
           summarise(quadrats = n(),
                     first_visit_diff_incidence = sum(different(`first_positive_Severity above zero`,
                                                                `first_positive_Incidence above zero`)),
                     first_visit_diff_5pct = sum(different(`first_positive_Severity above zero`,
                                                           `first_positive_Severity at least 5%`)),
                     censoring_diff_incidence = sum(`censoring_Severity above zero` !=
                                                     `censoring_Incidence above zero`),
                     censoring_diff_5pct = sum(`censoring_Severity above zero` !=
                                                `censoring_Severity at least 5%`), .groups = "drop"),
         "detection_definition_disagreements")

positive <- filter(detection, definition == "Severity above zero")
final <- positive |>
  group_by(year) |>
  filter(date == max(date)) |>
  group_by(year, block, rotation) |>
  summarise(fraction = mean(ever_detected),
            among_detected = if (any(ever_detected)) mean(severity[ever_detected]) else NA_real_,
            mean_severity = mean(severity), .groups = "drop")
components <- bind_rows(lapply(contrasts, function(pair) {
  wide <- final |>
    filter(rotation %in% pair) |>
    pivot_wider(names_from = rotation, values_from = c(fraction, among_detected, mean_severity))
  value <- function(metric, rotation) wide[[paste(metric, rotation, sep = "_")]]
  f1 <- value("fraction", pair[[1L]])
  f2 <- value("fraction", pair[[2L]])
  m1 <- value("among_detected", pair[[1L]])
  m2 <- value("among_detected", pair[[2L]])
  wide |>
    transmute(year, block, contrast = paste(pair, collapse = " minus "),
              contrast_pp = value("mean_severity", pair[[1L]]) - value("mean_severity", pair[[2L]]),
              detected_fraction_component = (f1 - f2) * (m1 + m2) / 2,
              among_detected_component = (m1 - m2) * (f1 + f2) / 2)
}))
error <- with(components, contrast_pp - detected_fraction_component - among_detected_component)
stopifnot(all(abs(error[!is.na(error)]) < 1e-9))
save_csv(components, "decomposition_by_block")
save_csv(components |>
           group_by(year, contrast) |>
           summarise(blocks = sum(!is.na(detected_fraction_component)),
                     contrast_pp = mean(contrast_pp[!is.na(detected_fraction_component)]),
                     detected_fraction_component = mean(detected_fraction_component, na.rm = TRUE),
                     among_detected_component = mean(among_detected_component, na.rm = TRUE),
                     .groups = "drop"),
         "final_severity_decomposition")
subsequent <- positive |>
  group_by(unit_id) |>
  arrange(date, .by_group = TRUE) |>
  mutate(next_gain = lead(severity) - severity, lag_days = as.integer(lead(date) - date)) |>
  ungroup() |>
  filter(censoring == "interval", date == first_positive, !is.na(next_gain))
save_csv(subsequent |>
           group_by(year, rotation, block, plot) |>
           summarise(quadrats = n(), mean_gain_pp = mean(next_gain),
                     min_days = min(lag_days), max_days = max(lag_days), .groups = "drop") |>
           group_by(year, rotation) |>
           summarise(plots = n(), quadrats = sum(quadrats), mean_gain_pp = mean(mean_gain_pp),
                     min_days = min(min_days), max_days = max(max_days), .groups = "drop"),
         "first_followup_severity")

palette <- c(S2 = "#AA412E", S3 = "#216C60", S4 = "#40558F")
style <- theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        panel.spacing.x = grid::unit(1.8, "lines"), plot.title.position = "plot",
        plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
assessment_breaks <- function(limits) {
  dates <- sort(unique(disease$date[between(disease$date, limits[[1L]], limits[[2L]])]))
  dates[unique(round(seq(1, length(dates), length.out = min(3, length(dates)))))]
}
severity_figure <- ggplot(plot_dates, aes(date, severity, colour = rotation)) +
  geom_line(aes(group = plot), alpha = 0.27, linewidth = 0.55) +
  geom_line(data = means, aes(y = mean_severity, group = rotation), linewidth = 1.15) +
  geom_point(data = means, aes(y = mean_severity), size = 2) +
  facet_wrap(vars(year), scales = "free_x", nrow = 1L) +
  scale_colour_manual(values = palette) +
  scale_x_date(date_labels = "%b %d", breaks = assessment_breaks,
               expand = expansion(mult = 0.09)) +
  labs(title = "Marsden severity trajectories by cropping system",
       x = "Assessment date", y = "Mean plot severity (%)", colour = "Cropping system",
       caption = "Thin lines represent main plots. Thick lines give equal weight to each of four blocks.") + style
detection_figure <- plot_detection |>
  filter(definition == "Severity above zero") |>
  group_by(year, rotation, date) |>
  summarise(percent_detected = mean(percent_detected), .groups = "drop") |>
  ggplot(aes(date, percent_detected, colour = rotation, group = rotation)) +
  geom_step(linewidth = 1.1) +
  geom_point(size = 2) +
  facet_wrap(vars(year), scales = "free_x", nrow = 1L) +
  scale_colour_manual(values = palette) +
  scale_x_date(date_labels = "%b %d", breaks = assessment_breaks,
               expand = expansion(mult = 0.09)) +
  scale_y_continuous(limits = c(0, 100)) +
  labs(title = "Marsden cumulative first detection of positive severity",
       x = "Assessment date", y = "Quadrats detected (%)", colour = "Cropping system",
       caption = "Plot proportions are averaged across four blocks. Steps occur at recorded assessments.") + style
ggsave(file.path(out, "severity_trajectories.png"), severity_figure, width = 11.3, height = 5.2,
       dpi = 180, bg = "white", device = ragg::agg_png)
ggsave(file.path(out, "first_detection.png"), detection_figure, width = 11.3, height = 5.2,
       dpi = 180, bg = "white", device = ragg::agg_png)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg", "digest")
save_csv(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                   vapply(packages, function(x) as.character(packageVersion(x)), character(1)))), "software")
