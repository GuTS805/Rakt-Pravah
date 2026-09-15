import 'package:bloodlink/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores the selected appearance mode on this device', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('bloodlink_appearance_theme_mode'),
      ThemeMode.dark.name,
    );
  });

  test('restores the selected appearance mode', () async {
    SharedPreferences.setMockInitialValues({
      'bloodlink_appearance_theme_mode': ThemeMode.light.name,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(themeModeProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
