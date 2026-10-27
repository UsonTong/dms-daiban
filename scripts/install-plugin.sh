#!/bin/sh
# 把 DMS 插件装到 ~/.config/dms/plugins/Daiban，并装好 daiban 启动脚本。
# 注意：插件目录必须是真实文件，不能软链接——Qt 加载同目录 QML 时会因路径不一致报
# "File name case mismatch"。改了插件代码后重新跑一遍本脚本即可。
set -e
cd "$(dirname "$0")/.."
REPO=$(pwd)
DEST=${XDG_CONFIG_HOME:-$HOME/.config}/dms/plugins/Daiban

mkdir -p "$DEST"
cp dms-plugin/*.qml dms-plugin/*.js dms-plugin/plugin.json "$DEST/"
echo "插件已装到 $DEST"

# 完整应用（Flutter 版）的启动脚本，Mod+Shift+D 用
mkdir -p "$HOME/.local/bin"
sed "s#@APP_BIN@#$REPO/app/build/linux/x64/release/bundle/vikunja_md#" scripts/daiban > "$HOME/.local/bin/daiban"
chmod +x "$HOME/.local/bin/daiban"
echo "已安装 ~/.local/bin/daiban"

# 重新加载插件要重启 DMS（dms ipc call plugins reload 会让同目录 QML 解析出错）
if command -v dms >/dev/null && [ "${NO_RESTART:-0}" != 1 ]; then
  dms restart >/dev/null 2>&1 && echo "已重启 DMS"
fi
cat <<MSG

还差两步（只需做一次）：
1. DMS 设置 → 插件 里启用「待办」，并把它加到顶栏（可选）
2. 在 niri 配置里加一行：include "$REPO/niri/daiban.kdl"
MSG
