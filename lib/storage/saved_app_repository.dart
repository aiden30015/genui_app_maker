import 'saved_app.dart';

/// 저장된 앱 보관소. (SPEC 7장)
abstract interface class SavedAppRepository {
  /// 최근에 만든 순서로 돌려준다.
  Future<List<SavedApp>> list();

  /// 같은 id가 있으면 덮어쓴다.
  Future<void> save(SavedApp app);

  Future<void> delete(String id);
}
