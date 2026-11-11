import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import 'ai/app_generator.dart';
import 'ai/app_session.dart';
import 'ai/demo_app_generator.dart';
import 'ai/firebase_app_generator.dart';
import 'ai/system_prompt.dart';
import 'app/app.dart';
import 'catalog/app_catalog.dart';
import 'firebase_options.dart';
import 'storage/shared_prefs_saved_app_repository.dart';

/// true면 Firebase 대신 정해진 응답을 쓴다: `--dart-define=DEMO_LLM=true`
const bool kDemoLlm = bool.fromEnvironment('DEMO_LLM');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDemoLlm) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  final Catalog catalog = buildAppCatalog();
  // 프롬프트는 카탈로그에서 한 번만 만든다(수천 토큰 분량의 문자열).
  final String systemPrompt = kDemoLlm ? '' : buildSystemPrompt(catalog);

  AppGenerator createGenerator() => kDemoLlm
      ? DemoAppGenerator()
      : FirebaseAppGenerator(systemPrompt: systemPrompt);

  runApp(
    GenuiAppMaker(
      repository: SharedPrefsSavedAppRepository(),
      // 실행 화면이 세션을 dispose하므로 매번 새 세션과 새 생성기를 준다.
      createSession: () =>
          AppSession(catalog: catalog, generator: createGenerator()),
    ),
  );
}
