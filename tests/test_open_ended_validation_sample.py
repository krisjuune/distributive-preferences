import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src" / "preprocess"))

from open_ended_validation_sample import (  # noqa: E402
    assign_item_ids,
    build_validation_sample,
    stratified_sample,
)


def test_build_validation_sample_joins_and_keeps_only_substantive():
    open_ended = pd.DataFrame(
        {
            "respondent_id": [0, 1, 2],
            "context": ["general", "tax", "subsidy"],
            "response_clean": ["a", "b", "c"],
            "is_substantive": [True, False, True],
        }
    )
    classes = pd.DataFrame(
        {"respondent_id": [0, 1, 2], "profile_class": ["Egalitarian", "Utilitarian", "Universalist"]}
    )

    joined = build_validation_sample(open_ended, classes, wave_id="wave3_ch", country="CH")

    assert list(joined["respondent_id"]) == [0, 2]
    assert (joined["wave_id"] == "wave3_ch").all()
    assert (joined["country"] == "CH").all()
    assert list(joined["profile_class"]) == ["Egalitarian", "Universalist"]


def test_stratified_sample_respects_targets_and_caps_at_availability():
    data = pd.DataFrame(
        {
            "country": ["CH"] * 10 + ["CN"] * 3,
            "context": ["general"] * 13,
            "profile_class": ["Egalitarian"] * 10 + ["Utilitarian"] * 3,
            "response_clean": [f"r{i}" for i in range(13)],
        }
    )

    sample = stratified_sample(
        data, n_per_cell={"Egalitarian": 4, "Utilitarian": 10}, random_seed=42
    )

    counts = sample.groupby(["country", "profile_class"]).size()
    assert counts[("CH", "Egalitarian")] == 4  # target of 4, 10 available
    assert counts[("CN", "Utilitarian")] == 3  # target of 10, only 3 available -- capped


def test_assign_item_ids_are_unique_and_shuffle_preserves_rows():
    data = pd.DataFrame({"response_clean": [f"r{i}" for i in range(20)]})

    result = assign_item_ids(data, random_seed=42)

    assert result["item_id"].tolist() == [f"item_{i:04d}" for i in range(20)]
    assert set(result["response_clean"]) == set(data["response_clean"])
    assert result["response_clean"].tolist() != data["response_clean"].tolist()
