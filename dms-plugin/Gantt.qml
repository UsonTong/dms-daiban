import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "Dates.js" as D

// 甘特图：左侧任务表 + 右侧时间轴（横向滚动，表头跟随）。
// 拖横条中间平移、拖两端改起止；长期在做的只能改开始；只有截止的画成一天的描边块。
Item {
    id: root

    required property var store
    signal openTask(var task)

    property real dayW: 36
    property var labelFilter: ({})
    readonly property bool filtering: Object.keys(labelFilter).length > 0
    readonly property int offset: store.offset
    readonly property var t0: D.today(offset)
    readonly property real rowH: 40
    readonly property real leftW: 260
    readonly property real headerH: 46

    // 有日期的任务 → 行
    readonly property var rows: {
        const out = [];
        for (const t of store.tasks) {
            const s = store.start(t), e = store.end(t), d = store.due(t);
            const dim = filtering && !(t.labels || []).some(l => labelFilter[l.id]);
            const color = store.taskColor(t, Theme.primary);
            if (s && !e && !d)
                out.push({ task: t, start: D.dayOf(s), end: s > t0 ? D.dayOf(s) : t0, open: true, dueOnly: false, dim: dim, color: color });
            else if (s || e)
                out.push({ task: t, start: D.dayOf(s || e), end: D.dayOf(e || s), open: false, dueOnly: false, dim: dim, color: color });
            else if (d)
                out.push({ task: t, start: D.dayOf(d), end: D.dayOf(d), open: false, dueOnly: true, dim: dim, color: color });
        }
        out.sort((a, b) => a.start - b.start || a.end - b.end);
        return out;
    }

    // 时间轴范围：今天前两周到两个月后，覆盖所有任务，从周一开始、前后多留一周
    readonly property var rangeStart: {
        let first = D.addDays(t0, -14);
        for (const r of rows)
            if (r.start < first)
                first = r.start;
        const dow = first.getUTCDay() || 7;
        return D.addDays(first, -(dow - 1) - 7);
    }
    readonly property int dayCount: {
        let last = D.addDays(t0, 60);
        for (const r of rows)
            if (r.end > last)
                last = r.end;
        return D.daysBetween(rangeStart, last) + 21;
    }
    readonly property real timelineW: dayCount * dayW

    function xOf(day) {
        return D.daysBetween(rangeStart, day) * dayW;
    }
    function scrollToToday() {
        timeline.contentX = Math.max(0, Math.min(timeline.contentWidth - timeline.width, xOf(t0) - 3 * dayW));
    }
    // 起点前移/后移时保持看的是同一天
    onRangeStartChanged: Qt.callLater(scrollToToday)
    onDayWChanged: Qt.callLater(scrollToToday)
    Component.onCompleted: Qt.callLater(scrollToToday)

    // ---------- 工具栏：标签筛选 + 今天 + 日/周/月 ----------
    Row {
        id: toolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        height: 40
        spacing: Theme.spacingS

        Flickable {
            width: toolbar.width - zoom.width - todayBtn.width - Theme.spacingS * 2
            height: parent.height
            contentWidth: chips.width
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            Row {
                id: chips
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                Repeater {
                    model: root.store.labels
                    Rectangle {
                        required property var modelData
                        readonly property bool on: !!root.labelFilter[modelData.id]
                        readonly property color c: root.store.color(modelData.hex_color, Theme.secondary)
                        width: chipText.implicitWidth + 20
                        height: 28
                        radius: 8
                        color: on ? c : Theme.withAlpha(c, 0.1)
                        border.width: 1
                        border.color: Theme.withAlpha(c, 0.6)
                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: modelData.title
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.on ? (Qt.colorEqual(parent.c, "white") ? "black" : "white") : Theme.surfaceText
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const f = Object.assign({}, root.labelFilter);
                                if (f[modelData.id])
                                    delete f[modelData.id];
                                else
                                    f[modelData.id] = true;
                                root.labelFilter = f;
                            }
                        }
                    }
                }
            }
        }

        DIconButton {
            id: todayBtn
            anchors.verticalCenter: parent.verticalCenter
            iconName: "today"
            tooltipText: "回到今天"
            onClicked: root.scrollToToday()
        }

        DButtonGroup {
            id: zoom
            anchors.verticalCenter: parent.verticalCenter
            size: "small"
            model: ["日", "周", "月"]
            currentIndex: root.dayW >= 30 ? 0 : root.dayW >= 15 ? 1 : 2
            selectionMode: "single"
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.dayW = [36, 18, 8][index];
            }
        }
    }

    // ---------- 表头 ----------
    Rectangle {
        id: header
        anchors.top: toolbar.bottom
        anchors.topMargin: Theme.spacingXS
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerH
        color: "transparent"

        Row {
            width: root.leftW
            height: parent.height
            leftPadding: Theme.spacingM
            StyledText {
                width: root.leftW - 110
                anchors.verticalCenter: parent.verticalCenter
                text: "任务"
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
            StyledText {
                width: 56
                anchors.verticalCenter: parent.verticalCenter
                text: "开始"
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
            StyledText {
                width: 40
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: "天数"
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
        }

        Item {
            x: root.leftW
            width: parent.width - root.leftW
            height: parent.height
            clip: true

            Item {
                x: -timeline.contentX
                width: root.timelineW
                height: parent.height

                Repeater {
                    model: root.dayCount
                    Item {
                        required property int index
                        readonly property var d: D.addDays(root.rangeStart, index)
                        readonly property bool isToday: D.daysBetween(root.t0, d) === 0
                        x: index * root.dayW
                        width: root.dayW
                        height: parent.height

                        Rectangle {
                            visible: (parent.d.getUTCDay() === 0 || parent.d.getUTCDay() === 6) && root.dayW >= 8
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height - 20
                            color: Theme.withAlpha(Theme.surfaceText, 0.05)
                        }
                        // 月份标签
                        StyledText {
                            visible: parent.d.getUTCDate() === 1 || parent.index === 0
                            x: 6
                            y: 2
                            text: parent.d.getUTCFullYear() + "年" + (parent.d.getUTCMonth() + 1) + "月"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                        Rectangle {
                            visible: parent.isToday
                            width: 22
                            height: 22
                            radius: 11
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            color: Theme.primary
                        }
                        StyledText {
                            visible: root.dayW >= 18 || parent.d.getUTCDay() === 1 || parent.isToday
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            text: parent.d.getUTCDate()
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.isToday ? Theme.onPrimary : Theme.surfaceVariantText
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.outlineVariant
        }
    }

    // ---------- 主体：竖向一起滚，右侧单独横向滚 ----------
    DFlickable {
        id: body
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        contentHeight: Math.max(height, root.rows.length * root.rowH)
        clip: true

        // 左侧表格
        Column {
            width: root.leftW
            Repeater {
                model: root.rows
                Item {
                    required property var modelData
                    width: root.leftW
                    height: root.rowH
                    opacity: modelData.dim ? 0.4 : 1
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: Theme.spacingM
                        StyledText {
                            width: root.leftW - 110
                            text: modelData.task.title
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            maximumLineCount: 1
                            color: Theme.surfaceText
                        }
                        StyledText {
                            width: 56
                            text: D.shortDate(modelData.start)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            text: D.daysBetween(modelData.start, modelData.end) + 1
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outlineVariant, 0.5)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openTask(modelData.task)
                    }
                }
            }
        }

        Rectangle {
            x: root.leftW
            width: 1
            height: body.contentHeight
            color: Theme.outlineVariant
        }

        Flickable {
            id: timeline
            x: root.leftW + 1
            width: body.width - root.leftW - 1
            height: body.contentHeight
            contentWidth: root.timelineW
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // 周末、网格
            Repeater {
                model: root.dayCount
                Rectangle {
                    required property int index
                    readonly property var d: D.addDays(root.rangeStart, index)
                    readonly property bool weekend: d.getUTCDay() === 0 || d.getUTCDay() === 6
                    x: index * root.dayW
                    width: root.dayW
                    height: timeline.height
                    color: weekend && root.dayW >= 8 ? Theme.withAlpha(Theme.surfaceText, 0.04) : "transparent"
                    Rectangle {
                        visible: root.dayW >= 18 || parent.d.getUTCDay() === 1
                        width: 1
                        height: parent.height
                        color: Theme.withAlpha(Theme.outlineVariant, 0.35)
                    }
                }
            }
            // 行分隔
            Repeater {
                model: root.rows.length
                Rectangle {
                    required property int index
                    y: (index + 1) * root.rowH - 1
                    width: root.timelineW
                    height: 1
                    color: Theme.withAlpha(Theme.outlineVariant, 0.35)
                }
            }
            // 今天
            Rectangle {
                x: root.xOf(root.t0)
                width: root.dayW
                height: timeline.height
                color: Theme.withAlpha(Theme.primary, 0.07)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 1.5
                    height: parent.height
                    color: Theme.withAlpha(Theme.primary, 0.6)
                }
            }

            // 横条
            Repeater {
                model: root.rows
                GanttBar {
                    required property var modelData
                    required property int index
                    bar: modelData
                    y: index * root.rowH + 7
                    height: root.rowH - 14
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: body
        visible: root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: "还没有带日期的任务\n在待办里点 ▶ 开始做，或写上截止日期，就会出现在这里"
        color: Theme.surfaceVariantText
    }

    // 一根横条：拖动时只改预览，松手才提交
    component GanttBar: Item {
        id: gb
        property var bar
        property int shiftStart: 0
        property int shiftEnd: 0
        readonly property var s: D.addDays(bar.start, shiftStart)
        readonly property var e: D.addDays(bar.end, shiftEnd)
        x: root.xOf(s) + 1
        width: (D.daysBetween(s, e) + 1) * root.dayW - 2
        opacity: bar.dim ? 0.3 : 1
        z: drag.pressed ? 10 : 1

        Rectangle {
            id: shape
            anchors.fill: parent
            radius: 6
            color: gb.bar.dueOnly ? Theme.withAlpha(gb.bar.color, 0.18) : gb.bar.color
            border.width: gb.bar.dueOnly ? 1.5 : 0
            border.color: gb.bar.color
            // 长期在做：末端渐隐，表示还没结束
            gradient: gb.bar.open ? fade : null
            Gradient {
                id: fade
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: gb.bar.color
                }
                GradientStop {
                    position: Math.max(0, 1 - root.dayW * 1.5 / Math.max(1, gb.width))
                    color: gb.bar.color
                }
                GradientStop {
                    position: 1
                    color: Theme.withAlpha(gb.bar.color, 0)
                }
            }
            layer.enabled: drag.pressed
        }

        StyledText {
            readonly property bool inside: gb.width >= 56
            x: inside ? 8 : gb.width + 6
            width: inside ? gb.width - 12 : 240
            anchors.verticalCenter: parent.verticalCenter
            text: gb.bar.task.title
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: inside && !gb.bar.dueOnly ? (gb.bar.color.hslLightness > 0.6 ? "#222" : "white") : Theme.surfaceText
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.leftMargin: -4
            anchors.rightMargin: -4
            hoverEnabled: true
            preventStealing: true
            property real pressX: 0
            property string mode: ""
            readonly property real edge: Math.min(10, gb.width / 3)
            cursorShape: pressed ? Qt.ClosedHandCursor : (mouseX <= edge + 4 || mouseX >= width - edge - 4) ? Qt.SizeHorCursor : Qt.OpenHandCursor

            onPressed: mouse => {
                pressX = mouse.x;
                mode = mouse.x >= width - edge - 4 ? "end" : mouse.x <= edge + 4 ? "start" : "move";
                // 长期任务右端是"今天"，整体拖没意义，按中间也只改开始
                if (gb.bar.open && mode === "move")
                    mode = "start";
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const n = Math.round((mouse.x - pressX) / root.dayW);
                if (mode === "move") {
                    gb.shiftStart = n;
                    gb.shiftEnd = n;
                } else if (mode === "start") {
                    gb.shiftStart = Math.min(n, D.daysBetween(gb.bar.start, gb.bar.end));
                } else {
                    gb.shiftEnd = Math.max(n, -D.daysBetween(gb.bar.start, gb.bar.end));
                }
            }
            onReleased: mouse => {
                const moved = Math.abs(mouse.x - pressX) > 4;
                const ds = gb.shiftStart, de = gb.shiftEnd;
                if (!moved) {
                    gb.shiftStart = gb.shiftEnd = 0;
                    root.openTask(gb.bar.task);
                    return;
                }
                if (ds !== 0 || de !== 0) {
                    const startOnly = gb.bar.open && mode === "start";
                    root.store.updateRange(gb.bar.task, gb.s, gb.e, startOnly);
                }
                gb.shiftStart = gb.shiftEnd = 0;
            }
        }
    }
}
