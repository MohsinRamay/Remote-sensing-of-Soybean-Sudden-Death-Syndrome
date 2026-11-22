# Run after 08_marsden_disease_seasons.R, from the repository root.
# Optional arguments: output directory and Marsden disease-season output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1L]] else "results/early_warning"
prepared <- if (length(args) == 2L) args[[2L]] else "results/marsden_disease"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, filename, detail = FALSE) {
  target <- if (detail) file.path(out, "local") else out
  write.csv(data, file.path(target, paste0(filename, ".csv")), row.names = FALSE, na = "")
}
inventory <- read.csv("audit/tables/inventory.csv")
read_input <- function(path) {
  expected <- inventory$sha256[inventory$file == path]
  stopifnot(identical(digest::digest(path, algo = "sha256", file = TRUE), expected))
  read.csv(path)
}
key <- function(year, quadrat) paste("Marsden", year, quadrat, sep = "/")
visits <- read_input("data/Marsden_SDS.csv") |>
  transmute(year = as.integer(substr(Date, 1L, 4L)), landmark = as.Date(Date),
            unit_id = key(year, Quadrat), block = Block, plot = Plot, rotation = Rotation) |>
  group_by(unit_id) |>
  arrange(landmark, .by_group = TRUE) |>
  mutate(next_assessment = lead(landmark), gap_days = as.integer(next_assessment - landmark)) |>
  ungroup()
bounds <- read.csv(file.path(prepared, "local", "detection_bounds.csv")) |>
  transmute(year, unit_id, block, plot, rotation, definition, first_positive = as.Date(first_positive))
stopifnot(!anyDuplicated(visits[c("unit_id", "landmark")]),
          !anyDuplicated(bounds[c("unit_id", "definition")]), all(count(bounds, unit_id)$n == 3L))
unit_keys <- c("year", "unit_id", "block", "plot", "rotation")
stopifnot(nrow(anti_join(visits, bounds, by = unit_keys)) == 0L,
          nrow(anti_join(bounds, visits, by = unit_keys)) == 0L,
          all(is.na(visits$gap_days) | visits$gap_days > 0))
spectra <- read_input("data/Marsden_RFL.csv") |>
  filter(Wavelength %in% c(660L, 810L), is.finite(Reflectance)) |>
  transmute(year = as.integer(substr(DATE, 1L, 4L)), unit_id = key(year, Quadrat),
            acquisition = as.Date(DATE), band = Wavelength)
stopifnot(!anyDuplicated(spectra[c("unit_id", "acquisition", "band")]))
spectral_dates <- spectra |>
  count(year, unit_id, acquisition) |>
  filter(n == 2L) |>
  select(-n)
upcoming <- visits |>
  left_join(spectral_dates, by = join_by(year, unit_id, closest(landmark > acquisition)),
            relationship = "many-to-one") |>
  inner_join(bounds, by = unit_keys, relationship = "many-to-many") |>
  mutate(status = case_when(!is.na(first_positive) & first_positive <= landmark ~ "Already detected",
                            is.na(gap_days) ~ "No next assessment",
                            gap_days > 10L ~ "Next assessment beyond 10 days",
                            TRUE ~ "Eligible"),
         eligible = status == "Eligible",
         event = if_else(eligible, !is.na(first_positive) & first_positive == next_assessment, NA),
         spectral_age_days = as.integer(landmark - acquisition),
         spectra_ready = eligible & coalesce(spectral_age_days <= 7L, FALSE),
         fold = block) |>
  arrange(year, definition, landmark, block, plot, unit_id)
stopifnot(nrow(upcoming) == 3L * nrow(visits), all(is.na(upcoming$acquisition) | upcoming$acquisition < upcoming$landmark),
          all(upcoming$gap_days[upcoming$eligible] >= 1L),
          all(upcoming$gap_days[upcoming$eligible] <= 10L))
save_csv(upcoming, "landmark_eligibility", detail = TRUE)
save_csv(count(upcoming, year, definition, landmark, status), "eligibility_status")
coverage <- upcoming |>
  group_by(year, definition, landmark, next_assessment, gap_days) |>
  summarise(assessed = n(), at_risk = sum(eligible), next_positive = sum(event, na.rm = TRUE),
            with_recent_spectrum = sum(spectra_ready),
            positive_with_spectrum = sum(event[spectra_ready]), .groups = "drop")
save_csv(coverage, "landmark_coverage")

eligible <- filter(upcoming, eligible) |>
  select(year, definition, landmark, block, plot, rotation, unit_id, event, spectra_ready, fold)
sets <- bind_rows(mutate(eligible, denominator = "All eligible"),
                  mutate(filter(eligible, spectra_ready), denominator = "Spectrum matched"))
support <- sets |>
  group_by(year, definition, denominator, landmark, block, plot) |>
  summarise(opportunities = n(), events = sum(event), .groups = "drop") |>
  group_by(year, definition, denominator) |>
  summarise(plot_landmarks = n(), mixed_outcome_plot_landmarks = sum(events > 0 & events < opportunities),
            opportunities = sum(opportunities), events = sum(events), .groups = "drop")
save_csv(support, "within_plot_support")

