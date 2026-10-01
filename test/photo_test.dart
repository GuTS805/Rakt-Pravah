import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rakt_pravah/core/services/photo_picker.dart';
import 'package:rakt_pravah/core/theme/app_theme.dart';
import 'package:rakt_pravah/core/widgets/avatar.dart';
import 'package:rakt_pravah/core/widgets/profile_card.dart';
import 'package:rakt_pravah/core/widgets/request_card.dart';
import 'package:rakt_pravah/data/models/models.dart';
import 'package:rakt_pravah/data/providers.dart';
import 'package:rakt_pravah/features/profile/profile_edit_screen.dart';

import 'fakes.dart';

/// A real 1x1 PNG, so the image decoder has something valid to chew on.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

UserProfile _user({String? photo}) => UserProfile(
  id: 'u1',
  name: 'Alok Sharma',
  bloodGroup: BloodGroup.oPos,
  phone: '9876543210',
  dateOfBirth: DateTime(1990),
  gender: Gender.male,
  photo: photo,
);

BloodRequest _request({String? photo}) => BloodRequest(
  id: 'r1',
  requesterId: 'u1',
  requesterName: 'Alok Sharma',
  requesterPhoto: photo,
  bloodGroups: const [BloodGroup.oPos],
  units: 1,
  urgency: Urgency.critical,
  status: RequestStatus.searching,
  createdAt: DateTime.now(),
  destination: const Destination(name: 'City Hospital', address: 'MG Road'),
  requestLocationLabel: 'Bengaluru',
);

Finder _inPhotoCell(Finder f) =>
    find.descendant(of: find.byKey(ProfileCard.photoKey), matching: f);

void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('photo encoding', () {
    test('a small picture is kept as base64', () {
      expect(Photos.encode([1, 2, 3]), 'AQID');
    });

    test('a picture too big to keep is refused', () {
      expect(Photos.encode(List.filled(23000, 7)), isNull);
    });

    test('a picture just under the limit is kept', () {
      // 22000 bytes encode to about 29,300 characters.
      expect(Photos.encode(List.filled(22000, 7)), isNotNull);
    });
  });

  group('preparing a picked picture', () {
    // A large, noisy PNG is the worst case: PNG keeps it near full size.
    Uint8List noisyPng(int w, int h) {
      final image = img.Image(width: w, height: h);
      var seed = 7;
      for (final p in image) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p
          ..r = seed & 255
          ..g = (seed >> 8) & 255
          ..b = (seed >> 16) & 255;
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('any picture becomes a small square JPEG', () {
      final png = noisyPng(640, 360);
      final out = Photos.prepare(png)!;

      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, Photos.side);
      expect(decoded.height, Photos.side);
      expect(out.length, lessThan(png.length ~/ 10));
    });

    test('even a noisy picture fits under the stored limit', () {
      final out = Photos.prepare(noisyPng(800, 800))!;
      expect(Photos.encode(out), isNotNull);
    });

    test('something that is not a picture is refused', () {
      expect(Photos.prepare([1, 2, 3, 4, 5]), isNull);
    });
  });

  group('photo on a card', () {
    Future<void> show(WidgetTester tester, BloodRequest request) async {
      _tallPhone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(FakeBackend(user: _user())),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: RequestCard(request: request)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the requester photo fills the left 30%', (tester) async {
      await show(tester, _request(photo: _png));

      expect(_inPhotoCell(find.byType(MemoryPhoto)), findsOneWidget);
      expect(_inPhotoCell(find.byType(Avatar)), findsNothing);
      expect(_inPhotoCell(find.text('Alok Sharma')), findsOneWidget);

      final cell = tester.getSize(find.byKey(ProfileCard.photoKey));
      final photo = tester.getSize(find.byType(MemoryPhoto));
      expect(photo, cell, reason: 'the photo covers the whole left side');
    });

    testWidgets('without a photo the initials stand in', (tester) async {
      await show(tester, _request());

      expect(_inPhotoCell(find.byType(MemoryPhoto)), findsNothing);
      expect(_inPhotoCell(find.text('AS')), findsOneWidget);
    });

    testWidgets('a photo that cannot be decoded falls back quietly', (
      tester,
    ) async {
      await show(tester, _request(photo: '%%% not base64 %%%'));

      expect(tester.takeException(), isNull);
      expect(_inPhotoCell(find.text('Alok Sharma')), findsOneWidget);
    });
  });

  group('adding a profile photo', () {
    late FakeBackend backend;
    late FakePhotoPicker picker;
    late ProviderContainer container;

    Future<void> open(WidgetTester tester, {String? photo}) async {
      _tallPhone(tester);
      backend = FakeBackend(user: _user(photo: photo));
      picker = FakePhotoPicker();
      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(backend),
          photoPickerProvider.overrideWithValue(picker),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).finishStartup();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ProfileEditScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> choose(
      WidgetTester tester,
      String opener,
      String option,
    ) async {
      await tester.tap(find.text(opener));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    testWidgets('offers to add a photo when there is none', (tester) async {
      await open(tester);

      expect(find.text('Add photo'), findsOneWidget);
      expect(find.text('Change photo'), findsNothing);
    });

    testWidgets('choosing from the gallery saves it on the profile', (
      tester,
    ) async {
      await open(tester);
      picker.next = _png;

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove photo'), findsNothing);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(picker.asked, [PhotoSource.gallery]);
      expect(backend.currentUser!.photo, _png);
      expect(container.read(currentUserProvider)!.photo, _png);
      expect(find.text('Change photo'), findsOneWidget);
    });

    testWidgets('the camera is offered too', (tester) async {
      await open(tester);
      picker.next = _png;

      await choose(tester, 'Add photo', 'Take a photo');

      expect(picker.asked, [PhotoSource.camera]);
      expect(backend.currentUser!.photo, _png);
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      await open(tester);
      picker.next = null;

      await choose(tester, 'Add photo', 'Choose from gallery');

      expect(backend.currentUser!.photo, isNull);
    });

    testWidgets('a photo can be removed', (tester) async {
      await open(tester, photo: _png);

      await choose(tester, 'Change photo', 'Remove photo');

      expect(backend.currentUser!.photo, isNull);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('saving the rest of the profile keeps the photo', (
      tester,
    ) async {
      await open(tester, photo: _png);

      await container
          .read(authControllerProvider.notifier)
          .updateProfile(
            name: 'Alok S',
            bloodGroup: BloodGroup.oPos,
            dateOfBirth: DateTime(1990),
            gender: Gender.male,
            country: 'India',
            state: 'Karnataka',
            city: 'Bengaluru',
          );

      expect(backend.currentUser!.photo, _png);
    });

    testWidgets('a request made afterwards carries the photo', (tester) async {
      await open(tester, photo: _png);

      final created = await backend.createRequest(
        patientName: 'Sita',
        patientBloodGroup: BloodGroup.oPos,
        bloodGroups: const [BloodGroup.oPos],
        units: 1,
        urgency: Urgency.urgent,
        requestLocationLabel: 'Bengaluru',
        destination: const Destination(name: 'City Hospital', address: ''),
      );

      expect(created.requesterPhoto, _png);
    });
  });
}
