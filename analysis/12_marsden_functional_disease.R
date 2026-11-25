# Optional arguments: output directory and output directory from script 08.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 2L)
out <- if (length(args)) args[[1L]] else "results/exploration"
prepared <- if (length(args) == 2L) args[[2L]] else "results/marsden_disease"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name, local = FALSE) {
  target <- if (local) file.path(out, "local") else out
  write.csv(data, file.path(target, paste0("disease_", name, ".csv")), row.names = FALSE, na = "")
}
source_file <- "data/Marsden_SDS.csv"
inventory <- read.csv("audit/tables/inventory.csv")
stopifnot(identical(digest::digest(source_file, algo = "sha256", file = TRUE),
                    inventory$sha256[inventory$file == source_file]))
disease <- read.csv(source_file) |>
  mutate(date = as.Date(Date), year = as.integer(format(date, "%Y")),
         unit_id = paste("Marsden", year, Quadrat, sep = "/")) |>
  transmute(year, date, unit_id, block = Block, plot = Plot, rotation = Rotation,
            severity = Severity, incidence = Incidence) |>
  arrange(year, unit_id, date)
registry <- read.csv(file.path(prepared, "local", "unit_registry.csv"))
keys <- c("year", "unit_id", "block", "plot", "rotation")
stopifnot(nrow(anti_join(disease, registry, by = keys)) == 0L,
          !anyDuplicated(disease[c("unit_id", "date")]))
plot_visits <- disease |>
  group_by(year, rotation, block, plot, date) |>
  summarise(severity = mean(severity) / 100, .groups = "drop") |>
  group_by(year) |>
  mutate(day = as.numeric(date - min(date)), visit = factor(day), time = day / max(day)) |>
  ungroup()

# Equal plot-visit weight. Fractional-logit smooth and visit models handle 0 and 1.
# The logistic growth curve has a fixed zero lower limit and a fitted upper limit.
growth_risk <- function(time, par) {
  plogis(par[1L]) * plogis((time - par[2L]) * exp(par[3L]))
}
growth_predictions <- function(train, test) {
  risk <- numeric(nrow(test))
  for (r in sort(unique(test$rotation))) {
    rows <- test$rotation == r
    current <- filter(train, rotation == r)
    loss <- function(par) mean((growth_risk(current$time, par) - current$severity)^2)
    fit <- optim(c(1, 0.75, 2), loss, method = "L-BFGS-B",
                 lower = c(-12, -0.5, -2), upper = c(12, 1.5, 5))
    stopifnot(fit$convergence == 0L)
    risk[rows] <- growth_risk(test$time[rows], fit$par)
  }
  risk
}
disease_predictions <- plot_visits |>
  group_by(year) |>
  group_modify(function(data, key) {
    bind_rows(lapply(sort(unique(data$block)), function(held_out) {
      train <- filter(data, block != held_out)
      test <- filter(data, block == held_out)
      visit_fit <- glm(severity ~ rotation * visit, data = train, family = quasibinomial())
      smooth <- glm(severity ~ rotation * splines::ns(time, df = 3), data = train,
                    family = quasibinomial())
      stopifnot(visit_fit$converged, smooth$converged)
      test |>
        mutate(`Visit factor` = predict(visit_fit, test, type = "response"),
               `Bounded natural spline` = predict(smooth, test, type = "response"),
               `Logistic growth` = growth_predictions(train, test))
    }))
  }) |>
  ungroup() |>
  pivot_longer(c(`Visit factor`, `Bounded natural spline`, `Logistic growth`), names_to = "model",
               values_to = "prediction") |>
  mutate(error_pp = 100 * (prediction - severity))
save_csv(disease_predictions, "heldout", TRUE)
save_csv(disease_predictions |>
           group_by(year, model) |>
           summarise(rmse_pp = sqrt(mean(error_pp^2)), mae_pp = mean(abs(error_pp)),
                     plot_visits = n(), .groups = "drop"), "model_rmse")

# Estimated cumulative detection from discrete interval hazards equals the empirical
# curve with complete common visit schedules. Keep first-visit positives separate.
aligned <- disease |>
  group_by(year, unit_id) |>
  mutate(first_visit = min(date), detected = any(severity > 0),
         first_detection = if (detected[1L]) min(date[severity > 0]) else as.Date(NA),
         days_from_detection = as.integer(date - first_detection)) |>
  ungroup() |>
  filter(detected, first_detection > first_visit, days_from_detection >= 0L) |>
  mutate(window = cut(days_from_detection, c(-1, 0, 7, 14, 21, Inf),
                      labels = c("Detection", "1–7", "8–14", "15–21", "22+")))
plot_aligned <- aligned |>
  group_by(year, rotation, block, plot, window) |>
  summarise(severity = mean(severity), quadrats = n_distinct(unit_id), .groups = "drop")