train_rates <- function(training, keys) {
  training |>
    group_by(across(all_of(keys))) |>
    summarise(probability = (sum(event) + 0.5) / (n() + 1), .groups = "drop")
}
score_fold <- function(data, held_out) {
  training <- filter(data, fold != held_out)
  test <- filter(data, fold == held_out)
  stopifnot(nrow(training) > 0L, nrow(test) > 0L, !any(test$unit_id %in% training$unit_id))
  overall <- train_rates(training, character())$probability
  scored <- test |>
    left_join(rename(train_rates(training, "rotation"), rotation_rate = probability),
              by = "rotation", relationship = "many-to-one") |>
    left_join(rename(train_rates(training, "landmark"), visit_rate = probability),
              by = "landmark", relationship = "many-to-one") |>
    left_join(rename(train_rates(training, c("landmark", "rotation")), joint_rate = probability),
              by = c("landmark", "rotation"), relationship = "many-to-one")
  output <- function(model, risk, fallback) {
    scored |>
      select(landmark, rotation, unit_id, plot, fold, event) |>
      mutate(model = .env$model, risk = .env$risk, fallback = .env$fallback)
  }
  bind_rows(output("Constant", overall, FALSE),
            output("Cropping system", coalesce(scored$rotation_rate, overall), is.na(scored$rotation_rate)),
            output("Visit", coalesce(scored$visit_rate, overall), is.na(scored$visit_rate)),
            output("Visit × cropping system", coalesce(scored$joint_rate, scored$visit_rate, overall),
                   is.na(scored$joint_rate)))
}
predictions <- sets |>
  group_by(year, definition, denominator) |>
  group_modify(function(data, key) {
    bind_rows(lapply(sort(unique(data$fold)), function(held_out) score_fold(data, held_out)))
  }) |>
  ungroup()
stopifnot(nrow(predictions) == 4L * nrow(sets),
          !anyDuplicated(predictions[c("year", "definition", "denominator", "landmark", "unit_id", "model")]),
          all(predictions$risk > 0 & predictions$risk < 1))
save_csv(predictions, "heldout_predictions", detail = TRUE)

# Group tied scores for threshold-based average precision. AUROC uses midranks.
metric_values <- function(risk, event) {
  positives <- sum(event)
  negatives <- length(event) - positives
  ranked <- tibble(risk, event) |>
    group_by(risk) |>
    summarise(positive = sum(event), total = n(), .groups = "drop") |>
    arrange(desc(risk))
  precision <- cumsum(ranked$positive) / cumsum(ranked$total)
  tibble(opportunities = length(event), events = positives, event_rate = mean(event),
         brier = mean((risk - event)^2),
         auroc = if (positives * negatives > 0) {
           (sum(rank(risk)[event]) - positives * (positives + 1) / 2) / (positives * negatives)
         } else NA_real_,
         average_precision = if (positives > 0) sum(precision * ranked$positive) / positives else NA_real_)
}
key_columns <- c("year", "definition", "denominator", "model")
scores <- function(keys) {
  predictions |>
    group_by(across(all_of(keys))) |>
    group_modify(function(data, key) {
      metric_values(data$risk, data$event) |> mutate(fallback_rows = sum(data$fallback))
    }) |>
    ungroup()
}
block_performance <- scores(c(key_columns, "fold"))
within_block <- block_performance |>
  mutate(pairs = events * (opportunities - events)) |>
  filter(pairs > 0L) |>
  group_by(across(all_of(key_columns))) |>
  summarise(blocks_with_both_outcomes = n(), within_block_pairs = sum(pairs),
            within_block_auroc = weighted.mean(auroc, pairs), .groups = "drop")
performance <- scores(key_columns) |>
  left_join(within_block, by = key_columns, relationship = "one-to-one")
save_csv(performance, "baseline_metrics")
save_csv(block_performance, "block_metrics")
save_csv(performance |>
           select(all_of(key_columns), brier, auroc, within_block_auroc, average_precision) |>
           pivot_wider(names_from = model, values_from = c(brier, auroc, within_block_auroc,
                                                         average_precision)) |>
           mutate(brier_gain_cropping_system = brier_Constant - `brier_Cropping system`,
                  brier_gain_cropping_system_given_visit = brier_Visit - `brier_Visit × cropping system`),
         "baseline_comparison")

figure <- filter(coverage, definition == "Severity above zero", at_risk > 0L) |>
  pivot_longer(c(at_risk, with_recent_spectrum), names_to = "cohort", values_to = "opportunities") |>
  mutate(cohort = recode_values(cohort, "at_risk" ~ "All eligible",
                               "with_recent_spectrum" ~ "Spectrum matched")) |>
  ggplot(aes(landmark, opportunities, group = cohort, colour = cohort, shape = cohort)) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.5) +
  facet_wrap(vars(year), scales = "free_x", nrow = 1) +
  scale_x_date(date_labels = "%b %d", breaks = function(limits) {
    observed <- sort(unique(filter(coverage, at_risk > 0)$landmark))
    observed <- observed[observed >= limits[[1L]] & observed <= limits[[2L]]]
    observed[unique(round(seq(1, length(observed), length.out = min(3, length(observed)))))]
  }, expand = expansion(mult = 0.08)) +
  scale_colour_manual(values = c("All eligible" = "#216C60", "Spectrum matched" = "#40558F")) +
  labs(title = "Marsden early-warning opportunities by scouting visit",
       x = "Prediction landmark", y = "Eligible quadrats", colour = NULL, shape = NULL,
       caption = "Spectrum matched requires 660 nm and 810 nm from the same prior acquisition within seven days.") +
  theme_minimal(base_size = 14) +
  theme(panel.grid.minor = element_blank(), panel.spacing.x = grid::unit(1.7, "lines"),
        legend.position = "bottom", plot.title.position = "plot",
        plot.caption.position = "plot", plot.caption = element_text(hjust = 0))
ggsave(file.path(out, "eligibility_coverage.png"), figure, width = 11.2, height = 4.8,
       dpi = 180, bg = "white", device = ragg::agg_png)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg", "digest")
save_csv(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                  vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software")
