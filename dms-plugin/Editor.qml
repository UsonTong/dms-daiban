import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "Dates.js" as D

// 任务编辑器：面板里滑进来的一页（不另开弹窗——两个 DMS 弹窗叠着会抢键盘和点击）。
// 截止日期直接打字（"明天下午3点""周五"），清空即去掉。Esc 回到列表。
FocusScope {
    id: root

    required property var store
    signal closed

    property bool shown: false
    visible: slide < 1
    // 0 = 完全显示，1 = 收在右边
    property real slide: 1
    Behavior on slide {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }

    property var original: null
    property var draft: null
    property var labelIds: []
    // 截止：墙上时间（账号时区），null = 不设；选择器是否展开；日历当前显示哪个月
    property var due: null
    property bool pickerOpen: false
    property var viewMonth: null

    readonly property int offset: store.offset
    readonly property var priorityNames: ["无", "低", "中", "高", "紧急", "立即"]

    function edit(task) {
        original = task;
        draft = Object.assign({}, task);
        labelIds = (task.labels || []).map(l => l.id);
        const d = store.due(task);
        due = d;
        pickerOpen = false;
        viewMonth = d ? d : D.today(offset);
        shown = true;
        slide = 0;
        Qt.callLater(() => titleField.forceActiveFocus());
    }

    function close() {
        shown = false;
        slide = 1;
        closed();
    }

    function set(key, value) {
        const d = Object.assign({}, draft);
        d[key] = value;
        draft = d;
    }

    // 选某一天：保留原来的钟点，原来没有就算全天（23:59）
    function pickDay(day) {
        const h = due && D.hasTime(due) ? due.getUTCHours() : 23;
        const m = due && D.hasTime(due) ? due.getUTCMinutes() : 59;
        due = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), h, m));
        viewMonth = due;
    }

    // 选钟点：h < 0 表示全天；还没选日子就默认今天
    function pickTime(h) {
        const day = due || D.today(offset);
        due = h < 0 ? D.endOfDay(day) : new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), h, 0));
    }

    function save() {
        if (!draft.title || !draft.title.trim())
            return;
        set("due_date", due ? D.iso(due, offset) : null);
        store.saveTask(original, draft, labelIds, null);
        close();
    }

    // 盖住列表的不透明底，带一点右滑进场
    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceContainer
        radius: Theme.cornerRadiusXL
        opacity: 1 - root.slide
    }

    Item {
        anchors.fill: parent
        transform: Translate {
            x: root.slide * 48
        }
        opacity: 1 - root.slide
            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }

            DFlickable {
                id: scroller
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                anchors.bottomMargin: actions.height + Theme.spacingL * 2
                contentHeight: form.implicitHeight
                clip: true

                Column {
                    id: form
                    width: scroller.width
                    spacing: Theme.spacingM

                    DTextField {
                        id: titleField
                        width: parent.width
                        outlined: true
                        labelText: "标题"
                        text: root.draft ? root.draft.title : ""
                        onTextEdited: root.set("title", text)
                        onAccepted: root.save()
                    }

                    DTextEdit {
                        width: parent.width
                        height: 110
                        placeholderText: "备注：做到哪了、下一步是什么…"
                        text: root.draft ? (root.draft.description || "").replace(/<\/(p|div|li)>|<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").trim() : ""
                        onTextEdited: root.set("description", text)
                    }

                    // 项目：一排可点的小块（下拉菜单会弹在编辑器下面点不到，所以不用下拉）
                    FormRow {
                        label: "项目"
                        Flow {
                            width: form.width - 72
                            spacing: Theme.spacingXS
                            Repeater {
                                model: root.store.projectList
                                Chip {
                                    required property var modelData
                                    text: modelData.title
                                    dot: root.store.color(modelData.hex_color, Theme.primary)
                                    on: root.draft !== null && root.draft.project_id === modelData.id
                                    onClicked: root.set("project_id", modelData.id)
                                }
                            }
                        }
                    }

                    FormRow {
                        label: "截止"
                        Chip {
                            text: (root.due ? D.friendly(root.due, root.offset) : "不设截止") + (root.pickerOpen ? "  ▴" : "  ▾")
                            on: root.due !== null
                            onClicked: root.pickerOpen = !root.pickerOpen
                        }
                    }

                    // 截止选择器：快捷日子 + 月历 + 常用钟点，全部点选
                    Column {
                        visible: root.pickerOpen
                        x: 56 + Theme.spacingM
                        width: form.width - x
                        spacing: Theme.spacingS

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS
                            Repeater {
                                model: [
                                    {
                                        t: "今天",
                                        d: 0
                                    },
                                    {
                                        t: "明天",
                                        d: 1
                                    },
                                    {
                                        t: "后天",
                                        d: 2
                                    },
                                    {
                                        t: "下周一",
                                        d: -1
                                    }
                                ]
                                Chip {
                                    required property var modelData
                                    readonly property var day: {
                                        const t0 = D.today(root.offset);
                                        if (modelData.d >= 0)
                                            return D.addDays(t0, modelData.d);
                                        return D.addDays(t0, 8 - (t0.getUTCDay() || 7));
                                    }
                                    text: modelData.t
                                    on: root.due !== null && D.daysBetween(day, root.due) === 0
                                    onClicked: root.pickDay(day)
                                }
                            }
                            Chip {
                                text: "不设截止"
                                on: root.due === null
                                onClicked: root.due = null
                            }
                        }

                        // 月历（DMS 自带组件；它用系统时区的 Date，这里按年月日换算）
                        Rectangle {
                            width: Math.min(parent.width, 340)
                            height: 300
                            radius: Theme.cornerRadiusL
                            color: Theme.surfaceContainerHigh

                            Row {
                                id: monthHeader
                                anchors.top: parent.top
                                anchors.topMargin: Theme.spacingXS
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Theme.spacingS
                                DIconButton {
                                    iconName: "chevron_left"
                                    onClicked: {
                                        const v = root.viewMonth;
                                        root.viewMonth = new Date(Date.UTC(v.getUTCFullYear(), v.getUTCMonth() - 1, 1));
                                    }
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 110
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.viewMonth ? root.viewMonth.getUTCFullYear() + "年" + (root.viewMonth.getUTCMonth() + 1) + "月" : ""
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                }
                                DIconButton {
                                    iconName: "chevron_right"
                                    onClicked: {
                                        const v = root.viewMonth;
                                        root.viewMonth = new Date(Date.UTC(v.getUTCFullYear(), v.getUTCMonth() + 1, 1));
                                    }
                                }
                            }

                            DMonthGrid {
                                anchors.top: monthHeader.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.spacingS
                                readonly property var t0: D.today(root.offset)
                                function local(w) {
                                    return w ? new Date(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate()) : new Date(0);
                                }
                                displayDate: local(root.viewMonth)
                                selectedDate: root.due ? local(root.due) : new Date(0)
                                today: local(t0)
                                firstDayOfWeek: 1
                                dayNames: ["一", "二", "三", "四", "五", "六", "日"]
                                onDayClicked: date => root.pickDay(new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())))
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS
                            Repeater {
                                model: [-1, 9, 12, 15, 18, 21]
                                Chip {
                                    required property int modelData
                                    text: modelData < 0 ? "全天" : modelData + ":00"
                                    on: root.due !== null && (modelData < 0 ? !D.hasTime(root.due) : D.hasTime(root.due) && root.due.getUTCHours() === modelData && root.due.getUTCMinutes() === 0)
                                    onClicked: root.pickTime(modelData)
                                }
                            }
                        }
                    }

                    FormRow {
                        label: "状态"
                        // 有截止的事不需要"开始做"，只有没截止的才显示
                        visible: root.draft !== null && root.store.due(root.draft) === null
                        readonly property bool started: root.draft && root.store.start(root.draft) !== null
                        DButton {
                            text: parent.started ? "暂停（回到待办）" : "开始做"
                            iconName: parent.started ? "pause" : "play_arrow"
                            onClicked: {
                                const t0 = D.today(root.offset);
                                if (parent.started) {
                                    root.set("start_date", null);
                                    root.set("end_date", null);
                                } else {
                                    root.set("start_date", D.iso(t0, root.offset));
                                    if (root.store.planDays > 0)
                                        root.set("end_date", D.iso(D.endOfDay(D.addDays(t0, root.store.planDays - 1)), root.offset));
                                }
                            }
                        }
                    }

                    FormRow {
                        label: "优先级"
                        DButtonGroup {
                            size: "small"
                            model: root.priorityNames
                            currentIndex: root.draft ? root.draft.priority || 0 : 0
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (selected)
                                    root.set("priority", index);
                            }
                        }
                    }

                    // 标签：点一下选上/取消；"+ 新标签"就地输入，回车新建并选上
                    FormRow {
                        label: "标签"
                        Flow {
                            width: form.width - 72
                            spacing: Theme.spacingXS
                            Repeater {
                                model: root.store.labels
                                Chip {
                                    required property var modelData
                                    text: modelData.title
                                    dot: root.store.color(modelData.hex_color, Theme.secondary)
                                    on: root.labelIds.indexOf(modelData.id) >= 0
                                    onClicked: root.labelIds = on ? root.labelIds.filter(id => id !== modelData.id) : root.labelIds.concat([modelData.id])
                                }
                            }
                            Chip {
                                id: addLabel
                                visible: !newLabel.visible
                                text: "+ 新标签"
                                onClicked: {
                                    newLabel.visible = true;
                                    newLabel.text = "";
                                    newLabel.forceActiveFocus();
                                }
                            }
                            DTextField {
                                id: newLabel
                                visible: false
                                width: 160
                                height: 32
                                controlHeight: 32
                                cornerRadius: height / 2
                                placeholderText: "标签名，回车"
                                onAccepted: {
                                    const name = text.trim();
                                    visible = false;
                                    if (name)
                                        root.store.ensureLabel(name, l => {
                                            if (root.labelIds.indexOf(l.id) < 0)
                                                root.labelIds = root.labelIds.concat([l.id]);
                                        });
                                }
                                Keys.onEscapePressed: event => {
                                    visible = false;
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }
            }

            Row {
                id: actions
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingL
                layoutDirection: Qt.RightToLeft
                spacing: Theme.spacingS

                DButton {
                    text: "保存"
                    onClicked: root.save()
                }
                DButton {
                    text: "取消"
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: root.close()
                }
                Item {
                    width: actions.width - 260
                    height: 1
                }
                DButton {
                    text: "删除"
                    iconName: "delete"
                    backgroundColor: "transparent"
                    textColor: Theme.error
                    onClicked: {
                        root.store.deleteTask(root.original);
                        root.close();
                    }
                }
            }
    }

    // 圆角小块：选中时填色，可带颜色点
    component Chip: Rectangle {
        id: chip
        property string text
        property color dot: "transparent"
        property bool on: false
        signal clicked
        width: chipRow.implicitWidth + 24
        height: 32
        radius: height / 2
        color: on ? Theme.withAlpha(Qt.colorEqual(dot, "transparent") ? Theme.primary : dot, 0.25) : chipMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
        border.width: on ? 1 : 0
        border.color: Qt.colorEqual(dot, "transparent") ? Theme.primary : dot
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                visible: !Qt.colorEqual(chip.dot, "transparent")
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: chip.dot
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component FormRow: Row {
        property string label
        spacing: Theme.spacingM
        StyledText {
            width: 56
            topPadding: 8
            text: parent.label
            color: Theme.surfaceVariantText
        }
    }
}
