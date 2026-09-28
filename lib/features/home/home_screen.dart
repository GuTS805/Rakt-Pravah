import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/semantics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/badges.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/brand_mark.dart';
import 'donor_status_card.dart';

/// The Home dashboard prioritizes what the user needs to do now: request blood,
/// see an active request or donation, and manage Donor Mode (spec §9).
///
/// Visual idea: the sheet is quiet — warm neutral ground, flat cards, hairline
/// borders — so the one saturated element (the emergency card) carries all the
/// urgency by itself. Cards are deliberately not uniform: weight signals
/// importance.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Ask for real location permission once, right as the user lands in the
    // app after logging in — this is a genuine OS permission dialog, not a
    // fake toggle. If already decided (granted/denied), this just syncs state
    // silently without prompting again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = ref.read(deviceLocationProvider).status;
      if (status == DeviceLocationStatus.unknown) {
        ref.read(deviceLocationProvider.notifier).request();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final activeRequest = ref.watch(activeRequestProvider);
    final acceptedInvite = ref.watch(acceptedInvitationProvider);
    final pending = ref.watch(pendingInvitationsProvider).length;
    final location = ref.watch(deviceLocationProvider);
    final requestCount = ref.watch(myRequestsProvider).valueOrNull?.length ?? 0;
    final donations = ref.watch(donorProfileValueProvider).totalDonations;

    return Scaffold(
      body: Container(
        // A single warm blush behind the hero, fading out before the fold —
        // the page reads blood-adjacent without red being used as wallpaper.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              context.isDark
                  ? const Color(0xFF1B1215)
                  : const Color(0xFFFFF1F0),
              c.background,
            ],
            stops: const [0, 0.42],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRequestsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl,
              ),
              children: [
                _BrandRow(
                  hasUnread: pending > 0,
                  place: location.status == DeviceLocationStatus.granted
                      ? Fmt.placeName(location.label, user?.city)
                      : null,
                ),
                const SizedBox(height: AppSpacing.xxl),

                _Hero(
                  name: user?.name ?? 'there',
                  hasActiveRequest: activeRequest != null,
                  isDonating: acceptedInvite != null,
                ),
                const SizedBox(height: AppSpacing.xxl),

                // If the one-shot auto-prompt on first load was missed, denied,
                // or blocked, this stays visible so there's always an obvious
                // way to grant location — never a silent dead end.
                if (location.status != DeviceLocationStatus.granted) ...[
                  _LocationBanner(status: location.status),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Whatever is already in flight leads — a live request matters
                // more than an invitation to start another one.
                if (activeRequest != null) ...[
                  _ActiveRequestCard(request: activeRequest),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (acceptedInvite != null) ...[
                  _ActiveDonationCard(invitation: acceptedInvite),
                  const SizedBox(height: AppSpacing.lg),
                ],

                _EmergencyCard(
                  compact: activeRequest != null,
                  onTap: () => context.push(Routes.createRequest),
                ),
                const SizedBox(height: AppSpacing.lg),

                const DonorStatusCard(),
                const SizedBox(height: AppSpacing.lg),

                _StatsStrip(
                  requests: requestCount,
                  donations: donations,
                  bloodGroup: user?.bloodGroup,
                ),
                const SizedBox(height: AppSpacing.lg),

                const _MedicalNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand identity, where you are, and what's waiting for you — the three
/// things that orient someone the second the app opens.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.hasUnread, this.place});
  final bool hasUnread;
  final String? place;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        const BrandMark(size: 34),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rakt Pravah', style: context.text.titleLarge),
              Text(
                'Life, connected.',
                style: context.text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
        if (place != null) ...[
          _LocationChip(place: place!),
          const SizedBox(width: AppSpacing.sm),
        ],
        _BellButton(hasUnread: hasUnread),
      ],
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.place});
  final String place;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, size: 15, color: c.brand),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.hasUnread});
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkResponse(
      onTap: () => context.push(Routes.notifications),
      radius: 24,
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 21,
              color: c.textPrimary,
            ),
            if (hasUnread)
              Positioned(
                right: 9,
                top: 9,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Greeting + headline. The headline is state-aware on purpose: an
/// inspirational line is right when nothing is happening, and wrong while
/// someone's own request is out searching for a donor.
class _Hero extends ConsumerWidget {
  const _Hero({
    required this.name,
    required this.hasActiveRequest,
    required this.isDonating,
  });

  final String name;
  final bool hasActiveRequest;
  final bool isDonating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(currentTimeProvider).valueOrNull ?? DateTime.now();
    final headline = hasActiveRequest
        ? 'Your request is live.'
        : isDonating
        ? 'Someone is counting on you.'
        : 'A little help can\nmean everything.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting()}, ${name.split(' ').first}',
          style: context.text.titleMedium?.copyWith(color: c.brand),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: c.textTertiary),
            const SizedBox(width: 4),
            Text(
              Fmt.localDateTime(now),
              style: AppTypography.mono(
                size: 11,
                weight: FontWeight.w500,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(headline, style: context.text.displaySmall),
      ],
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

/// The only saturated, shadowed, gradient element on the page — everything
/// else stays flat so this reads as the emergency path without competing.
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.onTap, this.compact = false});

  final VoidCallback onTap;

  /// When a request is already in flight this shrinks to a quieter prompt —
  /// still available, no longer shouting.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.xl);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.brand, c.brandPressed],
          ),
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: c.brand.withValues(alpha: context.isDark ? 0.34 : 0.26),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(compact ? AppSpacing.xl : AppSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? 'Need blood for someone else?' : 'Need blood now?',
                  style:
                      (compact
                              ? context.text.titleLarge
                              : context.text.headlineMedium)
                          ?.copyWith(color: c.onBrand),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  compact
                      ? 'Start a second request.'
                      : 'Create a request in under a minute. We\'ll alert '
                            'nearby donors whose blood type matches.',
                  style: context.text.bodyMedium?.copyWith(
                    color: c.onBrand.withValues(alpha: 0.88),
                    height: 1.45,
                  ),
                ),
                SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
                _CtaPill(label: 'Create blood request'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual affordance only — the whole card is the tap target, which is the
/// right call for the one thing someone might be tapping in a panic.
class _CtaPill extends StatelessWidget {
  const _CtaPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: c.onBrand,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_circle_outline_rounded, size: 19, color: c.brand),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: context.text.labelLarge?.copyWith(color: c.brand)),
        ],
      ),
    );
  }
}

