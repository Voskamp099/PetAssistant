#!/usr/bin/env bash
# 安装 / 卸载开机自启（LaunchAgent）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT/build/PetAssistant.app"
PLIST="$HOME/Library/LaunchAgents/com.zhaozong.petassistant.plist"

LABEL="com.zhaozong.petassistant"

usage() {
    cat <<EOF
Usage: $0 {install|uninstall|run|status}
  install   写入 ~/Library/LaunchAgents/$LABEL.plist，开机自动跑
  uninstall 移除
  run       立刻手动启动一次
  status    看当前状态
EOF
}

install() {
    test -d "$APP_PATH" || { echo "✗ 先跑 scripts/build.sh 构建出 .app"; exit 1; }
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-W</string>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load -w "$PLIST"
    echo "✓ 已安装：$PLIST"
    echo "▶ 重启测试：注销再登录或 sudo launchctl kickstart -k gui/\$(id -u)/$LABEL"
}

uninstall() {
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        echo "✓ 已移除 $PLIST"
    else
        echo "未安装过"
    fi
}

run() {
    test -d "$APP_PATH" || { echo "✗ 先跑 scripts/build.sh"; exit 1; }
    open "$APP_PATH"
    echo "▶ 已启动"
}

status() {
    if [[ -f "$PLIST" ]]; then
        echo "plist: $PLIST"
        launchctl list | grep -i petassistant || echo "(未加载)"
    else
        echo "未安装"
    fi
}

case "${1:-}" in
    install) install ;;
    uninstall) uninstall ;;
    run) run ;;
    status) status ;;
    *) usage; exit 1 ;;
esac
