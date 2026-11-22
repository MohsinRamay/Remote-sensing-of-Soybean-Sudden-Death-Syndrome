# Run after 03_prepare_phase2.R with the same output directory.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
source("analysis/marsden_disease_methods.R")
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
out <- if (length(args)) args[[1]] else "results/phase2"
save_csv <- function(data, name) {
  write.csv(data, file.path(out, paste0(name, ".csv")), row.names = FALSE, na = "")
}

disease <- read.csv(file.path(out, "local", "marsden2016_disease.csv")) |>
  mutate(date = as.Date(date))
dates <- sort(unique(disease$date))
days <- as.integer(dates - min(dates))
duration <- max(days)
gaps <- diff(days)
weights <- (c(0, gaps) + c(gaps, 0)) / (2 * duration)
rotations <- sort(unique(disease$rotation))
blocks <- sort(unique(disease$block))
stopifnot(length(dates) == 6L, duration == 41L, length(rotations) == 3L,
          length(blocks) == 4L, abs(sum(weights) - 1) < 1e-12,
          !anyNA(disease[c("severity", "incidence")]))

plot_dates <- disease |>
  group_by(block, plot, plot_id, rotation, date) |>
  summarise(quadrats = n(), severity = mean(severity), incidence = mean(incidence),
            prevalence = mean(severity > 0), .groups = "drop") |>
  arrange(block, rotation, date) |>
  mutate(day = as.integer(date - min(dates)))
stopifnot(nrow(plot_dates) == 72L, all(plot_dates$quadrats == 20L))
save_csv(plot_dates, "marsden2016_plot_dates")

curves <- plot_dates |>
  group_by(rotation, date, day) |>
  summarise(visit_mean = mean(severity), .groups = "drop")
curve_fit <- lm(severity ~ rotation * splines::ns(day, df = 3), data = plot_dates)
curves$spline_mean <- predict(curve_fit, newdata = curves)
save_csv(curves, "marsden2016_curve_means")

save_csv(marsden_permutation(plot_dates, dates, weights, duration),
         "marsden2016_permutation")

contrasts <- combn(rotations, 2, simplify = FALSE)
contrast_one <- function(profile, left, right, metric, by_date = FALSE) {
  keys <- if (by_date) c("block", "date") else "block"
  paired <- profile |>
    filter(rotation %in% c(left, right)) |>
    select(all_of(keys), rotation, all_of(metric)) |>
    pivot_wider(names_from = rotation, values_from = all_of(metric))
  difference <- paired[[left]] - paired[[right]]
  paired$difference <- difference
  if (by_date) paired <- group_by(paired, date)
  paired |>
    summarise(blocks = n(), estimate = mean(difference),
              margin = qt(0.975, df = blocks - 1L) * sd(difference) / sqrt(blocks), .groups = "drop") |>
    transmute(across(any_of("date")), contrast = paste(left, right, sep = " minus "),
              outcome = metric, blocks, estimate, lower = estimate - margin, upper = estimate + margin)
}
dated_effects <- bind_rows(lapply(contrasts, function(pair) {
  contrast_one(plot_dates, pair[[1]], pair[[2]], "severity", by_date = TRUE)
}))
save_csv(dated_effects, "marsden2016_visit_contrasts")

conventional <- plot_dates |>
  group_by(block, plot, rotation) |>
  arrange(date, .by_group = TRUE) |>
  summarise(final_severity_pp = last(severity), audpc_pp_days = sum(severity * weights) * duration,
            weighted_mean_severity_pp = sum(severity * weights), .groups = "drop")
save_csv(conventional, "marsden2016_plot_summaries")
save_csv(bind_rows(lapply(contrasts, function(pair) {
  bind_rows(lapply(c("final_severity_pp", "audpc_pp_days", "weighted_mean_severity_pp"),
                   function(metric) contrast_one(conventional, pair[[1]], pair[[2]], metric)))
})), "marsden2016_summary_contrasts")

holdout <- bind_rows(lapply(blocks, function(b) {
  training <- filter(plot_dates, block != b)
  test <- filter(plot_dates, block == b)
  visit_model <- lm(severity ~ rotation * factor(day), data = training)
  spline_model <- lm(severity ~ rotation * splines::ns(day, df = 3), data = training)
  test |>
    transmute(block, plot, rotation, date, observed = severity,
              visit_factor = as.numeric(predict(visit_model, newdata = test)),
              natural_spline = as.numeric(predict(spline_model, newdata = test)))
})) |>
  pivot_longer(c(visit_factor, natural_spline), names_to = "model", values_to = "prediction")
holdout_metrics <- function(data, keys) {
  data |>
    group_by(across(all_of(keys))) |>
    summarise(plot_dates = n(), rmse_pp = sqrt(mean((observed - prediction)^2)),
              mae_pp = mean(abs(observed - prediction)),
              outside_percent_scale = sum(prediction < -1e-8 | prediction > 100 + 1e-8),
              min_prediction_pp = min(prediction), max_prediction_pp = max(prediction), .groups = "drop")
}
save_csv(bind_rows(mutate(holdout_metrics(holdout, "model"), holdout_block = "pooled"),
                   mutate(holdout_metrics(holdout, c("model", "block")),
                          holdout_block = as.character(block)) |> select(-block)),
         "marsden2016_block_holdout")

