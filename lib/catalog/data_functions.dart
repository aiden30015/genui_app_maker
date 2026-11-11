import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// 데이터 모델을 기기에서 바로 바꾸는 함수들. (SPEC 5.2)
///
/// Button의 `functionCall` 액션으로 호출되며 LLM 왕복이 없다.
/// `BasicCatalogItems.asNoAssetCatalog().copyWith(newFunctions: dataFunctions)`
/// 로 등록한다.
final List<ClientFunction> dataFunctions = List.unmodifiable(<ClientFunction>[
  const _SetValueFunction(),
  const _ListAppendFunction(),
  const _ListRemoveFunction(),
  const _ToggleFunction(),
  const _IncrementFunction(),
]);

const String _pathRule =
    'MUST be a plain string holding a data model path, e.g. "/notes" '
    '(absolute) or "done" (relative to the current List row). NEVER pass a '
    '{"path": ...} binding object here: bindings are replaced by the stored '
    'value before the function runs, so the function would not know where '
    'to write.';

abstract class _DataFunction extends SynchronousClientFunction {
  const _DataFunction();

  @override
  ClientFunctionReturnType get returnType => ClientFunctionReturnType.empty;

  /// 데이터 모델을 바꾸고 `null`을 돌려준다.
  ///
  /// [SynchronousClientFunction.execute]가 이 값을 `Stream.value`로 즉시
  /// 내보내므로 Button의 10초 타임아웃에 걸리지 않는다.
  @override
  Object? executeSync(JsonMap args, ExecutionContext context) {
    apply(args, context);
    return null;
  }

  /// 데이터 모델을 실제로 바꾼다.
  void apply(JsonMap args, ExecutionContext context);

  /// 필수 `path` 인자를 읽는다. 문자열이 아니면 LLM이 고칠 수 있게 오류를 낸다.
  DataPath targetPath(JsonMap args) {
    final Object? path = args['path'];
    if (path is String && path.isNotEmpty) return DataPath(path);
    throw A2uiFunctionException(
      '"path" must be a literal path string such as "/notes", not a '
      '{"path": ...} binding and not empty. Got: ${path.runtimeType}.',
      functionName: name,
      argumentKey: 'path',
    );
  }
}

bool _isBlank(Object? value) =>
    value == null || (value is String && value.trim().isEmpty);

/// 키가 `path` 하나뿐이고 값이 문자열인 맵만 바인딩으로 본다.
bool _isBinding(Object? value) =>
    value is Map && value.length == 1 && value['path'] is String;

/// 중첩된 `{"path": ...}` 바인딩을 현재 값으로 바꾼 **새** 값을 만든다.
///
/// genui는 최상위 인자만 풀어 주므로 `{"text": {"path": "/draft"}}` 같은
/// 중첩 바인딩은 여기서 직접 푼다. 풀린 값은 [boundValues]에 모은다.
Object? _resolveBindings(
  Object? value,
  ExecutionContext context, [
  List<Object?>? boundValues,
]) {
  if (_isBinding(value)) {
    final Object? resolved = context.getValue<Object?>(
      DataPath((value! as Map)['path'] as String),
    );
    boundValues?.add(resolved);
    return resolved;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key.toString(): _resolveBindings(
          entry.value,
          context,
          boundValues,
        ),
    };
  }
  if (value is List) {
    return <Object?>[
      for (final Object? element in value)
        _resolveBindings(element, context, boundValues),
    ];
  }
  return value;
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final double v when v == v.truncateToDouble() => v.toInt(),
  final String v => int.tryParse(v.trim()),
  _ => null,
};

class _SetValueFunction extends _DataFunction {
  const _SetValueFunction();

  @override
  String get name => 'setValue';

  @override
  String get description =>
      'Writes a value into the data model on the device, without contacting '
      'the AI. Use as a Button action for local state changes such as '
      'selecting a tab, resetting a counter or clearing a field. Example: '
      '{"functionCall": {"call": "setValue", "args": {"path": "/filter", '
      '"value": "done"}}}';

