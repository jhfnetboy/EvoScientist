"""Sanitize tool results so they conform to Anthropic's tool_result schema.

DeepAgents' ``read_file`` returns PDF/image content as a list of content blocks
on ``ToolMessage.content``. If the blocks use non-Anthropic shapes
(e.g. ``image_url`` instead of ``image``, or ``media_type="application/pdf"``),
the next request is rejected with a 422 validation error on
``messages[*].content[*].tool_result.content``.

This middleware rewrites such content to a safe text placeholder after
execution so subsequent turns can continue.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from typing import TYPE_CHECKING, Any

from langchain.agents.middleware.types import AgentMiddleware
from langchain_core.messages import ToolMessage
from langgraph.types import Command

if TYPE_CHECKING:
    from langchain.agents.middleware.types import ToolCallRequest

_ANTHROPIC_IMAGE_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}


def _sanitize_content(content: Any) -> tuple[Any, bool]:
    """Return (sanitized_content, changed)."""
    if not isinstance(content, list):
        return content, False

    new_blocks: list[Any] = []
    changed = False
    for block in content:
        if isinstance(block, str):
            new_blocks.append({"type": "text", "text": block})
            changed = True
            continue
        if not isinstance(block, dict):
            new_blocks.append(
                {"type": "text", "text": f"[unsupported tool-result block: {type(block).__name__}]"}
            )
            changed = True
            continue

        btype = block.get("type")

        if btype == "text" and isinstance(block.get("text"), str):
            new_blocks.append({"type": "text", "text": block["text"]})
            continue

        if btype == "image":
            source = block.get("source") or {}
            media_type = source.get("media_type")
            if isinstance(source, dict) and media_type in _ANTHROPIC_IMAGE_TYPES:
                new_blocks.append(block)
                continue
            new_blocks.append(
                {
                    "type": "text",
                    "text": f"[image omitted: unsupported media_type={media_type!r}]",
                }
            )
            changed = True
            continue

        if btype == "image_url":
            new_blocks.append({"type": "text", "text": "[image omitted: image_url not supported in tool_result]"})
            changed = True
            continue

        text = block.get("text") or block.get("content")
        if isinstance(text, str):
            new_blocks.append({"type": "text", "text": text})
            changed = True
            continue

        new_blocks.append({"type": "text", "text": f"[dropped unsupported block type={btype!r}]"})
        changed = True

    if not new_blocks:
        return "[empty tool result]", True
    return new_blocks, changed


def _sanitize_tool_message(msg: Any) -> Any:
    if not isinstance(msg, ToolMessage):
        return msg
    new_content, changed = _sanitize_content(msg.content)
    if not changed:
        return msg
    return ToolMessage(
        content=new_content,
        tool_call_id=msg.tool_call_id,
        name=msg.name,
        status=getattr(msg, "status", None) or "success",
        additional_kwargs=getattr(msg, "additional_kwargs", {}) or {},
    )


def _sanitize_result(result: Any) -> Any:
    if isinstance(result, ToolMessage):
        return _sanitize_tool_message(result)
    if isinstance(result, Command):
        update = getattr(result, "update", None)
        if isinstance(update, dict) and "messages" in update:
            msgs = update["messages"]
            if isinstance(msgs, list):
                new_msgs = [_sanitize_tool_message(m) for m in msgs]
                if any(n is not o for n, o in zip(new_msgs, msgs)):
                    new_update = dict(update)
                    new_update["messages"] = new_msgs
                    return Command(
                        update=new_update,
                        goto=getattr(result, "goto", None),
                        resume=getattr(result, "resume", None),
                        graph=getattr(result, "graph", None),
                    )
    return result


class ToolResultSanitizerMiddleware(AgentMiddleware):
    """Normalize tool-result content blocks to Anthropic's allowed schema."""

    name = "tool_result_sanitizer"

    def wrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], ToolMessage | Command[Any]],
    ) -> ToolMessage | Command[Any]:
        return _sanitize_result(handler(request))

    async def awrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], Awaitable[ToolMessage | Command[Any]]],
    ) -> ToolMessage | Command[Any]:
        return _sanitize_result(await handler(request))