save_csv(plot_aligned |>
           group_by(year, rotation, window) |>
           summarise(severity_pp = mean(severity), plots = n(), quadrats = sum(quadrats),
                     .groups = "drop"), "onset_aligned")

# Work on the observed seasonal domain. A daily grid gives each day equal
# weight in the covariance and trapezoidal summaries. Center within plots.
curve_matrix <- function(data, variable, grid, time = "day") {
  by_unit <- split(data, data$unit_id)
  t(vapply(by_unit, function(d) approx(d[[time]], d[[variable]], xout = grid)$y,
           numeric(length(grid))))
}
weighted_pca <- function(x, weights, fit = rep(TRUE, nrow(x))) {
  weights <- weights[fit] / sum(weights[fit])
  svd(x[fit, , drop = FALSE] * sqrt(weights), nu = 0L, nv = 2L)
}
functional <- function(data, year) {
  data <- mutate(data, day = as.integer(date - min(date)))
  grid <- seq.int(0L, max(data$day))
  units <- arrange(distinct(data, unit_id, block, plot, rotation), unit_id) |>
    group_by(block, plot) |>
    mutate(weight = 1 / n()) |>
    ungroup()
  severity <- curve_matrix(data, "severity", grid)
  incidence <- curve_matrix(data, "incidence", grid)
  stopifnot(!anyNA(severity), !anyNA(incidence), identical(rownames(severity), units$unit_id))
  adjust <- function(x) lm.fit(model.matrix(~ factor(plot) - 1, units), x)$residuals
  sev <- adjust(severity)
  inc <- adjust(incidence)
  # Equal total residual variation per channel for joint FPCA.
  energy <- function(x) sqrt(sum(units$weight * rowSums(x^2)) / sum(units$weight))
  signal <- list(Severity = sev, Joint = cbind(sev / energy(sev), inc / energy(inc)))
  modes <- lapply(names(signal), function(method) {
    x <- signal[[method]]
    full <- weighted_pca(x, units$weight)
    held <- lapply(sort(unique(units$block)), function(b) {
      weighted_pca(x, units$weight, units$block != b)$v
    })
    cosines <- vapply(held, function(v) abs(sum(full$v[, 1L] * v[, 1L])), numeric(1))
    subspace <- vapply(held, function(v) min(svd(crossprod(full$v, v), nu = 0, nv = 0)$d),
                       numeric(1))
    summary <- tibble(year, method, pc1_fraction = full$d[1L]^2 / sum(full$d^2),
                      pc2_fraction = full$d[2L]^2 / sum(full$d^2),
                      pc1_min_block_cosine = min(cosines), rank2_min_block_cosine = min(subspace))
    v <- full$v
    # Orient the first mode to positive integrated severity.
    v[, 1L] <- v[, 1L] * ifelse(sum(v[seq_along(grid), 1L]) >= 0, 1, -1)
    score <- x %*% v
    loadings <- tibble(year, method, day = rep(grid, length.out = nrow(v)),
                       variable = rep(c("Severity", "Incidence"), each = length(grid))[seq_len(nrow(v))],
                       pc1 = v[, 1L], pc2 = v[, 2L])
    if (method == "Severity") {
      # Test whether similar within-plot mean severity can conceal timing variation.
      auc <- rowMeans(sev[, 1:(ncol(sev) - 1L), drop = FALSE] + sev[, 2:ncol(sev), drop = FALSE]) / 2
      final <- sev[, ncol(sev)]
      summary <- mutate(summary, pc1_audpc_r = cor(score[, 1L], auc),
                         pc2_audpc_r = cor(score[, 2L], auc),
                         pc1_final_r = cor(score[, 1L], final), pc2_final_r = cor(score[, 2L], final))
      write.csv(bind_cols(units, tibble(pc1 = score[, 1L], pc2 = score[, 2L], mean_severity_pp = auc,
                                      final_severity_pp = final)),
                file.path(out, "local", paste0("disease_severity_scores_", year, ".csv")), row.names = FALSE)
    }
    list(summary = summary, loadings = loadings)
  }) |> setNames(names(signal))
  # Similar time-weighted mean severity within one plot can conceal a
  # different final assessment. Count pairs descriptively, without inference.
  observed_mean <- rowMeans(severity[, -1L] + severity[, -ncol(severity)]) / 2
  observed_final <- severity[, ncol(severity)]
  matched_pairs <- do.call(cbind, lapply(split(seq_len(nrow(units)), units$plot), combn, m = 2L))
  near <- abs(observed_mean[matched_pairs[1L, ]] - observed_mean[matched_pairs[2L, ]]) <= 1
  final_gap <- abs(observed_final[matched_pairs[1L, ]] - observed_final[matched_pairs[2L, ]])
  similar <- tibble(year, similar_mean_pairs = sum(near),
                   similar_mean_final_gap_ge10 = sum(near & final_gap >= 10),
                   fraction = mean(final_gap[near] >= 10))
  joint <- tibble(year, day = grid, correlation = vapply(seq_along(grid), function(j) {
    if (sd(sev[, j]) == 0 || sd(inc[, j]) == 0) return(NA_real_)
    cov.wt(cbind(sev[, j], inc[, j]), wt = units$weight, cor = TRUE)$cor[1L, 2L]
  }, numeric(1)))
  aucs <- (cbind(sev[, -ncol(sev)] + sev[, -1L], inc[, -ncol(inc)] + inc[, -1L])) / 2
  mid <- seq_len(ncol(sev) - 1L)
  summary <- mutate(modes$Joint$summary,
                    severity_incidence_audpc_r = cov.wt(cbind(rowMeans(aucs[, mid]),
                      rowMeans(aucs[, max(mid) + mid])), wt = units$weight, cor = TRUE)$cor[1L, 2L])
  list(summary = bind_rows(modes$Severity$summary, summary),
       loadings = bind_rows(modes$Severity$loadings, modes$Joint$loadings), joint = joint, similar = similar)
}
# Use a list to keep the PCA products and their season keys together.
by_year <- split(disease, disease$year)
fpca <- Map(function(data, year) functional(data, as.integer(year)), by_year, names(by_year))
save_csv(bind_rows(lapply(fpca, `[[`, "summary")), "functional_summary")
save_csv(bind_rows(lapply(fpca, `[[`, "similar")), "similar_audpc_pairs")
loadings <- bind_rows(lapply(fpca, `[[`, "loadings"))
save_csv(loadings, "functional_modes")
correlations <- bind_rows(lapply(fpca, `[[`, "joint"))
save_csv(correlations, "joint_correlation")
figure <- correlations |>
  ggplot(aes(day, correlation, color = factor(year))) +
  geom_line(linewidth = 0.9) + coord_cartesian(ylim = c(0, 1)) +
  labs(x = "Days since first disease assessment", y = "Within-plot correlation", colour = "Season",
       title = "Association between recorded incidence and severity") +
  theme_minimal(base_size = 13) + theme(legend.position = "bottom")
