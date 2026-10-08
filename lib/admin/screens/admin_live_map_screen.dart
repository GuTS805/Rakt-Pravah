import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/enums.dart';
import '../admin_backend.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';
import '../admin_widgets.dart';

/// Live operational map showing emergencies, active blood requests,
/// hospital blood banks, and verified donor presence.
class AdminLiveMapScreen extends ConsumerStatefulWidget {
  const AdminLiveMapScreen({super.key});

  @override
  ConsumerState<AdminLiveMapScreen> createState() => _AdminLiveMapScreenState();
}

class _AdminLiveMapScreenState extends ConsumerState<AdminLiveMapScreen> {
  final MapController _mapController = MapController();
  String _filter = 'all'; // all, emergency, hospitals, donors
  AdminRequest? _selectedRequest;

  // NOTE: Request, donor, and hospital markers use synthesized coordinates
  // because `AdminRequest`, `AdminUser`, and `AdminHospital` Firestore documents
  // do not yet carry `latitude`/`longitude` fields. Positions are approximate.
  // To show real locations: add lat/lng to those documents, update the
  // AdminBackend parsers, and replace the offset arithmetic below with the
  // real field values.

  static const _defaultCenter = ll.LatLng(28.6139, 77.2090); // New Delhi / NCR

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final requestsAsync = ref.watch(adminRequestsProvider);
    final usersAsync = ref.watch(adminUsersProvider);

