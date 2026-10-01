import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/photo_picker.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/blood_group_picker.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/profile_photo_sheet.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../shared/profile_fields.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _country;
  late final TextEditingController _state;
  late final TextEditingController _city;
  late BloodGroup _group;
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _busy = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    _name = TextEditingController(text: user.name);
    _country = TextEditingController(text: user.country ?? 'India');
    _state = TextEditingController(text: user.state ?? '');
    _city = TextEditingController(text: user.city ?? '');
    _group = user.bloodGroup;
    _dateOfBirth = user.dateOfBirth;
    _gender = user.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    _state.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto(PhotoSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _photoBusy = true);
    try {
      final photo = await ref.read(photoPickerProvider).pick(source);
      if (photo == null) {
        // Backed out, or the picture was too big to keep after shrinking.
        return;
      }
      if (!mounted) return;
      final user = ref.read(currentUserProvider)!;
      final confirmed = await showPhotoPreviewDialog(
        context: context,
        photoBase64: photo,
        initials: user.initials,
      );
      if (confirmed == true && mounted) {
        await ref.read(authControllerProvider.notifier).setPhoto(photo);
        messenger.showSnackBar(
          const SnackBar(content: Text('Profile photo updated.')),
        );
      }
    } on PhotoValidationException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add that photo. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await ref.read(authControllerProvider.notifier).setPhoto(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _photoOptions(bool hasPhoto) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Use camera to take a portrait'),
              onTap: () {
                Navigator.pop(sheet);
                _choosePhoto(PhotoSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('JPG, JPEG, PNG, or WEBP (up to 5 MB)'),
              onTap: () {
                Navigator.pop(sheet);
                _choosePhoto(PhotoSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: context.colors.danger,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.colors.danger),
                ),
                subtitle: const Text('Return to initials avatar'),
                onTap: () {
                  Navigator.pop(sheet);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            name: _name.text.trim(),
            bloodGroup: _group,
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            country: _country.text.trim(),
            state: _state.text.trim(),
            city: _city.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t save changes. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final hasPhoto = user.photo != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: Column(
                children: [
                  Avatar(
                    initials: user.initials,
                    photo: user.photo,
                    size: 96,
                    showCameraBadge: true,
                    onCameraTap: _photoBusy
                        ? null
                        : () => _photoOptions(hasPhoto),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _photoBusy
                        ? null
                        : () => _photoOptions(hasPhoto),
                    child: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const FieldLabel('Full name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Your name'),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Enter your name' : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Blood group'),
            BloodGroupPicker(
              selected: _group,
              onChanged: (g) => setState(() => _group = g),
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Date of birth'),
            DateOfBirthField(
              initialValue: _dateOfBirth,
              onChanged: (d) => _dateOfBirth = d,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Gender'),
            GenderField(initialValue: _gender, onChanged: (g) => _gender = g),
            const SizedBox(height: AppSpacing.lg),
            HomeLocationFields(country: _country, state: _state, city: _city),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(label: 'Save changes', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