ggsave(file.path(out, "disease_joint_correlation.png"), figure, width = 7.2, height = 4,
       dpi = 180, bg = "white", device = ragg::agg_png)

mode_figure <- filter(loadings, method == "Severity") |>
  pivot_longer(c(pc1, pc2), names_to = "component", values_to = "loading") |>
  ggplot(aes(day, loading, color = toupper(component))) +
  geom_hline(yintercept = 0, color = "grey75") + geom_line(linewidth = 0.85) +
  facet_wrap(vars(year), scales = "free_x") +
  labs(x = "Days since first assessment", y = "Loading", colour = NULL,
       title = "First two within-plot severity modes",
       subtitle = "PC1 oriented to positive integrated severity. PC2 signs are arbitrary.") +
  theme_minimal(base_size = 13) + theme(legend.position = "bottom")
ggsave(file.path(out, "disease_severity_modes.png"), mode_figure, width = 8.3, height = 3.6,
       dpi = 180, bg = "white", device = ragg::agg_png)

# Align named calendar dates across years for descriptive treatment recurrence.
calendar <- mutate(plot_visits, calendar = as.Date(paste0("2001-", format(date, "%m-%d"))))
limits <- calendar |> group_by(year) |> summarise(first = min(calendar), last = max(calendar))
grid <- seq(max(limits$first), min(limits$last), by = "day")
common <- calendar |>
  group_by(year, block, plot, rotation) |>
  reframe(severity_pp = 100 * approx(calendar, severity, xout = grid)$y, calendar = grid) |>
  group_by(year, block, rotation) |>
  summarise(mean_severity_pp = mean((head(severity_pp, -1L) + tail(severity_pp, -1L)) / 2),
            .groups = "drop") |>
  pivot_wider(names_from = rotation, values_from = mean_severity_pp) |>
  transmute(year, block, `S2 minus S3` = S2 - S3, `S2 minus S4` = S2 - S4, `S3 minus S4` = S3 - S4) |>
  pivot_longer(-c(year, block), names_to = "contrast", values_to = "difference_pp")
save_csv(common |>
           group_by(year, contrast) |>
           summarise(first = format(min(grid), "%b %d"), last = format(max(grid), "%b %d"),
                     min_block_pp = min(difference_pp),
                     max_block_pp = max(difference_pp), difference_pp = mean(difference_pp), blocks = n(), .groups = "drop"),
         "common_window")
