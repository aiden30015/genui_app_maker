import 'package:flutter/material.dart';

import '../../ai/app_session.dart';
import '../../storage/saved_app.dart';
import '../../storage/saved_app_repository.dart';
import '../runner/runner_screen.dart';

/// 홈 화면의 예시 프롬프트. (H-2)
const List<String> examplePrompts = ['메모장 만들어줘', '핀볼 게임 만들어줘', '할 일 목록 만들어줘'];

/// `2026.11.10` 형식. (intl 없이 직접 만든다)
String formatCreatedDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)}';
}

/// 프롬프트 입력과 저장된 앱 목록. (SPEC 3.1)
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.createSession,
  });

  final SavedAppRepository repository;
  final AppSession Function() createSession;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _prompt = TextEditingController();

  List<SavedApp>? _apps;
  bool _loadFailed = false;

  /// 늦게 도착한 이전 요청의 결과가 최신 목록을 덮어쓰지 않게 한다.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int token = ++_loadToken;
    setState(() => _loadFailed = false);
    try {
      final List<SavedApp> apps = await widget.repository.list();
      if (!mounted || token != _loadToken) return;
      setState(() => _apps = apps);
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _apps = null;
        _loadFailed = true;
      });
    }
  }

  void _submitPrompt() {
    final String prompt = _prompt.text.trim();
    if (prompt.isEmpty) return;
    _prompt.clear();
    _startGeneration(prompt);
  }

  void _startGeneration(String prompt) {
    FocusScope.of(context).unfocus();
    _openRunner(
      RunnerScreen.create(
        prompt: prompt,
        repository: widget.repository,
        createSession: widget.createSession,
      ),
    );
  }

  void _openSaved(SavedApp app) {
    _openRunner(
      RunnerScreen.restore(
        savedApp: app,
        repository: widget.repository,
        createSession: widget.createSession,
      ),
    );
  }

  Future<void> _openRunner(RunnerScreen screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  Future<void> _confirmDelete(SavedApp app) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('앱 삭제'),
        content: Text('"${app.name}"을(를) 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.delete(app.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('삭제하지 못했습니다. 다시 시도해 주세요.')));
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('앱 만들기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('어떤 앱을 만들까요?', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _prompt,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitPrompt(),
              decoration: const InputDecoration(
                hintText: '예: 메모장 만들어줘',
                labelText: '만들고 싶은 앱',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _submitPrompt,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('만들기'),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final String example in examplePrompts)
                  ActionChip(
                    label: Text(example),
                    onPressed: () => _startGeneration(example),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text('내 앱', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._buildSavedApps(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSavedApps(BuildContext context) {
    final List<SavedApp>? apps = _apps;
    if (_loadFailed) {
      return [
        _Notice(
          icon: Icons.error_outline,
          message: '저장된 앱을 불러오지 못했습니다.',
          action: TextButton(onPressed: _load, child: const Text('다시 시도')),
        ),
      ];
    }
    if (apps == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (apps.isEmpty) {
      return const [
        _Notice(
          icon: Icons.apps_outlined,
          message: '아직 저장된 앱이 없습니다.\n위에서 만들고 싶은 앱을 입력해 보세요.',
        ),
      ];
    }
    return [
      for (final SavedApp app in apps)
        Card(
          key: ValueKey(app.id),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatCreatedDate(app.createdAt)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSaved(app),
            onLongPress: () => _confirmDelete(app),
          ),
        ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
