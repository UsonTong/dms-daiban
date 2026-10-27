import QtQuick
import Quickshell.Io
import qs.Services
import qs.Modules.Plugins

// 常驻部分：数据、Mod+D 面板、编辑器，以及快捷键命令
//   dms ipc call daiban toggle   开关面板（niri 里绑 Mod+D）
PluginComponent {
    id: root

    Store {
        id: store
        // 顶栏按钮读这两个数
        readonly property int overdueCount: groups.overdue.length
        readonly property int todayCount: groups.today.length
        onOverdueCountChanged: PluginService.setGlobalVar("daiban", "overdue", overdueCount)
        onTodayCountChanged: PluginService.setGlobalVar("daiban", "today", todayCount)
        onReadyChanged: PluginService.setGlobalVar("daiban", "ready", ready)
    }

    PanelModal {
        id: panel
        store: store
    }

    IpcHandler {
        target: "daiban"

        function toggle(): string {
            panel.toggle();
            return "ok";
        }
        function open(): string {
            panel.open();
            return "ok";
        }
        function close(): string {
            panel.close();
            return "ok";
        }
        // 直接打开某个任务的编辑器（调试用，以后 Hermes 也能用）
        function edit(id: string): string {
            const t = store.tasks.concat(store.doneToday).find(x => String(x.id) === id);
            if (!t)
                return "not found";
            panel.open();
            Qt.callLater(() => panel.editTask(t));
            return "ok";
        }
        function gantt(): string {
            panel.gantt = true;
            panel.open();
            return "ok";
        }
    }
}
