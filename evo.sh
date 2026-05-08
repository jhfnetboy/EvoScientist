#!/usr/bin/env bash
# evo.sh — 在当前 shell 会话范围内启动 EvoScientist
#
# 用法:
#   ./evo.sh                            # 用 config 默认 provider/model + 当前目录
#   ./evo.sh /path/to/project           # 指定 workdir
#   ./evo.sh -p "你的问题"               # 单次查询
#
# 切换 AI（覆盖 config，仅本次有效）:
#   ./evo.sh --claude                   # Claude Sonnet 4.6
#   ./evo.sh --opus                     # Claude Opus 4.7
#   ./evo.sh --codex                    # Codex (gpt-5.3-codex via ChatGPT Plus)
#
# 组合（顺序任意）:
#   ./evo.sh --codex /path -p "分析数据"
#   ./evo.sh --opus -p "写论文摘要"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 确保 node / bun / codex 在 PATH ---
# nvm 管理的 node 默认不在非交互 shell 的 PATH 里
_NVM_NODE_DIR=""
if [[ -d "$HOME/.nvm/versions/node" ]]; then
  _NVM_NODE_DIR=$(ls -td "$HOME/.nvm/versions/node"/*/bin 2>/dev/null | head -1)
fi
[[ -n "$_NVM_NODE_DIR" ]] && export PATH="$_NVM_NODE_DIR:$PATH"
[[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"

# 默认工作目录（不带任何路径参数时使用）
DEFAULT_WORKDIR="/Users/jason/Dev/jhfnetboy/DSR-Research-Flow"

# --- 参数解析 ---
WORKDIR=""
PROVIDER=""
MODEL=""
PASSTHROUGH_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --claude)
      PROVIDER="anthropic"
      MODEL="claude-sonnet-4-6"
      ;;
    --opus)
      PROVIDER="anthropic"
      MODEL="claude-opus-4-7"
      ;;
    --codex)
      PROVIDER="openai"
      MODEL="gpt-5.3-codex"
      ;;
    *)
      if [[ -d "$arg" ]]; then
        WORKDIR="$arg"
      else
        PASSTHROUGH_ARGS+=("$arg")
      fi
      ;;
  esac
done

# 没传路径就用 DEFAULT_WORKDIR；如果它也不存在则退到脚本目录
if [[ -z "$WORKDIR" ]]; then
  if [[ -d "$DEFAULT_WORKDIR" ]]; then
    WORKDIR="$DEFAULT_WORKDIR"
  else
    WORKDIR="$SCRIPT_DIR"
  fi
fi
WORKDIR="$(cd "$WORKDIR" && pwd)"

# --- 仅在本 shell 会话中设置环境变量（不影响全局） ---
export EVOSCIENTIST_WORKSPACE_DIR="$WORKDIR"

# 如果 all_proxy 是 SOCKS 但 http_proxy 有值，用 http_proxy 覆盖（避免缺 socksio）
if [[ "${all_proxy:-}" == socks* ]] && [[ -n "${http_proxy:-}" ]]; then
  export all_proxy="$http_proxy"
  export ALL_PROXY="$http_proxy"
fi

# --- 拼装 EvoSci 启动参数 ---
EVO_ARGS=()
if [[ -n "$PROVIDER" ]]; then
  EVO_ARGS+=(--provider "$PROVIDER" --model "$MODEL")
fi
EVO_ARGS+=("${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}")

# --- Token pre-flight: 只在 anthropic 路径才检查 Claude ---
# 思路:
#   1) 查 token 过期时间
#   2) 剩余 > 30min: 直接跑（最常见情况）
#   3) 剩余 < 30min 或已过期: 调一次 ccproxy auth refresh
#   4) refresh 失败（rate limit 或协议）: 提示 ccproxy auth login，但不阻塞
#      （ccproxy 启动后自己也会再尝试一次）
_check_claude_token() {
  local provider="${1:-}"
  if [[ "$provider" != "anthropic" && -n "$provider" ]]; then
    return 0  # 不是 Claude 路径，跳过
  fi
  local exp_line
  exp_line=$(ccproxy auth status claude_api 2>/dev/null | grep "Token Expires" | head -1)
  [[ -z "$exp_line" ]] && return 0  # status 失败就让 ccproxy 自己处理

  # 解析 "Token Expires    2026-05-06 01:48:46.997000+00:00"
  local exp_str
  exp_str=$(echo "$exp_line" | awk '{print $3" "$4}' | sed 's/\.[0-9]*//;s/+00:00/+0000/')
  local exp_epoch now_epoch remaining
  exp_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S%z" "$exp_str" +%s 2>/dev/null || echo 0)
  now_epoch=$(date +%s)
  remaining=$(( exp_epoch - now_epoch ))

  if (( remaining > 1800 )); then
    return 0  # 还剩 >30 分钟，跳过
  fi

  if (( remaining > 0 )); then
    echo "[evo] Claude token 将在 $((remaining/60)) 分钟内过期，刷新中..."
  else
    echo "[evo] Claude token 已过期 $((-remaining/60)) 分钟，刷新中..."
  fi

  if ccproxy auth refresh claude_api >/dev/null 2>&1; then
    echo "[evo] ✓ token 已刷新"
  else
    echo "[evo] ⚠️  refresh 失败（多半是 Anthropic OAuth 限流）"
    echo "[evo]    若 evo 启动后 401，请运行: ccproxy auth login claude_api"
  fi
}

_check_claude_token "$PROVIDER"

# --- 状态摘要 ---
echo "[evo] workdir:  $WORKDIR"
echo "[evo] provider: ${PROVIDER:-（用 config 默认）}"
[[ -n "$MODEL" ]] && echo "[evo] model:    $MODEL"
echo "[evo] args:     ${PASSTHROUGH_ARGS[*]:-（交互模式）}"
echo ""

# --- 启动 ---
cd "$WORKDIR"
exec uv run --project "$SCRIPT_DIR" EvoSci "${EVO_ARGS[@]+"${EVO_ARGS[@]}"}"
