import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "Dates.js" as D

// 一行任务：勾选圈、标题、日期/项目/标签、备注第一行（做到哪了）、行尾 ▶/⏸。
// 勾掉时先打勾划线再收起高度；新加的从 0 高度展开。
Item {
    id: row

    required property var task
    required property var store
    property bool showProject: true
    // "start" = 行尾 ▶ 开始做；"pause" = ⏸ 暂停；"" = 没有
    property string action: ""
    // 分组列表里的位置：首行上角、末行下角用大圆角，中间用小圆角（DMS 分组列表样式）
    property bool first: true
    property bool last: true

    signal opened

    readonly property int offset: store.offset
    readonly property bool completing: !!store.completing[task.id]
    readonly property bool checked: completing || task.done

    // 收起/展开的进度：1 = 完整高度
    property real reveal: store.justAdded[task.id] ? 0 : 1
    Component.onCompleted: if (reveal === 0)
        revealIn.start()
    NumberAnimation on reveal {
        id: revealIn
        running: false
        to: 1
        duration: 320
        easing.type: Easing.OutCubic
    }
    onCompletingChanged: if (completing)
        collapse.start()
    SequentialAnimation {
        id: collapse
        PauseAnimation {
            duration: 260
        }
        NumberAnimation {
            target: row
            property: "reveal"
            to: 0
            duration: 300
            easing.type: Easing.InOutCubic
        }
    }

    implicitHeight: (content.implicitHeight + Theme.spacingM * 2) * reveal
    height: implicitHeight
    opacity: Math.min(1, reveal * 1.5)
    clip: true

    Rectangle {
        anchors.fill: parent
        readonly property real outer: Theme.groupedListOuterRadius
        readonly property real inner: Theme.groupedListInnerRadius
        topLeftRadius: row.first ? outer : inner
        topRightRadius: row.first ? outer : inner
        bottomLeftRadius: row.last ? outer : inner
        bottomRightRadius: row.last ? outer : inner
        color: hover.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.opened()
    }

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.spacingM
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingM

        // 勾选圈：边框颜色表示优先级
        Item {
            width: 24
            height: 24

            Rectangle {
                id: circle
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: 10
                readonly property color ring: row.task.priority >= 5 ? "#e03131" : row.task.priority >= 4 ? "#e8590c" : row.task.priority >= 3 ? "#f08c00" : Theme.outline
                color: row.checked ? Theme.primary : (row.task.priority >= 3 ? Theme.withAlpha(ring, 0.12) : "transparent")
                border.width: 2
                border.color: row.checked ? Theme.primary : ring
                scale: checkMouse.pressed ? 0.88 : 1
                Behavior on color {
                    ColorAnimation {
                        duration: 180
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 120
                    }
                }

                DIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: 14
                    color: Theme.onPrimary
                    scale: row.checked ? 1 : 0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }

            MouseArea {
                id: checkMouse
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: row.store.toggleDone(row.task)
            }
        }

        Column {
            width: content.width - 24 - Theme.spacingM - (trailing.visible ? trailing.width + Theme.spacingM : 0)
            spacing: 4

            StyledText {
                width: parent.width
                text: row.task.title
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                font.strikeout: row.checked
                color: row.checked ? Theme.surfaceVariantText : Theme.surfaceText
                Behavior on color {
                    ColorAnimation {
                        duration: 180
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS

                // 截止
                MetaText {
                    readonly property var d: row.store.due(row.task)
                    visible: !!d
                    icon: "event"
                    text: d ? D.friendly(d, row.offset) : ""
                    tint: d && !row.task.done && d < D.nowWall(row.offset) ? Theme.error : Theme.surfaceVariantText
                }

                // 正在做：长期 / 按计划
                MetaText {
                    readonly property var s: row.store.start(row.task)
                    readonly property var e: row.store.end(row.task)
                    readonly property var t0: D.today(row.offset)
                    readonly property int day: s ? D.daysBetween(s, t0) + 1 : 0
                    readonly property int total: s && e ? D.daysBetween(s, e) + 1 : 0
                    readonly property int over: e ? D.daysBetween(e, t0) : 0
                    visible: !!s && !row.store.due(row.task)
                    icon: over > 0 ? "timer_off" : (e ? "date_range" : "play_circle")
                    text: !s ? "" : over > 0 ? "超出计划 " + over + " 天" : !e ? (day <= 1 ? "今天开始" : "已做 " + day + " 天") : day >= 1 ? "第 " + day + "/" + total + " 天 · " + D.shortDate(s) + "–" + D.shortDate(e) : D.shortDate(s) + "–" + D.shortDate(e)
                    tint: over > 0 ? Theme.error : Theme.tertiary
                }

                // 项目
                Row {
                    readonly property var p: row.store.projects[row.task.project_id]
                    visible: row.showProject && !!p
                    spacing: 4
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.p ? row.store.color(parent.p.hex_color, Theme.primary) : Theme.primary
                    }
                    StyledText {
                        text: parent.p ? parent.p.title : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                // 标签
                Repeater {
                    model: row.task.labels || []
                    Rectangle {
                        required property var modelData
                        readonly property color c: row.store.color(modelData.hex_color, Theme.secondary)
                        width: labelText.implicitWidth + 12
                        height: labelText.implicitHeight + 2
                        radius: 4
                        color: Theme.withAlpha(c, 0.16)
                        StyledText {
                            id: labelText
                            anchors.centerIn: parent
                            text: modelData.title
                            font.pixelSize: Theme.fontSizeSmall
                            color: Qt.tint(parent.c, Theme.withAlpha(Theme.surfaceText, 0.25))
                        }
                    }
                }
            }

            // 备注第一行：切回来一眼看到"做到哪了"
            Row {
                readonly property string line: {
                    const plain = (row.task.description || "").replace(/<\/(p|div|li)>|<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ");
                    const first = plain.split("\n").map(s => s.trim()).find(s => s.length > 0);
                    return first || "";
                }
                visible: line.length > 0
                width: parent.width
                spacing: 3
                DIcon {
                    name: "subdirectory_arrow_right"
                    size: 14
                    color: Theme.surfaceVariantText
                }
                StyledText {
                    width: parent.width - 17
                    text: parent.line
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        DIconButton {
            id: trailing
            visible: row.action !== "" && !row.checked
            iconName: row.action === "start" ? "play_arrow" : "pause"
            iconColor: row.action === "start" ? Theme.tertiary : Theme.surfaceVariantText
            tooltipText: row.action === "start" ? "开始做" : "暂停（回到待办）"
            onClicked: row.store.setStarted(row.task, row.action === "start")
        }
    }

    component MetaText: Row {
        property string icon
        property string text
        property color tint: Theme.surfaceVariantText
        spacing: 3
        DIcon {
            name: parent.icon
            size: 14
            color: parent.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        StyledText {
            text: parent.text
            font.pixelSize: Theme.fontSizeSmall
            color: parent.tint
        }
    }
}
