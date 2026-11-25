# Run after 09_marsden_early_warning.R. Optional arguments: output and baseline directories.
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
source("analysis/marsden_early_warning_methods.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1L]] else "results/exploration"
prepared <- if (length(args) == 2L) args[[2L]] else "results/early_warning"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name) write.csv(data, file.path(out, paste0("warning_", name, ".csv")),
                                            row.names = FALSE, na = "")
frozen <- read.csv(file.path(prepared, "local", "landmark_eligibility.csv")) |>
  filter(spectra_ready) |>
  mutate(across(c(landmark, acquisition), as.Date))
source_file <- "data/Marsden_RFL.csv"
inventory <- read.csv("audit/tables/inventory.csv")
stopifnot(identical(digest::digest(source_file, algo = "sha256", file = TRUE),
                    inventory$sha256[inventory$file == source_file]))
bands <- c("nm660", "nm810")
spectra <- paired_spectra(read.csv(source_file)) |> rename(history_date = acquisition)
visits <- distinct(frozen, year, unit_id, landmark, acquisition) |>
  mutate(history_start = landmark - 21L)
history <- visits |>
  inner_join(spectra, by = join_by(year, unit_id, landmark > history_date,
                                  history_start <= history_date), relationship = "many-to-many") |>
  arrange(history_date) |>
  mutate(weeks = as.numeric(history_date - landmark) / 7)
stopifnot(all(history$weeks < 0 & history$weeks >= -3))
features <- history |>
  group_by(year, unit_id, landmark) |>
  group_modify(function(data, key) {
    y <- as.matrix(data[bands])
    latest <- nrow(data)
    stopifnot(data$history_date[[latest]] == data$acquisition[[latest]])
    # A linear trend and a two-term polynomial basis fitted to each observed prefix.
    # Center time at the latest acquisition for the polynomial fit.
    t <- data$weeks - data$weeks[[latest]]
    linear <- if (latest >= 2L) qr.coef(qr(cbind(1, t)), y)[2L, ] else c(NA, NA)
    quadratic <- if (latest >= 3L) qr.coef(qr(cbind(1, t, t^2)), y)[3L, ] else c(NA, NA)
    tibble(acquisitions = latest, nm660 = y[latest, 1L], nm810 = y[latest, 2L],
           slope660 = linear[[1L]], slope810 = linear[[2L]],
           curve660 = quadratic[[1L]], curve810 = quadratic[[2L]])
  }) |>
  ungroup()
data <- left_join(frozen, features, by = c("year", "unit_id", "landmark"), relationship = "many-to-one")
stopifnot(!anyNA(data$acquisitions))
save_csv(data |>
           group_by(year, definition, landmark) |>
           summarise(matched = n(), matched_events = sum(event),
                     linear = sum(acquisitions >= 2L), linear_events = sum(event[acquisitions >= 2L]),
                     quadratic = sum(acquisitions >= 3L),
                     quadratic_events = sum(event[acquisitions >= 3L]), .groups = "drop"),
         "history_coverage")

fit <- function(data, held_out, quadratic) {
  training <- filter(data, fold != held_out)
  test <- filter(data, fold == held_out)
  stopifnot(!any(test$unit_id %in% training$unit_id))
  train <- baseline_rates(training, training)
  test <- baseline_rates(test, training)
  test <- mutate(test, cropping = coalesce(rotation_rate, overall_rate),
                 visit = coalesce(visit_rate, overall_rate))
  band_sets <- list(Latest = bands, `Latest + slopes` = c(bands, "slope660", "slope810"))
  if (quadratic) band_sets[["Latest + slopes + curvature"]] <-
    c(band_sets[["Latest + slopes"]], "curve660", "curve810")
  for (model in names(band_sets)) {
    test[[model]] <- spectral_ridge_risk(train, test, band_sets[[model]],
                                        qlogis(train$joint_risk), qlogis(test$joint_risk))
  }
  test |>
    select(fold, plot, unit_id, landmark, event, `Cropping system` = cropping,
           Visit = visit, `Visit × cropping system` = joint_risk, all_of(names(band_sets))) |>
    pivot_longer(-c(fold, plot, unit_id, landmark, event), names_to = "model", values_to = "risk")
}
compare <- function(minimum) {
  filter(data, acquisitions >= minimum) |>
    group_by(year, definition) |>
    group_modify(function(data, key) {
      folds <- sort(unique(data$fold))
      if (length(folds) != 4L || n_distinct(data$event) != 2L) return(tibble())
      bind_rows(lapply(folds, function(held_out) fit(data, held_out, minimum == 3L)))
    }) |>
    ungroup() |>
    mutate(min_acquisitions = minimum)
}
predictions <- bind_rows(compare(2L), compare(3L))
write.csv(predictions, file.path(out, "local", "warning_predictions.csv"), row.names = FALSE)

