#include "high_refresh_vsync.h"

#include <dlfcn.h>

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <atomic>
#include <vector>

// 与引擎同一发行版的 embedder.h 副本。该头文件是只追加的稳定 ABI，
// 这里用到的字段偏移不会变。
#include "flutter_embedder.h"

namespace {

FlutterEngineProcTable* g_api = nullptr;
FlutterEngineInitializeFnPtr g_original_initialize = nullptr;
FLUTTER_API_SYMBOL(FlutterEngine)* g_engine_slot = nullptr;
GtkWidget* g_toplevel = nullptr;

constexpr uint64_t kDefaultIntervalUs = 1000000 / 60;

bool in_flutter_library(void* fn) {
  Dl_info info;
  return fn != nullptr && dladdr(fn, &info) != 0 && info.dli_fname != nullptr &&
         strstr(info.dli_fname, "libflutter_linux_gtk") != nullptr;
}

// 刷新间隔只能在主线程查（GDK），每秒更新一次缓存，供引擎线程读
std::atomic<uint64_t> g_interval_ns{kDefaultIntervalUs * 1000};
// 两帧开始时间的最小间隔（占刷新间隔的比例），排查节拍用 VMD_VSYNC_SPACING 覆盖
double g_spacing = 0.9;
// 上一帧的开始时间，只在引擎的 UI 线程读写
uint64_t g_last_start = 0;

// VMD_FPS=1 时每秒打印计数，排查用：引擎要帧次数、GTK 实际提交到屏幕的次数
std::atomic<int> g_n_vsync{0};
int g_n_paint = 0;
gint64 g_paint_start = 0, g_paint_total_us = 0, g_paint_max_us = 0;

// ---- GTK3 帧时钟提速 ----
// Flutter 画完一帧后交给 GTK 在主线程贴到窗口上，由 GTK 帧时钟决定节拍。
// GTK3 用每帧记录里的 refresh_interval 算"下一帧最早什么时候"，拿不到合成器的数据时
// 默认 16667us，于是实际上屏被锁在 60Hz（引擎多画的帧全丢）。这里每帧画完把真实刷新间隔
// 写进记录。GdkFrameTimings 是私有结构，但 GTK3 已冻结不再改；写之前用公开 getter
// 逐字段核对偏移，对不上就什么都不做。
constexpr size_t kTimingsFrameCounter = 8, kTimingsFrameTime = 24,
                 kTimingsPresentation = 48, kTimingsRefresh = 56;
bool g_timings_ok = false, g_timings_checked = false;
bool g_clock_fix = true;  // VMD_NO_CLOCKFIX=1 关掉修正（只计数），对比用

gint64& timings_field(GdkFrameTimings* t, size_t off) {
  return *reinterpret_cast<gint64*>(reinterpret_cast<uint8_t*>(t) + off);
}

bool timings_layout_matches(GdkFrameTimings* t) {
  return timings_field(t, kTimingsFrameCounter) == gdk_frame_timings_get_frame_counter(t) &&
         timings_field(t, kTimingsFrameTime) == gdk_frame_timings_get_frame_time(t) &&
         timings_field(t, kTimingsPresentation) == gdk_frame_timings_get_presentation_time(t) &&
         timings_field(t, kTimingsRefresh) == gdk_frame_timings_get_refresh_interval(t);
}

void on_paint(GdkFrameClock*, gpointer) { g_paint_start = g_get_monotonic_time(); }

void on_after_paint(GdkFrameClock* clock, gpointer) {
  g_n_paint++;
  if (g_paint_start != 0) {
    const gint64 d = g_get_monotonic_time() - g_paint_start;
    g_paint_total_us += d;
    if (d > g_paint_max_us) g_paint_max_us = d;
  }
  GdkFrameTimings* t =
      gdk_frame_clock_get_timings(clock, gdk_frame_clock_get_frame_counter(clock));
  if (t == nullptr) return;
  // 帧时间不为 0 才能区分字段，核对一次即可
  if (!g_timings_checked && gdk_frame_timings_get_frame_time(t) != 0) {
    g_timings_checked = true;
    g_timings_ok = timings_layout_matches(t);
    if (!g_timings_ok) g_warning("high_refresh_vsync: GdkFrameTimings 布局不符，保持 GTK 默认节拍");
  }
  if (!g_timings_ok || !g_clock_fix) return;
  const gint64 us = static_cast<gint64>(g_interval_ns / 1000);
  if (timings_field(t, kTimingsRefresh) == 0 || timings_field(t, kTimingsRefresh) > us) {
    timings_field(t, kTimingsRefresh) = us;
  }
}

void hook_frame_clock(GtkWidget* toplevel, gpointer) {
  GdkFrameClock* clock = gtk_widget_get_frame_clock(toplevel);
  if (clock != nullptr) {
    g_signal_connect(clock, "paint", G_CALLBACK(on_paint), nullptr);
    g_signal_connect(clock, "after-paint", G_CALLBACK(on_after_paint), nullptr);
  }
}

// 窗口所在显示器的刷新间隔（纳秒）。注意不能用 GTK 帧时钟：Flutter 用自己的 GL
// 表面出图，GTK 窗口不提交，帧时钟收不到合成器回调，会退回默认的 60Hz 定时器
uint64_t refresh_interval_ns() {
  int mhz = 0;
  GdkWindow* win = g_toplevel ? gtk_widget_get_window(g_toplevel) : nullptr;
  GdkDisplay* display = gdk_display_get_default();
  if (display != nullptr) {
    GdkMonitor* monitor = win ? gdk_display_get_monitor_at_window(display, win)
                              : gdk_display_get_primary_monitor(display);
    if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
      monitor = gdk_display_get_monitor(display, 0);
    }
    if (monitor != nullptr) mhz = gdk_monitor_get_refresh_rate(monitor);
  }
  if (mhz < 30000 || mhz > 500000) return kDefaultIntervalUs * 1000;
  return static_cast<uint64_t>(1e12 / mhz);
}

