# Use the audited quadrat ID and acquisition date to keep the bands paired.
paired_spectra <- function(raw) {
  spectra <- raw |>
    filter(Wavelength %in% c(660L, 810L), is.finite(Reflectance)) |>
    transmute(year = as.integer(substr(DATE, 1L, 4L)),
              unit_id = paste("Marsden", year, Quadrat, sep = "/"),
              acquisition = as.Date(DATE), band = Wavelength, Reflectance)
  stopifnot(!anyDuplicated(spectra[c("unit_id", "acquisition", "band")]))
  spectra |>
    pivot_wider(names_from = band, names_prefix = "nm", values_from = Reflectance) |>
    filter(is.finite(nm660), is.finite(nm810))
}

pair_auroc <- function(risk, event) {
  positives <- sum(event)
  pairs <- positives * (length(event) - positives)
  if (pairs == 0L) return(NA_real_)
  (sum(rank(risk)[event]) - positives * (positives + 1) / 2) / pairs
}

# Group tied scores for threshold-based average precision. AUROC uses midranks.
metric_values <- function(risk, event) {
  positives <- sum(event)
  ranked <- tibble(risk, event) |>
    group_by(risk) |>
    summarise(positive = sum(event), total = n(), .groups = "drop") |>
    arrange(desc(risk))
  precision <- cumsum(ranked$positive) / cumsum(ranked$total)
  tibble(opportunities = length(event), events = positives, event_rate = mean(event),
         brier = mean((risk - event)^2),
         auroc = pair_auroc(risk, event),
         average_precision = if (positives > 0) sum(precision * ranked$positive) / positives else NA_real_)
}

train_rates <- function(training, keys) {
  training |>
    group_by(across(all_of(keys))) |>
    summarise(probability = (sum(event) + 0.5) / (n() + 1), .groups = "drop")
}

# All rates are estimated on the training blocks.
baseline_rates <- function(data, training) {
  data |>
    left_join(rename(train_rates(training, "rotation"), rotation_rate = probability),
              by = "rotation", relationship = "many-to-one") |>
    left_join(rename(train_rates(training, "landmark"), visit_rate = probability),
              by = "landmark", relationship = "many-to-one") |>
    left_join(rename(train_rates(training, c("landmark", "rotation")), joint_rate = probability),
              by = c("landmark", "rotation"), relationship = "many-to-one") |>
    mutate(overall_rate = train_rates(training, character())$probability,
           joint_risk = coalesce(joint_rate, visit_rate, overall_rate))
}

# Fit standardized slopes with a fixed offset and unit ridge penalty.
spectral_ridge_risk <- function(training, test, features, offset, test_offset) {
  x <- as.matrix(training[features])
  center <- colMeans(x)
  spread <- apply(x, 2L, sd)
  stopifnot(all(is.finite(spread) & spread > 0))
  x <- scale(x, center = center, scale = spread)
  test_x <- scale(as.matrix(test[features]), center = center, scale = spread)

  # Fixed ridge penalty of 1/2 times the squared slopes on the log-loss sum.
  # The offset stays fixed and there is no additional intercept.
  objective <- function(beta) {
    eta <- offset + drop(x %*% beta)
    sum(pmax(eta, 0) + log1p(exp(-abs(eta))) - training$event * eta) + sum(beta^2) / 2
  }
  gradient <- function(beta) {
    eta <- offset + drop(x %*% beta)
    drop(crossprod(x, plogis(eta) - training$event)) + beta
  }
  fit <- optim(rep(0, length(features)), objective, gradient, method = "BFGS",
               control = list(reltol = 1e-12))
  if (any(abs(gradient(fit$par)) >= 1e-4)) {
    # Refine a numerically converged solution using the local log-loss Hessian.
    probability <- plogis(offset + drop(x %*% fit$par))
    hessian <- crossprod(x, x * (probability * (1 - probability))) + diag(length(features))
    fit$par <- fit$par - drop(solve(hessian, gradient(fit$par)))
  }
  stopifnot(fit$convergence == 0L, all(abs(gradient(fit$par)) < 1e-4))

  plogis(test_offset + drop(test_x %*% fit$par))
}
