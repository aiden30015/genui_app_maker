import 'package:flutter/material.dart';

import 'error_message.dart';

/// 모델이 보낸 일반 텍스트. 높이를 제한하고 닫을 수 있다. (R-3)
class ModelTextBanner extends StatelessWidget {
  const ModelTextBanner({
    super.key,
    required this.text,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 96),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
                child: Text(
                  text,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ),
            IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close, size: 20),
              color: scheme.onSecondaryContainer,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// 오류 안내와 재시도 버튼. (R-6)
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;

  /// 다시 보낼 요청이 없으면 null.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    describeError(error),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    errorDetail(error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

/// 하단 수정 요청 입력줄. (R-4)
class RequestInputRow extends StatelessWidget {
  const RequestInputRow({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    hintText: '수정할 내용을 입력하세요',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: '보내기',
                icon: const Icon(Icons.send),
                onPressed: enabled ? onSubmit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 저장할 이름을 묻는 대화상자. 확인하면 입력한 이름을 돌려준다. (R-5)
class SaveNameDialog extends StatefulWidget {
  const SaveNameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<SaveNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_name.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('앱 저장'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 40,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: '앱 이름'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('저장')),
      ],
    );
  }
}
