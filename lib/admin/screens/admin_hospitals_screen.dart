import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../admin_backend.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

// ---------------------------------------------------------------------------
// Hospitals Management Screen
// ---------------------------------------------------------------------------

/// Provider for hospitals (reads from `hospitals` Firestore collection).
/// The collection may not exist yet — this reads an empty list gracefully.
final adminHospitalsProvider = StreamProvider.autoDispose<List<AdminHospital>>((
  ref,
) {
  final admin = ref.watch(adminBackendProvider);
  if (admin == null) return Stream.value(const []);
  return admin.hospitals;
});

class AdminHospitalsScreen extends ConsumerStatefulWidget {
  const AdminHospitalsScreen({super.key});

  @override
  ConsumerState<AdminHospitalsScreen> createState() =>
      _AdminHospitalsScreenState();
}

class _AdminHospitalsScreenState extends ConsumerState<AdminHospitalsScreen> {
  String _search = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(adminHospitalsProvider);

    return AdminPage(
      title: 'Hospitals',
      subtitle: 'Manage registered hospitals and blood banks.',
      actions: [
        AdminSearchBar(
          hint: 'Search hospitals...',
          onChanged: (v) => setState(() => _search = v.toLowerCase()),
        ),
        const SizedBox(width: AppSpacing.md),
        FilledButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add Hospital'),
          onPressed: () => _showAddDialog(context),
        ),
      ],
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not read: $e',
        ),
        data: (hospitals) {
          final verified = hospitals.where((h) => h.isVerified).length;

          var shown = switch (_filter) {
            'verified' => hospitals.where((h) => h.isVerified).toList(),
            'pending' => hospitals.where((h) => !h.isVerified).toList(),
            _ => hospitals,
          };

          if (_search.isNotEmpty) {
            shown = shown
                .where(
                  (h) =>
                      h.name.toLowerCase().contains(_search) ||
                      h.city.toLowerCase().contains(_search) ||
                      (h.state?.toLowerCase().contains(_search) ?? false),
                )
                .toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  AdminStatCard(
                    icon: Icons.local_hospital_rounded,
                    value: '${hospitals.length}',
                    label: 'Total Hospitals',
                    description: 'Registered in the system',
                    color: c.info,
                  ),
                  AdminStatCard(
                    icon: Icons.verified_rounded,
                    value: '$verified',
                    label: 'Verified',
                    description: 'Confirmed and active',
                    color: c.success,
                  ),
                  AdminStatCard(
                    icon: Icons.pending_rounded,
                    value: '${hospitals.length - verified}',
                    label: 'Pending Verification',
                    description: 'Needs review',
                    color: c.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  AdminFilterChip(
                    label: 'All',
                    count: hospitals.length,
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                  AdminFilterChip(
                    label: 'Verified',
                    count: verified,
                    selected: _filter == 'verified',
                    onTap: () => setState(() => _filter = 'verified'),
                  ),
                  AdminFilterChip(
                    label: 'Pending',
                    count: hospitals.length - verified,
                    selected: _filter == 'pending',
                    onTap: () => setState(() => _filter = 'pending'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              AdminPanel(
                title: 'Hospitals',
                trailing: Text(
                  '${shown.length}',
                  style: AppTypography.mono(size: 12, color: c.textTertiary),
                ),
                child: shown.isEmpty
                    ? AdminEmpty(
                        icon: Icons.local_hospital_rounded,
                        message: hospitals.isEmpty
                            ? 'No hospitals registered yet. Add a hospital '
                                  'using the button above.'
                            : 'No hospitals match this filter.',
                      )
                    : AdminTableScroll(
                        minWidth: 680,
                        child: Column(
                          children: [
                            adminHeaderRow(context, [
                              ('Name', 3),
                              ('City', 2),
                              ('Contact', 2),
                              ('Type', 2),
                              ('Status', 2),
                              ('Actions', 2),
                            ]),
                            for (final h in shown) _HospitalRow(hospital: h),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameC = TextEditingController();
    final cityC = TextEditingController();
    final contactC = TextEditingController();
    final addressC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Hospital'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Hospital Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: cityC,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: addressC,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: contactC,
                decoration: const InputDecoration(labelText: 'Contact Number'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameC.text.trim().isEmpty || cityC.text.trim().isEmpty) {
                return;
              }
              final admin = ref.read(adminBackendProvider);
              await admin?.addHospital(
                name: nameC.text.trim(),
                city: cityC.text.trim(),
                address: addressC.text.trim(),
                contact: contactC.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _HospitalRow extends ConsumerWidget {
  const _HospitalRow({required this.hospital});
  final AdminHospital hospital;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          AdminCell(
            flex: 3,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hospital.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
                if (hospital.address != null)
                  Text(
                    hospital.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: c.textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              hospital.city,
              style: context.text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            Text(
              hospital.contact ?? '—',
              style: AppTypography.mono(size: 12, color: c.textSecondary),
            ),
          ),
          AdminCell(
            flex: 2,
            StatusPill(hospital.type, fg: c.info, bg: c.infoSubtle),
          ),
          AdminCell(
            flex: 2,
            StatusPill(
              hospital.isVerified ? 'Verified' : 'Pending',
              fg: hospital.isVerified ? c.success : c.warning,
              bg: hospital.isVerified ? c.successSubtle : c.warningSubtle,
            ),
          ),
          AdminCell(
            flex: 2,
            Row(
              children: [
                if (!hospital.isVerified)
                  Tooltip(
                    message: 'Verify hospital',
                    child: IconButton(
                      icon: Icon(
                        Icons.verified_rounded,
                        size: 18,
                        color: c.success,
                      ),
                      onPressed: () async {
                        final admin = ref.read(adminBackendProvider);
                        await admin?.verifyHospital(hospital.id);
                        if (context.mounted) {
                          showAdminToast(context, '${hospital.name} verified.');
                        }
                      },
                    ),
                  ),
                Tooltip(
                  message: 'Delete hospital',
                  child: IconButton(
                    icon: Icon(Icons.delete_rounded, size: 18, color: c.danger),
                    onPressed: () async {
                      final confirmed = await showAdminConfirmDialog(
                        context,
                        title: 'Delete ${hospital.name}?',
                        message:
                            'This will permanently remove this hospital '
                            'from the system.',
                        confirmLabel: 'Delete',
                        isDangerous: true,
                      );
                      if (!confirmed) return;
                      final admin = ref.read(adminBackendProvider);
                      await admin?.deleteHospital(hospital.id);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