  @override
  Schema get argumentSchema => S.object(
    properties: {
      'path': S.string(description: 'Where to write. $_pathRule'),
      'value': S.any(
        description:
            'The value to store: a literal, or a {"path": ...} binding (also '
            'allowed nested inside an object or array) which is replaced by '
            'the value currently stored at that path.',
      ),
    },
    required: ['path', 'value'],
  );

  @override
  void apply(JsonMap args, ExecutionContext context) {
    context.update(targetPath(args), _resolveBindings(args['value'], context));
  }
}

class _ListAppendFunction extends _DataFunction {
  const _ListAppendFunction();

  @override
  String get name => 'listAppend';

  @override
  String get description =>
      'Appends an item to the end of a list in the data model on the device, '
      'without contacting the AI. The list is created if it does not exist. '
      'Use as the action of an "add" Button: bind a TextField to a draft path, '
      'build the item from that draft and list the draft path in "clear" so '
      'the input is emptied afterwards. Nothing is added (and nothing is '
      'cleared) when the item is blank: null, an empty or whitespace-only '
      'string, an object whose values are all empty, or an object whose '
      'bound values are all empty. Example: {"functionCall": {"call": '
      '"listAppend", "args": {"path": "/notes", "item": {"text": {"path": '
      '"/draft"}}, "clear": ["/draft"]}}}';

  @override
  Schema get argumentSchema => S.object(
    properties: {
      'path': S.string(description: 'The list to append to. $_pathRule'),
      'item': S.any(
        description:
            'The new item. Usually an object whose fields are literals or '
            '{"path": ...} bindings, e.g. {"text": {"path": "/draft"}, '
            '"done": false}. Bindings are replaced by the value stored at '
            'that path at the moment the button is pressed.',
      ),
      'clear': S.list(
        items: S.string(),
        description:
            'Optional. Plain path strings that are set to an empty string '
            'after the item was added, e.g. ["/draft"] to empty the input.',
      ),
    },
    required: ['path', 'item'],
  );

  @override
  void apply(JsonMap args, ExecutionContext context) {
    final DataPath path = targetPath(args);
    final boundValues = <Object?>[];
    final Object? item = _resolveBindings(args['item'], context, boundValues);

    final bool blank =
        _isBlank(item) ||
        (item is Map &&
            (item.values.every(_isBlank) ||
                (boundValues.isNotEmpty && boundValues.every(_isBlank))));
    if (blank) return;

    final Object? current = context.getValue<Object?>(path);
    if (current != null && current is! List) {
      throw A2uiFunctionException(
        'The value at "$path" is not a list.',
        functionName: name,
        argumentKey: 'path',
      );
    }
    context.update(path, <Object?>[...?(current as List?), item]);

    final Object? clear = args['clear'];
    final Iterable<Object?> clearPaths = switch (clear) {
      final List<Object?> list => list,
      final String single => [single],
      _ => const [],
    };
    for (final Object? clearPath in clearPaths) {
      if (clearPath is String && clearPath.isNotEmpty) {
        context.update(DataPath(clearPath), '');
      }
    }
  }
}

class _ListRemoveFunction extends _DataFunction {
  const _ListRemoveFunction();

  @override
  String get name => 'listRemove';

  @override
  String get description =>
      'Removes one item from a list in the data model on the device, without '
      'contacting the AI. Inside the row template of a List, call it with '
      'empty args to remove the row that contains the button: '
      '{"functionCall": {"call": "listRemove", "args": {}}}. Outside a row '
      'template pass both the list path and the index: {"functionCall": '
      '{"call": "listRemove", "args": {"path": "/notes", "index": 0}}}. An '
      'index outside the list is ignored.';

  @override
  Schema get argumentSchema => S.object(
    properties: {
      'path': S.string(
        description:
            'The list to remove from. Optional inside a List row template '
            '(defaults to the list the row belongs to). $_pathRule',
      ),
      'index': S.integer(
        description:
            'Zero-based position of the item to remove. Optional inside a '
            'List row template (defaults to the row containing the button).',
      ),
    },
  );

