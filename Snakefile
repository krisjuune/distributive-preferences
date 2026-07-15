configfile: "config/default.yaml"

include: "rules/preprocess.smk"
include: "rules/analyse.smk"
include: "rules/vis.smk"

wildcard_constraints:
    wave_id = "|".join(config["waves"].keys()),
    cfa_group = "|".join(config["cfa"]["groups"].keys())


rule all:
    message: "Preprocess all waves and run the full analysis + visualisation."
    localrule: True
    input:
        expand("build/data/processed/{wave_id}.parquet", wave_id=config["waves"].keys()),
        expand("build/results/lpa/{wave_id}_fit_stats.csv", wave_id=config["waves"].keys()),
        expand("build/results/cfa/{cfa_group}_fit_measures.csv", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa_{cfa_group}_four_factor.png", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa_{cfa_group}_two_factor.png", cfa_group=config["cfa"]["groups"].keys()),
        expand("build/figures/cfa_{cfa_group}_bifactor.png", cfa_group=config["cfa"]["groups"].keys()),
        "build/figures/lpa_fit_all_waves.png",
        "build/figures/lpa_spaghetti_all_waves.png",
        "build/figures/lpa_composition.png",
        "build/figures/lpa_shapes_by_topic.png",


rule clean:
    message: "Remove all generated results but keep raw-data/."
    localrule: True
    run:
        import shutil
        shutil.rmtree("build", ignore_errors=True)
