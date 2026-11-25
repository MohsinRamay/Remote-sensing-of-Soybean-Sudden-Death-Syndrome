# Usage: Rscript analysis/13_sds_yield.R <archive root> [output dir] [phase2 dir]
suppressPackageStartupMessages({library(dplyr); library(tidyr)})
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) %in% 1:3)
archive <- normalizePath(args[[1]], mustWork = TRUE)
out <- if (length(args) >= 2L) args[[2]] else "results/exploration"
phase2 <- if (length(args) == 3L) args[[3]] else "results/phase2"
dir.create(file.path(out, "local"), recursive = TRUE, showWarnings = FALSE)
save_csv <- function(data, name, local = FALSE) {
  target <- if (local) file.path(out, "local") else out
  write.csv(data, file.path(target, paste0("yield_", name, ".csv")), row.names = FALSE, na = "")
}
manifest <- read.csv("audit/evidence/sds_paper_source_manifest.csv")
read_archive <- function(file, sheet) {
  relative <- file.path("04_source_data", file)
  path <- file.path(archive, relative)
  expected <- unique(manifest$sha256[manifest$file == relative & manifest$root_scope == "SDS Paper"])
  stopifnot(identical(digest::digest(path, algo = "sha256", file = TRUE), expected))
  readxl::read_excel(path, sheet, .name_repair = "unique_quiet")
}
y16 <- read_archive("2016 Research/Marsden/Marsden SDS Yield.xlsx", "Specific Date")
y17 <- read_archive("2017 Research/Marsden Yield/Marsden Yield.xlsx", "Quadrats")
y17_join <- read_archive("2017 Research/Marsden/Marsden SDS Yield.xlsx", "Specific Date")
y18 <- read_archive("2018 Research/Marsden/Yield/Yield Correction.xlsx", "Sheet1")
y18_join <- read_archive("2018 Research/Marsden/Visuals/Marsden SDS Yield.xlsx", "Sheet1")
stopifnot(all(abs(y16[["Kg per Ha"]] / y16$Yield - 67.25) < 1e-6))
check_yield <- function(raw, quadrat, value, joined, tolerance = 1e-7) {
  mapped <- match(joined$Quadrat, raw[[quadrat]])
  stopifnot(!anyNA(mapped), !anyDuplicated(mapped), length(mapped) == nrow(raw),
            all(abs(raw[[value]][mapped] - joined$Yield) <= tolerance))
}
check_yield(y17, "Quadrat...9", "buacA", y17_join)
check_yield(y18, "Quadrat", "Adj. Plot Yield (bu/Ac)", y18_join)
marsden_yield <- bind_rows(
  transmute(y16, year = 2016L, quadrat = Canopy, yield = Yield),
  transmute(y17, year = 2017L, quadrat = Quadrat...9, yield = buacA),
  transmute(y18, year = 2018L, quadrat = Quadrat, yield = `Adj. Plot Yield (bu/Ac)`)
)
file <- "data/Marsden_SDS.csv"
inventory <- read.csv("audit/tables/inventory.csv")
stopifnot(identical(digest::digest(file, algo = "sha256", file = TRUE),
                    inventory$sha256[inventory$file == file]))
marsden <- read.csv(file) |>
  transmute(site = "Marsden", year = as.integer(substr(Date, 1, 4)), date = as.Date(Date),
            block = Block, plot = Plot, treatment = Rotation, quadrat = Quadrat,
            unit_id = paste(site, year, quadrat, sep = "/"), severity = Severity) |>
  left_join(marsden_yield, by = c("year", "quadrat"), relationship = "many-to-one")
stopifnot(sum(!is.na(distinct(marsden, unit_id, yield)$yield)) == nrow(marsden_yield))
meta <- distinct(marsden, year, quadrat, block, plot, treatment)
m16 <- filter(meta, year == 2016) |> arrange(match(quadrat, y16$Canopy))
stopifnot(all(m16$block == y16$Block), all(m16$plot == y16$Plot), all(m16$treatment == y16$Rotation))
m17 <- filter(meta, year == 2017, quadrat %in% y17$Quadrat...9) |>
  arrange(match(quadrat, y17$Quadrat...9))
stopifnot(all(m17$plot == y17$Plot), all(m17$treatment == y17$Rotation))
hinds <- read.csv(file.path(phase2, "local", "hinds2018_severity.csv")) |>
  transmute(site = "Hinds", year = 2018L, date = as.Date(date), block, plot, treatment,
            unit_id, severity, entry_severity) |>
  left_join(read.csv(file.path(phase2, "local", "hinds2018_yield.csv")) |>
              transmute(unit_id, yield = yield_bu_per_ac),
            by = "unit_id", relationship = "many-to-one")
