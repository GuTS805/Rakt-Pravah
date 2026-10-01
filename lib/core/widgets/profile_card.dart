import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import 'avatar.dart';

/// The frame shared by the request cards and the invitation cards. The person
/// asking is a round photo on the left with their name, who the request is
/// for and their id beside it; everything else about the request sits in
/// [body] underneath, across the full width. Putting the same frame on what
/// you sent and what you received is what lets the two lists read as one
/// thing.
///
/// Someone who hasn't added a photo, or a request made before they did, shows
/// their initials in the circle instead.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.requesterName,
    required this.userId,
    required this.body,
    this.subtitle,
    this.requesterPhoto,
    this.aside,
    this.footer,
    this.accent,
    this.onTap,
  });

  static const avatarSize = 76.0;

  static const photoKey = ValueKey('profile-card-photo');
  static const detailsKey = ValueKey('profile-card-details');

  final String requesterName;

  /// The requester's short id, from [Fmt.userId].
  final String userId;

  /// Under the name: who the request is for, or why that isn't shown yet.
  final String? subtitle;

  /// Base64 JPEG, or null for initials.
  final String? requesterPhoto;

  /// Sits at the right end of the name line, usually how long ago.
  final String? aside;

  /// Everything below the header, full width.
  final Widget body;

  /// Full-width row under the body, e.g. Accept and Decline.
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
                  Padding(
                    key: detailsKey,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Photo(
                              key: photoKey,
                              photo: requesterPhoto,
                              name: requesterName,
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: _Headline(
                                name: requesterName,
                                subtitle: subtitle,
                                userId: userId,
                                aside: aside,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        body,
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

/// A round photo with a soft red ring, or the initials when there is none.
class _Photo extends StatelessWidget {
  const _Photo({super.key, required this.photo, required this.name});
  final String? photo;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.brand.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Avatar(
        initials: Fmt.initials(name),
        photo: photo,
        size: ProfileCard.avatarSize - 9,
      ),
    );
  }
}

/// Requester name with the time at the far end, who it is for, then the id.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.name,
    required this.userId,
    this.subtitle,
    this.aside,
  });

  final String name;
  final String userId;
  final String? subtitle;
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium,
              ),
            ),
            if (aside != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  aside!,
                  style: context.text.bodySmall?.copyWith(
                    color: c.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'ID $userId',
          style: AppTypography.mono(size: 12, color: c.textTertiary),
        ),
      ],
    );
  }
}
