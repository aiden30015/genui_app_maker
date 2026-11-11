/// 오류를 사용자에게 보여 줄 한국어 안내문으로 바꾼다. (R-6)
String describeError(Object error) {
  final String raw = error.toString().toLowerCase();
  bool has(List<String> needles) => needles.any(raw.contains);

  if (has(['quota', '429', 'resource-exhausted', 'resource_exhausted'])) {
    return '요청 한도를 넘었습니다. 잠시 뒤에 다시 시도해 주세요.';
  }
  if (has([
    'socketexception',
    'failed host lookup',
    'network',
    'connection',
    'timeout',
    'timed out',
    'offline',
    'unavailable',
  ])) {
    return '네트워크에 연결할 수 없습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.';
  }
  return '앱을 만드는 중에 문제가 생겼습니다. 다시 시도해 주세요.';
}

/// 안내문 아래에 작게 붙일 원인 한 줄.
String errorDetail(Object error, {int maxLength = 120}) {
  final String oneLine = error
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (oneLine.length <= maxLength) return oneLine;
  return '${oneLine.substring(0, maxLength)}…';
}