stopifnot(n_distinct(hinds$unit_id) == 60L, all(is.finite(hinds$yield)))
data <- bind_rows(mutate(marsden, version = "Reference"), mutate(hinds, version = "Reference"),
                  transmute(hinds, site, year, date, block, plot, treatment, unit_id, yield,
                            severity = entry_severity, version = "Entry sheet"))
save_csv(data |>
           distinct(site, year, version, block, plot, treatment, unit_id, yield) |>
           group_by(site, year, version, treatment) |>
           summarise(rated_units = n(), harvested_units = sum(is.finite(yield)),
                     rated_plots = n_distinct(block, plot),
                     harvested_plots = n_distinct(block[is.finite(yield)], plot[is.finite(yield)]),
                     .groups = "drop"), "coverage")

# Fit on harvested quadrats or microplots, weighting each training plot equally.
# Treatment indicators are unpenalized. Standardized disease terms use unit ridge.
ridge <- function(y, nuisance, predictors, new_nuisance, new_predictors, weight) {
  use <- apply(predictors, 2L, sd) > 1e-10
  x <- predictors[, use, drop = FALSE]
  new_x <- new_predictors[, use, drop = FALSE]
  if (ncol(x)) {
    center <- colMeans(x)
    spread <- apply(x, 2L, sd)
    x <- scale(x, center, spread)
    new_x <- scale(new_x, center, spread)
  }
  design <- cbind(nuisance, x)
  penalty <- diag(c(rep(0, ncol(nuisance)), rep(1, ncol(x))))
  coefficients <- solve(crossprod(design * sqrt(weight)) + penalty,
                        crossprod(design, y * weight))
  drop(cbind(new_nuisance, new_x) %*% coefficients)
}
fit_trial <- function(data) {
  harvested <- filter(data, is.finite(yield))
  visits <- sort(unique(harvested$date))
  day <- as.integer(visits - visits[1L])
  grid <- seq.int(0L, max(day))
  wide <- harvested |>
    select(unit_id, block, plot, treatment, yield, date, severity) |>
    pivot_wider(names_from = date, values_from = severity, names_sort = TRUE) |>
    group_by(block, plot) |>
    mutate(weight = 1 / n()) |>
    ungroup()
  y <- as.matrix(wide[as.character(visits)])
  stopifnot(!anyNA(y))
  x <- t(apply(y, 1L, function(severity) approx(day, severity, xout = grid)$y))
  first <- apply(y, 1L, function(severity) match(TRUE, severity > 0))
  rate <- rowMeans(x[, -1L] + x[, -ncol(x)]) / 2
  simple <- cbind(final = y[, ncol(y)], audpc = rate,
                  first_visit_positive = as.numeric(first %in% 1L),
                  day_detected = ifelse(is.na(first), max(day), day[first]),
                  never_detected = as.numeric(is.na(first)))
  nuisance <- model.matrix(~ factor(treatment) - 1, wide)
  bind_rows(lapply(sort(unique(wide$block)), function(block) {
    train <- wide$block != block
    test <- !train
    stopifnot(all(colSums(nuisance[train, , drop = FALSE]) > 0))
    center <- colSums(x[train, , drop = FALSE] * wide$weight[train]) / sum(wide$weight[train])
    centered <- sweep(x, 2L, center)
    basis <- svd(centered[train, , drop = FALSE] * sqrt(wide$weight[train]), nu = 0L, nv = 2L)$v
    terms <- cbind(simple, centered %*% basis)
    models <- list(Treatment = integer(), Final = 1L, AUDPC = 2L, Onset = 3:5,
                   `Final + AUDPC + onset` = 1:5, `Functional scores` = 6:7,
                   `Summaries + functional scores` = 1:7)
    bind_rows(lapply(names(models), function(model) {
      columns <- models[[model]]
      predictions <- ridge(wide$yield[train], nuisance[train, , drop = FALSE],
                           terms[train, columns, drop = FALSE], nuisance[test, , drop = FALSE],
                           terms[test, columns, drop = FALSE], wide$weight[train])
      select(wide[test, ], unit_id, block, plot, weight, yield) |>
        mutate(model = .env$model, prediction = predictions)
    }))
  }))
}
predictions <- data |>
  group_by(site, year, version) |>
  group_modify(function(data, key) fit_trial(data)) |>
  ungroup() |>
  mutate(error = prediction - yield)
save_csv(predictions, "predictions", TRUE)
save_csv(predictions |>
           group_by(site, year, version, model) |>
           summarise(units = n(), plots = n_distinct(block, plot),
                     rmse_bu_ac = sqrt(weighted.mean(error^2, weight)),
                     mae_bu_ac = weighted.mean(abs(error), weight), .groups = "drop"), "models")
