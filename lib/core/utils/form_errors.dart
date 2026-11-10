import 'package:flutter/widgets.dart';

/// Scrolls a long form so its topmost error is in view. Called after a failed
/// submit: otherwise the errors can all sit above the screen while the person
/// looks at a button that seemed to do nothing. [alsoInvalid] are inputs
/// outside the [Form]'s fields that are showing an error of their own.
void revealFirstError(
  GlobalKey<FormState> form, {
  List<BuildContext?> alsoInvalid = const [],
}) {
  final root = form.currentContext;
  if (root == null) return;
  final candidates = <BuildContext>[for (final c in alsoInvalid) ?c];
  void visit(Element element) {
    if (element is StatefulElement) {
      final state = element.state;
      if (state is FormFieldState && state.hasError) {
        candidates.add(element);
        return;
      }
    }
    element.visitChildren(visit);
  }

  root.visitChildElements(visit);
  BuildContext? top;
  double? topY;
  for (final c in candidates) {
    final box = c.findRenderObject();
    if (box is! RenderBox || !box.attached) continue;
    final y = box.localToGlobal(Offset.zero).dy;
    if (topY == null || y < topY) {
      top = c;
      topY = y;
    }
  }
  if (top == null) return;
  Scrollable.ensureVisible(
    top,
    alignment: 0.2,
    duration: const Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );
}
