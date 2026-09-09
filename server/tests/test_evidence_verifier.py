import json

import pytest

import app.evidence_verifier as verifier_module
from app.evidence_verifier import (
    EvidenceVerificationError,
    OpenAICompatibleEvidenceVerifier,
    parse_supported_indices,
)


def test_parse_supported_indices_accepts_none_and_deduplicates():
    assert parse_supported_indices("SUPPORTED: NONE", 3) == []
    assert parse_supported_indices("SUPPORTED: 0, 2, 0", 3) == [0, 2]


def test_parse_supported_indices_rejects_malformed_or_out_of_range_output():
    with pytest.raises(EvidenceVerificationError):
        parse_supported_indices("The answer is evidence 0", 2)
    with pytest.raises(EvidenceVerificationError):
        parse_supported_indices("SUPPORTED: 2", 2)


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.payload).encode("utf-8")


def test_openai_compatible_verifier_returns_only_explicit_supported_indices(monkeypatch):
    captured = {}

    def fake_urlopen(request, timeout):
        captured["url"] = request.full_url
        captured["timeout"] = timeout
        captured["body"] = json.loads(request.data.decode("utf-8"))
        return FakeResponse(
            {
                "choices": [
                    {"message": {"content": "SUPPORTED: 1"}}
                ]
            }
        )

    monkeypatch.setattr(verifier_module, "urlopen", fake_urlopen)
    verifier = OpenAICompatibleEvidenceVerifier(
        base_url="https://example.invalid/v1",
        api_key="secret",
        model="judge-model",
        timeout_seconds=7,
    )

    result = verifier.verify(
        "Where is the service deployed?",
        [
            "The service uses Qdrant for vector search.",
            "The service is deployed in Singapore.",
        ],
    )

    assert result == [1]
    assert captured["url"].endswith("/chat/completions")
    assert captured["timeout"] == 7
    assert captured["body"]["temperature"] == 0
    assert captured["body"]["max_tokens"] == 32


def test_verifier_treats_provider_format_drift_as_failure(monkeypatch):
    monkeypatch.setattr(
        verifier_module,
        "urlopen",
        lambda *_args, **_kwargs: FakeResponse(
            {"choices": [{"message": {"content": "Probably passage zero."}}]}
        ),
    )
    verifier = OpenAICompatibleEvidenceVerifier(
        base_url="https://example.invalid",
        api_key="",
        model="judge-model",
    )

    with pytest.raises(EvidenceVerificationError):
        verifier.verify("Question", ["Evidence"])
