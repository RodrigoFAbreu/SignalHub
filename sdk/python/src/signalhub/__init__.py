"""SignalHub producer SDK: publish events to a SignalHub server.

from signalhub import SignalHub

hub = SignalHub.from_env()  # SIGNALHUB_URL and SIGNALHUB_API_KEY
event = hub.publish(category="COMPLETED", severity="NORMAL", title="Backup finished")
"""

from signalhub.client import (
    AuthenticationError,
    Category,
    ConfigurationError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    ValidationError,
    Violation,
)

__all__ = [
    "AuthenticationError",
    "Category",
    "ConfigurationError",
    "RequestError",
    "Severity",
    "SignalHub",
    "SignalHubError",
    "UnreachableError",
    "ValidationError",
    "Violation",
]
