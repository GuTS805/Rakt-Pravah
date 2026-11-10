import 'package:flutter/widgets.dart';

/// Closes the on-screen keyboard. Call it before opening a picker: when a
/// dialog or sheet closes, Flutter hands focus back to the text field that
/// had it, and the keyboard springs up again over the form.
void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();