/// Three real numbers, set in the mono face the app uses for every piece of
/// hard data. The third is the user's own blood group — the single most
/// identity-defining fact in this product.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.requests,
    required this.donations,
    required this.bloodGroup,
  });

  final int requests;
  final int donations;
  final BloodGroup? bloodGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _Stat(value: '$requests', label: 'Requests'),
            ),
            VerticalDivider(width: 1, thickness: 1, color: c.border),
            Expanded(
              child: _Stat(value: '$donations', label: 'Donations'),
            ),
            VerticalDivider(width: 1, thickness: 1, color: c.border),
            Expanded(
              child: _Stat(
                value: bloodGroup?.label ?? '—',
                label: 'Your type',
                accent: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.mono(
            size: 20,
            weight: FontWeight.w600,
            color: accent ? c.brand : c.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(color: c.textTertiary),
        ),
      ],
    );
  }
}

/// Rakt Pravah coordinates people; it does not clear anyone to donate. Saying so
/// plainly, once, near the bottom is the honest placement — not buried in a
/// terms page, not shouted at the top.
class _MedicalNotice extends StatelessWidget {
  const _MedicalNotice();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.warningSubtle,
        borderRadius: AppRadius.cardLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 19, color: c.warning),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Rakt Pravah connects people. Medical professionals decide '
              'donation suitability.',
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A persistent, tappable prompt to enable location — the visible recovery
/// path when the one-shot system dialog on first login gets missed, ignored,
/// or denied. Never a dead end: tapping always re-triggers a real permission
/// request (or opens system/app settings once the OS has permanently blocked
/// it).
class _LocationBanner extends ConsumerStatefulWidget {
  const _LocationBanner({required this.status});
  final DeviceLocationStatus status;

