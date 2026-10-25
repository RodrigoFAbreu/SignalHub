"""SignalHub producer SDK: publish events to a SignalHub server.

from signalhub import SignalHub

hub = SignalHub.from_env()  # SIGNALHUB_URL and SIGNALHUB_API_KEY
event = hub.publish(category="COMPLETED", severity="NORMAL", title="Backup finished")

# Ask a question and wait for the answer:
from signalhub import Ask, Choice
event = hub.publish(
    category="ACTION_REQUIRED", severity="HIGH", title="Merge it?",
    ask=Ask([Choice("merge", "Merge"), Choice("hold", "Hold")]),
)
state = hub.wait_answer(event["id"], timeout=1800)  # state["answer"]["choices"]
"""

from signalhub.client import (
    Ask,
    AuthenticationError,
    Category,
    Choice,
    ConfigurationError,
    QuestionAnsweredError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    ValidationError,
    Violation,
    derive_choice_ids,
)

__all__ = [
    "Ask",
    "AuthenticationError",
    "Category",
    "Choice",
    "ConfigurationError",
    "QuestionAnsweredError",
    "RequestError",
    "Severity",
    "SignalHub",
    "SignalHubError",
    "UnreachableError",
    "ValidationError",
    "Violation",
    "derive_choice_ids",
]
