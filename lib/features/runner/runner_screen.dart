import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../../ai/app_session.dart';
import '../../storage/saved_app.dart';
import '../../storage/saved_app_repository.dart';
import 'runner_widgets.dart';
import 'surface_view.dart';

/// 기본 저장 이름의 최대 길이.
const int _defaultNameMaxLength = 30;

/// 생성된 앱을 띄우고, 수정·저장하는 화면. (SPEC 3.2)
class RunnerScreen extends StatefulWidget {
  /// 새 프롬프트로 앱을 만든다.
  const RunnerScreen.create({
    super.key,
    required String this.prompt,
    required this.repository,
    required this.createSession,
  }) : savedApp = null;

  /// 저장된 앱을 복원한다. 생성 요청은 보내지 않는다.
  const RunnerScreen.restore({
    super.key,
    required SavedApp this.savedApp,
    required this.repository,
    required this.createSession,
  }) : prompt = null;

  final String? prompt;
  final SavedApp? savedApp;
  final SavedAppRepository repository;
  final AppSession Function() createSession;

  @override
  State<RunnerScreen> createState() => _RunnerScreenState();
}

class _RunnerScreenState extends State<RunnerScreen> {
  late final AppSession _session;
  late final StreamSubscription<ConversationEvent> _events;
  late final AppLifecycleListener _lifecycle;
  late final String _firstPrompt;
  final TextEditingController _input = TextEditingController();

  /// null이 아니면 이미 저장된 앱이다. 이후 저장은 같은 id를 덮어쓴다.
  SavedApp? _saved;

  /// 재시도 때 다시 보낼, 사용자가 마지막으로 입력한 요청.
  String? _lastRequest;
  Object? _error;

  /// 이번 응답에서 모델이 보낸 일반 텍스트 조각을 이어 붙인 것.
  ///
  /// `ConversationState.latestText`는 마지막 조각만 담는데, JSON 블록 사이의
  /// 공백도 조각으로 오기 때문에 그대로 쓰면 안내문이 공백으로 덮인다.
  String _modelText = '';

  /// 복원 중 재생되는 예전 응답의 텍스트는 모으지 않는다.
  bool _collectText = false;

  /// 사용자가 닫은 안내 텍스트. 새 텍스트가 오면 다시 보인다.
  String? _dismissedText;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _session = widget.createSession();
    _events = _session.events.listen(_onEvent);
    // 뒤로 가기 없이 앱이 백그라운드로 가거나 종료돼도 내용이 남게 한다. (S-4)
    _lifecycle = AppLifecycleListener(onPause: _saveOnPause);

