import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/firebase_app_generator.dart';

/// `SurfaceController.handleUiEvent`가 만드는 것과 같은 메시지.
ChatMessage uiEventMessage(UserActionEvent event) => ChatMessage.user(
  '',
  parts: [
    UiInteractionPart.create(
      jsonEncode({'version': 'v0.9', 'action': event.toMap()}),
    ),
  ],
);

void main() {
  group('chatMessageToPromptText', () {
    test('plain user prompt is passed through unchanged', () {
      expect(chatMessageToPromptText(ChatMessage.user('메모장 만들어줘')), '메모장 만들어줘');
    });

    test('UI event keeps the event name and context as JSON', () {
      final String text = chatMessageToPromptText(
        uiEventMessage(
          UserActionEvent(
            surfaceId: 'main',
            name: 'clarify_answered',
            sourceComponentId: 'root',
            context: {
              'answers': {'genre': '핀볼'},
            },
          ),
        ),
      );

      expect(text, startsWith('[UI event]'));
      final decoded = jsonDecode(text.substring(text.indexOf('{'))) as Map;
      expect(decoded['version'], 'v0.9');
      final action = decoded['action'] as Map;
      expect(action['name'], 'clarify_answered');
      expect(action['surfaceId'], 'main');
      expect(action['sourceComponentId'], 'root');
      expect(action['context'], {
        'answers': {'genre': '핀볼'},
      });
    });

    test('client error is labelled as an error', () {
      final String text = chatMessageToPromptText(
        ChatMessage.user(
          '',
          parts: [
            UiInteractionPart.create(
              jsonEncode({
                'version': 'v0.9',
                'error': {'code': 'VALIDATION_FAILED', 'message': 'bad root'},
              }),
            ),
          ],
        ),
      );

      expect(text, startsWith('[UI error]'));
      expect(text, contains('VALIDATION_FAILED'));
      expect(text, contains('bad root'));
    });

    test('text and event parts are both kept, in order', () {
      final String text = chatMessageToPromptText(
        ChatMessage.user(
          '저장 눌렀어',
          parts: [
            UiInteractionPart.create(
              '{"version":"v0.9","action":{"name":"x"}}',
            ),
          ],
        ),
      );

      expect(text.indexOf('저장 눌렀어'), 0);
      expect(text, contains('"name":"x"'));
    });

    test('unknown binary parts are not inlined', () {
      final String text = chatMessageToPromptText(
        ChatMessage.user(
          '',
          parts: [
            DataPart(Uint8List.fromList([1, 2, 3]), mimeType: 'image/png'),
          ],
        ),
      );

      expect(text, '[attachment omitted: image/png]');
    });

    test('message without content becomes empty text', () {
      expect(chatMessageToPromptText(ChatMessage.user('')), isEmpty);
    });
  });

  group('FirebaseAppGenerator', () {
    late List<({String systemPrompt, String model, List<HistoryTurn> history})>
    starts;
    late List<String> sent;

    ChatSend fakeStarter({
      required String systemPrompt,
      required String model,
      required List<HistoryTurn> history,
    }) {
      starts.add((systemPrompt: systemPrompt, model: model, history: history));
      return (String text) {
        sent.add(text);
        return Stream.fromIterable(['a', 'b']);
      };
    }

    setUp(() {
      starts = [];
      sent = [];
    });

    test('opens the chat lazily, once, with the default model', () async {
      final generator = FirebaseAppGenerator(
        systemPrompt: 'SYS',
        chatStarter: fakeStarter,
      );
      expect(starts, isEmpty);

      expect(await generator.generate(ChatMessage.user('하나')).toList(), [
        'a',
        'b',
      ]);
      await generator.generate(ChatMessage.user('둘')).drain<void>();

      expect(starts, hasLength(1));
      expect(starts.single.systemPrompt, 'SYS');
      expect(starts.single.model, kGeminiModel);
      expect(starts.single.history, isEmpty);
      expect(sent, ['하나', '둘']);
    });

    test('primeHistory seeds a user turn then a model turn', () async {
      final generator = FirebaseAppGenerator(
        systemPrompt: 'SYS',
        model: 'custom-model',
        chatStarter: fakeStarter,
      )..primeHistory(prompt: '메모장 만들어줘', transcript: 'createSurface...');

      await generator.generate(ChatMessage.user('제목 바꿔줘')).drain<void>();

      expect(starts.single.model, 'custom-model');
      expect(starts.single.history, [
        (isModel: false, text: '메모장 만들어줘'),
        (isModel: true, text: 'createSurface...'),
      ]);
      expect(
        () => generator.primeHistory(prompt: 'p', transcript: 't'),
        throwsStateError,
      );
    });

    test('UI events reach the chat as serialised text', () async {
      final generator = FirebaseAppGenerator(
        systemPrompt: 'SYS',
        chatStarter: fakeStarter,
      );

      await generator
          .generate(
            uiEventMessage(
              UserActionEvent(name: 'save_note', sourceComponentId: 'save'),
            ),
          )
          .drain<void>();

      expect(sent.single, contains('"name":"save_note"'));
    });

    test('empty messages are not sent', () async {
      final generator = FirebaseAppGenerator(
        systemPrompt: 'SYS',
        chatStarter: fakeStarter,
      );

      expect(await generator.generate(ChatMessage.user('')).toList(), isEmpty);
      expect(starts, isEmpty);
    });

    test('chat failures surface as stream errors', () async {
      final generator = FirebaseAppGenerator(
        systemPrompt: 'SYS',
        chatStarter:
            ({
              required String systemPrompt,
              required String model,
              required List<HistoryTurn> history,
            }) =>
                (String text) => Stream.error(StateError('offline')),
      );

      await expectLater(
        generator.generate(ChatMessage.user('하나')),
        emitsError(isStateError),
      );
    });
  });
}
