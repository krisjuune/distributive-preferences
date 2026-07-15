import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src" / "preprocess"))

from harmonise import (  # noqa: E402
    clean_dataframe,
    coerce_mixed_type_columns,
    compute_justice_principle_scores,
    filter_invalid_responses,
    fix_known_typos,
    fix_wave3_ch_conjoint_numbering,
    harmonise_justice_columns,
)


def test_clean_dataframe_drops_pii_and_tags_rows():
    raw = pd.DataFrame(
        {
            "RecipientEmail": ["a@example.com", "b@example.com"],
            "IPAddress": ["1.2.3.4", "5.6.7.8"],
            "StartDate": ["2026-01-01", "2026-01-02"],
            "age": [34, 51],
        }
    )
    # A topic with no wave-specific invalid-response filtering, so this test
    # stays focused on PII-dropping/tagging rather than needing to fabricate
    # DistributionChannel/Finished/etc. columns too.
    wave_meta = {"wave": 3, "country": "CH", "topic": "unit-test-topic"}

    cleaned = clean_dataframe(
        raw,
        wave_meta=wave_meta,
        pii_columns=["RecipientEmail", "IPAddress"],
        metadata_columns=["StartDate"],
    )

    assert "RecipientEmail" not in cleaned.columns
    assert "IPAddress" not in cleaned.columns
    assert "StartDate" not in cleaned.columns
    assert list(cleaned["wave"]) == [3, 3]
    assert list(cleaned["country"]) == ["CH", "CH"]
    assert list(cleaned["respondent_id"]) == [0, 1]
    assert list(cleaned["age"]) == [34, 51]


def test_clean_dataframe_is_a_noop_for_missing_pii_columns():
    raw = pd.DataFrame({"age": [22]})
    wave_meta = {"wave": 1, "country": "CH", "topic": "unit-test-topic"}

    cleaned = clean_dataframe(
        raw, wave_meta=wave_meta, pii_columns=["RecipientEmail"], metadata_columns=[]
    )

    assert list(cleaned["age"]) == [22]


def test_clean_dataframe_filters_a_multi_country_raw_file_to_one_country():
    raw = pd.DataFrame(
        {
            "LANGUAGE": ["ita", "fre", "ita", "eng"],
            "STATUS": ["complete", "complete", "complete", "complete"],
            "age": [34, 51, 29, 40],
        }
    )
    wave_meta = {
        "wave": 4,
        "country": "IT",
        "topic": "policy-instruments",
        "country_column": "LANGUAGE",
        "country_value": "ita",
    }

    cleaned = clean_dataframe(
        raw, wave_meta=wave_meta, pii_columns=[], metadata_columns=[]
    )

    assert list(cleaned["age"]) == [34, 29]
    assert list(cleaned["country"]) == ["IT", "IT"]
    assert list(cleaned["respondent_id"]) == [0, 1]


def test_harmonise_justice_columns_recodes_wave1_german_likert_text():
    raw = pd.DataFrame(
        {
            "justice-general_1": ["Stimme voll und ganz zu", "Stimme überhaupt nicht zu", None],
            "justice-tax_3": ["Stimme eher zu", "Stimme zu", "Stimme nicht zu"],
        }
    )
    wave_meta = {"topic": "heating-pv-choice"}

    harmonised = harmonise_justice_columns(raw, wave_meta)

    assert harmonised["justice_general_1"].tolist()[:2] == [5, 0]
    assert pd.isna(harmonised["justice_general_1"].tolist()[2])
    assert list(harmonised["justice_tax_3"]) == [3, 4, 1]
    assert "justice-general_1" not in harmonised.columns


def test_harmonise_justice_columns_recodes_wave3_english_likert_text():
    raw = pd.DataFrame(
        {
            "justice_gen_2": ["Strongly agree", "Disagree"],
            "justice_sub_4": ["Somewhat disagree", "Strongly disagree"],
            "justice_tax_1": ["Agree", "Somewhat agree"],
            "justice_open1_gen": ["some free text", "more free text"],
        }
    )
    wave_meta = {"topic": "ccs-conjoint"}

    harmonised = harmonise_justice_columns(raw, wave_meta)

    assert list(harmonised["justice_general_2"]) == [5, 1]
    assert list(harmonised["justice_subsidy_4"]) == [2, 0]
    assert list(harmonised["justice_tax_1"]) == [4, 3]
    # Open-ended follow-up text isn't part of the Likert battery -- left alone.
    assert list(harmonised["justice_open1_gen"]) == ["some free text", "more free text"]


