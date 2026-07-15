# CFA path diagrams (factors as circles, items as boxes, loading/residual/
# factor-correlation values labelled on the arrows), one PNG per model.
# Diagram body built via DiagrammeR (Graphviz), which auto-computes node
# positions and edge routing -- avoids semPlot/tidySEM/lavaanPlot, which are
# only available from the `defaults`/`pkgs/r` conda channel (pinned to an
# old R build), the same channel-mixing conflict tidyLPA had (see
# src/analyse/lpa.R). A hand-rolled ggplot2 version of the whole diagram was
# tried first but its manually approximated curve midpoints/offsets produced
# floating labels and disconnected-looking arrows.
#
# The title is composited on afterwards with magick, at full pixel
# resolution (no resampling step): Graphviz sizes its SVG canvas from the
# diagram content, not the title, and under-estimates bold-text width badly
# enough in this layout to clip the title outright -- margin/justification
# attributes don't fix it because the miscalculated bounding box is baked
# into Graphviz's own SVG output before rsvg ever sees it. An earlier
# ggplot2-based compositing step (annotation_raster + ggsave) worked but
# re-rasterised the image at a low DPI, visibly softening it; magick just
# concatenates pixel data directly.
#
# Run through Snakemake (see rules/vis.smk).

library(dplyr)
library(readr)
library(magick)
library(DiagrammeR)
library(DiagrammeRsvg)
library(rsvg)

cfa_group <- snakemake@wildcards[["cfa_group"]]
fit_measures <- read_csv(snakemake@input[["fit_measures"]], show_col_types = FALSE)
params_path <- snakemake@input[["loadings"]]
params <- tryCatch(read_csv(params_path, show_col_types = FALSE), error = function(e) NULL)
# Both models can fail to fit (e.g. wave2's singular covariance matrix), in
# which case cfa.R writes an empty CSV -- readr reads that back as a 0-row,
# 0-column tibble rather than raising an error.
if (!is.null(params) && nrow(params) == 0) params <- NULL

# Matches the "Wave N Country (...)"/topic-name convention used in the
# other LPA figures (see config/default.yaml's lpa.spaghetti_titles).
cfa_group_labels <- c(wave1_3 = "wave 1 & 3", wave2 = "wave 2", wave4 = "wave 4")
model_titles <- c(
  four_factor = sprintf("4-factor solution on %s data", cfa_group_labels[[cfa_group]]),
  two_factor = sprintf("2-factor solution on %s data", cfa_group_labels[[cfa_group]]),
  bifactor = sprintf("Bifactor solution on %s data", cfa_group_labels[[cfa_group]])
)

# wave4's raw item names describe the policy mechanism (see
# src/preprocess/harmonise.py's _WAVE4_PRINCIPLE_BY_SUBSCALE_ITEM); relabel
# them to justice_<domain>_<principle position> for display so wave4's
# diagrams read the same way as waves 1-3's (whose _1/_2/_3/_4 suffix is the
# principle position by construction).
wave4_item_relabel <- c(
  justice_general_costmin = "justice_general_1", justice_general_inequ = "justice_general_2",
  justice_general_minim = "justice_general_3", justice_general_many_benefits = "justice_general_4",
  justice_tax_moderate = "justice_tax_1", justice_tax_basic = "justice_tax_2",
  justice_tax_all = "justice_tax_3", justice_tax_luxury = "justice_tax_4",
  justice_subsidy_everyone = "justice_subsidy_1", justice_subsidy_lower = "justice_subsidy_2",
  justice_subsidy_additional = "justice_subsidy_3", justice_subsidy_high = "justice_subsidy_4",
  justice_ban_reduction = "justice_ban_1", justice_ban_all_income = "justice_ban_2",
  justice_ban_alternatives = "justice_ban_3", justice_ban_fleets = "justice_ban_4"
)
relabel_items <- function(x) {
  hit <- x %in% names(wave4_item_relabel)
  x[hit] <- wave4_item_relabel[x[hit]]
  x
}

# Add a white title bar above `img` sized to its actual pixel width, then
# stack -- avoids Graphviz's own title clipping and any resampling loss.
add_title_bar <- function(img, title) {
  w <- image_info(img)$width
  title_bar <- image_blank(width = w, height = round(w * 0.07), color = "white") |>
    image_annotate(title, gravity = "center", size = round(w * 0.028), weight = 700, font = "Helvetica")
  image_append(c(title_bar, img), stack = TRUE)
}

