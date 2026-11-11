import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:genui_app_maker/ai/system_prompt.dart';
import 'package:genui_app_maker/catalog/clarify_questions.dart';

void main() {
  final Catalog catalog = BasicCatalogItems.asNoAssetCatalog().copyWith(
    newItems: [clarifyQuestionsItem],
  );

  group('buildSystemPromptFragments', () {
    final String fragments = buildSystemPromptFragments().join('\n');

    test('states role and Korean output', () {
      expect(fragments, contains('app maker'));
      expect(fragments, contains('in Korean'));
    });

    test('pins one surface named main and updates it in place', () {
      expect(fragments, contains('surfaceId "main"'));
      expect(fragments, contains('Never create a second surface'));
      expect(fragments, contains('update the same surface'));
    });

    test('carries the clarifying rules C-1..C-5', () {
      expect(fragments, contains('ClarifyQuestions'));
      expect(fragments, contains('clarify_answered'));
      expect(fragments, contains('At most 3 questions'));
      expect(fragments, contains('Ask at most once per request'));
      expect(fragments, contains('If a sensible default exists, do not ask'));
      expect(fragments, contains('For an unsupported request do NOT ask'));
      expect(fragments, contains('suggest the closest thing you can build'));
    });

    test('prefers local data functions over events', () {
      for (final name in [
        'setValue',
        'listAppend',
        'listRemove',
        'toggle',
        'increment',
      ]) {
        expect(fragments, contains(name));
      }
      expect(fragments, contains('"functionCall":{"call":"listAppend"'));
      expect(fragments, contains('only when you yourself must respond'));
    });

    test('describes PhysicsGame with a pinball example bound to state', () {
      expect(fragments, contains('"component":"PhysicsGame"'));
      expect(fragments, contains('"type":"flipper"'));
      expect(fragments, contains('"statePath":"/game"'));
      expect(fragments, contains(r'${/game/score}'));
      expect(fragments, contains(r'${/game/lives}'));
    });
  });

  group('buildSystemPrompt', () {
    final String prompt = buildSystemPrompt(catalog);

    test('includes the app fragments and the catalog items', () {
      for (final String fragment in buildSystemPromptFragments()) {
        expect(prompt, contains(fragment.trim()));
      }
      for (final CatalogItem item in catalog.items) {
        expect(prompt, contains('"${item.name}"'), reason: item.name);
      }
      expect(prompt, contains('"ClarifyQuestions"'));
    });

    test('tells the model the catalog id the controller matches on', () {
      expect(catalog.catalogId, basicCatalogId);
      expect(prompt, contains('The active catalog ID is: "$basicCatalogId"'));
    });

    test('allows updating the existing surface', () {
      expect(prompt, contains('To update an existing UI'));
      expect(prompt, contains('`updateDataModel`'));
      expect(prompt, isNot(contains('DO NOT update or modify surfaces')));
    });
  });
}
