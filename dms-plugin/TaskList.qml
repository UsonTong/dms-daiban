import QtQuick
import qs.Common
import qs.DCommon.Widgets

// "今天"视图：已逾期 → 今天 → 正在做 → 待办，底部可展开"今天已完成"（点勾恢复）
DFlickable {
    id: root

    required property var store
    signal openTask(var task)

    contentHeight: column.implicitHeight + Theme.spacingL
    clip: true

    readonly property var g: store.groups
    readonly property var sections: [
        {
            title: "已逾期",
            tint: Theme.error,
            tasks: g.overdue,
            action: ""
        },
        {
            title: "今天",
            tint: Theme.primary,
            tasks: g.today,
            action: ""
        },
        {
            title: "正在做",
            tint: Theme.tertiary,
            tasks: g.doing,
            action: "pause"
        },
        {
            title: "待办",
            tint: Theme.primary,
            tasks: g.todo,
            action: "start"
        }
    ]
    readonly property bool empty: sections.every(s => s.tasks.length === 0)
    property bool showDone: false

    Column {
        id: column
        width: root.width
        spacing: 0

        Repeater {
            model: root.sections

            Column {
                id: section
                required property var modelData
                width: column.width
                visible: modelData.tasks.length > 0

                Row {
                    spacing: Theme.spacingXS
                    leftPadding: Theme.spacingM
                    topPadding: Theme.spacingM
                    bottomPadding: Theme.spacingXS
                    StyledText {
                        text: section.modelData.title
                        color: section.modelData.tint
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: section.modelData.tasks.length
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Column {
                    width: column.width
                    spacing: Theme.groupedListGap
                Repeater {
                    id: sectionRows
                    model: section.modelData.tasks
                    TaskRow {
                        required property var modelData
                        required property int index
                        first: index === 0
                        last: index === sectionRows.count - 1
                        width: column.width
                        task: modelData
                        store: root.store
                        // 正在做里有截止的不给暂停（暂停会清排期，但截止还在）
                        action: section.modelData.action === "pause" && root.store.due(modelData) ? "" : section.modelData.action
                        onOpened: root.openTask(modelData)
                    }
                }
                }
            }
        }

        // 空状态
        Column {
            visible: root.empty && root.store.ready && !root.store.loading
            width: column.width
            topPadding: 64
            bottomPadding: 32
            spacing: Theme.spacingM
            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "wb_sunny"
                size: 56
                color: Theme.withAlpha(Theme.primary, 0.6)
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "今天没有待办，轻松一下"
                color: Theme.surfaceVariantText
            }
        }

        // 今天已完成：不小心勾掉的点勾恢复
        Item {
            visible: root.store.doneToday.length > 0
            width: column.width
            height: 44

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingXS
                anchors.topMargin: 4
                radius: Theme.groupedListOuterRadius
                color: doneMouse.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                DIcon {
                    name: "task_alt"
                    size: 18
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: "今天已完成 " + root.store.doneToday.length + " 件"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    visible: root.showDone
                    text: "点勾可恢复"
                    color: Theme.withAlpha(Theme.surfaceVariantText, 0.7)
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            DIcon {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                name: "expand_more"
                size: 20
                color: Theme.surfaceVariantText
                rotation: root.showDone ? 180 : 0
                Behavior on rotation {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
            MouseArea {
                id: doneMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showDone = !root.showDone
            }
        }

        Column {
            width: column.width
            spacing: Theme.groupedListGap
        Repeater {
            id: doneRows
            model: root.showDone ? root.store.doneToday : []
            TaskRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === doneRows.count - 1
                width: column.width
                task: modelData
                store: root.store
                onOpened: root.openTask(modelData)
            }
        }
        }
    }
}
