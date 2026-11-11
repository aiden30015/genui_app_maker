import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

/// 높이가 정해져 있어야 그릴 수 있는 컴포넌트 타입.
///
/// 게임 위젯은 주어진 영역에 맞춰 비율을 유지하며 그리므로, 세로로 무한한
/// 스크롤 영역 안에 둘 수 없다.
const Set<String> boundedHeightComponentTypes = {'PhysicsGame'};

/// surface 정의에 높이 제약이 필요한 컴포넌트가 있는지 본다.
///
/// - [boundedHeightComponentTypes]에 속한 타입이 있거나,
/// - `weight`를 직접 지정한 컴포넌트가 있으면(= `FlexFit.tight`. 높이가 무한한
///   Column 안에서는 Flutter가 레이아웃 예외를 던진다) true.
bool needsBoundedHeight(SurfaceDefinition? definition) {
  if (definition == null) return false;
  return definition.components.values.any(
    (Component component) =>
        boundedHeightComponentTypes.contains(component.type) ||
        component.properties['weight'] != null,
  );
}

/// 생성된 surface 하나를 주어진 영역에 맞춰 그린다. (R-1)
///
/// 부모가 높이를 정해 줘야 한다(Expanded 등).
/// - 일반 폼: 세로 스크롤 안에 자연 높이로 그린다. 키보드가 올라오거나 내용이
///   길어도 넘치지 않는다.
/// - 높이 제약이 필요한 화면([needsBoundedHeight]): 스크롤 없이 영역을 그대로
///   넘겨준다.
class SurfaceView extends StatelessWidget {
  const SurfaceView({super.key, required this.surfaceContext});

  final SurfaceContext surfaceContext;

  static const EdgeInsets _padding = EdgeInsets.all(16);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SurfaceDefinition?>(
      valueListenable: surfaceContext.definition,
      builder: (context, definition, _) {
        final Widget surface = Surface(surfaceContext: surfaceContext);
        if (needsBoundedHeight(definition)) {
          return Padding(padding: _padding, child: surface);
        }
        return SingleChildScrollView(padding: _padding, child: surface);
      },
    );
  }
}
