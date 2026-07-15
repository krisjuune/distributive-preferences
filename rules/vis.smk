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
        figure = "build/figures/lpa_fit_all_waves.png"
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
        figure = "build/figures/lpa_spaghetti_all_waves.png"
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
        figure = "build/figures/lpa_composition.png"
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
        figure = "build/figures/lpa_shapes_by_topic.png"
    conda: "../environment.yml"
    script:
        "../src/vis/plot_shapes_by_topic.R"


rule plot_cfa_diagram:
    message: "Plot CFA path diagrams for {wildcards.cfa_group}."
    input:
        fit_measures = "build/results/cfa/{cfa_group}_fit_measures.csv",
        loadings = "build/results/cfa/{cfa_group}_loadings.csv"
    output:
        four_factor = "build/figures/cfa_{cfa_group}_four_factor.png",
        two_factor = "build/figures/cfa_{cfa_group}_two_factor.png",
        bifactor = "build/figures/cfa_{cfa_group}_bifactor.png"
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
