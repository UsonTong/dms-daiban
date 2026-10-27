import QtQuick
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.DCommon.Widgets
import "Dates.js" as D

// Mod+D 弹出的"今天"面板：和 DMS 的 Mod+Space 一样是居中弹窗（压暗、点外面/Esc 关闭）。
// 上面一行输入框直接加任务；可以切到甘特图（弹窗随之变宽）。
DModal {
    id: root

    required property var store

    layerNamespace: "dms:daiban"
    // 放在 overlay 层：全屏窗口（远程桌面、视频）上面也能弹出来
    useOverlayLayer: true
    property bool gantt: false
    // DankDash 风格：外框中等圆角，内容分成一块块色块
    cornerRadius: Theme.cornerRadiusXL
    modalWidth: Math.min(gantt ? 1280 : 640, screenWidth - Theme.spacingXL * 2)
    modalHeight: Math.min(gantt ? 820 : 760, screenHeight - Theme.spacingXL * 2)
    onBackgroundClicked: close()
    onOpened: {
        store.refresh();
        Qt.callLater(() => {
            if (contentLoader.item)
                contentLoader.item.focusInput();
        });
    }

    // 底部提示条（带撤销）
    property string toastText: ""
    property var toastUndo: null
    Timer {
        id: toastTimer
        onTriggered: root.toastText = ""
    }
    Connections {
        target: root.store
        function onToast(message, undo) {
            root.toastText = message;
            root.toastUndo = undo;
            toastTimer.interval = undo ? 6000 : 4000;
            toastTimer.restart();
        }
    }

    // 打开某个任务的编辑页（内嵌在面板里）
    function editTask(task) {
        if (contentLoader.item)
            contentLoader.item.openEditor(task);
    }

    function openFullApp() {
        close();
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/daiban"]);
    }

    content: Component {
        FocusScope {
            id: page
            anchors.fill: parent
            focus: true

            function focusInput() {
                input.forceActiveFocus();
            }
            function openEditor(task) {
                editorSheet.edit(task);
            }

            // Esc：编辑页开着先回列表，否则关面板
            Keys.onEscapePressed: event => {
                if (editorSheet.shown)
                    editorSheet.close();
                else
                    root.close();
                event.accepted = true;
            }

            readonly property var g: root.store.groups
            readonly property var now: D.nowWall(root.store.offset)
            readonly property real gap: Theme.spacingM

            // ---------- 顶部标签（和 DankDash 同一个组件） ----------
            DNavigationBar {
                id: nav
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: Theme.spacingS
                anchors.leftMargin: page.gap
                anchors.rightMargin: page.gap
                evenlySpaced: true
                model: [
                    {
                        icon: "checklist",
                        text: "今天"
                    },
                    {
                        icon: "view_timeline",
                        text: "甘特图"
                    }
                ]
                currentIndex: root.gantt ? 1 : 0
                onActivated: index => root.gantt = index === 1
            }

            // ---------- 日期块 + 统计块 ----------
            Row {
                id: tiles
                anchors.top: nav.bottom
                anchors.topMargin: page.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: page.gap
                anchors.rightMargin: page.gap
                height: 96
                spacing: page.gap

                DCard {
                    id: dateCard
                    width: 168
                    height: parent.height
                    tone: "primary"
                    radius: Theme.cornerRadiusXL

                    DIconButton {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -Theme.spacingS
                        anchors.rightMargin: -Theme.spacingS
                        iconName: "open_in_new"
                        iconColor: dateCard.contentColor
                        tooltipText: "打开完整应用"
                        onClicked: root.openFullApp()
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingM
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.now.getUTCDate()
                            font.pixelSize: Theme.fontSizeDisplay + 8
                            font.weight: Font.Bold
                            color: dateCard.contentColor
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText {
                                text: D.weekday(page.now)
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Theme.fontWeightMedium
                                color: dateCard.contentColor
                            }
                            StyledText {
                                text: (page.now.getUTCMonth() + 1) + "月"
                                font.pixelSize: Theme.fontSizeSmall
                                color: dateCard.contentColor
                                opacity: 0.8
                            }
                        }
                    }
                }

                // 四个小色块（2×2），像控制中心的开关块：圆角方框里放图标
                Grid {
                    width: parent.width - 168 - page.gap
                    height: parent.height
                    columns: 2
                    spacing: Theme.groupedListGap * 2
                    visible: root.store.ready
                    readonly property real cellW: (width - spacing) / 2
                    readonly property real cellH: (height - spacing) / 2

                    Repeater {
                        model: [
                            {
                                label: "已逾期",
                                icon: "running_with_errors",
                                n: page.g.overdue.length,
                                tint: Theme.error
                            },
                            {
                                label: "今天",
                                icon: "today",
                                n: page.g.today.length,
                                tint: Theme.primary
                            },
                            {
                                label: "正在做",
                                icon: "play_circle",
                                n: page.g.doing.length,
                                tint: Theme.tertiary
                            },
                            {
                                label: "待办",
                                icon: "inbox",
                                n: page.g.todo.length,
                                tint: Theme.secondary
                            }
                        ]
                        Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.cellW
                            height: parent.cellH
                            radius: Theme.cornerRadiusL
                            color: Theme.surfaceContainerHigh

                            Rectangle {
                                id: iconBox
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.height - Theme.spacingS * 2
                                height: width
                                radius: Theme.cornerRadiusM
                                color: modelData.n > 0 ? Theme.withAlpha(modelData.tint, 0.22) : Theme.withAlpha(Theme.surfaceText, 0.06)
                                DIcon {
                                    anchors.centerIn: parent
                                    name: modelData.icon
                                    size: 18
                                    color: modelData.n > 0 ? modelData.tint : Theme.surfaceVariantText
                                }
                            }
                            Row {
                                anchors.left: iconBox.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.n
                                    font.pixelSize: Theme.fontSizeLarge + 2
                                    font.weight: Theme.fontWeightMedium
                                    color: modelData.n > 0 ? Theme.surfaceText : Theme.surfaceVariantText
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }

                DCard {
                    width: parent.width - 168 - page.gap
                    height: parent.height
                    radius: Theme.cornerRadiusXL
                    visible: !root.store.ready
                    StyledText {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "还没连上：先打开一次待办完整应用并登录"
                        color: Theme.error
                    }
                }
            }

            // ---------- 快速添加块 ----------
            DCard {
                id: addCard
                anchors.top: tiles.bottom
                anchors.topMargin: page.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: page.gap
                anchors.rightMargin: page.gap
                height: input.height + (preview.visible ? preview.height + 4 : 0) + pad * 2
                radius: Theme.cornerRadiusXL
                pad: Theme.spacingS
                visible: root.store.ready
                Behavior on height {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }

                DTextField {
                    id: input
                    width: parent.width
                    leftIconName: "add"
                    cornerRadius: height / 2
                    placeholderText: "添加任务"
                    readonly property var parsed: text.trim() ? D.parseQuickAdd(text, root.store.offset) : null
                    onAccepted: {
                        if (!text.trim())
                            return;
                        root.store.quickAdd(text, 0, null);
                        text = "";
                    }
                }

                // 识别出的日期/优先级/项目/标签，边打字边显示
                StyledText {
                    id: preview
                    anchors.top: input.bottom
                    anchors.topMargin: 4
                    leftPadding: Theme.spacingS
                    readonly property var p: input.parsed
                    visible: !!p && (p.due || p.priority || p.project || p.labels.length)
                    text: !p ? "" : [p.due ? "截止 " + D.friendly(p.due, root.store.offset) : "", p.priority ? "优先级 " + ["", "低", "中", "高", "紧急", "立即"][p.priority] : "", p.project ? "+" + p.project : "", p.labels.map(l => "*" + l).join(" ")].filter(x => x).join("   ·   ")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                }
            }

            // ---------- 列表 / 甘特图块 ----------
            DCard {
                anchors.top: root.store.ready ? addCard.bottom : tiles.bottom
                anchors.topMargin: page.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: page.gap
                radius: Theme.cornerRadiusXL
                pad: Theme.spacingXS

                TaskList {
                    anchors.fill: parent
                    store: root.store
                    opacity: root.gantt ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }
                    }
                    onOpenTask: task => page.openEditor(task)
                }

                Loader {
                    anchors.fill: parent
                    anchors.topMargin: Theme.spacingS
                    active: root.gantt
                    opacity: root.gantt ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }
                    }
                    sourceComponent: Gantt {
                        store: root.store
                        onOpenTask: task => page.openEditor(task)
                    }
                }
            }

            // ---------- 编辑页：从右侧滑入，盖住整个面板内容 ----------
            Editor {
                id: editorSheet
                anchors.fill: parent
                z: 5
                store: root.store
                onClosed: page.focusInput()
            }

            // ---------- 提示条（浮在底部） ----------
            Rectangle {
                id: toast
                z: 10
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: page.gap * 2
                width: Math.min(parent.width - page.gap * 4, toastRow.implicitWidth + Theme.spacingM * 2)
                height: 44
                radius: height / 2
                color: Theme.inverseSurface
                opacity: root.toastText ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Row {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingM
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.toastText
                        color: Theme.inverseOnSurface
                    }
                    DButton {
                        visible: !!root.toastUndo
                        anchors.verticalCenter: parent.verticalCenter
                        text: "撤销"
                        backgroundColor: "transparent"
                        textColor: Theme.inversePrimary
                        onClicked: {
                            const u = root.toastUndo;
                            root.toastText = "";
                            root.toastUndo = null;
                            if (u)
                                u();
                        }
                    }
                }
            }
        }
    }
}
