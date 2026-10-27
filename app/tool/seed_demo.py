#!/usr/bin/env python3
"""往 Vikunja 测试账号里灌一批演示数据（会清空该账号的所有任务）。
用法: tool/seed_demo.py <用户名> <密码> [服务器]"""
import datetime as dt
import json
import sys
import urllib.parse
import urllib.request

user, password = sys.argv[1], sys.argv[2]
B = (sys.argv[3] if len(sys.argv) > 3 else 'http://localhost:3456') + '/api/v1'


def call(method, path, body=None, tok=None):
    h = {'Content-Type': 'application/json'}
    if tok:
        h['Authorization'] = 'Bearer ' + tok
    data = json.dumps(body).encode() if body is not None else None
    with urllib.request.urlopen(urllib.request.Request(B + path, method=method, data=data, headers=h)) as r:
        return json.load(r)


tok = call('POST', '/login', {'username': user, 'password': password})['token']
req = lambda m, p, b=None: call(m, p, b, tok)  # noqa: E731

tz = dt.timezone(dt.timedelta(hours=8))
today = dt.datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)


def d(days, h=23, m=59):
    return (today + dt.timedelta(days=days)).replace(hour=h, minute=m).isoformat()


for f in ['done = false', 'done = true']:
    for t in req('GET', '/tasks?per_page=50&filter=' + urllib.parse.quote(f)) or []:
        req('DELETE', f"/tasks/{t['id']}")

wanted = [('商城项目', 'e8590c'), ('智能体平台', '1971c2'), ('生活', '2f9e44')]
projs = {}
for p in req('GET', '/projects'):
    if p['id'] <= 0:
        continue
    if p['title'] in ('Inbox',) or p['title'] in dict(wanted):
        projs[p['title']] = p['id']
    else:
        req('DELETE', f"/projects/{p['id']}")
for name, color in wanted:
    if name not in projs:
        projs[name] = req('PUT', '/projects', {'title': name, 'hex_color': color})['id']

labels = {l['title']: l['id'] for l in (req('GET', '/labels') or [])}
for name, color in [('客户', 'e8590c'), ('开发', '1971c2'), ('运维', '9c36b5'), ('杂事', '2f9e44')]:
    if name not in labels:
        labels[name] = req('PUT', '/labels', {'title': name, 'hex_color': color})['id']

tasks = [
    ('商城项目', '发报价单给客户', {'due_date': d(-1), 'priority': 4}, ['客户']),
    ('商城项目', '对接微信支付回调', {'start_date': d(-3, 0, 0), 'end_date': d(4), 'priority': 3}, ['开发']),
    ('商城项目', '确认商品类目和资质', {'due_date': d(0, 15, 0)}, ['客户']),
    ('商城项目', '后台商品管理页', {'start_date': d(2, 0, 0), 'end_date': d(12)}, ['开发']),
    ('智能体平台', '调度模块改事件流',
     {'start_date': d(-6, 0, 0), 'end_date': d(1), 'priority': 2, 'description': '轮询已经拆出来了，下一步：接 SSE'}, ['开发']),
    ('智能体平台', '写设计文档第三章', {'due_date': d(0)}, []),
    ('智能体平台', '接口限流重试', {'start_date': d(5, 0, 0), 'end_date': d(9)}, ['开发']),
    ('Inbox', '续费 VPS', {'due_date': d(3), 'priority': 3}, ['运维']),
    ('Inbox', '显存占用排查', {'start_date': d(0, 0, 0), 'end_date': d(2)}, ['运维']),
    ('生活', '给爸妈打电话', {'due_date': d(0, 20, 0)}, ['杂事']),
    ('生活', '体检预约', {'due_date': d(8)}, ['杂事']),
    ('生活', '买净水器滤芯', {}, []),
    # 长期在做、没有截止
    ('智能体平台', '重构工具调用', {'start_date': d(-12, 0, 0),
     'description': '做到：工具注册表拆完了\n下一步：把轮询换成事件流'}, ['开发']),
    ('生活', '每天练英语口语', {'start_date': d(-40, 0, 0)}, ['杂事']),
    ('Inbox', '研究插件机制', {'start_date': d(0, 0, 0), 'description': '先看 TG 适配器怎么写'}, []),
    # 没安排
    ('生活', '整理相册', {}, []),
    ('智能体平台', '写使用文档', {}, ['开发']),
]
for proj, title, extra, ls in tasks:
    t = req('PUT', f"/projects/{projs[proj]}/tasks", {'title': title, **extra})
    for l in ls:
        req('PUT', f"/tasks/{t['id']}/labels", {'label_id': labels[l]})
print('seeded', len(tasks), 'tasks')