  @override
  void apply(JsonMap args, ExecutionContext context) {
    final Object? pathArg = args['path'];
    final Object? indexArg = args['index'];
    final DataPath row = context.path;
    final bool insideRow = row.segments.isNotEmpty;

    final DataPath listPath;
    if (pathArg == null) {
      if (!insideRow) {
        throw A2uiFunctionException(
          '"path" is required when the button is not inside a List row '
          'template.',
          functionName: name,
          argumentKey: 'path',
        );
      }
      listPath = row.dirname;
    } else {
      listPath = context.resolvePath(targetPath(args));
    }

    final Object? key;
    if (indexArg != null) {
      key = indexArg;
    } else if (insideRow && row.dirname == listPath) {
      key = row.basename;
    } else {
      throw A2uiFunctionException(
        '"index" is required unless the button is inside a row template of '
        'the List bound to "$listPath".',
        functionName: name,
        argumentKey: 'index',
      );
    }

    final Object? current = context.getValue<Object?>(listPath);
    if (current is List) {
      final int? index = _asInt(key);
      if (index == null || index < 0 || index >= current.length) return;
      context.update(listPath, <Object?>[
        for (var i = 0; i < current.length; i++)
          if (i != index) current[i],
      ]);
    } else if (current is Map) {
      // List 템플릿은 맵에도 바인딩된다. 이때 행의 키는 맵의 키다.
      final mapKey = key.toString();
      if (!current.containsKey(mapKey)) return;
      context.update(listPath, <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in current.entries)
          if (entry.key != mapKey) entry.key.toString(): entry.value,
      });
    }
  }
}

class _ToggleFunction extends _DataFunction {
  const _ToggleFunction();

  @override
  String get name => 'toggle';

  @override
  String get description =>
      'Flips a boolean in the data model on the device, without contacting '
      'the AI (true becomes false, false or missing becomes true). Inside a '
      'List row template use a relative path to flip a field of that row. '
      'Example: {"functionCall": {"call": "toggle", "args": {"path": '
      '"done"}}}';

  @override
  Schema get argumentSchema => S.object(
    properties: {
      'path': S.string(description: 'The boolean to flip. $_pathRule'),
    },
    required: ['path'],
  );

  @override
  void apply(JsonMap args, ExecutionContext context) {
    final DataPath path = targetPath(args);
    final Object? current = context.getValue<Object?>(path);
    if (current != null && current is! bool) {
      throw A2uiFunctionException(
        'The value at "$path" is not a boolean.',
        functionName: name,
        argumentKey: 'path',
      );
    }
    context.update(path, !((current as bool?) ?? false));
  }
}

class _IncrementFunction extends _DataFunction {
  const _IncrementFunction();

  @override
  String get name => 'increment';

  @override
  String get description =>
      'Adds a number to a number in the data model on the device, without '
      'contacting the AI. Use for counters and scoreboards; a missing value '
      'counts as 0 and a negative "by" subtracts. Example: {"functionCall": '
      '{"call": "increment", "args": {"path": "/count", "by": 1}}}';

  @override
  Schema get argumentSchema => S.object(
    properties: {
      'path': S.string(description: 'The number to change. $_pathRule'),
      'by': S.number(
        description: 'Optional amount to add. Defaults to 1. May be negative.',
      ),
    },
    required: ['path'],
  );

  @override
  void apply(JsonMap args, ExecutionContext context) {
    final DataPath path = targetPath(args);
    final Object? byArg = args['by'];
    final num? by = switch (byArg) {
      null => 1,
      final num v => v,
      final String v => num.tryParse(v.trim()),
      _ => null,
    };
    if (by == null) {
      throw A2uiFunctionException(
        '"by" must be a number.',
        functionName: name,
        argumentKey: 'by',
      );
    }
    final Object? current = context.getValue<Object?>(path);
    if (current != null && current is! num) {
      throw A2uiFunctionException(
        'The value at "$path" is not a number.',
        functionName: name,
        argumentKey: 'path',
      );
    }
    context.update(path, ((current as num?) ?? 0) + by);
  }
}
