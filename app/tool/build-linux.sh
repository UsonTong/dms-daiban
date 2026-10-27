#!/bin/sh
# 构建 Linux 发布版。
# --no-tree-shake-icons：Flutter 3.47 的图标字体裁剪步骤不把 Dart 代码列为输入，
# 新加的图标不会进字体（显示成别的图标）。桌面端直接带完整字体（约 1.6MB），一劳永逸
set -e
cd "$(dirname "$0")/.."
# 找 Flutter：PATH 里有就用；SDK 10-25 从 ~/development 挪到了 /opt/development
if ! command -v flutter >/dev/null 2>&1; then
  for d in /opt/development/flutter/bin "$HOME/development/flutter/bin"; do
    [ -x "$d/flutter" ] && PATH="$d:$PATH" && break
  done
fi
flutter build linux --release --no-tree-shake-icons "$@"
