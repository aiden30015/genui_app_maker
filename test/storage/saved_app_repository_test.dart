import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui_app_maker/storage/in_memory_saved_app_repository.dart';
import 'package:genui_app_maker/storage/saved_app.dart';
import 'package:genui_app_maker/storage/saved_app_repository.dart';
import 'package:genui_app_maker/storage/shared_prefs_saved_app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedApp app(String id, int day, {String? name}) => SavedApp(
  id: id,
  name: name ?? '앱 $id',
  prompt: '메모장 만들어줘',
  createdAt: DateTime(2026, 11, day),
  transcript: 'transcript-$id',
  data: {
    'main': {
      'notes': [
        {'text': '메모 $id'},
      ],
    },
  },
);

const String key = SharedPrefsSavedAppRepository.storageKey;

/// 두 구현이 똑같이 지켜야 하는 계약.
void contractTests(SavedAppRepository Function() create) {
  test('starts empty', () async {
    expect(await create().list(), isEmpty);
  });

  test('lists newest first regardless of save order', () async {
    final SavedAppRepository repo = create();
    await repo.save(app('a', 2));
    await repo.save(app('b', 5));
    await repo.save(app('c', 1));

    expect((await repo.list()).map((a) => a.id), ['b', 'a', 'c']);
  });

  test('save with an existing id replaces instead of adding', () async {
    final SavedAppRepository repo = create();
    await repo.save(app('a', 2));
    await repo.save(app('b', 5));
    await repo.save(app('a', 2, name: '바뀐 이름'));

    final List<SavedApp> apps = await repo.list();
    expect(apps.map((a) => a.id), ['b', 'a']);
    expect(apps.last.name, '바뀐 이름');
  });

  test('delete removes only the given id; unknown id is a no-op', () async {
    final SavedAppRepository repo = create();
    await repo.save(app('a', 2));
    await repo.save(app('b', 5));

    await repo.delete('a');
    await repo.delete('없는 id');

    expect((await repo.list()).map((a) => a.id), ['b']);
  });
}

void main() {
  group('InMemorySavedAppRepository', () {
    contractTests(InMemorySavedAppRepository.new);

    test('accepts initial apps', () async {
      final repo = InMemorySavedAppRepository([app('a', 1), app('b', 2)]);
      expect((await repo.list()).map((a) => a.id), ['b', 'a']);
    });
  });

  group('SharedPrefsSavedAppRepository', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    contractTests(SharedPrefsSavedAppRepository.new);

    test('data survives a new repository instance', () async {
      await SharedPrefsSavedAppRepository().save(app('a', 3));

      final List<SavedApp> apps = await SharedPrefsSavedAppRepository().list();
      expect(apps, hasLength(1));
      expect(apps.single.id, 'a');
      expect(apps.single.name, '앱 a');
      expect(apps.single.createdAt, DateTime(2026, 11, 3));
      expect(apps.single.transcript, 'transcript-a');
      expect(apps.single.data, {
        'main': {
          'notes': [
            {'text': '메모 a'},
          ],
        },
      });
    });

    test('stores everything as one JSON string under one key', () async {
      await SharedPrefsSavedAppRepository().save(app('a', 3));
      await SharedPrefsSavedAppRepository().save(app('b', 4));

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {key});
      expect(jsonDecode(prefs.getString(key)!), hasLength(2));
    });

    for (final String bad in ['{not json', '{"a":1}', '"text"', '']) {
      test('corrupt data "$bad" lists as empty and is left alone', () async {
        SharedPreferences.setMockInitialValues({key: bad});
        final repo = SharedPrefsSavedAppRepository();

        expect(await repo.list(), isEmpty);
        await repo.delete('a');

        final SharedPreferences prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), bad);
      });
    }

    test('a value of the wrong type under the key is not a crash', () async {
      SharedPreferences.setMockInitialValues({key: 42});
      expect(await SharedPrefsSavedAppRepository().list(), isEmpty);
    });

    test('save after corrupt data starts a fresh list', () async {
      SharedPreferences.setMockInitialValues({key: '{not json'});
      final repo = SharedPrefsSavedAppRepository();

      await repo.save(app('a', 3));

      expect((await repo.list()).map((a) => a.id), ['a']);
    });

    test('entries that fail to parse are skipped', () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode([
          app('a', 3).toJson(),
          {'id': 'no-other-fields'},
          'not a map',
          {...app('bad-date', 4).toJson(), 'createdAt': 'yesterday'},
          {...app('bad-type', 4).toJson(), 'name': 7},
          app('b', 5).toJson(),
        ]),
      });

      final List<SavedApp> apps = await SharedPrefsSavedAppRepository().list();
      expect(apps.map((a) => a.id), ['b', 'a']);
    });
  });
}
