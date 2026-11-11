import 'package:flutter/material.dart';

import '../ai/app_session.dart';
import '../features/home/home_screen.dart';
import '../storage/saved_app_repository.dart';
import 'theme.dart';

/// 앱 루트. 의존성은 바깥(main.dart)에서 주입한다.
class GenuiAppMaker extends StatelessWidget {
  const GenuiAppMaker({
    super.key,
    required this.repository,
    required this.createSession,
  });

  final SavedAppRepository repository;

  /// 실행 화면을 열 때마다 새 세션을 돌려주는 팩토리.
  final AppSession Function() createSession;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '앱 만들기',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: HomeScreen(repository: repository, createSession: createSession),
    );
  }
}
