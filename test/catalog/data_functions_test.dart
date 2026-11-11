import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/app_session.dart';
import 'package:genui_app_maker/ai/fake_app_generator.dart';
import 'package:genui_app_maker/catalog/data_functions.dart';
import 'package:json_schema_builder/json_schema_builder.dart' show Schema;

/// 시스템 프롬프트의 few-shot 예시로 쓸 메모장. 추가·삭제가 모두 로컬 함수다.
const notesResponse = '''
메모장을 만들었습니다.

```json
{"version":"v0.9","createSurface":{"surfaceId":"main","catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json","sendDataModel":true}}
```

```json
{"version":"v0.9","updateDataModel":{"surfaceId":"main","path":"/","value":{"draft":"","notes":[{"text":"첫 메모"},{"text":"둘째 메모"}]}}}
```

```json
{"version":"v0.9","updateComponents":{"surfaceId":"main","components":[
 {"id":"root","component":"Column","children":["title","input","add","notes"]},
 {"id":"title","component":"Text","text":"메모장","variant":"h2"},
 {"id":"input","component":"TextField","label":"새 메모","value":{"path":"/draft"}},
 {"id":"add","component":"Button","child":"addLabel","variant":"primary","action":{"functionCall":{"call":"listAppend","args":{"path":"/notes","item":{"text":{"path":"/draft"}},"clear":["/draft"]}}}},
 {"id":"addLabel","component":"Text","text":"추가"},
 {"id":"notes","component":"List","children":{"componentId":"noteRow","path":"/notes"}},
 {"id":"noteRow","component":"Row","children":["noteText","noteDelete"]},
 {"id":"noteText","component":"Text","text":{"path":"text"}},
 {"id":"noteDelete","component":"Button","child":"noteDeleteLabel","variant":"borderless","action":{"functionCall":{"call":"listRemove","args":{}}}},
 {"id":"noteDeleteLabel","component":"Text","text":"삭제"}
]}}
```
''';

Widget host(AppSession session) => MaterialApp(
  home: Scaffold(
    body: ValueListenableBuilder<ConversationState>(
      valueListenable: session.state,
      builder: (context, state, _) => Column(
        children: [
          for (final id in state.surfaces)
            Expanded(child: Surface(surfaceContext: session.contextFor(id))),
        ],
      ),
    ),
  ),
);

/// 실행 횟수를 세는 탐침. genui는 최상위 인자가 바인딩이면 그 경로를 구독하고
/// 값이 바뀔 때 함수를 다시 부를 수 있다(switchMap). 함수가 자기 인자가 묶인
/// 경로에 쓸 때 한 번의 누름이 몇 번 실행되는지 확인한다. 혹시 반복되더라도
/// 테스트가 멈추지 않게 5회에서 쓰기를 그만둔다.
class NaiveDouble extends SynchronousClientFunction {
  int runs = 0;

  @override
  String get name => 'naiveDouble';

  @override
  String get description => 'test only';

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.empty;

  @override
  Schema get argumentSchema => dataFunctions.first.argumentSchema;

  @override
  Object? executeSync(JsonMap args, ExecutionContext context) {
    runs++;
    if (runs <= 5) {
      final path = DataPath(args['path']! as String);
      context.update(
        path,
        (context.getValue<num>(path) ?? 0) + (args['by']! as num),
      );
    }
    return null;
  }
}

