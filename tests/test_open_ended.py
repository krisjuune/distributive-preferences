import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src" / "preprocess"))

from open_ended import (  # noqa: E402
    classify_exclusion,
    clean_open_ended,
    melt_open_ended,
    normalize_text,
)


def test_melt_open_ended_keeps_one_row_per_shown_respondent():
    df = pd.DataFrame(
        {
            "respondent_id": [0, 1, 2],
            "language": ["Deutsch", "Français", "Deutsch"],
            "show_open_Q1": [1, None, None],
            "justice_open1_gen": ["weil es fair ist", None, None],
            "show_open_Q2": [None, 1, None],
            "justice_open2_tax": [None, "pour les plus pauvres", None],
            "show_open_Q3": [None, None, 1],
            "justice_open3_sub": [None, None, "günstiger für alle"],
        }
    )

    melted = melt_open_ended(df, country="CH")

    assert len(melted) == 3
    assert set(melted["respondent_id"]) == {0, 1, 2}
    assert dict(zip(melted["respondent_id"], melted["context"])) == {
        0: "general",
        1: "tax",
        2: "subsidy",
    }
    assert dict(zip(melted["respondent_id"], melted["language"])) == {
        0: "de",
        1: "fr",
        2: "de",
    }


def test_melt_open_ended_defaults_to_zh_when_no_language_column():
    df = pd.DataFrame(
        {
            "respondent_id": [0],
            "show_open_Q1": [1],
            "justice_open1_gen": ["公平"],
            "show_open_Q2": [None],
            "justice_open2_tax": [None],
            "show_open_Q3": [None],
            "justice_open3_sub": [None],
        }
    )

    melted = melt_open_ended(df, country="CN")

    assert melted["language"].tolist() == ["zh"]


def test_normalize_text_strips_and_collapses_whitespace():
    assert normalize_text("  fair   for  all  ") == "fair for all"
    assert normalize_text(None) is None
    assert normalize_text("   ") is None


def test_classify_exclusion_flags_expected_reasons():
    assert classify_exclusion(None, "de") == "missing"
    assert classify_exclusion("6", "de") == "numeric_or_punctuation_only"
    assert classify_exclusion(".", "de") == "numeric_or_punctuation_only"
    assert classify_exclusion("x", "de") == "too_short"
    assert classify_exclusion("weiss nicht", "de") == "non_answer_phrase"
    assert classify_exclusion("不知道", "zh") == "non_answer_phrase"
    assert classify_exclusion("x" * 61, "de") == "suspected_artifact"
    # Chinese has no whitespace between words, so a long unspaced response
    # is a normal answer, not a suspected export artifact.
    assert classify_exclusion("这" * 61, "zh") is None
    assert classify_exclusion("it should be based on need", "en") is None


def test_clean_open_ended_end_to_end():
    df = pd.DataFrame(
        {
            "respondent_id": [0, 1],
            "language": ["Deutsch", "Deutsch"],
            "show_open_Q1": [1, 1],
            "justice_open1_gen": ["weil es allen gleich viel bringt", "nn"],
            "show_open_Q2": [None, None],
            "justice_open2_tax": [None, None],
            "show_open_Q3": [None, None],
            "justice_open3_sub": [None, None],
        }
    )

    cleaned = clean_open_ended(df, country="CH")

    assert list(cleaned["is_substantive"]) == [True, False]
    assert cleaned.loc[cleaned["respondent_id"] == 1, "exclusion_reason"].item() == "non_answer_phrase"
