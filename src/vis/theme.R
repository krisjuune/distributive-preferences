# Shared ggplot2 theme, sourced by scripts under src/vis/.

library(ggplot2)

theme_dp <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title = element_text(face = "bold"),
      legend.position = "bottom"
    )
}
