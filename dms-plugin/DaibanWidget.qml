import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// 顶栏按钮：今天还剩几件（逾期标红）；点击开关 Mod+D 面板。数字由常驻部分算好放在全局变量里
PluginComponent {
    id: root

    PluginGlobalVar {
        id: overdueVar
        varName: "overdue"
        defaultValue: 0
    }
    PluginGlobalVar {
        id: todayVar
        varName: "today"
        defaultValue: 0
    }

    readonly property int overdue: overdueVar.value
    readonly property int total: overdueVar.value + todayVar.value
    readonly property color accent: overdue > 0 ? Theme.error : Theme.primary

    pillClickAction: () => Quickshell.execDetached(["dms", "ipc", "call", "daiban", "toggle"])
    pillRightClickAction: () => Quickshell.execDetached(["dms", "ipc", "call", "daiban", "gantt"])

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DIcon {
                name: root.total === 0 ? "task_alt" : "checklist"
                size: root.iconSize
                color: root.total > 0 ? root.accent : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.total > 0
                text: root.overdue > 0 ? root.total + " · 逾期 " + root.overdue : root.total
                color: root.accent
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DIcon {
                name: root.total === 0 ? "task_alt" : "checklist"
                size: root.iconSize
                color: root.total > 0 ? root.accent : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                visible: root.total > 0
                text: root.total
                color: root.accent
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
