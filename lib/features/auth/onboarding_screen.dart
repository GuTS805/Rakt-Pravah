import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/buttons.dart';
import '../../data/providers.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(
    Icons.bloodtype_rounded,
    'Blood when it counts',
    'Rakt Pravah connects you directly with nearby registered donors during an emergency — no queues, no middlemen.',
  ),
  _Page(
    Icons.radar_rounded,
    'How a request works',
    'Create a request in seconds. Rakt Pravah notifies eligible donors nearby in waves until someone accepts.',
  ),
  _Page(
    Icons.favorite_rounded,
    'Donor Mode is yours to control',
    'Turn Donor Mode on to receive matching requests near you. Pause or turn it off anytime — you\'re always in control.',
  ),
  _Page(
    Icons.shield_moon_rounded,
    'Private by design',
    'Your phone number and exact location stay private until you choose to share. Live location is temporary and always opt-in.',
  ),
  _Page(
    Icons.forum_rounded,
    'Coordinate and help',
    'Once a donor accepts, a private chat opens so you can arrange the details and get to the hospital fast.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _requestingLocation = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _pages.length - 1) {
      ref.read(authControllerProvider.notifier).completeOnboarding();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _requestLocation() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    final result = await ref.read(deviceLocationProvider.notifier).request();
    if (!mounted) return;
    setState(() => _requestingLocation = false);

    if (!result.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location was not enabled. You can change this later in Privacy & location.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLast = _index == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: TextButton(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .completeOnboarding(),
                  child: Text(
                    'Skip',
                    style: context.text.labelLarge?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 76,
                          width: 76,
                          decoration: BoxDecoration(
                            color: c.brandSubtle,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                          child: Icon(p.icon, size: 36, color: c.brand),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(p.title, style: context.text.headlineLarge),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          p.body,
                          style: context.text.bodyLarge?.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 6,
                          width: i == _index ? 20 : 6,
                          decoration: BoxDecoration(
                            color: i == _index ? c.brand : c.border,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (isLast) ...[
                    OutlinedButton.icon(
                      onPressed: _requestingLocation ? null : _requestLocation,
                      icon: _requestingLocation
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: Text(
                        _requestingLocation
                            ? 'Requesting location…'
                            : 'Use my location',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Optional. It helps find nearby requests. Your exact location is not shared automatically.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  PrimaryButton(
                    label: isLast ? 'Get started' : 'Next',
                    onPressed: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
