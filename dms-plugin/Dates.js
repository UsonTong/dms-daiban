.pragma library

// 日期一律按账号时区的"墙上时间"处理：用 Date 对象承载，但只读 getUTC* 字段，
// 与系统时区（洛杉矶）无关。offset = 账号时区相对 UTC 的分钟数（来自 dms.json）。

const DAY = 86400000;

// 服务器的 ISO 时间 → 墙上时间；Vikunja 用 0001-01-01 表示"没有日期"
function wall(iso, offset) {
    if (!iso || iso.startsWith("0001-"))
        return null;
    return new Date(Date.parse(iso) + offset * 60000);
}

// 墙上时间 → 发给服务器的 ISO（UTC）
function iso(w, offset) {
    return w ? new Date(w.getTime() - offset * 60000).toISOString() : null;
}

// 测试用：固定"现在"（毫秒时间戳），null = 真实时间
var fixedNow = null;

function nowWall(offset) {
    return new Date((fixedNow === null ? Date.now() : fixedNow) + offset * 60000);
}

function dayOf(w) {
    return new Date(Date.UTC(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate()));
}

function today(offset) {
    return dayOf(nowWall(offset));
}

function addDays(w, n) {
    return new Date(w.getTime() + n * DAY);
}

function endOfDay(w) {
    return new Date(Date.UTC(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate(), 23, 59));
}

function daysBetween(a, b) {
    return Math.round((dayOf(b).getTime() - dayOf(a).getTime()) / DAY);
}

function key(w) {
    return w ? dayOf(w).toISOString().slice(0, 10) : "";
}

// 23:59 / 00:00 当作"全天"
function hasTime(w) {
    const h = w.getUTCHours(), m = w.getUTCMinutes();
    return !(h === 23 && m === 59) && !(h === 0 && m === 0);
}

const WEEK = ["日", "一", "二", "三", "四", "五", "六"];

function weekday(w) {
    return "周" + WEEK[w.getUTCDay()];
}

function hm(w) {
    return String(w.getUTCHours()).padStart(2, "0") + ":" + String(w.getUTCMinutes()).padStart(2, "0");
}

function shortDate(w) {
    return (w.getUTCMonth() + 1) + "/" + w.getUTCDate();
}

// 今天 / 明天 / 周五 / 10月25日 [+ 时间]
function friendly(w, offset, withTime) {
    const diff = daysBetween(today(offset), w);
    let day;
    if (diff === 0)
        day = "今天";
    else if (diff === 1)
        day = "明天";
    else if (diff === 2)
        day = "后天";
    else if (diff === -1)
        day = "昨天";
    else if (diff > 2 && diff < 7)
        day = weekday(w);
    else if (w.getUTCFullYear() === nowWall(offset).getUTCFullYear())
        day = (w.getUTCMonth() + 1) + "月" + w.getUTCDate() + "日";
    else
        day = w.getUTCFullYear() + "年" + (w.getUTCMonth() + 1) + "月" + w.getUTCDate() + "日";
    return (withTime !== false && hasTime(w)) ? day + " " + hm(w) : day;
}

// ---------- 快速添加解析 ----------
// "明天下午3点 改报价 !3 +商城 *客户"

const WD = { "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 0, "天": 0 };
// 注意：Qt 的 JS 引擎不支持后行断言 (?<!…)，写了不报错但永远匹配不上，所以"1/5"单独处理
const DATE_RE = /(大后天|后天|明天|今天|今晚|下周[一二三四五六日天]|(?:周|星期)[一二三四五六日天]|(\d{1,2})月(\d{1,2})[日号]?)/;
const SLASH_RE = /(^|[^\d])(\d{1,2})[\/\-](\d{1,2})(?!\d)/;
const TIME_RE = /(上午|早上|中午|下午|晚上)?\s*(\d{1,2})(?:[:：](\d{2})|点(半|(\d{1,2})分?)?)/;

function parseQuickAdd(input, offset) {
    let text = " " + input + " ";
    const t0 = today(offset);
    let priority = null, project = null, labels = [];

    text = text.replace(/[!！]([1-5])/, (m, p) => { priority = Number(p); return " "; });
    text = text.replace(/\s\+(\S+)/, (m, p) => { project = p; return " "; });
    text = text.replace(/\s[*#](\S+)/g, (m, l) => { labels.push(l); return " "; });

    let day = null, evening = false;
    const t0y = t0.getUTCFullYear();
    const monthDay = (month, d) => {
        let c = new Date(Date.UTC(t0y, month - 1, d));
        if (c < t0)
            c = new Date(Date.UTC(t0y + 1, month - 1, d));
        return c;
    };
    text = text.replace(DATE_RE, (s, all, m1, d1) => {
        if (s === "今天") day = t0;
        else if (s === "今晚") { day = t0; evening = true; }
        else if (s === "明天") day = addDays(t0, 1);
        else if (s === "后天") day = addDays(t0, 2);
        else if (s === "大后天") day = addDays(t0, 3);
        else if (s.startsWith("下周")) {
            // 下周一 = 本周一 + 7；周日算一周的最后一天
            const target = WD[s.slice(2)] || 7;
            const dow = t0.getUTCDay() || 7;
            day = addDays(t0, 7 - dow + target);
        } else if (s.startsWith("周") || s.startsWith("星期")) {
            const target = WD[s.slice(-1)];
            day = addDays(t0, (target - t0.getUTCDay() + 7) % 7);
        } else {
            day = monthDay(Number(m1), Number(d1));
        }
        return " ";
    });
    if (!day) {
        text = text.replace(SLASH_RE, (s, pre, m, d) => {
            day = monthDay(Number(m), Number(d));
            return pre + " ";
        });
    }

    let hour = null, minute = 0;
    if (day) {
        text = text.replace(TIME_RE, (s, period, h, mm, half, mi) => {
            let H = Number(h);
            if ((period === "下午" || period === "晚上" || evening) && H < 12) H += 12;
            if (period === "中午" && H < 6) H += 12;
            if (H > 23) return s;
            hour = H;
            if (mm) minute = Number(mm);
            else if (half === "半") minute = 30;
            else if (mi) minute = Number(mi);
            return " ";
        });
    }

    let due = null;
    if (day) {
        if (hour !== null)
            due = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), hour, minute));
        else if (evening)
            due = new Date(Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 20));
        else
            due = endOfDay(day);
    }
    return {
        title: text.replace(/\s+/g, " ").trim(),
        due: due,
        priority: priority,
        project: project,
        labels: labels
    };
}
