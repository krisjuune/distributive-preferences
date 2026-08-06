configfile: "config/default.yaml"

# The three probability-grid figures (rules/vis.smk's plot_regression_
# probability_grid[_worldviews|_categorical]) each fit one focal model
# per rows x columns cell (see rules/analyse.smk's regression_focal
# rule) rather than reusing one shared per-row model across every
# column -- see regression.R's module docstring for why. A column's
# model_key is its own predictor name UNLESS it names a `group` in
# config, in which case every column sharing that group name is fit
# together in ONE combined model (e.g. the worldviews grid's individualism-
# communitarianism and hierarchy-egalitarianism columns, two dimensions
# of one underlying construct rather than independent ones -- each
# should hold the OTHER worldview dimension constant, not ignore it).
# These helpers enumerate that full cross product once, shared between
# the model_key wildcard constraint below and rules/vis.smk's per-grid
# input lists. Defined before the includes below since rules/vis.smk's
# rule bodies call them directly (not via a lambda) at rule-definition
# time.
_PROBABILITY_GRID_NAMES = ["probability_grid", "probability_grid_worldviews", "probability_grid_categorical"]


def _column_model_key(col):
    return col.get("group", col["predictor"])


def _focal_pairs(grid_name):
    """List of (wave_id, model_key) pairs for one probability-grid
    config's full rows x columns cross product -- model_key may repeat
    across columns that share a `group`, since they're fit together."""
    rows = config["regression"][grid_name]["rows"]
    columns = config["regression"][grid_name]["columns"]
    return [(row["wave_id"], _column_model_key(col)) for row in rows for col in columns]


def _all_focal_pairs():
    pairs = []
    for grid_name in _PROBABILITY_GRID_NAMES:
        pairs.extend(_focal_pairs(grid_name))
    return pairs


def _model_key_predictors(model_key):
    """All predictor(s) belonging to a model_key -- its own name (a
    standalone column) or every column's predictor sharing that name as
    a `group`, across all three probability-grid configs."""
    predictors = []
    for grid_name in _PROBABILITY_GRID_NAMES:
        for col in config["regression"][grid_name]["columns"]:
            if _column_model_key(col) == model_key and col["predictor"] not in predictors:
                predictors.append(col["predictor"])
    return predictors


include: "rules/preprocess.smk"
include: "rules/analyse.smk"
include: "rules/vis.smk"

wildcard_constraints:
    # Includes regression.groups' pooled unit names (e.g. "wave4_eu") --
    # the `regression` rule's output is keyed on {wave_id} whether it
    # names an individual wave or a pooled group, see rules/analyse.smk.
    wave_id = "|".join(list(config["waves"].keys()) + list(config["regression"]["groups"].keys())),
    cfa_group = "|".join(config["cfa"]["groups"].keys()),
    model_key = "|".join(sorted(set(key for _, key in _all_focal_pairs())))


# Wave 4's 9 individual countries are pooled into regression.groups.wave4_eu
# (see rules/analyse.smk's `regression` rule) rather than regressed/plotted
# per-country -- individual countries run as small as ~100-250 respondents
# post listwise deletion, too little for a stable fit. The rule itself can
# still produce a per-country wave4 regression if directly requested; this
# list just controls what `rule all` builds by default.
_individual_regression_waves = [
    wave_id for wave_id, meta in config["waves"].items() if meta["topic"] != "policy-instruments"
]


rule all:
    message: "Preprocess all waves and run the full analysis + visualisation."
    localrule: True
    input:
        expand("build/data/processed/{wave_id}.parquet", wave_id=config["waves"].keys()),
        expand("build/results/lpa/{wave_id}_fit_stats.csv", wave_id=config["waves"].keys()),
        expand("build/results/lpa/{wave_id}_blrt.csv", wave_id=config["waves"].keys()),
        expand("build/results/cfa/{cfa_group}_fit_measures.csv", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa/cfa_{cfa_group}_four_factor.png", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa/cfa_{cfa_group}_two_factor.png", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa/cfa_{cfa_group}_bifactor.png", cfa_group=config["cfa"]["groups"].keys()),
        "build/figures/lpa/lpa_fit_all_waves.png",
        "build/figures/lpa/lpa_spaghetti_all_waves.png",
        "build/figures/lpa/lpa_spaghetti_all_waves_g4.png",
        "build/figures/lpa/lpa_composition.png",
        "build/figures/lpa/lpa_shapes_by_topic.png",
        expand("build/results/open_ended/{wave_id}_clean.csv", wave_id=config["open_ended"]["waves"]),
        expand("build/results/open_ended/{wave_id}_selection_bias_tests.csv", wave_id=config["open_ended"]["waves"]),
        "build/results/open_ended/validation_sample_full.csv",
        "build/results/open_ended/validation_sample_blind.csv",
        expand("build/results/regression/{wave_id}_coefficients.csv", wave_id=_individual_regression_waves),
        expand("build/results/regression/{wave_id}_coefficients.csv", wave_id=config["regression"]["groups"].keys()),
        "build/figures/lpa/regression_probability_surface.png",
        "build/figures/lpa/regression_probability_grid.png",
        "build/figures/lpa/regression_probability_grid_worldviews.png",
        "build/figures/lpa/regression_probability_grid_categorical.png",

        # LLM classification targets are appended below, gated on
        # open_ended.llm_classification.enabled -- it costs money and
        # isn't bit-reproducible the way the rest of this list is, so it
        # stays opt-in rather than part of the unconditional default run.
        *(
            expand(
                "build/results/open_ended/{wave_id}_llm_labels.csv",
                wave_id=config["open_ended"]["waves"],
            )
            if config["open_ended"]["llm_classification"]["enabled"]
            else []
        ),


rule clean:
    message: "Remove all generated results but keep raw-data/."
    localrule: True
    run:
        import shutil
        shutil.rmtree("build", ignore_errors=True)
