#ifndef RUNNER_PANEL_MODE_H_
#define RUNNER_PANEL_MODE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// 面板模式（命令行带 --panel）：Mod+D 弹出的"今天"面板。详见 panel_mode.cc 开头的说明。
// 窗口是铺满当前显示器的 layer-shell 覆盖层，背景透明，卡片由 Flutter 画在右上角。
// 隐藏时输入区域为空、不抢键盘，鼠标直接穿透；显示时独占键盘，点卡片外面由 Dart 负责收起。
// Dart 通过 "vikunja_md/panel" 通道调 setInteractive(bool)；收到 SIGUSR1 时通知 Dart "toggle"。
// 进程号写在 $XDG_RUNTIME_DIR/vikunja-md-panel.pid，给快捷键脚本发信号用。

gboolean panel_mode_requested(char** args);

// 窗口 realize 之前调用
void panel_mode_setup_window(GtkWindow* window);

// FlView 创建之后调用
void panel_mode_attach(FlView* view, GtkWindow* window);

#endif  // RUNNER_PANEL_MODE_H_
