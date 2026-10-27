#ifndef RUNNER_HIGH_REFRESH_VSYNC_H_
#define RUNNER_HIGH_REFRESH_VSYNC_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Flutter 的 Linux GTK 嵌入层没有接入显示器垂直同步，引擎退回到写死 60Hz 的定时器，
// 高刷屏上也只有 60 帧。这里在引擎启动前给它挂上 vsync 回调，按窗口所在显示器的
// 刷新率给出帧节拍。找不到内部结构时什么都不做，保持原来的 60 帧。
//
// 必须在 fl_view_new() 之后、窗口显示（引擎启动）之前调用。
// 环境变量 VMD_NO_VSYNC=1 可关闭，用于对比。
void install_high_refresh_vsync(FlView* view, GtkWidget* toplevel);

#endif  // RUNNER_HIGH_REFRESH_VSYNC_H_