def test_harmonise_justice_columns_renames_wave4_already_numeric_columns():
    # Trans_fair_* -> justice_general_* (same subscale as waves 1-3's
    # "general", just named differently in the wave 4 SoSci export).
    raw = pd.DataFrame(
        {
            "Trans_fair_costmin": [3, 5],
            "Tax_fair_all": [7, 1],
            "Subsidy_fair_lower": [2, 4],
            "ban_fair_fleets": [6, 6],
        }
    )
    wave_meta = {"topic": "policy-instruments"}

    harmonised = harmonise_justice_columns(raw, wave_meta)

    assert list(harmonised["justice_general_costmin"]) == [3, 5]
    assert list(harmonised["justice_tax_all"]) == [7, 1]
    assert list(harmonised["justice_subsidy_lower"]) == [2, 4]
    assert list(harmonised["justice_ban_fleets"]) == [6, 6]


def test_harmonise_justice_columns_is_a_noop_for_wave2():
    raw = pd.DataFrame({"justice_general_1": [0, 3, 6]})
    wave_meta = {"topic": "flying-wtc-wtp"}

    harmonised = harmonise_justice_columns(raw, wave_meta)

    assert list(harmonised["justice_general_1"]) == [0, 3, 6]


def test_fix_known_typos_wave1_renames_language_column():
    raw = pd.DataFrame({"languge": ["german", "french"]})
    wave_meta = {"topic": "heating-pv-choice", "country": "CH"}

    fixed = fix_known_typos(raw, wave_meta)

    assert list(fixed["language"]) == ["german", "french"]
    assert "languge" not in fixed.columns


def test_fix_known_typos_wave2_renames_recent_flights_and_fixes_us_income():
    raw = pd.DataFrame(
        {
            "recent_flights": [2, 4],
            "personal_income": ["15k_35k", "25k_35k"],
        }
    )
    wave_meta = {"topic": "flying-wtc-wtp", "country": "US"}

    fixed = fix_known_typos(raw, wave_meta)

    assert list(fixed["flying_recent_number"]) == [2, 4]
    assert list(fixed["personal_income"]) == ["15k_25k", "25k_35k"]


def test_filter_invalid_responses_wave1_drops_preview_unfinished_and_quota_full():
    raw = pd.DataFrame(
        {
            "DistributionChannel": ["anonymous", "preview", "anonymous", "anonymous"],
            "Finished": [True, True, False, True],
            "canton": ["ZH", "BE", "GE", None],
        }
    )
    wave_meta = {"topic": "heating-pv-choice", "country": "CH"}

    filtered = filter_invalid_responses(raw, wave_meta)

    assert list(filtered["canton"]) == ["ZH"]


def test_filter_invalid_responses_wave2_drops_screened_out_and_quota_met():
    raw = pd.DataFrame(
        {
            "DistributionChannel": ["anonymous"] * 5,
            "Finished": [True, True, True, True, True],
            "screened_out": ["false", "true", "true_trap1", "true_region", "false"],
            "Q_TerminateFlag": [None, None, None, None, "QuotaMet"],
        }
    )
    wave_meta = {"topic": "flying-wtc-wtp", "country": "CH"}

    filtered = filter_invalid_responses(raw, wave_meta)

    assert len(filtered) == 1
    assert filtered["screened_out"].tolist() == ["false"]


def test_filter_invalid_responses_wave2_only_drops_true_region_for_ch():
    raw = pd.DataFrame(
        {
            "DistributionChannel": ["anonymous", "anonymous"],
            "Finished": [True, True],
            "screened_out": ["false", "true_region"],
            "Q_TerminateFlag": [None, None],
        }
    )
    wave_meta = {"topic": "flying-wtc-wtp", "country": "US"}

    filtered = filter_invalid_responses(raw, wave_meta)

    assert len(filtered) == 2


