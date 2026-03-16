                                             

⏺ Here's the full setup for Mac Mini 24/7:

  1. Install dependencies

  # Install uv (if not already)
  curl -LsSf https://astral.sh/uv/install.sh | sh

  # Clone your fork
  git clone https://github.com/jhfnetboy/EvoScientist.git ~/Dev/EvoScientist
  cd ~/Dev/EvoScientist
  git checkout jhf-research

  # Install with all channel + STT deps
  uv pip install -e '.[telegram,stt]'

  2. Configure

  uv run EvoSci config set anthropic_base_url "http://localhost:8000/claude"
  uv run EvoSci config set anthropic_api_key "sk-dummy"
  uv run EvoSci config set model "claude-sonnet-4-6"
  uv run EvoSci config set telegram_bot_token "YOUR_TOKEN"
  uv run EvoSci config set telegram_allowed_senders "YOUR_TELEGRAM_ID"
  uv run EvoSci config set stt_enabled true
  uv run EvoSci config set stt_language zh

  3. Pre-download STT model

  uv run python -c "from faster_whisper import WhisperModel; WhisperModel('Systran/faster-whisper-small', device='cpu',
  compute_type='int8'); print('ready')"

  4. Auto-start with launchd (macOS native)

  Create two plist files — one for ccproxy, one for EvoSci:

  ccproxy:
  cat > ~/Library/LaunchAgents/com.evosci.ccproxy.plist << 'EOF'
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.evosci.ccproxy</string>
      <key>ProgramArguments</key>
      <array>
          <string>/usr/local/bin/ccproxy</string>
          <string>serve</string>
          <string>--port</string>
          <string>8000</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>/tmp/ccproxy.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/ccproxy.log</string>
  </dict>
  </plist>
  EOF

  EvoSci serve:
  cat > ~/Library/LaunchAgents/com.evosci.serve.plist << 'EOF'
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.evosci.serve</string>
      <key>ProgramArguments</key>
      <array>
          <string>/Users/YOUR_USERNAME/Dev/EvoScientist/.venv/bin/EvoSci</string>
          <string>serve</string>
      </array>
      <key>WorkingDirectory</key>
      <string>/Users/YOUR_USERNAME/Dev/EvoScientist</string>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StartInterval</key>
      <integer>10</integer>
      <key>StandardOutPath</key>
      <string>/tmp/evosci.log</string>
      <key>StandardErrorPath</key>
      <string>/tmp/evosci.log</string>
  </dict>
  </plist>
  EOF

  Replace YOUR_USERNAME with your actual username (whoami).

  5. Load and start

  launchctl load ~/Library/LaunchAgents/com.evosci.ccproxy.plist
  launchctl load ~/Library/LaunchAgents/com.evosci.serve.plist

  6. Check logs

  tail -f /tmp/evosci.log
  tail -f /tmp/ccproxy.log

  Managing the service

  # Stop
  launchctl unload ~/Library/LaunchAgents/com.evosci.serve.plist

  # Restart
  launchctl kickstart -k gui/$(id -u)/com.evosci.serve

  # Check status
  launchctl list | grep evosci

  KeepAlive: true means macOS will automatically restart both processes if they crash. They also start automatically on
  login/reboot.


