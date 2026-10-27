import QtQuick
import Quickshell
import "Dates.js" as D

ShellRoot {
    Component.onCompleted: {
        D.fixedNow = Date.UTC(2026, 9, 23, 2, 0);
        const cases = ["明天下午3点 改报价 !3 +商城 *客户", "后天交周报", "下周三 续服务器", "11月2日 9:30 面试", "1/5 年检", "今晚 打电话", "买 3 箱水"];
        for (const c of cases) {
            const r = D.parseQuickAdd(c, 480);
            console.warn("[T]", c, "=>", JSON.stringify({title: r.title, due: r.due ? r.due.toISOString() : null, p: r.priority}));
        }
        try { console.warn("[T] lookbehind:", /(?<!\d)a/.test("ba")); } catch (e) { console.warn("[T] lookbehind 不支持:", e); }
        Qt.quit();
    }
}
