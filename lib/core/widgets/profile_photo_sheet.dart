import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../services/photo_picker.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import 'avatar.dart';

/// Shows a photo preview dialog allowing the user to inspect the cropped
/// profile photo before committing to saving it.
Future<bool?> showPhotoPreviewDialog({
  required BuildContext context,
  required String photoBase64,
  required String initials,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final c = dialogContext.colors;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
        backgroundColor: c.surface,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Preview Profile Photo',
                style: dialogContext.text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This is how your circular profile photo will appear across the app.',
                textAlign: TextAlign.center,
                style: dialogContext.text.bodyMedium?.copyWith(
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Circular Cropped Photo Preview
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.brand.withValues(alpha: 0.35),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: dialogContext.isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Avatar(
                  initials: initials,
                  photo: photoBase64,
                  size: 130,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: c.success),
                    const SizedBox(width: 6),
                    // Wraps rather than overflowing on a narrow dialog.
                    Flexible(
                      child: Text(
                        'Square cropped • Auto-compressed • Under 5 MB',
                        textAlign: TextAlign.center,
                        style: AppTypography.mono(
                          size: 11,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Action Buttons: Cancel and Save Photo
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        side: BorderSide(color: c.border),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.brand,
                        foregroundColor: c.onBrand,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text(
                        'Save Photo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Opens the options bottom sheet (Take photo / Gallery / Remove) and guides
/// the user through image picking, validation, preview, and saving.
Future<void> showProfilePhotoOptions({
  required BuildContext context,
  required WidgetRef ref,
  VoidCallback? onBusyChanged,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return;
  final hasPhoto = user.photo != null && user.photo!.isNotEmpty;
  final messenger = ScaffoldMessenger.of(context);

  Future<void> handleChoose(PhotoSource source) async {
    try {
      final picker = ref.read(photoPickerProvider);
      final rawPhoto = await picker.pick(source);
      if (rawPhoto == null) {
        // Backed out or cancelled picker
        return;
      }

      if (!context.mounted) return;

      // Show preview dialog before saving
      final confirmed = await showPhotoPreviewDialog(
        context: context,
        photoBase64: rawPhoto,
        initials: user.initials,
      );

      if (confirmed == true && context.mounted) {
        onBusyChanged?.call();
        await ref.read(authControllerProvider.notifier).setPhoto(rawPhoto);
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully.')),
        );
      }
    } on PhotoValidationException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not upload that photo. Please try another image.'),
        ),
      );
    } finally {
      onBusyChanged?.call();
    }
  }

  Future<void> handleRemove() async {
    try {
      onBusyChanged?.call();
      await ref.read(authControllerProvider.notifier).setPhoto(null);
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile photo removed.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove photo. Try again.')),
      );
    } finally {
      onBusyChanged?.call();
    }
  }

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) {
      final c = sheetContext.colors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Text(
                      hasPhoto ? 'Change Profile Photo' : 'Upload Profile Photo',
                      style: sheetContext.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                subtitle: const Text('Use camera to take a new portrait'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  handleChoose(PhotoSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                subtitle: const Text('JPG, JPEG, PNG, or WEBP (up to 5 MB)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  handleChoose(PhotoSource.gallery);
                },
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: c.danger,
                  ),
                  title: Text(
                    'Remove photo',
                    style: TextStyle(color: c.danger, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Return to initials avatar'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    handleRemove();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}
