# Shared date support and block-level estimators for the Marsden Q4 analyses.
marsden_date_support <- function(disease, spectra) {
  acquisitions <- sort(unique(spectra$acquisition))
  assessments <- sort(unique(disease$assessment))
  tibble(assessment = assessments) |>
    rowwise() |>
    mutate(previous = last(acquisitions[acquisitions <= assessment], default = as.Date(NA)),
           following = first(acquisitions[acquisitions >= assessment], default = as.Date(NA)),
           previous_days = as.integer(assessment - previous),
           following_days = as.integer(following - assessment)) |>
    ungroup() |>
    mutate(use_preceding = coalesce(previous_days <= 4L, FALSE),
           use_interpolation = coalesce(previous_days <= 7L & following_days <= 7L, FALSE))
}

slope <- function(x, y) sum(x * y) / sum(x^2)
fit_block_slopes <- function(data) {
  balanced <- all(count(data, wavelength_nm, unit_id)$n == n_distinct(data$assessment))
  if (!balanced) {
    return(data |>
      group_by(wavelength_nm, block) |>
      group_modify(function(records, key) {
        x <- records$severity_10pp
        y <- records$reflectance
        cell <- interaction(records$plot_id, records$assessment, drop = TRUE)
        partial <- function(design) {
          residuals <- lm.fit(design, cbind(x, y))$residuals
          slope(residuals[, 1], residuals[, 2])
        }
        tibble(quadrat_visits = nrow(records), assessments = n_distinct(records$assessment),
               specification = c("pooled", "plot_visit", "quadrat_plot_visit"),
               slope_pp = c(slope(x - mean(x), y - mean(y)),
                            partial(model.matrix(~ cell)),
                            partial(model.matrix(~ factor(records$unit_id) + cell))))
      }) |>
      ungroup() |>
      arrange(wavelength_nm, specification, block))
  }
  # With the same quadrats at each visit within a plot, first centering on
  # plot-by-visit and then quadrat gives the joint fixed-effect residuals.
  adjusted <- data |>
    group_by(wavelength_nm, plot_id, assessment) |>
    mutate(severity_plot = severity_10pp - mean(severity_10pp),
           reflectance_plot = reflectance - mean(reflectance)) |>
    group_by(wavelength_nm, unit_id) |>
    mutate(severity_within = severity_plot - mean(severity_plot),
           reflectance_within = reflectance_plot - mean(reflectance_plot)) |>
    ungroup()
  adjusted |>
    group_by(wavelength_nm, block) |>
    summarise(quadrat_visits = n(), assessments = n_distinct(assessment),
              pooled = slope(severity_10pp - mean(severity_10pp), reflectance - mean(reflectance)),
              plot_visit = slope(severity_plot, reflectance_plot),
              quadrat_plot_visit = slope(severity_within, reflectance_within), .groups = "drop") |>
    tidyr::pivot_longer(c(pooled, plot_visit, quadrat_plot_visit),
                        names_to = "specification", values_to = "slope_pp") |>
    arrange(wavelength_nm, specification, block)
}
summarize_blocks <- function(slopes) {
  stopifnot(all(is.finite(slopes$slope_pp)))
  slopes |>
    group_by(wavelength_nm, specification) |>
    summarise(blocks = n(), quadrat_visits = sum(quadrat_visits),
              estimate_pp = mean(slope_pp),
              margin = qt(0.975, df = blocks - 1) * sd(slope_pp) / sqrt(blocks),
              minimum_block_pp = min(slope_pp), maximum_block_pp = max(slope_pp),
              lower_pp = estimate_pp - margin, upper_pp = estimate_pp + margin, .groups = "drop") |>
    select(-margin)
}
