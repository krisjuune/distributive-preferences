configfile: "config/default.yaml"

include: "rules/preprocess.smk"
include: "rules/analyse.smk"
include: "rules/vis.smk"

wildcard_constraints:
    # Includes regression.groups' pooled unit names (e.g. "wave4_eu") --
    # the `regression` rule's output is keyed on {wave_id} whether it
    # names an individual wave or a pooled group, see rules/analyse.smk.
    wave_id = "|".join(list(config["waves"].keys()) + list(config["regression"]["groups"].keys())),
    cfa_group = "|".join(config["cfa"]["groups"].keys())


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
