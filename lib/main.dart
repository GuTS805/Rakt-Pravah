import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'core/services/notification_watcher_provider.dart';
import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: RaktPravahApp()));
}

class RaktPravahApp extends ConsumerWidget {
  const RaktPravahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Keeps watching invitations/requests for the app's lifetime so a new
    // match or an accepted request surfaces a notification from any tab.
    ref.watch(notificationWatcherProvider);

    return MaterialApp.router(
      title: 'Rakt Pravah',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Clamp text scaling to a sane range so emergency layouts stay legible
        // without breaking, while still honoring the user's accessibility size.
        final media = MediaQuery.of(context);
        final clamped = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.35,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: clamped),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: context.isDark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