    final SavedApp? savedApp = widget.savedApp;
    if (savedApp != null) {
      _saved = savedApp;
      _firstPrompt = savedApp.prompt;
      _session.restore(savedApp);
    } else {
      _firstPrompt = widget.prompt!.trim();
      _lastRequest = _firstPrompt;
      _dispatch(_firstPrompt);
    }
  }

  /// 이미 저장된 앱만 조용히 덮어쓴다. 응답 중에는 원문이 반쯤 온 상태라 건너뛴다.
  void _saveOnPause() {
    if (_saved == null || _session.state.value.isWaiting) return;
    _persist().catchError((Object _) {});
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _events.cancel();
    _input.dispose();
    _session.dispose();
    super.dispose();
  }

  void _onEvent(ConversationEvent event) {
    if (!mounted) return;
    switch (event) {
      case ConversationWaiting():
        // 새 요청이 시작되면 이전 응답의 안내 텍스트를 지운다.
        setState(() {
          _collectText = true;
          _modelText = '';
          _dismissedText = null;
        });
      case ConversationContentReceived(:final text):
        if (_collectText) setState(() => _modelText += text);
      case ConversationError(:final error):
        setState(() => _error = error);
      default:
        break;
    }
  }

  void _send(String text) {
    setState(() {
      _error = null;
      _lastRequest = text;
    });
    _dispatch(text);
  }

  Future<void> _dispatch(String text) async {
    try {
      await _session.send(text);
    } catch (error) {
      // 응답을 기다리는 중에 화면을 나가면 세션이 먼저 정리될 수 있다.
      if (mounted) setState(() => _error = error);
    }
  }

  void _submitInput() {
    final String text = _input.text.trim();
    if (text.isEmpty || _session.state.value.isWaiting) return;
    _input.clear();
    _send(text);
  }

  void _retry() {
    final String? last = _lastRequest;
    if (last != null) _send(last);
  }

  String get _defaultName {
    final String prompt = _firstPrompt;
    if (prompt.length <= _defaultNameMaxLength) return prompt;
    return prompt.substring(0, _defaultNameMaxLength);
  }

  /// 현재 화면 정의(원문)와 데이터를 저장소에 쓴다.
  Future<void> _persist({String? name}) async {
    final SavedApp? saved = _saved;
    final now = DateTime.now();
    final app = SavedApp(
      id: saved?.id ?? now.microsecondsSinceEpoch.toString(),
      name: name ?? saved?.name ?? _defaultName,
      prompt: _firstPrompt,
      createdAt: saved?.createdAt ?? now,
      transcript: _session.transcript,
      data: _session.dataSnapshot(),
    );
    await widget.repository.save(app);
    if (mounted) setState(() => _saved = app);
  }

  Future<void> _onSavePressed() async {
    String? name;
    if (_saved == null) {
      final String? entered = await showDialog<String>(
        context: context,
        builder: (_) => SaveNameDialog(initialName: _defaultName),
      );
      if (entered == null || !mounted) return;
      name = entered.trim().isEmpty ? _defaultName : entered.trim();
    }
    try {
      await _persist(name: name);
      _showSnackBar('저장했습니다.');
    } catch (_) {
      _showSnackBar('저장하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 뒤로 가기가 막혔을 때 불린다. (R-7, S-4)
  Future<void> _onPopBlocked() async {
    if (_leaving) return;
    _leaving = true;
    try {
      bool leave;
      if (_saved != null) {
        // 저장된 앱은 묻지 않고 현재 상태를 저장한다.
        try {
          await _persist();
          leave = true;
        } catch (_) {
          leave = await _confirmLeave(
            title: '저장하지 못했습니다',
            message: '바뀐 내용을 저장하지 못했습니다. 그래도 나갈까요?',
          );
        }
      } else {
        leave = await _confirmLeave(
          title: '저장하지 않고 나갈까요?',
          message: '만든 앱을 저장하지 않으면 사라집니다.',
        );
      }
      if (leave && mounted) Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  Future<bool> _confirmLeave({
    required String title,
    required String message,
  }) async {
    if (!mounted) return false;
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('계속 사용'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConversationState>(
      valueListenable: _session.state,
      builder: (context, state, _) {
        final bool hasSurface = state.surfaces.isNotEmpty;
        final String text = _modelText.trim();
        final Object? error = _error;
        return PopScope(
          // 잃을 것이 없을 때만 바로 나간다.
          canPop: _saved == null && !hasSurface,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onPopBlocked();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _saved?.name ?? _firstPrompt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: '저장',
                  icon: const Icon(Icons.save_outlined),
                  onPressed: hasSurface && !state.isWaiting
                      ? _onSavePressed
                      : null,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: state.isWaiting
                    ? const LinearProgressIndicator(minHeight: 4)
                    : const SizedBox(height: 4),
              ),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (text.isNotEmpty && text != _dismissedText)
                  ModelTextBanner(
                    text: text,
                    onDismiss: () => setState(() => _dismissedText = text),
                  ),
                if (error != null)
                  ErrorPanel(
                    error: error,
                    onRetry: _lastRequest != null && !state.isWaiting
                        ? _retry
                        : null,
                  ),
                if (hasSurface)
                  for (final String id in state.surfaces)
                    Expanded(
                      child: SurfaceView(
                        key: ValueKey(id),
                        surfaceContext: _session.contextFor(id),
                      ),
                    )
                else
                  Expanded(child: _buildPlaceholder(state, error != null)),
                RequestInputRow(
                  controller: _input,
                  enabled: !state.isWaiting,
                  onSubmit: _submitInput,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(ConversationState state, bool hasError) {
    final ThemeData theme = Theme.of(context);
    if (state.isWaiting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('만드는 중…', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }
    if (hasError) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '아직 만들어진 화면이 없습니다.\n아래에 만들고 싶은 내용을 입력해 보세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
