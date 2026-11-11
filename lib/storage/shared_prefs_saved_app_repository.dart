import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'saved_app.dart';
import 'saved_app_repository.dart';

/// `shared_preferences`에 모든 앱을 JSON 문자열 하나로 저장한다. (SPEC S-5)
class SharedPrefsSavedAppRepository implements SavedAppRepository {
  /// [preferences]를 생략하면 처음 쓸 때 `SharedPreferences.getInstance()`를
  /// 부른다.
  SharedPrefsSavedAppRepository([SharedPreferences? preferences])
    : _preferences = preferences;

  /// 저장에 쓰는 키.
  static const String storageKey = 'saved_apps_v1';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<List<SavedApp>> list() async {
    final List<SavedApp> apps = _decode((await _prefs).get(storageKey));
    // List.sort는 안정 정렬이 아니므로 같은 시각이면 저장된 순서를 지킨다.
    final List<int> order = List.generate(apps.length, (i) => i)
      ..sort((a, b) {
        final int byDate = apps[b].createdAt.compareTo(apps[a].createdAt);
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    return [for (final int i in order) apps[i]];
  }

  @override
  Future<void> save(SavedApp app) async {
    final SharedPreferences prefs = await _prefs;
    final List<SavedApp> apps = _decode(prefs.get(storageKey));
    final int index = apps.indexWhere((a) => a.id == app.id);
    if (index >= 0) {
      apps[index] = app;
    } else {
      apps.add(app);
    }
    await _write(prefs, apps);
  }

  @override
  Future<void> delete(String id) async {
    final SharedPreferences prefs = await _prefs;
    final List<SavedApp> apps = _decode(prefs.get(storageKey));
    final int before = apps.length;
    apps.removeWhere((a) => a.id == id);
    // 지울 것이 없으면 쓰지 않는다. 손상된 원본을 덮어쓰지 않기 위해서다.
    if (apps.length == before) return;
    await _write(prefs, apps);
  }

  Future<void> _write(SharedPreferences prefs, List<SavedApp> apps) =>
      prefs.setString(
        storageKey,
        jsonEncode([for (final SavedApp app in apps) app.toJson()]),
      );

  /// 손상된 데이터는 빈 목록으로, 해석할 수 없는 항목은 건너뛴다.
  static List<SavedApp> _decode(Object? raw) {
    if (raw is! String || raw.isEmpty) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [];
    }
    if (decoded is! List) return [];
    final apps = <SavedApp>[];
    for (final Object? entry in decoded) {
      if (entry is! Map) continue;
      try {
        apps.add(SavedApp.fromJson(Map<String, Object?>.from(entry)));
      } catch (_) {
        // 필드 누락·타입 불일치(TypeError 포함)인 항목 하나만 버린다.
      }
    }
    return apps;
  }
}