onset <- disease |>
  select(unit_id, block, plot, rotation, date, severity, incidence) |>
  pivot_longer(c(severity, incidence), names_to = "definition", values_to = "rating") |>
  group_by(unit_id, block, plot, rotation, definition) |>
  summarise(first_positive = first(sort(date[rating > 0]), default = as.Date(NA)),
            last_negative = last(sort(date[rating == 0 &
                                             (is.na(first_positive) | date < first_positive)]),
                                 default = as.Date(NA)), .groups = "drop") |>
  mutate(censoring = case_when(is.na(first_positive) ~ "right",
                               is.na(last_negative) ~ "left", TRUE ~ "interval"))
save_csv(count(onset, rotation, definition, censoring), "marsden2016_onset_counts")
onset_wide <- onset |>
  select(unit_id, rotation, definition, first_positive) |>
  pivot_wider(names_from = definition, values_from = first_positive)
save_csv(onset_wide |>
           group_by(rotation) |>
           summarise(quadrats = n(),
                     differing_first_positive = sum(coalesce(severity != incidence,
                                                              xor(is.na(severity), is.na(incidence)))),
                     .groups = "drop"),
         "marsden2016_onset_sensitivity")
write.csv(onset, file.path(out, "local", "marsden2016_onset_bounds.csv"),
          row.names = FALSE, na = "")

progress <- disease |>
  left_join(select(filter(onset, definition == "severity"), unit_id, first_positive),
            by = "unit_id", relationship = "many-to-one") |>
  mutate(ever_positive = !is.na(first_positive) & date >= first_positive,
         severity_after_detection = if_else(ever_positive, severity, NA_real_)) |>
  group_by(rotation, block, plot, date) |>
  summarise(quadrats = n(), first_detections = sum(first_positive == date, na.rm = TRUE),
            cumulative_positive = sum(ever_positive), fraction_detected = mean(ever_positive),
            mean_severity_after_detection = if (any(ever_positive)) mean(severity_after_detection,
                                                                          na.rm = TRUE) else NA_real_,
            .groups = "drop")
save_csv(progress, "marsden2016_detection_by_plot")
progress_means <- progress |>
  group_by(rotation, date) |>
  summarise(fraction_detected = mean(fraction_detected), .groups = "drop")

palette <- c(S2 = "#AA412E", S3 = "#216C60", S4 = "#40558F")
style <- theme_minimal(base_size = 15) +
  theme(panel.grid.minor = element_blank(), legend.position = "bottom",
        plot.title.position = "plot", plot.caption.position = "plot",
        plot.caption = element_text(hjust = 0))
trajectory <- ggplot(plot_dates, aes(date, severity, colour = rotation)) +
  geom_line(aes(group = plot_id), linewidth = 0.5, alpha = 0.3) +
  geom_line(data = curves, aes(y = visit_mean, group = rotation), linewidth = 1.2) +
  geom_point(data = curves, aes(y = visit_mean), size = 2.1) +
  scale_colour_manual(values = palette) +
  scale_x_date(date_labels = "%b %d", breaks = dates) +
  labs(title = "Marsden 2016 foliar severity by cropping system",
       x = "Assessment date", y = "Mean quadrat-area severity (%)", colour = "System",
       caption = "Thin lines are 12 main plots. Thick lines average the four plots in each system.") + style
differences <- ggplot(dated_effects, aes(date, estimate)) +
  geom_hline(yintercept = 0, colour = "grey55") +
  geom_line(colour = "#284254") +
  geom_pointrange(aes(ymin = lower, ymax = upper), colour = "#284254") +
  facet_wrap(vars(contrast), nrow = 1L) +
  scale_x_date(date_labels = "%b %d", breaks = dates[c(1, 3, 5)]) +
  labs(title = "Severity differences estimated within blocks", x = "Assessment date",
       y = "Difference (percentage points)",
       caption = "Pointwise 95% paired t intervals summarize variability across four blocks.") + style
detection <- ggplot(progress_means, aes(date, fraction_detected, colour = rotation, group = rotation)) +
  geom_step(linewidth = 1.05) +
  geom_point(size = 2) +
  scale_colour_manual(values = palette) +
  scale_x_date(date_labels = "%b %d", breaks = dates) +
  scale_y_continuous(labels = scales::label_percent(), limits = c(0, 1)) +
  labs(title = "Quadrats with a recorded positive severity rating", x = "Assessment date",
       y = "Cumulative fraction detected", colour = "System",
       caption = "Steps mark observed detections. Biological onset is bounded by assessment dates.") + style
save_figure <- function(figure, name, width, height) {
  ggsave(file.path(out, paste0(name, ".png")), figure, width = width, height = height,
         dpi = 180, bg = "white", device = ragg::agg_png)
}
save_figure(trajectory, "marsden2016_severity", 9.2, 5.5)
save_figure(differences, "marsden2016_severity_contrasts", 12, 5.0)
save_figure(detection, "marsden2016_detection", 9.2, 5.5)
packages <- c("dplyr", "tidyr", "ggplot2", "ragg", "scales", "readxl", "digest")
save_csv(tibble(component = c("R", packages), version = c(as.character(getRversion()),
                  vapply(packages, function(x) as.character(packageVersion(x)), character(1)))),
         "software")
