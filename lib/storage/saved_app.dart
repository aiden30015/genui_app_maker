import 'package:flutter/foundation.dart';

/// 저장된 앱 하나. (SPEC 7장)
@immutable
class SavedApp {
  const SavedApp({
    required this.id,
    required this.name,
    required this.prompt,
    required this.createdAt,
    required this.transcript,
    required this.data,
  });

  factory SavedApp.fromJson(Map<String, Object?> json) => SavedApp(
    id: json['id']! as String,
    name: json['name']! as String,
    prompt: json['prompt']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    transcript: json['transcript']! as String,
    data: (json['data'] as Map<String, Object?>?) ?? const {},
  );

  final String id;
  final String name;

  /// 처음 입력한 프롬프트.
  final String prompt;
  final DateTime createdAt;

  /// 모델이 보낸 A2UI 응답 원문. 복원 시 재생한다.
  final String transcript;

  /// surfaceId → 저장 시점의 데이터 모델.
  final Map<String, Object?> data;

  SavedApp copyWith({
    String? name,
    String? transcript,
    Map<String, Object?>? data,
  }) => SavedApp(
    id: id,
    name: name ?? this.name,
    prompt: prompt,
    createdAt: createdAt,
    transcript: transcript ?? this.transcript,
    data: data ?? this.data,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'createdAt': createdAt.toIso8601String(),
    'transcript': transcript,
    'data': data,
  };
}