def test_filter_invalid_responses_wave3_drops_pre_launch_test_rows():
    raw = pd.DataFrame(
        {
            "DistributionChannel": ["anonymous", "anonymous"],
            "Finished": [True, True],
            "Q_TerminateFlag": [None, None],
            "StartDate": ["2025-01-08 11:08:03", "2025-02-14 09:00:00"],
        }
    )
    wave_meta = {"topic": "ccs-conjoint", "country": "CH"}

    filtered = filter_invalid_responses(raw, wave_meta)

    assert list(filtered["StartDate"]) == ["2025-02-14 09:00:00"]


def test_filter_invalid_responses_wave4_keeps_only_complete_status():
    raw = pd.DataFrame(
        {
            "STATUS": ["complete", "quality fail", "screenout", None],
        }
    )
    wave_meta = {"topic": "policy-instruments", "country": "IT"}

    filtered = filter_invalid_responses(raw, wave_meta)

    assert list(filtered["STATUS"]) == ["complete"]


def test_fix_wave3_ch_conjoint_numbering_shifts_task_numbers_down_by_5():
    raw = pd.DataFrame(
        {
            "6_conjoint_choose12": [1],
            "11_conjoint_plan1": ["x"],
            "other_column": [42],
        }
    )
    wave_meta = {"topic": "ccs-conjoint", "country": "CH"}

    fixed = fix_wave3_ch_conjoint_numbering(raw, wave_meta)

    assert list(fixed.columns) == ["1_conjoint_choose12", "6_conjoint_plan1", "other_column"]


def test_fix_wave3_ch_conjoint_numbering_is_a_noop_for_cn():
    raw = pd.DataFrame({"1_conjoint_choose12": [1]})
    wave_meta = {"topic": "ccs-conjoint", "country": "CN"}

    fixed = fix_wave3_ch_conjoint_numbering(raw, wave_meta)

    assert list(fixed.columns) == ["1_conjoint_choose12"]


def test_compute_justice_principle_scores_sums_across_domains():
    raw = pd.DataFrame(
        {
            "justice_general_1": [5, 0],
            "justice_tax_1": [4, 1],
            "justice_subsidy_1": [3, 2],
            "justice_general_2": [1, 1],
            "justice_tax_2": [1, 1],
            "justice_subsidy_2": [1, 1],
        }
    )
    wave_meta = {"topic": "heating-pv-choice"}

    scored = compute_justice_principle_scores(raw, wave_meta)

    assert list(scored["justice_principle_utilitarian"]) == [12, 3]
    assert list(scored["justice_principle_egalitarian"]) == [3, 3]
    assert "justice_principle_sufficientarian" not in scored.columns


def test_compute_justice_principle_scores_wave4_uses_named_item_mapping():
    # wave 4 items are named by policy mechanism, not positionally
    # (_1/_2/_3/_4 like waves 1-3) -- utilitarian here is
    # costmin (general) + moderate (tax) + everyone (subsidy) + reduction (ban).
    raw = pd.DataFrame(
        {
            "justice_general_costmin": [3, 1],
            "justice_tax_moderate": [2, 1],
            "justice_subsidy_everyone": [1, 1],
            "justice_ban_reduction": [1, 1],
            "justice_general_inequ": [5, 5],
        }
    )
    wave_meta = {"topic": "policy-instruments"}

    scored = compute_justice_principle_scores(raw, wave_meta)

    assert list(scored["justice_principle_utilitarian"]) == [7, 4]
    assert list(scored["justice_principle_egalitarian"]) == [5, 5]  # only 1 of 4 domains present
    assert "justice_principle_sufficientarian" not in scored.columns  # no domains present


def test_coerce_mixed_type_columns_is_parquet_safe():
    # A free-text field with a stray numeric value, as seen in wave 4's
    # SD23_01 column -- pandas leaves this as `object` dtype, which pyarrow
    # can't write since it mixes str and float within one column.
    raw = pd.DataFrame({"free_text": ["some answer", np.nan, 42.0]})

    coerced = coerce_mixed_type_columns(raw)

    assert coerced["free_text"].dtype == "string"
    assert coerced["free_text"].tolist()[0] == "some answer"
    assert pd.isna(coerced["free_text"].tolist()[1])