gboolean update_interval(gpointer) {
  g_interval_ns = refresh_interval_ns();
  return G_SOURCE_CONTINUE;
}

gboolean debug_dump(gpointer) {
  g_printerr("[vsync] callbacks=%d 上屏=%d 贴图平均=%.1fms 最慢=%.1fms interval=%.2fms 帧时钟修正=%s\n",
             g_n_vsync.exchange(0), g_n_paint,
             g_n_paint ? g_paint_total_us / 1000.0 / g_n_paint : 0.0,
             g_paint_max_us / 1000.0, g_interval_ns / 1e6, g_timings_ok ? "是" : "否");
  g_n_paint = 0;
  g_paint_total_us = g_paint_max_us = 0;
  return G_SOURCE_CONTINUE;
}

// 引擎 UI 线程调用，直接把 baton 还回去。
// FlutterEngineOnVsync 内部只是往 UI 任务队列投递任务，线程安全；不能绕道 GTK 主线程：
// 主线程在等新尺寸的帧时会阻塞（面板模式下很常见），vsync 卡在主线程队列里就互相等死。
// 不按固定网格对齐：上一帧交换缓冲区时已被合成器按真实 vblank 卡住，请求一到就开下一帧，
// 节拍自然与屏幕同相；只限制最小间隔，防止窗口不可见（交换不阻塞）时空转。
void vsync_callback(void*, intptr_t baton) {
  g_n_vsync++;
  if (g_engine_slot == nullptr || *g_engine_slot == nullptr) return;
  const uint64_t interval = g_interval_ns;
  const uint64_t now = g_api->GetCurrentTime();
  const uint64_t start =
      std::max(now, g_last_start + static_cast<uint64_t>(interval * g_spacing));
  g_last_start = start;
  g_api->OnVsync(*g_engine_slot, baton, start, start + interval);
}