  @override
  ConsumerState<_LocationBanner> createState() => _LocationBannerState();
}

class _LocationBannerState extends ConsumerState<_LocationBanner> {
  bool _busy = false;

  Future<void> _tap() async {
    if (widget.status == DeviceLocationStatus.deniedForever) {
      await ref.read(locationServiceProvider).openAppSettings();
      return;
    }
    if (widget.status == DeviceLocationStatus.serviceDisabled) {
      await ref.read(locationServiceProvider).openLocationSettings();
      return;
    }
    setState(() => _busy = true);
    await ref.read(deviceLocationProvider.notifier).request();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (title, action) = switch (widget.status) {
      DeviceLocationStatus.deniedForever => (
        'Location is blocked for Rakt Pravah',
        'Open settings',
      ),
      DeviceLocationStatus.serviceDisabled => (
        'Turn on device location',
        'Open settings',
      ),
      DeviceLocationStatus.denied => (
        'Location access was declined',
        'Try again',
      ),
      _ => ('Enable location to match you with nearby requests', 'Enable'),
    };

    return AppCard(
      onTap: _busy ? null : _tap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: c.infoSubtle,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.location_on_outlined, color: c.info, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: context.text.bodyMedium?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (_busy)
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(c.info),
              ),
            )
          else
            Text(
              action,
              style: context.text.labelLarge?.copyWith(color: c.brand),
            ),
        ],
      ),
    );
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = statusStyle(context, request.status);
    return AppCard(
      onTap: () => context.push(Routes.requestDetail(request.id)),
      emphasize: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your active request',
                  style: context.text.titleSmall,
                ),
              ),
              StatusBadge(request.status, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              BloodGroupBadges(request.bloodGroups, maxVisible: 2),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(request.units), style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (request.status == RequestStatus.searching)
            _SearchingRow(request: request)
          else
            Row(
              children: [
                Icon(style.icon, size: 16, color: style.color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _statusLine(request),
                    style: context.text.bodyMedium?.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                'Track request',
                style: context.text.labelLarge?.copyWith(color: c.brand),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(BloodRequest r) {
    switch (r.status) {
      case RequestStatus.donorAccepted:
        return '${r.acceptedDonorName} accepted — coordination starting';
      case RequestStatus.coordinating:
        return 'Coordinating with ${r.acceptedDonorName}';
      case RequestStatus.created:
        return 'Request created — preparing search';
      default:
        return r.status.label;
    }
  }
}

class _SearchingRow extends StatelessWidget {
  const _SearchingRow({required this.request});
  final BloodRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(c.info),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            request.donorsContacted == 0
                ? 'Searching for nearby donors…'
                : '${request.donorsContacted} donors contacted · '
                      'within ${request.searchRadiusKm.toStringAsFixed(0)} km',
            style: AppTypography.mono(size: 12.5, color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ActiveDonationCard extends StatelessWidget {
  const _ActiveDonationCard({required this.invitation});
  final Invitation invitation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: () => context.push(Routes.coordination(invitation.requestId)),
      accent: c.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('You\'re donating', style: context.text.titleSmall),
              ),
              Icon(Icons.how_to_reg_rounded, size: 18, color: c.success),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              BloodGroupBadges(invitation.bloodGroups, maxVisible: 2),
              const SizedBox(width: AppSpacing.sm),
              Text(Fmt.units(invitation.units), style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${invitation.destinationName} · ${invitation.destinationArea}',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                'Open coordination',
                style: context.text.labelLarge?.copyWith(color: c.brand),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, size: 16, color: c.brand),
            ],
          ),
        ],
      ),
    );
  }
}
