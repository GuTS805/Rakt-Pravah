import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';
import 'main.dart';

/// Entrypoint for web and desktop operations console.
/// Shares the single unified login page and role-based routing with the main app.
///
/// Build it with:
///   flutter build web -t lib/main_admin.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  runApp(const ProviderScope(child: AdminApp()));
}

/// Router provider alias forwarding to the unified [routerProvider].
final adminRouterProvider = routerProvider;

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => const RaktPravahApp();
}
