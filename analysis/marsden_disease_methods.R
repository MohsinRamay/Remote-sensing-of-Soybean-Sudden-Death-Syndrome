# Conditional RCBD tests on whole plot trajectories.
marsden_permutation <- function(plot_dates, dates, weights, duration) {
  blocks <- sort(unique(plot_dates$block))
  # One wide row per plot. Column order is determined by actual assessment date.
  profiles <- plot_dates |>
    select(block, plot, rotation, date, severity) |>
    pivot_wider(names_from = date, values_from = severity, names_sort = TRUE) |>
    arrange(block, rotation)
  profiles_by_block <- lapply(blocks, function(b) {
    as.matrix(filter(profiles, block == b)[as.character(dates)])
  })
  stopifnot(all(vapply(profiles_by_block, nrow, integer(1)) == 3L))
  label_orders <- rbind(c(1, 2, 3), c(1, 3, 2), c(2, 1, 3),
                        c(2, 3, 1), c(3, 1, 2), c(3, 2, 1))
  assignments <- expand.grid(rep(list(seq_len(nrow(label_orders))), length(blocks)))
  permuted_statistics <- function(indices) {
    group_curves <- Reduce("+", lapply(seq_along(blocks), function(i) {
      profiles_by_block[[i]][label_orders[indices[[i]], ], , drop = FALSE]
    })) / length(blocks)
    centered <- sweep(group_curves, 2, colMeans(group_curves), "-")
    # AUDPC is a conventional comparator. Both statistics use the same permutations.
    mean_audpc <- drop(group_curves %*% weights) * duration
    c(trajectory_mean_squared_pp = sum(colMeans(centered^2) * weights),
      audpc_variation_pp_days_squared = mean((mean_audpc - mean(mean_audpc))^2))
  }
  observed <- permuted_statistics(rep(1L, length(blocks)))
  permuted <- apply(assignments, 1, permuted_statistics)
  tail_count <- rowSums(permuted >= observed - 1e-10)
  tibble(statistic = names(observed), observed = unname(observed),
         assignments = ncol(permuted), as_or_more_extreme = tail_count,
         permutation_p = tail_count / ncol(permuted))
}
