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

# --- Pre-flight: 检查 ccproxy + token 状态，按需刷新 ---
SETUP_REFRESH_SH="/Users/jason/Dev/PhD/ccproxy-api/setup-token-refresh.sh"
CREDS="$HOME/.claude/.credentials.json"
CCPROXY_PORT=18080

# 从 .credentials.json 读取 token 剩余秒数；返回 -1 表示文件不存在/无法解析
_token_remaining_seconds() {
  [[ -f "$CREDS" ]] || { echo -1; return; }
  python3 - <<'PYEOF' "$CREDS"
import sys, json, time, pathlib
try:
    d = json.loads(pathlib.Path(sys.argv[1]).read_text())
    exp_ms = d.get("claude_ai_oauth", {}).get("expiresAt", 0)
    print(int(exp_ms / 1000 - time.time()) if exp_ms else -1)
except Exception:
    print(-1)
PYEOF
}

# 检查 ccproxy 是否在跑
_ccproxy_running() {
  curl -s --max-time 1 "http://127.0.0.1:${CCPROXY_PORT}/health/live" > /dev/null 2>&1
}

_preflight() {
  local provider="${1:-}"

  # Codex 路径：只需确保 ccproxy 在跑，无需检查 Claude token
  if [[ "$provider" == "openai" ]]; then
    if ! _ccproxy_running; then
      echo "[evo] ccproxy 未运行，启动中..."
      nohup "$HOME/.local/bin/ccproxy" serve --port "$CCPROXY_PORT" \
        >> /tmp/ccproxy-token-refresh.log 2>&1 &
      local i=0
      while (( i < 12 )); do
        _ccproxy_running && { echo "[evo] ✓ ccproxy 已启动"; break; }
        sleep 1; (( i++ ))
      done
      _ccproxy_running || echo "[evo] ⚠ ccproxy 启动超时，codex 可能失败"
    fi
    return 0
  fi

  # Claude 路径（anthropic 或未指定 provider）
  local remaining
  remaining=$(_token_remaining_seconds)

  # 1) token 充足（>30 min）且 ccproxy 在跑 → 直接启动
  if (( remaining > 1800 )) && _ccproxy_running; then
    local h=$(( remaining / 3600 ))
    local m=$(( (remaining % 3600) / 60 ))
    echo "[evo] ✓ token 有效（剩余 ${h}h ${m}m），ccproxy 运行中"
    return 0
  fi

  # 2) token 即将过期或已过期 → 刷新
  if (( remaining <= 1800 )); then
    if (( remaining > 0 )); then
      echo "[evo] ⚠ token 将在 $(( remaining / 60 )) 分钟内过期，刷新中..."
    elif (( remaining == -1 )); then
      echo "[evo] ⚠ 未找到 token 文件，尝试刷新..."
    else
      echo "[evo] ✗ token 已过期 $(( -remaining / 60 )) 分钟，刷新中..."
    fi

    if [[ -x "$SETUP_REFRESH_SH" ]]; then
      if "$SETUP_REFRESH_SH" refresh 2>&1 | sed 's/^/[evo]   /'; then
        echo "[evo] ✓ token 刷新并重启 ccproxy 完成"
        return 0
      else
        echo "[evo] ✗ 自动刷新失败，需要重新登录："
        echo "[evo]   请运行: ccproxy auth login claude_api"
        echo "[evo]   然后重新执行 evo"
        exit 1
      fi
    else
      echo "[evo] ⚠ 未找到 $SETUP_REFRESH_SH，跳过刷新"
    fi
  fi

  # 3) token 有效但 ccproxy 没跑 → 只需启动 ccproxy
  if ! _ccproxy_running; then
    echo "[evo] ccproxy 未运行，启动中..."
    nohup "$HOME/.local/bin/ccproxy" serve --port "$CCPROXY_PORT" \
      >> /tmp/ccproxy-token-refresh.log 2>&1 &
    local i=0
    while (( i < 12 )); do
      _ccproxy_running && { echo "[evo] ✓ ccproxy 已启动"; return 0; }
      sleep 1; (( i++ ))
    done
    echo "[evo] ⚠ ccproxy 启动超时"
  fi
}

_preflight "$PROVIDER"

# --- 状态摘要 ---
echo "[evo] workdir:  $WORKDIR"
echo "[evo] provider: ${PROVIDER:-（用 config 默认）}"
[[ -n "$MODEL" ]] && echo "[evo] model:    $MODEL"
echo "[evo] args:     ${PASSTHROUGH_ARGS[*]:-（交互模式）}"
echo ""

# --- 启动 ---
cd "$WORKDIR"
exec uv run --project "$SCRIPT_DIR" EvoSci "${EVO_ARGS[@]+"${EVO_ARGS[@]}"}"
