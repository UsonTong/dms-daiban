#!/bin/bash
# 在虚拟显示器上启动 Linux 版并截图，不打扰当前桌面
# 用法: tool/shot.sh <输出前缀> [宽 高] [xdotool 动作...]
set -e
cd "$(dirname "$0")/.."
OUT=$1; W=${2:-1280}; H=${3:-800}; shift 3 || true
# 用独立的数据目录，绝不碰真实配置（用户自己开着的 App 也在读写那份）
export XDG_DATA_HOME=$(mktemp -d /tmp/vmd-shot-XXXX)
# 配置目录也要隔离：App 会往 ~/.config/vikunja-md/dms.json 写面板凭证，
# 不隔离的话测试账号的凭证会顶掉真实账号的（10-24 出过一次）
export XDG_CONFIG_HOME=$(mktemp -d /tmp/vmd-shot-cfg-XXXX)
PREFS=$XDG_DATA_HOME/com.yl.vikunja_md/shared_preferences.json
if [ -n "$VMD_LOGIN" ]; then
  HDR=$(mktemp)
  TOKEN=$(curl -s -D "$HDR" -X POST http://localhost:3456/api/v1/login -H 'Content-Type: application/json' \
    -d "{\"username\":\"$VMD_LOGIN\",\"password\":\"$VMD_PASS\",\"long_token\":true}" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
  RT=$(grep -i set-cookie "$HDR" | head -1 | sed 's/.*vikunja_refresh_token=\([^;]*\).*/\1/' | tr -d '\r')
  mkdir -p "$(dirname "$PREFS")"
  printf '{"flutter.server":"http://localhost:3456","flutter.token":"%s","flutter.refresh":"%s"}' "$TOKEN" "$RT" > "$PREFS"
fi
Xvfb :99 -screen 0 ${W}x${H}x24 >/dev/null 2>&1 & XP=$!
sleep 1
DISPLAY=:99 GDK_BACKEND=x11 WAYLAND_DISPLAY= build/linux/x64/release/bundle/vikunja_md >/tmp/vmd-app.log 2>&1 & AP=$!
sleep 4
WID=$(DISPLAY=:99 xdotool search --pid $AP | tail -1)
DISPLAY=:99 xdotool windowmove $WID 0 0 windowsize $WID $W $H
sleep 1.5
i=0
DISPLAY=:99 import -window root "${OUT}-${i}.png"
for act in "$@"; do
  i=$((i+1))
  DISPLAY=:99 xdotool $act
  sleep 1.2
  DISPLAY=:99 import -window root "${OUT}-${i}.png"
done
kill $AP $XP 2>/dev/null || true
rm -rf "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"
