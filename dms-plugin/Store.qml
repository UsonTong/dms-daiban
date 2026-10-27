import QtQuick
import Quickshell
import Quickshell.Io
import "Dates.js" as D

// 待办数据层：直接读写 Vikunja。凭据来自 ~/.config/vikunja-md/dms.json
// （服务器、长期 API token、默认项目、账号时区偏移、"开始做"默认天数）。
// 规则与 Flutter 版一致：分组 已逾期 → 今天 → 正在做 → 待办，更新任务必须整包提交。
Item {
    id: root

    property var cfg: null
    readonly property bool ready: cfg !== null && !!cfg.token
    readonly property int offset: cfg ? (cfg.tzOffsetMinutes || 0) : 480
    readonly property int planDays: cfg && cfg.planDays !== undefined ? cfg.planDays : 3

    property var tasks: []
    property var doneToday: []
    property var projects: ({})
    property var projectList: []
    property var labels: []
    property bool loading: false
    property string error: ""

    // 刚勾掉、正在播放划掉动画的任务；刚加进来、要播放展开动画的任务
    property var completing: ({})
    property var justAdded: ({})

    // 任务列表一变就重算分组
    readonly property var groups: computeGroups(tasks)

    signal toast(string message, var undo)

    // ---------- 配置 ----------

    FileView {
        id: cfgFile
        path: Quickshell.env("HOME") + "/.config/vikunja-md/dms.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.cfg = JSON.parse(text());
                root.refresh();
            } catch (e) {
                root.cfg = null;
            }
        }
        onLoadFailed: root.cfg = null
    }

    Timer {
        interval: 60000
        running: root.ready
        repeat: true
        onTriggered: root.refresh()
    }

    // ---------- 请求 ----------

    function request(method, path, body, done, fail) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let json = null;
            try {
                json = xhr.responseText ? JSON.parse(xhr.responseText) : null;
            } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300) {
                if (done)
                    done(json, xhr);
            } else {
                const msg = xhr.status === 0 ? "连不上服务器" : ((json && json.message) || ("请求失败 " + xhr.status));
                root.error = msg;
                root.loading = false;
                if (fail)
                    fail(msg);
                else
                    root.toast(msg, null);
            }
        };
        xhr.open(method, cfg.server + "/api/v1" + path);
        xhr.setRequestHeader("Authorization", "Bearer " + cfg.token);
        if (body !== undefined && body !== null)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body === undefined || body === null ? null : JSON.stringify(body));
    }

    // 服务端每页最多 50 条，按响应头翻页
    function listAll(path, done, page, acc) {
        page = page || 1;
        acc = acc || [];
        const sep = path.indexOf("?") >= 0 ? "&" : "?";
        request("GET", path + sep + "per_page=50&page=" + page, null, (list, xhr) => {
            const all = acc.concat(list || []);
            if (page < parseInt(xhr.getResponseHeader("x-pagination-total-pages") || "1"))
                listAll(path, done, page + 1, all);
            else
                done(all);
        }, () => {});
    }

    function refresh() {
        if (!ready)
            return;
        loading = true;
        listAll("/projects", list => {
            const map = {};
            const arr = [];
            for (const p of list) {
                if (p.id > 0 && !p.is_archived) {
                    map[p.id] = p;
                    arr.push(p);
                }
            }
            arr.sort((a, b) => a.position - b.position);
            projects = map;
            projectList = arr;
        });
        listAll("/labels", list => labels = list);
        listAll("/tasks?filter=" + encodeURIComponent("done = false"), list => {
            // 正在播放划掉动画的保留到动画结束
            const keep = tasks.filter(t => completing[t.id] && !list.some(x => x.id === t.id));
            tasks = list.concat(keep);
            error = "";
            loading = false;
        });
        const tz = cfg.timezone ? "&filter_timezone=" + encodeURIComponent(cfg.timezone) : "";
        listAll("/tasks?filter=" + encodeURIComponent("done = true && done_at >= now/d") + tz, list => {
            doneToday = list.sort((a, b) => (b.done_at || "").localeCompare(a.done_at || ""));
        });
    }

    // ---------- 分组 ----------

    function due(t) {
        return D.wall(t.due_date, offset);
    }
    function start(t) {
        return D.wall(t.start_date, offset);
    }
    function end(t) {
        return D.wall(t.end_date, offset);
    }
    function isOngoing(t) {
        return !!start(t) && !end(t) && !due(t);
    }
    function isUnscheduled(t) {
        return !start(t) && !end(t) && !due(t);
    }

    function computeGroups(list) {
        const t0 = D.today(offset);
        const g = {
            overdue: [],
            today: [],
            doing: [],
            todo: []
        };
        for (const t of list) {
            const d = due(t), s = start(t);
            if (d && D.dayOf(d) < t0)
                g.overdue.push(t);
            else if (d && D.daysBetween(t0, d) === 0)
                g.today.push(t);
            else if (s && D.dayOf(s) <= t0)
                g.doing.push(t);
            else if (isUnscheduled(t))
                g.todo.push(t);
        }
        const byDue = (a, b) => (a.due_date || "").localeCompare(b.due_date || "") || b.priority - a.priority || a.id - b.id;
        g.overdue.sort(byDue);
        g.today.sort(byDue);
        // 有截止/计划结束日的按日子近远，长期在做（没结束日）的放最后
        g.doing.sort((a, b) => {
            const ao = isOngoing(a), bo = isOngoing(b);
            if (ao !== bo)
                return ao ? 1 : -1;
            if (ao)
                return (a.start_date || "").localeCompare(b.start_date || "");
            const ae = due(a) || end(a), be = due(b) || end(b);
            return ae - be;
        });
        g.todo.sort((a, b) => b.priority - a.priority || b.id - a.id);
        return g;
    }

    // ---------- 修改 ----------

    function replaceTask(t) {
        const i = tasks.findIndex(x => x.id === t.id);
        const next = tasks.slice();
        if (i >= 0)
            next[i] = t;
        else if (!t.done)
            next.push(t);
        tasks = next;
    }

    function setFlag(map, id, on) {
        const m = Object.assign({}, map);
        if (on)
            m[id] = true;
        else
            delete m[id];
        return m;
    }

    function toggleDone(task) {
        if (task.done) {
            reopen(task);
            return;
        }
        completing = setFlag(completing, task.id, true);
        request("POST", "/tasks/" + task.id, Object.assign({}, task, {
            done: true
        }), updated => {
            if (!updated.done) {
                // 重复任务：服务端把日期顺延并保持未完成
                completing = setFlag(completing, task.id, false);
                replaceTask(updated);
                const d = due(updated);
                toast("已完成，下次：" + (d ? D.friendly(d, offset) : "已顺延"), null);
                return;
            }
            doneToday = [updated].concat(doneToday.filter(x => x.id !== task.id));
            toast("已完成「" + task.title + "」", () => reopen(updated));
            removeLater.schedule(task.id);
        }, msg => {
            completing = setFlag(completing, task.id, false);
            toast(msg, null);
        });
    }

    // 划掉动画播完再从列表移除；动画期间点了撤销（已移出 completing）就不删
    QtObject {
        id: removeLater
        function schedule(id) {
            const timer = Qt.createQmlObject("import QtQuick; Timer { interval: 600 }", root);
            timer.triggered.connect(() => {
                if (root.completing[id]) {
                    root.completing = root.setFlag(root.completing, id, false);
                    root.tasks = root.tasks.filter(t => t.id !== id);
                }
                timer.destroy();
            });
            timer.start();
        }
    }

    function reopen(task) {
        request("POST", "/tasks/" + task.id, Object.assign({}, task, {
            done: false
        }), updated => {
            completing = setFlag(completing, task.id, false);
            doneToday = doneToday.filter(x => x.id !== task.id);
            replaceTask(updated);
            toast("已恢复「" + task.title + "」", null);
        });
    }

    // 开始做：今天开始，按 planDays 自动排到第 N 天（0 = 只记开始）；暂停：清掉排期回到待办
    function setStarted(task, on) {
        const t0 = D.today(offset);
        const body = Object.assign({}, task, {
            start_date: on ? D.iso(t0, offset) : null,
            end_date: on && planDays > 0 ? D.iso(D.endOfDay(D.addDays(t0, planDays - 1)), offset) : null
        });
        saveRaw(task, body, on ? ("开始做「" + task.title + "」" + (planDays > 0 ? "，计划 " + planDays + " 天" : "")) : ("已暂停「" + task.title + "」，放回待办"));
    }

    // 甘特图拖动：先本地更新保证跟手，失败回滚
    function updateRange(task, startWall, endWall, startOnly) {
        const body = Object.assign({}, task, {
            start_date: D.iso(D.dayOf(startWall), offset)
        });
        if (!startOnly)
            body.end_date = D.iso(D.endOfDay(endWall), offset);
        saveRaw(task, body, null);
    }

    function saveRaw(original, body, message) {
        replaceTask(body);
        request("POST", "/tasks/" + original.id, body, updated => {
            replaceTask(updated);
            if (message)
                toast(message, null);
        }, msg => {
            replaceTask(original);
            toast(msg, null);
        });
    }

    // 编辑器保存：标签走单独接口按差异增删，再整包更新任务
    function saveTask(original, edited, labelIds, done) {
        const before = (original.labels || []).map(l => l.id);
        const add = labelIds.filter(id => before.indexOf(id) < 0);
        const remove = before.filter(id => labelIds.indexOf(id) < 0);
        let pending = add.length + remove.length + 1;
        const finish = () => {
            if (--pending === 0) {
                refresh();
                if (done)
                    done();
            }
        };
        for (const id of add)
            request("PUT", "/tasks/" + original.id + "/labels", {
                label_id: id
            }, finish, finish);
        for (const id of remove)
            request("DELETE", "/tasks/" + original.id + "/labels/" + id, null, finish, finish);
        const body = Object.assign({}, edited, {
            labels: labels.filter(l => labelIds.indexOf(l.id) >= 0)
        });
        replaceTask(body);
        request("POST", "/tasks/" + original.id, body, updated => {
            replaceTask(Object.assign({}, updated, {
                labels: body.labels
            }));
            if (updated.done)
                tasks = tasks.filter(t => t.id !== updated.id);
            finish();
        }, msg => {
            replaceTask(original);
            toast(msg, null);
            finish();
        });
    }

    function deleteTask(task) {
        tasks = tasks.filter(t => t.id !== task.id);
        request("DELETE", "/tasks/" + task.id, null, () => toast("已删除「" + task.title + "」", null), msg => {
            replaceTask(task);
            toast(msg, null);
        });
    }

    // 找不到同名标签就新建（颜色轮流取）
    readonly property var palette: ["e8590c", "2f9e44", "1971c2", "9c36b5", "f08c00", "0c8599", "c2255c", "5c940d"]
    function ensureLabel(title, done) {
        const hit = labels.find(l => l.title.toLowerCase() === title.toLowerCase());
        if (hit) {
            done(hit);
            return;
        }
        request("PUT", "/labels", {
            title: title,
            hex_color: palette[labels.length % palette.length]
        }, l => {
            labels = labels.concat([l]);
            done(l);
        });
    }

    // 快速添加：默认不带任何日期，除非输入里写了；+项目 找不到就放默认项目并提示
    function quickAdd(input, projectId, done) {
        const r = D.parseQuickAdd(input, offset);
        if (!r.title)
            return;
        let pid = projectId || cfg.defaultProjectId;
        let missing = null;
        if (r.project) {
            const p = projectList.find(x => x.title.toLowerCase() === r.project.toLowerCase());
            if (p)
                pid = p.id;
            else
                missing = r.project;
        }
        const body = {
            title: r.title
        };
        if (r.due)
            body.due_date = D.iso(r.due, offset);
        if (r.priority)
            body.priority = r.priority;
        request("PUT", "/projects/" + pid + "/tasks", body, task => {
            justAdded = setFlag(justAdded, task.id, true);
            tasks = tasks.concat([task]);
            if (missing)
                toast("没有项目「" + missing + "」，已放进「" + (projects[pid] ? projects[pid].title : "默认项目") + "」", null);
            for (const name of r.labels) {
                ensureLabel(name, l => request("PUT", "/tasks/" + task.id + "/labels", {
                    label_id: l.id
                }, () => refresh()));
            }
            if (done)
                done(task);
        });
    }

    // 标签/项目颜色："e8590c" → "#e8590c"
    function color(hex, fallback) {
        return hex && hex.length === 6 ? "#" + hex : fallback;
    }

    function taskColor(t, fallback) {
        for (const l of (t.labels || []))
            if (l.hex_color)
                return color(l.hex_color, fallback);
        const p = projects[t.project_id];
        return p ? color(p.hex_color, fallback) : fallback;
    }
}
