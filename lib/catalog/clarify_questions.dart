import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// 한 번에 물을 수 있는 최대 문항 수(SPEC C-3).
const int kMaxClarifyQuestions = 3;

/// 답변 제출 시 dispatch하는 이벤트 이름.
const String kClarifyAnsweredEvent = 'clarify_answered';

final Schema _schema = S.object(
  description:
      'A card that asks the user up to $kMaxClarifyQuestions clarifying '
      'questions BEFORE building an app. Use it as the root component of the '
      'surface, only when the request is ambiguous in a way that changes the '
      'result. It has its own submit button; when the user submits, the '
      'client sends an action named "$kClarifyAnsweredEvent" whose context is '
      '{"answers": {"<question id>": "<answer text>"}}. Do not add a separate '
      'Button for submitting.',
  properties: {
    'title': S.string(
      description:
          'Short heading shown at the top of the card, in Korean. '
          'Example: "어떤 게임을 만들까요?"',
    ),
    'questions': S.list(
      description:
          'The questions to ask. At least 1, at most $kMaxClarifyQuestions.',
      minItems: 1,
      maxItems: kMaxClarifyQuestions,
      items: S.object(
        properties: {
          'id': S.string(
            description:
                'Unique key for this question. It becomes the key of the '
                'answer in the "$kClarifyAnsweredEvent" context. '
                'Example: "genre".',
          ),
          'text': S.string(
            description: 'The question shown to the user, in Korean.',
          ),
          'options': S.list(
            description:
                'Suggested answers shown as single-select chips. '
                'Provide 2 to 4 short options in Korean.',
            items: S.string(),
            maxItems: 4,
          ),
          'allowFreeText': S.boolean(
            description:
                'If true, a text field is also shown so the user can type '
                'their own answer instead of picking an option. '
                'Defaults to false.',
          ),
        },
        required: ['id', 'text', 'options'],
      ),
    ),
  },
  required: ['title', 'questions'],
);

/// 모호한 요청에 대해 사용자에게 되묻는 카드(SPEC 4장).
final CatalogItem clarifyQuestionsItem = CatalogItem(
  name: 'ClarifyQuestions',
  dataSchema: _schema,
  widgetBuilder: (CatalogItemContext itemContext) {
    final Object data = itemContext.data;
    final Map<String, Object?> json = data is Map
        ? data.cast<String, Object?>()
        : const {};
    return _ClarifyQuestionsCard(
      // 같은 id("root")로 다른 질문이 다시 오면 선택/제출 상태를 새로 시작한다.
      key: ValueKey(jsonEncode(json)),
      title: json['title'] is String ? json['title']! as String : '',
      questions: _parseQuestions(json['questions']),
      onSubmit: (Map<String, String> answers) {
        itemContext.dispatchEvent(
          UserActionEvent(
            name: kClarifyAnsweredEvent,
            sourceComponentId: itemContext.id,
            context: {'answers': answers},
          ),
        );
      },
    );
  },
  exampleData: [
    () => '''
      [
        {
          "id": "root",
          "component": "ClarifyQuestions",
          "title": "어떤 게임을 만들까요?",
          "questions": [
            {
              "id": "genre",
              "text": "장르",
              "options": ["핀볼", "벽돌깨기", "퐁"],
              "allowFreeText": true
            },
            {
              "id": "difficulty",
              "text": "난이도",
              "options": ["쉬움", "보통", "어려움"],
              "allowFreeText": false
            }
          ]
        }
      ]
    ''',
  ],
);

class _Question {
  const _Question({
    required this.id,
    required this.text,
    required this.options,
    required this.allowFreeText,
  });

  final String id;
  final String text;
  final List<String> options;
  final bool allowFreeText;
}

/// LLM이 스키마를 어겨도 화면이 깨지지 않게 느슨하게 읽는다.
List<_Question> _parseQuestions(Object? raw) {
  if (raw is! List) return const [];
  final questions = <_Question>[];
  for (final Object? entry in raw) {
    if (entry is! Map) continue;
    if (questions.length == kMaxClarifyQuestions) break;
    final Object? id = entry['id'];
    final Object? text = entry['text'];
    final Object? options = entry['options'];
    final List<String> parsedOptions = options is List
        ? [
            for (final Object? o in options)
              if (o != null && o.toString().isNotEmpty) o.toString(),
          ]
        : const [];
    questions.add(
      _Question(
        id: id is String && id.isNotEmpty ? id : 'q${questions.length + 1}',
        text: text is String ? text : '',
        options: parsedOptions,
        // 선택지가 하나도 없으면 답할 방법이 없으므로 직접 입력을 연다.
        allowFreeText: entry['allowFreeText'] == true || parsedOptions.isEmpty,
      ),
    );
  }
  return questions;
}

class _ClarifyQuestionsCard extends StatefulWidget {
  const _ClarifyQuestionsCard({
    super.key,
    required this.title,
    required this.questions,
    required this.onSubmit,
  });

  final String title;
  final List<_Question> questions;
  final void Function(Map<String, String> answers) onSubmit;

  @override
  State<_ClarifyQuestionsCard> createState() => _ClarifyQuestionsCardState();
}

class _ClarifyQuestionsCardState extends State<_ClarifyQuestionsCard> {
  /// 문항 id → 선택한 칩.
  final Map<String, String> _selected = {};

  /// 문항 id → 직접 입력 컨트롤러.
  late final Map<String, TextEditingController> _controllers = {
    for (final _Question q in widget.questions)
      if (q.allowFreeText) q.id: TextEditingController(),
  };

  bool _submitted = false;

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 직접 입력이 있으면 그 값, 없으면 선택한 칩. 둘 다 없으면 null.
  String? _answerFor(_Question q) {
    final String typed = _controllers[q.id]?.text.trim() ?? '';
    if (typed.isNotEmpty) return typed;
    return _selected[q.id];
  }

  bool get _allAnswered =>
      widget.questions.isNotEmpty &&
      widget.questions.every((q) => _answerFor(q) != null);

  void _selectOption(_Question q, String option, bool selected) {
    setState(() {
      if (selected) {
        _selected[q.id] = option;
        _controllers[q.id]?.clear();
      } else {
        _selected.remove(q.id);
      }
    });
  }

  void _onFreeTextChanged(_Question q, String value) {
    setState(() {
      if (value.trim().isNotEmpty) _selected.remove(q.id);
    });
  }

  void _submit() {
    if (_submitted || !_allAnswered) return;
    final answers = <String, String>{
      for (final _Question q in widget.questions) q.id: _answerFor(q)!,
    };
    setState(() => _submitted = true);
    widget.onSubmit(answers);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title.isNotEmpty)
              Text(widget.title, style: textTheme.titleLarge),
            for (final _Question q in widget.questions) ...[
              const SizedBox(height: 16),
              if (q.text.isNotEmpty) Text(q.text, style: textTheme.titleSmall),
              if (q.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final String option in q.options)
                      ChoiceChip(
                        label: Text(option),
                        selected: _selected[q.id] == option,
                        onSelected: _submitted
                            ? null
                            : (selected) => _selectOption(q, option, selected),
                      ),
                  ],
                ),
              ],
              if (q.allowFreeText) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _controllers[q.id],
                  enabled: !_submitted,
                  onChanged: (value) => _onFreeTextChanged(q, value),
                  decoration: const InputDecoration(
                    labelText: '직접 입력',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitted || !_allAnswered ? null : _submit,
              child: Text(_submitted ? '답변을 보냈어요' : '만들기'),
            ),
          ],
        ),
      ),
    );
  }
}