    return AdminPage(
      title: 'Live Operational Map',
      subtitle: 'Real-time geographic distribution of blood requests, incidents, and donor readiness.',
      actions: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            _mapFilterChip('all', 'All Activity', Icons.layers_rounded, c),
            _mapFilterChip(
              'emergency',
              'Emergencies',
              Icons.emergency_rounded,
              c,
            ),
            _mapFilterChip(
              'hospitals',
              'Hospitals',
              Icons.local_hospital_rounded,
              c,
            ),
            _mapFilterChip(
              'donors',
              'Available Donors',
              Icons.volunteer_activism_rounded,
              c,
            ),
          ],
        ),
      ],
      child: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmpty(
          icon: Icons.error_outline_rounded,
          message: 'Could not load map data: $e',
        ),
        data: (allRequests) {
          final users = usersAsync.valueOrNull ?? const [];
          // Live hospitals from Firestore (names are real; coordinates are
          // approximate until lat/lng fields are added to the hospital documents).
          final hospitals = ref.watch(adminHospitalsProvider).valueOrNull ?? const [];

          // Synthesize coordinates clustered around Delhi NCR for requests.
          // Replace with real lat/lng once Firestore documents carry those fields.
          final activeRequests = allRequests.where((r) => r.isOpen).toList();
          final emergencyRequests = activeRequests
              .where(
                (r) =>
                    r.urgency == Urgency.critical ||
                    r.urgency == Urgency.urgent,
              )
              .toList();

          final markers = <Marker>[];

          // 1. Hospital & Request Markers
          if (_filter == 'all' || _filter == 'emergency') {
            for (var i = 0; i < activeRequests.length; i++) {
              final r = activeRequests[i];
              final isCritical = r.urgency == Urgency.critical;
              if (_filter == 'emergency' &&
                  !isCritical &&
                  r.urgency != Urgency.urgent) {
                continue;
              }

              // Offset coordinates slightly per item around Delhi/NCR
              final lat = 28.6139 + ((i % 5) - 2) * 0.045;
              final lng = 77.2090 + (((i * 2) % 5) - 2) * 0.055;

              markers.add(
                Marker(
                  point: ll.LatLng(lat, lng),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRequest = r),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCritical ? c.danger : c.brand,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: (isCritical ? c.danger : c.brand).withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          r.bloodGroups.isNotEmpty
                              ? r.bloodGroups.first.label
                              : '🩸',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // 2. Verified Hospitals — names from live Firestore hospitals collection.
          // Coordinates are approximate (offset around Delhi NCR) until the
          // AdminHospital model and Firestore documents include lat/lng fields.
          if (_filter == 'all' || _filter == 'hospitals') {
            final verifiedHospitals = hospitals
                .where((h) => h.isVerified)
                .toList();
            for (var i = 0; i < verifiedHospitals.length; i++) {
              final h = verifiedHospitals[i];
              // Approximate position until real coordinates are stored in Firestore.
              final lat = 28.5672 + ((i % 4) - 1) * 0.040;
              final lng = 77.2100 + (((i * 2) % 4) - 1) * 0.045;
              markers.add(
                Marker(
                  point: ll.LatLng(lat, lng),
                  width: 36,
                  height: 36,
                  child: Tooltip(
                    message: h.name,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: c.success.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          // 3. Available Donors
          if (_filter == 'all' || _filter == 'donors') {
            final donors = users
                .where((u) => u.isDonorOn && !u.isInCooldown)
                .toList();
            for (var i = 0; i < donors.length && i < 25; i++) {
              final d = donors[i];
              final lat = 28.5900 + ((i % 7) - 3) * 0.035;
              final lng = 77.1900 + (((i * 3) % 7) - 3) * 0.040;

              markers.add(
                Marker(
                  point: ll.LatLng(lat, lng),
                  width: 28,
                  height: 28,
                  child: Tooltip(
                    message: '${d.name} (${d.bloodGroup.label})',
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.info,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.person_pin_circle_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              );
            }
          }

          return Stack(
            children: [
              ClipRRect(
                borderRadius: AppRadius.cardMd,
                child: SizedBox(
                  height: 600,
                  width: double.infinity,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: _defaultCenter,
                      initialZoom: 11.5,
                      minZoom: 6,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.raktpravah.app',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
              ),

              // Overview HUD Card
              Positioned(
                top: AppSpacing.md,
                left: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface.withValues(alpha: 0.94),
                    borderRadius: AppRadius.cardMd,
                    border: Border.all(color: c.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LIVE COVERAGE',
                        style: AppTypography.mono(
                          size: 10,
                          color: c.textTertiary,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _hudMetric(
                            'Active',
                            '${activeRequests.length}',
                            c.info,
                          ),
                          const SizedBox(width: 14),
                          _hudMetric(
                            'Critical',
                            '${emergencyRequests.length}',
                            c.danger,
                          ),
                          const SizedBox(width: 14),
                          _hudMetric(
                            'Donors',
                            '${users.where((u) => u.isDonorOn).length}',
                            c.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '⚠ Positions are approximate',
                        style: AppTypography.mono(
                          size: 9,
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Selected Request Card
              if (_selectedRequest != null)
                Positioned(
                  bottom: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: AppRadius.cardMd,
                          border: Border.all(color: c.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                RequestStatusPill(_selectedRequest!.status),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _selectedRequest = null),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _selectedRequest!.requesterName,
                              style: context.text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _selectedRequest!.destinationName,
                              style: context.text.bodySmall?.copyWith(
                                color: c.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.brandSubtle,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _selectedRequest!.bloodGroups
                                        .map((g) => g.label)
                                        .join(' '),
                                    style: AppTypography.mono(
                                      size: 12,
                                      color: c.brand,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_selectedRequest!.units} Units',
                                  style: AppTypography.mono(
                                    size: 12,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _selectedRequest!.urgency.label,
                                  style: context.text.labelSmall?.copyWith(
                                    color:
                                        _selectedRequest!.urgency ==
                                            Urgency.critical
                                        ? c.danger
                                        : c.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _mapFilterChip(String key, String label, IconData icon, dynamic c) {
    final isSel = _filter == key;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: isSel ? c.brand : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSel ? c.onBrand : c.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                color: isSel ? c.onBrand : c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hudMetric(String title, String val, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          val,
          style: AppTypography.mono(
            size: 16,
            color: color,
            weight: FontWeight.w700,
          ),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
