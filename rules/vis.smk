rule plot_lpa_fit_combined:
    message: "Plot combined LPA fit statistics across all wave/country samples."
    input:
        fit_stats = expand(
            "build/results/lpa/{wave_id}_fit_stats.csv",
            wave_id=config["waves"].keys()
        )
    params:
        wave_titles = config["lpa"]["spaghetti_titles"],
        ncol = config["lpa"]["spaghetti_ncol"]
    output:
        figure = "build/figures/lpa/lpa_fit_all_waves.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_lpa_fit_combined.R"


rule plot_lpa_spaghetti:
    message: "Plot spaghetti profiles across all wave/country samples."
    input:
        classes = expand(
            "build/results/lpa/{wave_id}_spaghetti_classes.csv",
            wave_id=config["waves"].keys()
        )
    params:
        sample_n = config["lpa"]["spaghetti_sample_n"],
        random_seed = config["lpa"]["random_seed"],
        wave_titles = config["lpa"]["spaghetti_titles"],
        ncol = config["lpa"]["spaghetti_ncol"]
    output:
        figure = "build/figures/lpa/lpa_spaghetti_all_waves.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_lpa_spaghetti.R"


rule plot_composition:
    message: "Plot publication composition chart (one sample per country)."
    input:
        classes = expand(
            "build/results/lpa/{wave_id}_spaghetti_classes.csv",
            wave_id=config["lpa"]["composition_waves"].keys()
        )
    params:
        wave_to_country = config["lpa"]["composition_waves"]
    output:
        figure = "build/figures/lpa/lpa_composition.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_composition.R"


def _shape_topic_wave_ids(config):
    wave_ids = set()
    for ids in config["lpa"]["shape_topics"].values():
        wave_ids.update(ids)
    return sorted(wave_ids)


rule plot_shapes_by_topic:
    message: "Plot supplementary shape figure (mean profile per class, by topic)."
    input:
        classes = expand(
            "build/results/lpa/{wave_id}_spaghetti_classes.csv",
            wave_id=_shape_topic_wave_ids(config)
        )
    params:
        shape_topics = config["lpa"]["shape_topics"]
    output:
        figure = "build/figures/lpa/lpa_shapes_by_topic.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_shapes_by_topic.R"


rule plot_cfa_diagram:
    message: "Plot CFA path diagrams for {wildcards.cfa_group}."
    input:
        fit_measures = "build/results/cfa/{cfa_group}_fit_measures.csv",
        loadings = "build/results/cfa/{cfa_group}_loadings.csv"
    output:
        four_factor = "build/figures/cfa/cfa_{cfa_group}_four_factor.png",
        two_factor = "build/figures/cfa/cfa_{cfa_group}_two_factor.png",
        bifactor = "build/figures/cfa/cfa_{cfa_group}_bifactor.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_cfa_diagram.R"


rule plot_regression:
    message: "Plot regression coefficients for {wildcards.wave_id}."
    input:
        coefficients = "build/results/regression/{wave_id}_coefficients.csv"
    output:
        figure = "build/figures/{wave_id}_regression.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_regression.R"


rule plot_regression_probability_grid:
    message: "Plot composite predicted-probability grid across value indices and samples."
    input:
        models = expand(
            "build/results/regression/{wave_id}_model.rds",
            wave_id=[row["wave_id"] for row in config["regression"]["probability_grid"]["rows"]]
        ),
        model_data = expand(
            "build/results/regression/{wave_id}_model_data.rds",
            wave_id=[row["wave_id"] for row in config["regression"]["probability_grid"]["rows"]]
        )
    params:
        row_labels = [row["label"] for row in config["regression"]["probability_grid"]["rows"]],
        row_wave_ids = [row["wave_id"] for row in config["regression"]["probability_grid"]["rows"]],
        col_labels = [col["label"] for col in config["regression"]["probability_grid"]["columns"]],
        col_predictors = [col["predictor"] for col in config["regression"]["probability_grid"]["columns"]],
        n_boot = config["regression"]["bootstrap"]["reps"],
        ci_level = config["regression"]["bootstrap"]["ci_level"],
        random_seed = config["regression"]["random_seed"],
        fig_width = 12,
        fig_height = 8
    output:
        figure = "build/figures/lpa/regression_probability_grid.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_regression_probability_grid.R"


rule plot_regression_probability_grid_worldviews:
    message: "Plot composite predicted-probability grid for cultural worldviews and energy security."
    input:
        models = expand(
            "build/results/regression/{wave_id}_model.rds",
            wave_id=[row["wave_id"] for row in config["regression"]["probability_grid_worldviews"]["rows"]]
        ),
        model_data = expand(
            "build/results/regression/{wave_id}_model_data.rds",
            wave_id=[row["wave_id"] for row in config["regression"]["probability_grid_worldviews"]["rows"]]
        )
    params:
        row_labels = [row["label"] for row in config["regression"]["probability_grid_worldviews"]["rows"]],
        row_wave_ids = [row["wave_id"] for row in config["regression"]["probability_grid_worldviews"]["rows"]],
        col_labels = [col["label"] for col in config["regression"]["probability_grid_worldviews"]["columns"]],
        col_predictors = [col["predictor"] for col in config["regression"]["probability_grid_worldviews"]["columns"]],
        n_boot = config["regression"]["bootstrap"]["reps"],
        ci_level = config["regression"]["bootstrap"]["ci_level"],
        random_seed = config["regression"]["random_seed"],
        fig_width = 12,
        fig_height = 16 / 3  # one row vs. the main grid's three, but doubled so panels aren't too squashed
    output:
        figure = "build/figures/lpa/regression_probability_grid_worldviews.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_regression_probability_grid.R"


rule plot_regression_probability_surface:
    message: "Plot 2D predicted probability surface for {params.focal_profile}."
    input:
        models = expand(
            "build/results/regression/{wave_id}_model.rds",
            wave_id=config["regression"]["probability_surface"]["wave_ids"]
        ),
        model_data = expand(
            "build/results/regression/{wave_id}_model_data.rds",
            wave_id=config["regression"]["probability_surface"]["wave_ids"]
        )
    params:
        wave_ids = config["regression"]["probability_surface"]["wave_ids"],
        x_predictor = config["regression"]["probability_surface"]["x_predictor"],
        y_predictor = config["regression"]["probability_surface"]["y_predictor"],
        focal_profile = config["regression"]["probability_surface"]["focal_profile"],
        country_labels = config["regression"]["probability_surface"]["country_labels"]
    output:
        figure = "build/figures/lpa/regression_probability_surface.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_regression_probability_surface.R"
