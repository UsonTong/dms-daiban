#!/bin/sh
# 用 Podman Quadlet 部署 Vikunja（rootless，开机自启）。
# 用法：scripts/install-server.sh [数据目录]，默认 ~/.local/share/vikunja
set -e
cd "$(dirname "$0")/.."
DATA_DIR=${1:-$HOME/.local/share/vikunja}
UNIT_DIR=$HOME/.config/containers/systemd

command -v podman >/dev/null || { echo "需要先安装 podman"; exit 1; }
mkdir -p "$DATA_DIR/db" "$DATA_DIR/files" "$UNIT_DIR"

if [ ! -f "$DATA_DIR/vikunja.env" ]; then
  sed "s/^VIKUNJA_SERVICE_SECRET=.*/VIKUNJA_SERVICE_SECRET=$(openssl rand -hex 32)/" \
    server/vikunja.env.example > "$DATA_DIR/vikunja.env"
  chmod 600 "$DATA_DIR/vikunja.env"
  echo "已生成 $DATA_DIR/vikunja.env（含随机密钥）"
else
  echo "保留已有的 $DATA_DIR/vikunja.env"
fi

sed "s#@DATA_DIR@#$DATA_DIR#g" server/vikunja.container.in > "$UNIT_DIR/vikunja.container"
systemctl --user daemon-reload
systemctl --user restart vikunja.service
echo "Vikunja 已启动：http://localhost:3456 （第一次打开先注册账号）"
