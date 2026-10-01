import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import 'avatar.dart';

/// The frame shared by the request cards and the invitation cards: the left
/// 30% is the person asking, the right 70% is everything about the request.
/// Putting the same frame on what you sent and what you received is what lets
/// the two lists read as one thing.
///
/// The left side is the requester's photo, filling the whole 30%. Someone who
/// hasn't added one, or a request made before they did, shows their initials
/// there instead.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.requesterName,
    required this.details,
    this.requesterPhoto,
    this.footer,
    this.accent,
    this.onTap,
  });

  /// Widths are a ratio, not a fixed size, so the split holds on every screen.
  static const photoFlex = 3;
  static const detailsFlex = 7;

  static const photoKey = ValueKey('profile-card-photo');
  static const detailsKey = ValueKey('profile-card-details');

  final String requesterName;

  /// Base64 JPEG, or null for initials.
  final String? requesterPhoto;

  /// Goes in the right 70%.
  final Widget details;

  /// Full-width row under both halves, e.g. Accept and Decline.
  final Widget? footer;

  /// Urgency colour for the thin bar down the left edge.
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardLg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.18 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardLg,
          side: BorderSide(color: c.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: photoFlex,
                          child: ColoredBox(
                            key: photoKey,
                            color: c.surfaceMuted,
                            child: requesterPhoto == null
                                ? _Initials(name: requesterName)
                                : _Photo(
                                    photo: requesterPhoto!,
                                    name: requesterName,
                                  ),
                          ),
                        ),
                        Expanded(
                          flex: detailsFlex,
                          child: Padding(
                            key: detailsKey,
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: details,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (footer != null) ...[
                    Divider(height: 1, color: c.border),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: footer,
                    ),
                  ],
                ],
              ),
              if (accent != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 4, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(initials: Fmt.initials(name), size: 52),
            const SizedBox(height: AppSpacing.sm),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo fills the space; the name sits on a dark band along the bottom so
/// it stays readable on any picture.
class _Photo extends StatelessWidget {
  const _Photo({required this.photo, required this.name});
  final String photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MemoryPhoto(photo: photo),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            color: Colors.black.withValues(alpha: 0.55),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: context.text.labelMedium?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The top of the details column: who the patient is, then the requester's id
/// with something small beside it, usually how long ago it was asked.
class CardHeadline extends StatelessWidget {
  const CardHeadline({
    super.key,
    required this.title,
    required this.userId,
    this.caption,
    this.aside,
  });

  /// The patient's name, or a stand-in when it isn't the viewer's to see yet.
  final String title;

  /// The requester's short id, from [Fmt.userId].
  final String userId;

  /// Explains a stand-in title, e.g. why the name isn't shown.
  final String? caption;

  /// Sits at the right end of the id line.
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleMedium,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              'ID $userId',
              style: AppTypography.mono(size: 12, color: c.textTertiary),
            ),
            if (aside != null) ...[
              const Spacer(),
              Text(
                aside!,
                style: context.text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ],
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: context.text.bodySmall),
        ],
      ],
    );
  }
}
