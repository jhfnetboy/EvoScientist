"""Middleware package for EvoScientist.

Re-exports middleware classes and factory functions so that existing
``from EvoScientist.middleware import X`` imports continue to work.
"""

from .ask_user import (
    AskUserMiddleware,
    AskUserRequest,
    AskUserWidgetResult,
    Choice,
    Question,
)
from .context_overflow import ContextOverflowMapperMiddleware
from .memory import (
    EvoMemoryMiddleware,
    EvoMemoryState,
    ExtractedMemory,
    create_memory_middleware,
)
from .tool_error_handler import ToolErrorHandlerMiddleware
from .tool_result_sanitizer import ToolResultSanitizerMiddleware

__all__ = [
    "AskUserMiddleware",
    "AskUserRequest",
    "AskUserWidgetResult",
    "Choice",
    "ContextOverflowMapperMiddleware",
    "EvoMemoryMiddleware",
    "EvoMemoryState",
    "ExtractedMemory",
    "Question",
    "ToolErrorHandlerMiddleware",
    "ToolResultSanitizerMiddleware",
    "create_memory_middleware",
]
