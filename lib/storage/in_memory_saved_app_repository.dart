import 'saved_app.dart';
import 'saved_app_repository.dart';

/// 메모리에만 보관하는 [SavedAppRepository]. 위젯 테스트용.
class InMemorySavedAppRepository implements SavedAppRepository {
  InMemorySavedAppRepository([Iterable<SavedApp> initial = const []]) {
    for (final SavedApp app in initial) {
      _apps[app.id] = app;
    }
  }

  final Map<String, SavedApp> _apps = {};

  @override
  Future<List<SavedApp>> list() async {
    final List<SavedApp> apps = _apps.values.toList();
    final List<int> order = List.generate(apps.length, (i) => i)
      ..sort((a, b) {
        final int byDate = apps[b].createdAt.compareTo(apps[a].createdAt);
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    return [for (final int i in order) apps[i]];
  }

  @override
  Future<void> save(SavedApp app) async => _apps[app.id] = app;

  @override
  Future<void> delete(String id) async => _apps.remove(id);
}
