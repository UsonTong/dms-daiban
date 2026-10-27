#!/usr/bin/env python3
"""登录 Vikunja，给 DMS 插件生成凭据 ~/.config/vikunja-md/dms.json。

插件不保存密码：这里用账号密码登录一次，创建一个只有任务/标签/项目权限、
有效期一年的 API token，连同账号时区、默认项目写进配置文件（仅本人可读）。
用法：scripts/daiban-login.py [服务器地址]   默认 http://localhost:3456
"""
import datetime
import getpass
import json
import os
import sys
import urllib.error
import urllib.request
from zoneinfo import ZoneInfo

PERMISSIONS = {
    "tasks": ["read_all", "read_one", "create", "update", "delete"],
    "projects": ["read_all"],
    "labels": ["read_all", "create"],
    "tasks_labels": ["read_all", "create", "delete"],
}
# 与 Flutter 客户端（app/lib/state/dms_bridge.dart）保持一致；权限变了要加一
TOKEN_VERSION = 2


def call(server, method, path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(
        server + "/api/v1" + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        msg = json.loads(e.read() or b"{}").get("message", "")
        sys.exit(f"请求失败 {e.code}：{msg or e.reason}")
    except urllib.error.URLError as e:
        sys.exit(f"连不上 {server}：{e.reason}")


def main():
    server = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3456").rstrip("/")
    username = input(f"Vikunja 用户名（{server}）：").strip()
    password = getpass.getpass("密码：")

    jwt = call(server, "POST", "/login", {"username": username, "password": password})["token"]
    user = call(server, "GET", "/user", token=jwt)
    settings = user.get("settings") or {}
    tz = settings.get("timezone") or "Asia/Shanghai"
    offset = int(datetime.datetime.now(ZoneInfo(tz)).utcoffset().total_seconds() // 60)

    expires = datetime.datetime.now(datetime.UTC) + datetime.timedelta(days=365)
    tok = call(server, "PUT", "/tokens", {
        "title": "DMS 顶栏面板",
        "expires_at": expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "permissions": PERMISSIONS,
    }, token=jwt)

    cfg = {
        "server": server,
        "username": username,
        "token": tok["token"],
        "tokenId": tok["id"],
        "tokenExpires": int(expires.timestamp() * 1000),
        "tokenVersion": TOKEN_VERSION,
        "defaultProjectId": settings.get("default_project_id") or 0,
        "timezone": tz,
        "tzOffsetMinutes": offset,
        "planDays": 3,
    }
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    path = os.path.join(config_home, "vikunja-md", "dms.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # 先建空文件设成仅本人可读，再写入 token
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"已写入 {path}（时区 {tz}，token 一年后过期，到时重新运行本脚本）")


if __name__ == "__main__":
    main()
