"""Build the stratified validation sample for the open-ended LLM
classification step. Pure functions, kept separate from
build_open_ended_validation_sample.py so they're testable without a
Snakemake context.

Sampling is stratified by (country, context, profile_class) and
deliberately oversamples the Utilitarian profile relative to its true
population share: it both responds to the open-ended questions less often
(see the selection-bias check) and is the profile the CFA/bifactor work
found weakest -- exactly the cell validation needs the most power in, not
proportional representation."""

import pandas as pd


def build_validation_sample(
    open_ended: pd.DataFrame, classes: pd.DataFrame, wave_id: str, country: str
) -> pd.DataFrame:
    """Join one wave's cleaned open-ended responses to its LPA
    profile_class, keeping only substantive responses -- the only ones a
    classifier (human or LLM) would ever be asked to label."""
    classes = classes[["respondent_id", "profile_class"]]
    merged = open_ended.merge(classes, on="respondent_id", how="inner")
    merged = merged[merged["is_substantive"]].copy()
    merged["wave_id"] = wave_id
    merged["country"] = country
    return merged


def stratified_sample(data: pd.DataFrame, n_per_cell: dict, random_seed: int) -> pd.DataFrame:
    """Sample up to n_per_cell[profile_class] rows (without replacement,
    capped at whatever's actually available) from every (country, context,
    profile_class) cell."""

    # Iterate directly rather than groupby(...).apply(): as of pandas 3,
    # apply() excludes the grouping columns from the group passed to the
    # function, which would drop profile_class/country/context from the
    # result -- direct iteration doesn't have that problem.
    samples = []
    for (_, _, profile), group in data.groupby(["country", "context", "profile_class"]):
        target = n_per_cell.get(profile, 0)
        n = min(target, len(group))
        samples.append(group.sample(n=n, random_state=random_seed))
    if not samples:
        return data.iloc[0:0]
    return pd.concat(samples, ignore_index=True)


def assign_item_ids(data: pd.DataFrame, random_seed: int) -> pd.DataFrame:
    """Shuffle row order -- so a coder can't infer profile_class/context/
    country from block structure in the exported sheet -- and assign an
    opaque item_id."""
    shuffled = data.sample(frac=1, random_state=random_seed).reset_index(drop=True)
    shuffled.insert(0, "item_id", [f"item_{i:04d}" for i in range(len(shuffled))])
    return shuffled
