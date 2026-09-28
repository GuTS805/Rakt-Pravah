import 'package:flutter_test/flutter_test.dart';
import 'package:rakt_pravah/admin/admin_backend.dart';
import 'package:rakt_pravah/data/models/models.dart';

void main() {
  group('User & Admin Role Authentication Tests', () {
    test('UserProfile reflects correct UserRole based on isAdmin flag', () {
      final standardUser = UserProfile(
        id: 'u1',
        name: 'Normal User',
        bloodGroup: BloodGroup.oPos,
        phone: '9876543210',
        isAdmin: false,
      );

      expect(standardUser.isAdmin, isFalse);
      expect(standardUser.role, equals(UserRole.user));
      expect(standardUser.role.isUser, isTrue);
      expect(standardUser.role.isAdmin, isFalse);

      final adminUser = UserProfile(
        id: 'a1',
        name: 'System Admin',
        bloodGroup: BloodGroup.abPos,
        phone: '9123456789',
        isAdmin: true,
      );

      expect(adminUser.isAdmin, isTrue);
      expect(adminUser.role, equals(UserRole.admin));
      expect(adminUser.role.isAdmin, isTrue);
      expect(adminUser.role.isUser, isFalse);
    });

    test('AdminBackend strictly blocks instantiation if caller is not admin', () {
      // Trying to instantiate AdminBackend with isAdmin: false MUST throw AdminUnauthorizedException
      expect(
        () => AdminBackend(
          null,
          actorId: 'attacker_1',
          actorName: 'Non Admin',
          isAdmin: false,
        ),
        throwsA(isA<AdminUnauthorizedException>()),
      );
    });
  });
}