render_failure_png <- function(model_name, output_path) {
  reason <- fit_measures$failure_reason[fit_measures$model == model_name]
  reason <- if (length(reason) && !is.na(reason)) reason else "unknown error"

  w <- 1600
  img <- image_blank(width = w, height = 500, color = "white") |>
    image_annotate(
      paste0("Model failed to fit:\n", reason),
      gravity = "center", size = 34, font = "Helvetica"
    )
  img <- add_title_bar(img, model_titles[[model_name]])
  image_write(img, path = output_path, format = "png")
}

render_diagram_png <- function(model_name, output_path) {
  mp <- params |> filter(model == model_name)
  if (cfa_group == "wave4") {
    mp <- mp |> mutate(lhs_var = relabel_items(lhs_var), rhs_var = relabel_items(rhs_var))
  }
  loadings <- mp |> filter(op == "=~")
  factors <- unique(loadings$lhs_var)
  items <- unique(loadings$rhs_var)
  residuals <- mp |> filter(op == "~~", lhs_var == rhs_var, lhs_var %in% items)
  # In the bifactor model, every factor pair (general-specific and
  # specific-specific) is fixed to exactly 0 by `orthogonal = TRUE` -- that's
  # the model's defining constraint, not an estimated result, so drawing
  # those edges would just clutter the diagram with a wall of "0.00" labels.
  factor_cors <- if (model_name == "bifactor") {
    mp[0, ]
  } else {
    mp |> filter(op == "~~", lhs_var != rhs_var, lhs_var %in% factors, rhs_var %in% factors)
  }

  q <- function(x) paste0('"', x, '"')

  # In the bifactor diagram, shade the general factor grey to set it apart
  # from the four specific factors at a glance.
  factor_fill <- if (model_name == "bifactor") {
    ifelse(factors == "general", "grey85", "white")
  } else {
    "white"
  }
  factor_nodes <- sprintf('%s [shape=ellipse, style=filled, fillcolor=%s]', q(factors), factor_fill)
  item_nodes <- sprintf('%s [shape=box, fontsize=10]', q(items))

  loading_edges <- sprintf(
    '%s -> %s [label=%s, fontsize=9]',
    q(loadings$lhs_var), q(loadings$rhs_var), q(sprintf("%.2f", loadings$std_estimate))
  )
  # Residual variance as a self-loop on the item itself (lavaan/semPlot
  # style), forced to bulge from the east side (right of the box) so it
  # doesn't collide with the loading arrow coming in from the factor on
  # the left in this left-to-right layout.
  resid_edges <- sprintf(
    '%s:e -> %s:e [label=%s, fontsize=8, fontcolor=grey40, color=grey60, arrowsize=0.6]',
    q(residuals$lhs_var), q(residuals$lhs_var), q(sprintf("%.2f", residuals$std_estimate))
  )
  # Forced to the west side (left of the factor column) so they don't
  # collide with the loading arrows exiting each factor's east side.
  cor_edges <- sprintf(
    '%s:w -> %s:w [dir=both, style=dashed, color=grey50, constraint=false, label=%s, fontsize=9]',
    q(factor_cors$lhs_var), q(factor_cors$rhs_var), q(sprintf("%.2f", factor_cors$std_estimate))
  )

  dot <- sprintf(
    'digraph cfa {
      graph [rankdir=LR, splines=true, nodesep=0.3, ranksep=1.1, margin=0.3]
      node [fontname="Helvetica"]
      edge [fontname="Helvetica"]

      { rank=same; %s }
      { rank=same; %s }

      %s
      %s

      %s
      %s
      %s
    }',
    paste(q(factors), collapse = "; "),
    paste(q(items), collapse = "; "),
    paste(factor_nodes, collapse = "\n      "),
    paste(item_nodes, collapse = "\n      "),
    paste(loading_edges, collapse = "\n      "),
    paste(resid_edges, collapse = "\n      "),
    paste(cor_edges, collapse = "\n      ")
  )

  svg <- export_svg(grViz(dot))
  tmp_png <- tempfile(fileext = ".png")
  on.exit(unlink(tmp_png))
  # High base resolution -- text stays crisp even when the image is viewed
  # or printed larger than its default display size.
  rsvg_png(charToRaw(svg), file = tmp_png, width = max(2400, 140 * length(items)))

  # rsvg's PNG has a transparent background; flatten it against white first
  # -- otherwise the transparent margin can render as solid black once
  # composited with the (opaque) title bar below.
  img <- image_read(tmp_png) |>
    image_background("white", flatten = TRUE) |>
    add_title_bar(model_titles[[model_name]])
  image_write(img, path = output_path, format = "png")
}

for (model_name in c("four_factor", "two_factor", "bifactor")) {
  output_path <- snakemake@output[[model_name]]
  has_fit <- !is.null(params) && model_name %in% unique(params$model)
  if (has_fit) {
    render_diagram_png(model_name, output_path)
  } else {
    render_failure_png(model_name, output_path)
  }
}