metric_keys <- c("year", "definition", "min_acquisitions", "model")
summarize_pairs <- function(strata) {
  predictions |>
    group_by(across(all_of(c(metric_keys, strata)))) |>
    summarise(pairs = sum(event) * sum(!event), auroc = pair_auroc(risk, event), .groups = "drop") |>
    filter(pairs > 0L) |>
    group_by(across(all_of(metric_keys))) |>
    summarise(strata = n(), auroc = weighted.mean(auroc, pairs), pairs = sum(pairs), .groups = "drop")
}
scored <- predictions |>
  group_by(across(all_of(metric_keys))) |>
  group_modify(function(data, key) metric_values(data$risk, data$event)) |>
  ungroup() |>
  left_join(rename(summarize_pairs("fold"), blocks = strata,
                   block_pairs = pairs, within_block_auroc = auroc), by = metric_keys) |>
  left_join(rename(summarize_pairs(c("fold", "plot", "landmark")), mixed_plot_visits = strata,
                   plot_visit_pairs = pairs, within_plot_visit_auroc = auroc), by = metric_keys)
save_csv(scored, "trajectory_metrics")

# Slides 2–4 of Marsden Schemes show the same four physical blocks. Exclude the
# target block in all source seasons, so recurring plots cannot enter training.
# Dates use a common non-leap calendar. No target-season rates are used.
transfer_data <- data |>
  mutate(calendar_day = as.integer(as.Date(paste0("2001-", format(landmark, "%m-%d"))) -
                                      as.Date("2001-08-01")))
rotation_rates <- function(target, training) {
  target |>
    left_join(train_rates(training, "rotation"), by = "rotation", relationship = "many-to-one") |>
    mutate(probability = coalesce(probability, train_rates(training, character())$probability))
}
transfer <- transfer_data |>
  group_by(definition) |>
  group_modify(function(data, key) {
    seasons <- sort(unique(data$year))
    bind_rows(lapply(seasons, function(year) {
      target <- filter(data, .data$year == .env$year)
      bind_rows(lapply(sort(unique(target$fold)), function(block) {
        train <- filter(data, .data$year != .env$year, fold != .env$block)
        test <- filter(target, fold == .env$block)
        stopifnot(!any(test$year %in% train$year), !any(test$fold %in% train$fold))
        train <- rotation_rates(train, train)
        test <- rotation_rates(test, train)
        offset <- qlogis(train$probability)
        test_offset <- qlogis(test$probability)
        test |>
          mutate(`Cropping system` = probability,
                 `Calendar + cropping system` = spectral_ridge_risk(
                   train, test, "calendar_day", offset, test_offset),
                 `Calendar + cropping system + spectrum` = spectral_ridge_risk(
                   train, test, c("calendar_day", bands), offset, test_offset),
                 calendar_extrapolation = !between(calendar_day, min(train$calendar_day),
                                                    max(train$calendar_day))) |>
          select(year, fold, event, calendar_extrapolation, `Cropping system`,
                 `Calendar + cropping system`, `Calendar + cropping system + spectrum`) |>
          pivot_longer(-c(year, fold, event, calendar_extrapolation),
                       names_to = "model", values_to = "risk")
      }))
    }))
  }) |>
  ungroup()
scout_events <- function(risk, event) {
  threshold <- sort(risk, decreasing = TRUE)[ceiling(0.2 * length(risk))]
  above <- risk > threshold
  tied <- risk == threshold
  sum(event[above]) + sum(event[tied]) * (0.2 * length(risk) - sum(above)) / sum(tied)
}
transfer_keys <- c("year", "definition", "model")
block_transfer <- transfer |>
  group_by(across(all_of(c(transfer_keys, "fold")))) |>
  summarise(events = sum(event), pairs = sum(event) * sum(!event),
            auroc = pair_auroc(risk, event), top20_events = scout_events(risk, event),
            .groups = "drop") |>
  group_by(across(all_of(transfer_keys))) |>
  summarise(within_block_auroc = weighted.mean(auroc[pairs > 0], pairs[pairs > 0]),
            sensitivity_at_20pct = sum(top20_events) / sum(events), .groups = "drop")
save_csv(transfer |>
           group_by(across(all_of(transfer_keys))) |>
           group_modify(function(data, key) {
             metric_values(data$risk, data$event) |>
               mutate(mean_risk = mean(data$risk), extrapolated_rows = sum(data$calendar_extrapolation))
           }) |>
           ungroup() |>
           left_join(block_transfer, by = transfer_keys, relationship = "one-to-one"),
         "transfer_metrics")