FlutterEngineResult patched_initialize(size_t version,
                                       const FlutterRendererConfig* config,
                                       const FlutterProjectArgs* args,
                                       void* user_data,
                                       FLUTTER_API_SYMBOL(FlutterEngine) *
                                           engine_out) {
  // 按引擎给的 struct_size 拷贝，避免新版本追加的字段被截断
  std::vector<uint8_t> buffer(
      std::max(args->struct_size, sizeof(FlutterProjectArgs)), 0);
  memcpy(buffer.data(), args, args->struct_size);
  auto* patched = reinterpret_cast<FlutterProjectArgs*>(buffer.data());
  if (args->struct_size >= offsetof(FlutterProjectArgs, vsync_callback) +
                               sizeof(VsyncCallback)) {
    patched->vsync_callback = vsync_callback;
    g_engine_slot = engine_out;
  }
  return g_original_initialize(version, config, patched, user_data, engine_out);
}

}  // namespace

void install_high_refresh_vsync(FlView* view, GtkWidget* toplevel) {
  if (g_strcmp0(g_getenv("VMD_NO_VSYNC"), "1") == 0) return;

  FlEngine* engine = fl_view_get_engine(view);
  GTypeQuery query;
  g_type_query(G_OBJECT_TYPE(engine), &query);
  auto* base = reinterpret_cast<uint8_t*>(engine);
  constexpr size_t kNeeded = offsetof(FlutterEngineProcTable, GetCurrentTime) +
                             sizeof(FlutterEngineGetCurrentTimeFnPtr);

  // FlEngine 里内嵌了一张函数表，首字段是表的大小；逐个对齐位置找，
  // 并确认几个函数指针确实落在 Flutter 引擎库里
  for (size_t offset = sizeof(GObject); offset + kNeeded <= query.instance_size;
       offset += alignof(FlutterEngineProcTable)) {
    auto* table = reinterpret_cast<FlutterEngineProcTable*>(base + offset);
    if (table->struct_size < kNeeded ||
        table->struct_size > sizeof(FlutterEngineProcTable) + 1024) {
      continue;
    }
    if (!in_flutter_library(reinterpret_cast<void*>(table->Initialize)) ||
        !in_flutter_library(reinterpret_cast<void*>(table->RunInitialized)) ||
        !in_flutter_library(reinterpret_cast<void*>(table->OnVsync)) ||
        !in_flutter_library(reinterpret_cast<void*>(table->GetCurrentTime))) {
      continue;
    }
    g_api = table;
    g_original_initialize = table->Initialize;
    table->Initialize = patched_initialize;
    g_toplevel = toplevel;
    if (const gchar* sp = g_getenv("VMD_VSYNC_SPACING")) {
      g_spacing = g_ascii_strtod(sp, nullptr);
    }
    // 窗口挂到显示器上后才能查到真实刷新率；之后每秒刷新一次（拖到别的屏也能跟上）
    g_idle_add([](gpointer) -> gboolean {
      update_interval(nullptr);
      return G_SOURCE_REMOVE;
    }, nullptr);
    g_timeout_add_seconds(1, update_interval, nullptr);
    g_clock_fix = g_strcmp0(g_getenv("VMD_NO_CLOCKFIX"), "1") != 0;
    if (gtk_widget_get_realized(toplevel)) {
      hook_frame_clock(toplevel, nullptr);
    } else {
      g_signal_connect(toplevel, "realize", G_CALLBACK(hook_frame_clock), nullptr);
    }
    if (g_strcmp0(g_getenv("VMD_FPS"), "1") == 0) {
      g_printerr("[vsync] 已挂上，函数表偏移 %zu，显示后端 %s\n", offset, G_OBJECT_TYPE_NAME(gdk_display_get_default()));
      g_timeout_add_seconds(1, debug_dump, nullptr);
    }
    return;
  }
  g_warning("high_refresh_vsync: 没找到引擎函数表，保持 60Hz");
}
