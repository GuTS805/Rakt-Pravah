import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/services/photo_picker.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/form_errors.dart';
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
  // Errors appear on the first submit, then follow what is typed.
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _countryCode;
  late final TextEditingController _country;
  late final TextEditingController _countryIsoCode;
  late final TextEditingController _state;
  late final TextEditingController _stateCode;
  late final TextEditingController _city;
  late final ValueNotifier<double?> _latitude;
  late final ValueNotifier<double?> _longitude;
  BloodGroup? _group;
  bool _groupError = false;
  final _groupKey = GlobalKey();
  DateTime? _dateOfBirth;
  Gender? _gender;
  bool _busy = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider)!;
    _name = TextEditingController(text: user.name);
    _phone = TextEditingController(text: user.phone);
    _countryCode = user.countryCode;
    _country = TextEditingController(text: user.country ?? 'India');
    _countryIsoCode = TextEditingController(text: user.countryIsoCode ?? 'IN');
    _state = TextEditingController(text: user.state ?? '');
    _stateCode = TextEditingController(text: user.stateCode ?? '');
    _city = TextEditingController(text: user.city ?? '');
    _latitude = ValueNotifier<double?>(user.latitude);
    _longitude = ValueNotifier<double?>(user.longitude);
    // A profile never filled in (an account made in the console) has no real
    // blood group, only the model's stand-in. Make the person choose one
    // rather than offer a guess that would go out to patients.
    final neverFilledIn = user.dateOfBirth == null && user.gender == null;
    _group = neverFilledIn ? null : user.bloodGroup;
    _dateOfBirth = user.dateOfBirth;
    _gender = user.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _country.dispose();
    _countryIsoCode.dispose();
    _state.dispose();
    _stateCode.dispose();
    _city.dispose();
    _latitude.dispose();
    _longitude.dispose();
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
    setState(() => _autovalidate = AutovalidateMode.always);
    final validForm = _formKey.currentState!.validate();
    setState(() => _groupError = _group == null);
    if (!validForm || _group == null) {
      revealFirstError(
        _formKey,
        alsoInvalid: [if (_group == null) _groupKey.currentContext],
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            name: _name.text.trim(),
            bloodGroup: _group!,
            phone: PhoneUtils.cleanDigits(_phone.text),
            countryCode: _countryCode,
            countryIsoCode: _countryIsoCode.text.trim().isNotEmpty
                ? _countryIsoCode.text.trim()
                : null,
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            country: _country.text.trim(),
            state: _state.text.trim(),
            stateCode: _stateCode.text.trim().isNotEmpty
                ? _stateCode.text.trim()
                : null,
            city: _city.text.trim(),
            latitude: _latitude.value,
            longitude: _longitude.value,
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
    final verifiedPhone = user.phoneVerified ? user.displayPhone : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        autovalidateMode: _autovalidate,
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
              validator: validatePersonName,
            ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Phone number'),
            if (verifiedPhone != null)
              _VerifiedPhone(number: verifiedPhone)
            else
              PhoneNumberField(
                phoneController: _phone,
                initialCountryCode: _countryCode,
                onCountryChanged: (c) =>
                    setState(() => _countryCode = c.dialCode),
              ),
            const SizedBox(height: AppSpacing.lg),
            const FieldLabel('Blood group'),
            BloodGroupPicker(
              key: _groupKey,
              selected: _group,
              onChanged: (g) => setState(() {
                _group = g;
                _groupError = false;
              }),
            ),
            if (_groupError) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Select your blood group',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.danger,
                ),
              ),
            ],
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
            HomeLocationFields(
              country: _country,
              countryCode: _countryIsoCode,
              state: _state,
              stateCode: _stateCode,
              city: _city,
              latitude: _latitude,
              longitude: _longitude,
            ),
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(label: 'Save changes', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

/// A verified number, shown instead of an editable field: changing it takes a
/// new code, so it goes through the verification screen.
class _VerifiedPhone extends StatelessWidget {
  const _VerifiedPhone({required this.number});
  final String number;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: AppRadius.inputRadius,
      ),
      child: Row(
        children: [
          Expanded(child: Text(number, style: context.text.bodyLarge)),
          Icon(Icons.verified_rounded, size: 18, color: c.success),
          const SizedBox(width: AppSpacing.xs),
          Text('Verified', style: context.text.bodySmall),
          TextButton(
            onPressed: () => context.push(Routes.verifyPhone),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}
