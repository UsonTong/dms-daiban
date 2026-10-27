# DMS 插件测试

- `node dates.test.mjs ~/.config/dms/plugins/Daiban/Dates.js`：日期/快速添加解析（Node）
- Qt 引擎里跑同一批用例（Qt 的 JS 引擎和 Node 有差异，比如不支持后行断言）：
  `cp ~/.config/dms/plugins/Daiban/Dates.js qt/ && timeout 10 qs -p qt/shell.qml 2>&1 | grep '\[T\]'`
