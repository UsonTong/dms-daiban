# 待办 Flutter 客户端

完整应用（今天 / 全部 / 甘特图 / 项目 / 设置），也是以后手机版的基础。日常的 Mod+D 面板在 `../dms-plugin`。
部署和整体说明见仓库根目录的 [README](../README.md)。

```bash
flutter run -d linux        # 开发
tool/build-linux.sh         # 发布构建（别直接 flutter build，原因见脚本注释）
flutter test                # 单元 + 组件测试
```

需要连 Vikunja 的测试：
`VIKUNJA_TEST=1 VIKUNJA_TEST_USER=… VIKUNJA_TEST_PASS=… flutter test test/api_refresh_test.dart`

- `lib/api/`：Vikunja 接口（JWT 10 分钟 + 一次性轮换的 refresh token，并发请求共用一次续期）
- `lib/state/`：数据与分组；`dms_bridge.dart` 维护 DMS 插件用的 `~/.config/vikunja-md/dms.json`
- `lib/ui/panel/`：旧的 layer-shell 面板（已由 DMS 插件取代，保留作参考）
- `linux/runner/`：`high_refresh_vsync.cc`（高刷新率）、`panel_mode.cc`（layer-shell 面板）
- `tool/seed_demo.py`：往测试账号灌演示数据；`tool/shot.sh`：Xvfb 上截图
