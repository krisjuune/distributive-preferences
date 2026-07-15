import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src" / "preprocess"))

from open_ended_translation import needs_translation, translate_response  # noqa: E402


def test_needs_translation_only_for_french_and_chinese():
    assert needs_translation("fr") is True
    assert needs_translation("zh") is True
    assert needs_translation("de") is False
    assert needs_translation("en") is False


class _FakeContentBlock:
    def __init__(self, text):
        self.text = text


class _FakeMessage:
    def __init__(self, text):
        self.content = [_FakeContentBlock(text)]


class _FakeMessages:
    def __init__(self, reply_text):
        self.reply_text = reply_text
        self.last_call_kwargs = None

    def create(self, **kwargs):
        self.last_call_kwargs = kwargs
        return _FakeMessage(self.reply_text)


class _FakeClient:
    def __init__(self, reply_text):
        self.messages = _FakeMessages(reply_text)


def test_translate_response_strips_whitespace_from_reply():
    client = _FakeClient(reply_text="  Equality for everyone  ")

    result = translate_response(client, model="claude-haiku-4-5-20251001", text="Gleichheit für alle")

    assert result == "Equality for everyone"


def test_translate_response_calls_api_with_pinned_model_and_zero_temperature():
    client = _FakeClient(reply_text="ok")

    translate_response(client, model="claude-haiku-4-5-20251001", text="平等")

    kwargs = client.messages.last_call_kwargs
    assert kwargs["model"] == "claude-haiku-4-5-20251001"
    assert kwargs["temperature"] == 0
    assert kwargs["messages"] == [{"role": "user", "content": "平等"}]