void main() {
  late InMemoryDataModel model;
  late DataContext root;
  late NaiveDouble naive;

  setUp(() {
    model = InMemoryDataModel();
    naive = NaiveDouble();
    root = DataContext(
      model,
      DataPath.root,
      functions: [...dataFunctions, naive],
    );
  });

  tearDown(() => model.dispose());

  Object? read(String path) => model.getValue<Object?>(DataPath(path));

  /// Button의 functionCall 분기와 같은 방식으로 호출한다:
  /// `dataContext.resolve(funcMap)`의 첫 이벤트를 기다린 뒤 취소.
  Future<void> press(String name, JsonMap args, {DataContext? context}) async {
    final iterator = StreamIterator<Object?>(
      (context ?? root).resolve({'call': name, 'args': args}),
    );
    try {
      await iterator.moveNext().timeout(const Duration(seconds: 2));
    } finally {
      await iterator.cancel();
    }
    await pumpEventQueue();
  }

  final throwsFunctionError = throwsA(isA<A2uiFunctionException>());

  test('exports exactly the five SPEC 5.2 functions, all documented', () {
    expect(dataFunctions.map((f) => f.name), [
      'setValue',
      'listAppend',
      'listRemove',
      'toggle',
      'increment',
    ]);
    for (final ClientFunction f in dataFunctions) {
      expect(f.description, contains('"call": "${f.name}"'));
      expect(f.returnType, ClientFunctionReturnType.empty);
      final schema = f.argumentSchema.value;
      expect(schema['type'], 'object');
      expect(
        ((schema['properties'] as Map)['path'] as Map)['type'],
        'string',
        reason: '${f.name}: target path must be a plain string',
      );
    }
  });

  test('catalog registration puts the functions in the prompt schema', () {
    final Catalog catalog = BasicCatalogItems.asNoAssetCatalog().copyWith(
      newFunctions: dataFunctions,
    );
    final List<Object?> functions =
        catalog.toCapabilitiesJson()['functions']! as List<Object?>;
    expect(
      functions.map((f) => (f! as Map)['name']),
      containsAll(['setValue', 'listAppend', 'listRemove', 'toggle']),
    );
  });

  group('setValue', () {
    test('writes a literal', () async {
      await press('setValue', {'path': '/filter', 'value': 'done'});
      expect(read('/filter'), 'done');
    });

    test('creates intermediate objects', () async {
      await press('setValue', {'path': '/game/score', 'value': 0});
      expect(read('/game'), {'score': 0});
    });

    test('resolves top-level and nested bindings', () async {
      model.update(DataPath('/draft'), 'hello');
      await press('setValue', {
        'path': '/a',
        'value': {'path': '/draft'},
      });
      await press('setValue', {
        'path': '/b',
        'value': {
          'title': {'path': '/draft'},
          'tags': [
            {'path': '/draft'},
            'x',
          ],
        },
      });
      expect(read('/a'), 'hello');
      expect(read('/b'), {
        'title': 'hello',
        'tags': ['hello', 'x'],
      });
    });

    test('a missing value writes null', () async {
      model.update(DataPath('/a'), 1);
      await press('setValue', {'path': '/a'});
      expect(read('/a'), isNull);
    });

    test('a binding as the target path is resolved before the call: a '
        'non-string value is an error', () async {
      model.update(DataPath('/notes'), ['a']);
      await expectLater(
        press('setValue', {
          'path': {'path': '/notes'},
          'value': 1,
        }),
        throwsFunctionError,
      );
      expect(read('/notes'), ['a']);
    });

    test(
      'a binding as the target path that holds a string is used as the '
      'path (indirection), so the bound path itself is not written',
      () async {
        model.update(DataPath('/a'), 'stored');
        await press('setValue', {
          'path': {'path': '/a'},
          'value': 1,
        });
        expect(read('/a'), 'stored');
        expect(read('/stored'), 1);
      },
    );
  });

  group('listAppend', () {
    test('appends a new list instance and notifies subscribers', () async {
      final original = <Object?>[
        {'text': 'a'},
      ];
      model.update(DataPath('/notes'), original);
      final ValueNotifier<Object?> notes = model.subscribe<Object?>(
        DataPath('/notes'),
      );
      var notified = 0;
      notes.addListener(() => notified++);

      await press('listAppend', {
        'path': '/notes',
        'item': {'text': 'b'},
      });

      expect(read('/notes'), [
        {'text': 'a'},
        {'text': 'b'},
      ]);
      expect(identical(read('/notes'), original), isFalse);
      expect(original, hasLength(1));
      expect(notified, greaterThan(0));
      notes.dispose();
    });

    test('creates the list when absent or null', () async {
      await press('listAppend', {'path': '/todos', 'item': 'first'});
      expect(read('/todos'), ['first']);

      model.update(DataPath('/nulled'), null);
      await press('listAppend', {'path': '/nulled', 'item': 1});
      expect(read('/nulled'), [1]);
    });

    test('nested bindings take the current value; clear resets', () async {
      model.update(DataPath.root, {'draft': '우유 사기', 'notes': <Object?>[]});

      await press('listAppend', {
        'path': '/notes',
        'item': {
          'text': {'path': '/draft'},
        },
        'clear': ['/draft'],
      });

      expect(read('/notes'), [
        {'text': '우유 사기'},
      ]);
      expect(read('/draft'), '');
    });

    test('top-level bound item with clear appends exactly once', () async {
      model.update(DataPath.root, {'draft': 'a', 'notes': <Object?>[]});

      await press('listAppend', {
        'path': '/notes',
        'item': {'path': '/draft'},
        'clear': ['/draft'],
      });

      expect(read('/notes'), ['a']);
      expect(read('/draft'), '');
    });

    test('clear accepts several paths and a single string', () async {
      // JSON에서 온 데이터처럼 값 타입을 열어 둔다. Map<String, String>이면
      // a2ui_core가 그 맵에 목록을 쓰지 못한다.
      model.update(DataPath.root, <String, Object?>{'title': 't', 'body': 'b'});
      await press('listAppend', {
        'path': '/notes',
        'item': {
          'title': {'path': '/title'},
          'body': {'path': '/body'},
        },
        'clear': ['/title', '/body'],
      });
      expect(read('/title'), '');
      expect(read('/body'), '');

      model.update(DataPath('/title'), 't2');
      await press('listAppend', {
        'path': '/notes',
        'item': {'path': '/title'},
        'clear': '/title',
      });
      expect(read('/title'), '');
      expect(read('/notes'), hasLength(2));
    });

    final blankItems = <String, Object?>{
      'null': null,
      'empty string': '',
      'whitespace': '  \n ',
      'bound to empty draft': {'path': '/draft'},
      'bound to missing path': {'path': '/missing'},
      'map of empty values': {'text': '', 'memo': null},
      'map bound to empty draft': {
        'text': {'path': '/draft'},
      },
      'todo with constant field but empty bound text': {
        'text': {'path': '/draft'},
        'done': false,
      },
    };
    for (final MapEntry<String, Object?> entry in blankItems.entries) {
      test(
        'blank item (${entry.key}) adds nothing and clears nothing',
        () async {
          model.update(DataPath.root, {
            'draft': '  ',
            'other': 'keep',
            'notes': ['x'],
          });

          await press('listAppend', {
            'path': '/notes',
            'item': entry.value,
            'clear': ['/other'],
          });

          expect(read('/notes'), ['x']);
          expect(read('/other'), 'keep');
          expect(read('/draft'), '  ');
        },
      );
    }

    test('missing item argument adds nothing', () async {
      await press('listAppend', {'path': '/notes'});
      expect(read('/notes'), isNull);
    });

    test('non-blank literals such as false and 0 are added', () async {
      await press('listAppend', {'path': '/l', 'item': false});
      await press('listAppend', {'path': '/l', 'item': 0});
      await press('listAppend', {
        'path': '/l',
        'item': {'text': 'x', 'done': false},
      });
      expect(read('/l'), [
        false,
        0,
        {'text': 'x', 'done': false},
      ]);
    });

    test('target that is not a list is an error', () async {
      model.update(DataPath('/notes'), 'oops');
      await expectLater(
        press('listAppend', {'path': '/notes', 'item': 'a'}),
        throwsFunctionError,
      );
      expect(read('/notes'), 'oops');
    });
  });

  group('listRemove', () {
    setUp(() => model.update(DataPath('/notes'), ['a', 'b', 'c']));

    test('removes by explicit index with a new list instance', () async {
      final Object? before = read('/notes');
      await press('listRemove', {'path': '/notes', 'index': 1});
      expect(read('/notes'), ['a', 'c']);
      expect(identical(read('/notes'), before), isFalse);
      expect(before, ['a', 'b', 'c']);
    });

    test('accepts an integral double or bound index', () async {
      model.update(DataPath('/selected'), 2);
      await press('listRemove', {
        'path': '/notes',
        'index': {'path': '/selected'},
      });
      expect(read('/notes'), ['a', 'b']);
      await press('listRemove', {'path': '/notes', 'index': 0.0});
      expect(read('/notes'), ['b']);
    });

    test('ignores out-of-range and non-integer indexes', () async {
      for (final Object index in [3, -1, 99, 1.5, 'x']) {
        await press('listRemove', {'path': '/notes', 'index': index});
      }
      expect(read('/notes'), ['a', 'b', 'c']);
    });

    test('ignores a missing list', () async {
      await press('listRemove', {'path': '/nothing', 'index': 0});
      expect(read('/nothing'), isNull);
    });

    test('inside a row: empty args remove the calling row', () async {
      final DataContext row = root.nested(DataPath('/notes/1'));
      expect(row.path, DataPath('/notes/1'));

      await press('listRemove', {}, context: row);

      expect(read('/notes'), ['a', 'c']);
    });

    test('inside a row: path of its own list needs no index', () async {
      final DataContext row = root.nested(DataPath('/notes/0'));
      await press('listRemove', {'path': '/notes'}, context: row);
      expect(read('/notes'), ['b', 'c']);
    });

    test('inside a row: explicit path and index still win', () async {
      model.update(DataPath('/other'), [1, 2]);
      final DataContext row = root.nested(DataPath('/notes/0'));
      await press('listRemove', {'path': '/other', 'index': 1}, context: row);
      expect(read('/other'), [1]);
      expect(read('/notes'), ['a', 'b', 'c']);
    });

    test('row of a map-bound List removes that key', () async {
      model.update(DataPath('/byId'), {'x': 1, 'y': 2});
      final DataContext row = root.nested(DataPath('/byId/x'));
      await press('listRemove', {}, context: row);
      expect(read('/byId'), {'y': 2});
    });

    test('outside a row: missing path or index is an error', () async {
      await expectLater(press('listRemove', {}), throwsFunctionError);
      await expectLater(
        press('listRemove', {'path': '/notes'}),
        throwsFunctionError,
      );
      await expectLater(press('listRemove', {'index': 0}), throwsFunctionError);
      expect(read('/notes'), ['a', 'b', 'c']);
    });
  });

  group('toggle', () {
    test('null becomes true, then flips', () async {
      await press('toggle', {'path': '/dark'});
      expect(read('/dark'), isTrue);
      await press('toggle', {'path': '/dark'});
      expect(read('/dark'), isFalse);
      await press('toggle', {'path': '/dark'});
      expect(read('/dark'), isTrue);
    });

    test('relative path flips a field of the calling row', () async {
      model.update(DataPath('/todos'), [
        {'text': 'a', 'done': false},
        {'text': 'b', 'done': false},
      ]);
      final ValueNotifier<Object?> done = model.subscribe<Object?>(
        DataPath('/todos/1/done'),
      );

      await press('toggle', {
        'path': 'done',
      }, context: root.nested(DataPath('/todos/1')));

      expect(read('/todos'), [
        {'text': 'a', 'done': false},
        {'text': 'b', 'done': true},
      ]);
      expect(done.value, isTrue);
      done.dispose();
    });

    test('non-boolean is an error and left unchanged', () async {
      model.update(DataPath('/dark'), 'yes');
      await expectLater(
        press('toggle', {'path': '/dark'}),
        throwsFunctionError,
      );
      expect(read('/dark'), 'yes');
    });
  });

  group('increment', () {
    test('null counts as 0 and by defaults to 1', () async {
      await press('increment', {'path': '/count'});
      expect(read('/count'), 1);
      await press('increment', {'path': '/count'});
      expect(read('/count'), 2);
    });

    test('adds by, including negative and fractional', () async {
      model.update(DataPath('/count'), 10);
      await press('increment', {'path': '/count', 'by': 5});
      expect(read('/count'), 15);
      expect(read('/count'), isA<int>());
      await press('increment', {'path': '/count', 'by': -20});
      expect(read('/count'), -5);
      await press('increment', {'path': '/count', 'by': 0.5});
      expect(read('/count'), -4.5);
    });

    test('non-number target or amount is an error', () async {
      model.update(DataPath('/count'), 'three');
      await expectLater(
        press('increment', {'path': '/count'}),
        throwsFunctionError,
      );
      model.update(DataPath('/count'), 3);
      await expectLater(
        press('increment', {'path': '/count', 'by': true}),
        throwsFunctionError,
      );
      expect(read('/count'), 3);
    });
  });

  group('one press mutates once', () {
    test('genui does not re-invoke a synchronous function that writes to a '
        'path one of its arguments is bound to', () async {
      model.update(DataPath('/count'), 1);
      await press('naiveDouble', {
        'path': '/count',
        'by': {'path': '/count'},
      });
      // Stream.value 결과가 인자 변경 알림보다 먼저 도착해 Button이 구독을
      // 끊는다. 이 순서가 바뀌면(genui 업그레이드) 이 테스트가 먼저 깨진다.
      expect(naive.runs, 1);
      expect(read('/count'), 2);
    });

    test('increment bound to its own target applies exactly once', () async {
      model.update(DataPath('/count'), 1);
      await press('increment', {
        'path': '/count',
        'by': {'path': '/count'},
      });
      expect(read('/count'), 2);
    });

    test('separate presses are never merged', () async {
      for (var i = 0; i < 3; i++) {
        await press('increment', {'path': '/count'});
      }
      expect(read('/count'), 3);
    });

    test('direct execute calls each apply', () async {
      final ClientFunction increment = dataFunctions.last;
      await increment.execute({'path': '/count'}, root).first;
      await increment.execute({'path': '/count'}, root).first;
      expect(read('/count'), 2);
    });
  });

  testWidgets('notes app adds and deletes without asking the generator', (
    tester,
  ) async {
    final generator = FakeAppGenerator([notesResponse]);
    final session = AppSession(
      catalog: BasicCatalogItems.asNoAssetCatalog().copyWith(
        newFunctions: dataFunctions,
      ),
      generator: generator,
    );
    final errors = <ConversationError>[];
    final StreamSubscription<ConversationEvent> subscription = session.events
        .listen((e) {
          if (e is ConversationError) errors.add(e);
        });
    Object? data(String path) =>
        session.contextFor('main').dataModel.getValue<Object?>(DataPath(path));

    await tester.pumpWidget(host(session));
    await session.send('메모장 만들어줘');
    await tester.pumpAndSettle();

    expect(find.text('첫 메모'), findsOneWidget);
    expect(find.text('둘째 메모'), findsOneWidget);
    expect(find.text('삭제'), findsNWidgets(2));
    expect(generator.requests, hasLength(1));

    // 빈 입력으로 추가: 아무 일도 없다.
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(data('/notes'), hasLength(2));

    // 메모 입력 후 추가.
    await tester.enterText(find.byType(TextField), '우유 사기');
    await tester.pumpAndSettle();
    expect(data('/draft'), '우유 사기');

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();

    expect(data('/notes'), [
      {'text': '첫 메모'},
      {'text': '둘째 메모'},
      {'text': '우유 사기'},
    ]);
    expect(data('/draft'), '');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    // 입력창이 비었으므로 목록의 Text 하나만 남는다.
    expect(find.text('우유 사기'), findsOneWidget);
    expect(find.text('삭제'), findsNWidgets(3));
    expect(generator.requests, hasLength(1));

    // 가운데 행 삭제: 행이 자기 인덱스를 context.path에서 알아낸다.
    await tester.tap(find.text('삭제').at(1));
    await tester.pumpAndSettle();

    expect(data('/notes'), [
      {'text': '첫 메모'},
      {'text': '우유 사기'},
    ]);
    expect(find.text('둘째 메모'), findsNothing);
    expect(find.text('첫 메모'), findsOneWidget);
    expect(find.text('우유 사기'), findsOneWidget);
    expect(find.text('삭제'), findsNWidgets(2));

    // 지운 뒤 다시 그려진 첫 행도 올바른 인덱스로 지워진다.
    await tester.tap(find.text('삭제').first);
    await tester.pumpAndSettle();
    expect(data('/notes'), [
      {'text': '우유 사기'},
    ]);

    // LLM 요청도, 오류 보고(이것도 요청으로 나간다)도 없었다.
    expect(generator.requests, hasLength(1));
    expect(errors, isEmpty);

    // testWidgets의 가짜 시간 안에서는 이 Future를 기다리면 끝나지 않는다.
    unawaited(subscription.cancel());
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
