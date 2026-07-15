"""Translate wave 3's open-ended validation-sample responses into English
via the Anthropic API, for coders who aren't fluent in the source
language. The translation is a coding *aid* only -- the original text
stays the authoritative version handed to both human coders and (later)
the LLM classifier itself, so no classification decision should ever be
based on the translation alone when the original is available.

Kept separate from translate_open_ended_validation_sample.py so the
prompt-building/response-parsing logic is testable without a live API
call -- tests pass in a fake client matching anthropic.Anthropic's
`.messages.create()` shape."""

_LANGUAGES_NEEDING_TRANSLATION = {"fr", "zh"}

_SYSTEM_PROMPT = (
    "You translate short survey responses into English. Each response "
    "answers an open-ended question in a survey about the fairness of "
    "climate/energy policy costs and benefits (a carbon tax, a subsidy, or "
    "the broader energy transition) -- treat that as context for resolving "
    "ambiguous words. Output ONLY the English translation, nothing else: "
    "no preamble, no quotation marks, no explanation. If the text is "
    "already in English, or isn't translatable (e.g. a stray number or "
    "punctuation), return it unchanged."
)


def needs_translation(language: str) -> bool:
    return language in _LANGUAGES_NEEDING_TRANSLATION


def translate_response(client, model: str, text: str) -> str:
    """Call the Anthropic API to translate a single short response.
    `client` is dependency-injected (an anthropic.Anthropic instance in
    production, a fake in tests)."""
    response = client.messages.create(
        model=model,
        max_tokens=500,
        temperature=0,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": text}],
    )
    return response.content[0].text.strip()
