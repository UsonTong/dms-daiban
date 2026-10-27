#include "panel_mode.h"

#include <cstdlib>

#include <glib-unix.h>
#include <gtk-layer-shell/gtk-layer-shell.h>
#include <signal.h>
#include <unistd.h>

// 面板由两层 layer-shell 表面组成（都在 overlay 层，背景层先映射，所以在下面）：
// - 背景层：铺满屏幕的纯 GTK 窗口，只画半透明黑色、接住"点外面"——不经过 Flutter，开销很小；
// - 卡片层：只有卡片那么大、合成器居中放置，由 Flutter 画。
// 之前整屏一个 Flutter 透明表面时，GTK3 每帧都要处理整屏像素，弹出动画只有 50~60 帧；
// 缩到卡片大小后 125 帧以上。

namespace {

GtkWindow* g_window = nullptr;  // 卡片层（Flutter）
GtkWindow* g_scrim = nullptr;   // 背景层
FlView* g_view = nullptr;
FlMethodChannel* g_channel = nullptr;
gboolean g_interactive = FALSE;

// 背景层压暗程度，与 DMS 自带弹窗一致：黑色 50%，进场 240ms、退场 160ms
constexpr double kScrimAlpha = 0.5;
double g_scrim_alpha = 0;
double g_scrim_from = 0, g_scrim_to = 0;
gint64 g_fade_start = 0, g_fade_us = 0;
guint g_fade_source = 0;

void set_input(GtkWindow* window, gboolean on) {
  if (window == nullptr) return;
  // 空区域 = 鼠标穿透；NULL = 整个窗口都接收输入
  if (on) {
    gtk_widget_input_shape_combine_region(GTK_WIDGET(window), nullptr);
  } else {
    cairo_region_t* empty = cairo_region_create();
    gtk_widget_input_shape_combine_region(GTK_WIDGET(window), empty);
    cairo_region_destroy(empty);
  }
}

void apply_input_shape() {
  set_input(g_window, g_interactive);
  set_input(g_scrim, g_interactive);
}

gboolean fade_step(gpointer) {
  const double t = g_fade_us <= 0
      ? 1.0
      : CLAMP((g_get_monotonic_time() - g_fade_start) / (double)g_fade_us, 0.0, 1.0);
  // 进场减速、退场加速，和卡片的曲线对上
  const double eased = g_scrim_to > g_scrim_from ? 1 - (1 - t) * (1 - t) * (1 - t)
                                                  : t * t * t;
  g_scrim_alpha = g_scrim_from + (g_scrim_to - g_scrim_from) * eased;
  gtk_widget_queue_draw(GTK_WIDGET(g_scrim));
  if (t >= 1.0) {
    g_fade_source = 0;
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

void fade_scrim(double to, gint64 duration_us) {
  if (g_scrim == nullptr) return;
  g_scrim_from = g_scrim_alpha;
  g_scrim_to = to;
  g_fade_start = g_get_monotonic_time();
  g_fade_us = duration_us;
  // 背景层每重画一次都是整屏像素，代价高；只分几步淡入，帧率留给卡片动画
  const gchar* step = g_getenv("VMD_SCRIM_STEP_MS");
  if (g_fade_source == 0) {
    g_fade_source = g_timeout_add(step ? atoi(step) : 60, fade_step, nullptr);
  }
}

gboolean on_scrim_draw(GtkWidget*, cairo_t* cr, gpointer) {
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0, 0, 0, g_scrim_alpha);
  cairo_paint(cr);
  return TRUE;
}

// 点到背景层 = 点了卡片外面，让 Dart 收起
gboolean on_scrim_press(GtkWidget*, GdkEventButton*, gpointer) {
  if (g_channel != nullptr && g_interactive) {
    fl_method_channel_invoke_method(g_channel, "dismiss", nullptr, nullptr,
                                    nullptr, nullptr);
  }
  return TRUE;
}

void set_interactive(gboolean on) {
  if (g_window == nullptr) return;
  g_interactive = on;
  apply_input_shape();
  gtk_layer_set_keyboard_mode(g_window, on ? GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE
                                           : GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  // VMD_SCRIM_FADE_MS 覆盖淡入时长（0 = 直接出现），排查用
  const gchar* fade = g_getenv("VMD_SCRIM_FADE_MS");
  const gint64 in_us = fade ? atoi(fade) * 1000 : 240000;
  fade_scrim(on ? kScrimAlpha : 0, on ? in_us : in_us * 2 / 3);
  if (on && g_view != nullptr) gtk_widget_grab_focus(GTK_WIDGET(g_view));
}

// 卡片层尺寸：按显示器大小夹住，返回实际用的尺寸
FlValue* set_card_size(int w, int h) {
  GdkDisplay* display = gdk_display_get_default();
  GdkWindow* gw = gtk_widget_get_window(GTK_WIDGET(g_window));
  GdkMonitor* monitor = gw ? gdk_display_get_monitor_at_window(display, gw)
                           : gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    GdkRectangle geo;
    gdk_monitor_get_geometry(monitor, &geo);
    w = MIN(w, geo.width - 32);
    h = MIN(h, geo.height - 32);
  }
  gtk_widget_set_size_request(GTK_WIDGET(g_window), w, h);
  gtk_window_resize(g_window, w, h);
  FlValue* result = fl_value_new_list();
  fl_value_append_take(result, fl_value_new_int(w));
  fl_value_append_take(result, fl_value_new_int(h));
  return result;
}

void on_method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(method, "setInteractive") == 0) {
    gboolean on = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                  fl_value_get_bool(args);
    set_interactive(on);
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "setCardSize") == 0 && args != nullptr &&
      fl_value_get_type(args) == FL_VALUE_TYPE_LIST && fl_value_get_length(args) == 2) {
    g_autoptr(FlValue) size =
        set_card_size(fl_value_get_int(fl_value_get_list_value(args, 0)),
                      fl_value_get_int(fl_value_get_list_value(args, 1)));
    fl_method_call_respond_success(call, size, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

gboolean on_sigusr1(gpointer) {
  if (g_channel != nullptr) {
    fl_method_channel_invoke_method(g_channel, "toggle", nullptr, nullptr,
                                    nullptr, nullptr);
  }
  return G_SOURCE_CONTINUE;
}

void on_realize(GtkWidget*, gpointer) { apply_input_shape(); }

// 只在 realize 里设空区域不够：首次按 layer-shell 尺寸分配后发给合成器的是 nil（整屏），
// 面板一启动就吃掉所有点击、顶栏点不动（WAYLAND_DEBUG 实测），所以每次分配尺寸后重新设一遍
void on_size_allocate(GtkWidget*, GdkRectangle*, gpointer) { apply_input_shape(); }

void make_transparent(GtkWindow* window) {
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_widget_get_screen(GTK_WIDGET(window)));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  g_signal_connect(window, "realize", G_CALLBACK(on_realize), nullptr);
  g_signal_connect_after(window, "size-allocate", G_CALLBACK(on_size_allocate), nullptr);
}

void create_scrim() {
  g_scrim = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_layer_init_for_window(g_scrim);
  gtk_layer_set_namespace(g_scrim, "vikunja-md-panel-scrim");
  gtk_layer_set_layer(g_scrim, GTK_LAYER_SHELL_LAYER_OVERLAY);
  static const GtkLayerShellEdge kEdges[] = {
      GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM,
      GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT};
  for (GtkLayerShellEdge edge : kEdges) gtk_layer_set_anchor(g_scrim, edge, TRUE);
  // 盖住顶栏等其他层
  gtk_layer_set_exclusive_zone(g_scrim, -1);
  gtk_layer_set_keyboard_mode(g_scrim, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  make_transparent(g_scrim);
  gtk_widget_add_events(GTK_WIDGET(g_scrim), GDK_BUTTON_PRESS_MASK);
  g_signal_connect(g_scrim, "draw", G_CALLBACK(on_scrim_draw), nullptr);
  g_signal_connect(g_scrim, "button-press-event", G_CALLBACK(on_scrim_press), nullptr);
  // 先于卡片层映射，叠放时就在卡片下面
  gtk_widget_show(GTK_WIDGET(g_scrim));
}

void write_pid_file() {
  const gchar* dir = g_get_user_runtime_dir();
  g_autofree gchar* path = g_build_filename(dir, "vikunja-md-panel.pid", nullptr);
  g_autofree gchar* pid = g_strdup_printf("%d\n", getpid());
  g_file_set_contents(path, pid, -1, nullptr);
}

}  // namespace

gboolean panel_mode_requested(char** args) {
  for (char** a = args; a != nullptr && *a != nullptr; a++) {
    if (g_strcmp0(*a, "--panel") == 0) return TRUE;
  }
  return FALSE;
}

void panel_mode_setup_window(GtkWindow* window) {
  create_scrim();

  g_window = window;
  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "vikunja-md-panel");
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  // 不贴任何边：合成器把它放在屏幕正中
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  // 初始为列表模式的卡片大小（含阴影边距），Dart 切到甘特图时再调
  gtk_window_set_default_size(window, 608, 728);
  gtk_widget_set_size_request(GTK_WIDGET(window), 608, 728);
  make_transparent(window);
}

void panel_mode_attach(FlView* view, GtkWindow* window) {
  g_view = view;
  GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                    "vikunja_md/panel", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method_call, nullptr, nullptr);

  g_unix_signal_add(SIGUSR1, on_sigusr1, nullptr);
  write_pid_file();
}
