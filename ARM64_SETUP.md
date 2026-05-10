# EvoScientist arm64 Setup Notes

记录从 Intel (x86_64) 迁移到 Apple Silicon (arm64) 的完整步骤，以及 Claude OAuth token 自动刷新机制。

---

## 一、arm64 迁移步骤（2026-05-09）

### 1. 重装 bun（arm64 原生）

```bash
curl -fsSL https://bun.sh/install | bash
```

bun 二进制位置：`~/.bun/bin/bun`（Mach-O arm64）

### 2. 重装 codex（带 arm64 原生包）

```bash
export PATH="$HOME/.bun/bin:$PATH"
bun install -g @openai/codex@latest
```

关键：安装后会带 `@openai/codex-darwin-arm64` 原生包。  
版本：`codex-cli 0.129.0`

### 3. 重建 Python venv（arm64）

旧 venv 是 x86_64，需删除重建：

```bash
# 先用 Homebrew 装 arm64 Python 3.12
/opt/homebrew/bin/brew install python@3.12

# 删旧 venv，用 arm64 Python 重建
cd /Users/jason/Dev/PhD/EvoScientist
rm -rf .venv
uv sync --dev --python /opt/homebrew/bin/python3.12

# 重装 ccproxy（editable）
uv pip install -e /Users/jason/Dev/PhD/ccproxy-api/
```

### 4. 清理 uv 管理的 x86_64 Python

```bash
rm -rf ~/.local/share/uv/python/cpython-3.12-macos-x86_64-none
rm -rf ~/.local/share/uv/python/cpython-3.12.9-macos-x86_64-none
```

### 5. 重装 ccproxy 全局工具

```bash
uv tool install --editable /Users/jason/Dev/PhD/ccproxy-api --python /opt/homebrew/bin/python3.12
```

补装缺失依赖：

```bash
uv pip install socksio --python ~/.local/share/uv/tools/ccproxy-api/bin/python3
uv pip install keyring --python ~/.local/share/uv/tools/ccproxy-api/bin/python3
```

### 6. 修复 EvoSci 全局命令（uv tool 删除后补链接）

```bash
ln -sf /Users/jason/Dev/PhD/EvoScientist/.venv/bin/evosci ~/.local/bin/EvoSci
ln -sf /Users/jason/Dev/PhD/EvoScientist/.venv/bin/EvoScientist ~/.local/bin/EvoScientist
```

---

## 二、evo.sh 启动脚本

路径：`/Users/jason/Dev/PhD/EvoScientist/evo.sh`

关键点：在脚本顶部注入 nvm node 和 bun 到 PATH（非交互 shell 默认没有）：

```bash
_NVM_NODE_DIR=$(ls -td "$HOME/.nvm/versions/node"/*/bin 2>/dev/null | head -1)
[[ -n "$_NVM_NODE_DIR" ]] && export PATH="$_NVM_NODE_DIR:$PATH"
[[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
```

用法：

```bash
./evo.sh                  # Claude 默认（config.yaml）
./evo.sh --claude         # Claude Sonnet 4.6
./evo.sh --opus           # Claude Opus 4.7
./evo.sh --codex          # Codex gpt-5.3-codex
./evo.sh /path/to/project # 指定 workdir
```

---

## 三、Claude OAuth Token 自动刷新

### 背景

- Claude OAuth token 有效期约 **8 小时**
- ccproxy 读取凭证路径：`~/.claude/.credentials.json`（JSON 文件，不走系统 Keychain）
- macOS Keychain 存储：`service="Claude Code-credentials", account="jason"`，key=`claudeAiOauth`

### 自动刷新机制

**脚本**：`~/.local/bin/ccproxy-refresh-token.sh`

1. 调用 `ccproxy auth refresh claude_api`（向 Anthropic 刷新 token）
2. 从 macOS Keychain 读取最新 token
3. 写入 `~/.claude/.credentials.json`（ccproxy 读取此文件）

**plist**：`~/Library/LaunchAgents/com.evoscientist.ccproxy-refresh.plist`

- 每 **7.5 小时**（27000 秒）运行一次
- 登录时立即运行一次（`RunAtLoad = true`）
- 日志：`/tmp/ccproxy-token-refresh.log`

### 管理命令

```bash
# 查看状态
launchctl list | grep ccproxy-refresh

# 手动触发刷新
launchctl start com.evoscientist.ccproxy-refresh

# 查看日志
tail -20 /tmp/ccproxy-token-refresh.log

# 停用
launchctl unload ~/Library/LaunchAgents/com.evoscientist.ccproxy-refresh.plist

# 重新启用
launchctl load ~/Library/LaunchAgents/com.evoscientist.ccproxy-refresh.plist
```

### 手动同步 token（紧急备用）

```bash
security find-generic-password -s "Claude Code-credentials" -a "$(id -un)" -w \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({'claude_ai_oauth':d['claudeAiOauth']}))" \
  > ~/.claude/.credentials.json
```

---

## 四、ccproxy 配置

配置文件：`~/.config/ccproxy/config.toml`

关键设置：

```toml
[server]
host = "127.0.0.1"
port = 18080

[security]
enable_auth = false
```

EvoScientist 对应配置（`~/.config/evoscientist/config.yaml`）：

```yaml
provider: anthropic
model: claude-sonnet-4-6
anthropic_auth_mode: api_key
anthropic_base_url: http://localhost:18080/claude
ccproxy_port: 18080
```

---

## 五、ccproxy headers 缓存（Codex）

Codex 所需 headers 缓存路径：`~/.cache/ccproxy/codex_headers_<version>.json`

当前版本：`0.129.0`（arm64 user-agent）

若版本升级后 Codex 报错，重新安装后执行：

```bash
sed 's/<旧版本>/<新版本>/g; s/x86_64/arm64/g' \
  ~/.cache/ccproxy/codex_headers_<旧版本>.json \
  > ~/.cache/ccproxy/codex_headers_<新版本>.json
```
