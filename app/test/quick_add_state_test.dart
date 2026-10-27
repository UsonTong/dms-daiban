import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/api/models.dart';
import 'package:vikunja_md/api/vikunja_api.dart';
import 'package:vikunja_md/state/app_state.dart';
import 'package:vikunja_md/utils/dates.dart';

/// 记下创建任务时发给服务器的内容
class _FakeApi extends VikunjaApi {
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<Task> createTask(int projectId, Map<String, dynamic> body) async {
    bodies.add(body);
    return Task.fromJson({
      'id': bodies.length,
      'project_id': projectId,
      ...body,
    });
  }
}

void main() {
  test('新建默认不带截止也不带排期，出现在"待办"组', () async {
    final api = _FakeApi();
    final s = AppState(api: api);
    final t = await s.quickAdd('写周报');
    expect(api.bodies.single.keys, ['title']);
    expect(t!.isUnscheduled, isTrue);
    expect(s.unscheduled.map((x) => x.id), [t.id]);
  });

  test('写了日期就按写的截止，不标开始', () async {
    final api = _FakeApi();
    final s = AppState(api: api);
    final t = await s.quickAdd('明天 交报价');
    expect(api.bodies.single.containsKey('start_date'), isFalse);
    expect(dayOf(t!.dueDate!), addDays(today(), 1));
  });
}
