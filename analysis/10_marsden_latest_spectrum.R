# Run from the repository root after 09_marsden_early_warning.R.
# Optional arguments: output directory and early-warning baseline directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
source("analysis/marsden_early_warning_methods.R")

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1L]] else "results/early_warning"
baseline_dir <- if (length(args) == 2L) args[[2L]] else "results/early_warning"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)

save_csv <- function(data, name, detail = FALSE) {
  target <- if (detail) file.path(out, "local") else out
  write.csv(data, file.path(target, paste0("latest_spectrum_", name, ".csv")),
            row.names = FALSE, na = "")
}

frozen <- read.csv(file.path(baseline_dir, "local", "landmark_eligibility.csv")) |>
  filter(spectra_ready) |>
  mutate(landmark = as.Date(landmark), acquisition = as.Date(acquisition))
row_keys <- c("year", "definition", "landmark", "unit_id")
match_keys <- c(row_keys, "rotation", "plot", "fold", "event")
stopifnot(!anyDuplicated(frozen[row_keys]), !anyNA(frozen[match_keys]),
          all(frozen$eligible), all(frozen$fold == frozen$block),
          all(frozen$gap_days %in% 1:10),
          all(as.integer(frozen$landmark - frozen$acquisition) %in% 1:7),
          all(frozen$spectral_age_days == as.integer(frozen$landmark - frozen$acquisition)),
          all(count(distinct(frozen, year, definition, fold), year, definition)$n == 4L))

source_file <- "data/Marsden_RFL.csv"
inventory <- read.csv("audit/tables/inventory.csv")
expected <- inventory$sha256[inventory$file == source_file]
stopifnot(identical(digest::digest(source_file, file = TRUE, algo = "sha256"), expected))
spectra <- paired_spectra(read.csv(source_file))
matched <- frozen |>
  left_join(rename(spectra, latest = acquisition),
            by = join_by(year, unit_id, closest(landmark > latest)), relationship = "many-to-one")
stopifnot(all(matched$latest == matched$acquisition), all(is.finite(matched$nm660)),
          all(is.finite(matched$nm810)))

reference <- "Visit × cropping system"
baselines <- read.csv(file.path(baseline_dir, "local", "heldout_predictions.csv")) |>
  filter(denominator == "Spectrum matched") |>
  mutate(landmark = as.Date(landmark)) |>
  select(all_of(match_keys), model, risk, fallback)
stopifnot(!anyDuplicated(baselines[c(row_keys, "model")]),
          setequal(baselines$model, c("Constant", "Cropping system", "Visit", reference)),
          nrow(baselines) == 4L * nrow(matched),
          nrow(anti_join(baselines, matched, by = match_keys)) == 0L,
          all(baselines$risk > 0 & baselines$risk < 1))

bands <- c("nm660", "nm810")
spectral_model <- "Visit × cropping system + spectrum"
fit_fold <- function(data, held_out) {
  training <- filter(data, fold != held_out)
  test <- filter(data, fold == held_out)
  stopifnot(!any(test$unit_id %in% training$unit_id))
  train <- baseline_rates(training, training)
  test <- baseline_rates(test, training)
  risk <- spectral_ridge_risk(train, test, bands, qlogis(train$joint_risk), qlogis(test$joint_risk))

  test |>
    transmute(landmark, rotation, unit_id, plot, fold, event, fallback = is.na(joint_rate), offset_risk = joint_risk,
              model = spectral_model, risk)
}

added <- matched |>
  group_by(year, definition) |>
  group_modify(function(data, key) {
    bind_rows(lapply(sort(unique(data$fold)), function(held_out) fit_fold(data, held_out)))
  }) |>
  ungroup()
offset_check <- added |>
  inner_join(filter(baselines, model == reference), by = match_keys, relationship = "one-to-one")
stopifnot(nrow(added) == nrow(matched), nrow(offset_check) == nrow(matched),
          all(abs(offset_check$offset_risk - offset_check$risk.y) < 1e-14),
          all(offset_check$fallback.x == offset_check$fallback.y),
          all(added$risk > 0 & added$risk < 1))

predictions <- bind_rows(baselines, select(added, -offset_risk))
save_csv(predictions, "predictions", detail = TRUE)

metric_keys <- c("year", "definition", "model")
scores <- function(keys) {
  predictions |>
    group_by(across(all_of(keys))) |>
    group_modify(function(data, key) metric_values(data$risk, data$event)) |>
    ungroup()
}
block_metrics <- scores(c(metric_keys, "fold"))
within_block <- block_metrics |>
  mutate(pairs = events * (opportunities - events)) |>
  filter(pairs > 0) |>
  group_by(across(all_of(metric_keys))) |>
  summarise(blocks_with_both_outcomes = n(), within_block_pairs = sum(pairs),
            within_block_auroc = weighted.mean(auroc, pairs), .groups = "drop")
plot_metrics <- predictions |>
  group_by(across(all_of(c(metric_keys, "fold", "plot", "landmark")))) |>
  summarise(opportunities = n(), events = sum(event), auroc = pair_auroc(risk, event),
            .groups = "drop") |>
  mutate(pairs = events * (opportunities - events)) |>
  filter(pairs > 0)
within_plot <- function(keys) {
  plot_metrics |>
    group_by(across(all_of(keys))) |>
    summarise(mixed_plot_visits = n(), plots_with_mixed_visits = n_distinct(fold, plot),
              within_plot_visit_pairs = sum(pairs),
              within_plot_visit_auroc = weighted.mean(auroc, pairs), .groups = "drop")
}
stopifnot(all(filter(plot_metrics, model != spectral_model)$auroc == 0.5))

save_csv(scores(metric_keys) |>
           left_join(within_block, by = metric_keys, relationship = "one-to-one") |>
           left_join(within_plot(metric_keys), by = metric_keys, relationship = "one-to-one"),
         "metrics")
block_keys <- c(metric_keys, "fold")
save_csv(block_metrics |>
           left_join(within_plot(block_keys), by = block_keys, relationship = "one-to-one"),
         "block_metrics")
save_csv(plot_metrics, "plot_visit_metrics", detail = TRUE)
packages <- c("dplyr", "tidyr", "digest")
save_csv(tibble(component = c("R", packages),
                version = c(as.character(getRversion()),
                            vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software")
