import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/services/location_service.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/auth/application/session.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/campus/campus_info.dart';
import 'package:campus_safety/features/safety/walk_screen.dart';
import 'package:campus_safety/features/safety/walks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'new_report_screen_test.dart' show FakeLocationService;

class _RecordingWalks implements WalkRepository {
  String? destination;
  int? minutes;

  @override
  Future<void> start({required String destination, required int minutes, LocationFix? at}) async {
    this.destination = destination;
    this.minutes = minutes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

const _student = AppUser(
  uid: 'u1',
  email: 'khoa@gmail.com',
  phone: '',
  displayName: 'Trần Minh Khoa',
  role: UserRole.reporter,
  memberType: MemberType.student,
  active: true,
  onDuty: false,
);

void main() {
  late _RecordingWalks walks;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    walks = _RecordingWalks();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(_student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử', hotline: null, buildings: ['Toà A1', 'Ký túc xá']),
        ),
        myActiveWalkProvider.overrideWith((ref) => Stream.value(null)),
        walkRepositoryProvider.overrideWithValue(walks),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: const WalkScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byKey(const Key('walk-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('chọn nơi đến trong danh sách', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('walk-destination-custom')), findsNothing);
    await choose(tester, 'Ký túc xá');
    await tester.tap(find.text('Bắt đầu đi'));
    await tester.pumpAndSettle();
    expect(walks.destination, 'Ký túc xá');
    expect(walks.minutes, 15);
  });

  testWidgets('chọn "Khác (tự nhập)" thì hiện ô nhập; bỏ trống bị nhắc, nhập rồi thì gửi đúng chữ đã gõ', (tester) async {
    await pump(tester);
    await choose(tester, 'Khác (tự nhập)');
    final custom = find.byKey(const Key('walk-destination-custom'));
    expect(custom, findsOneWidget);

    await tester.tap(find.text('Bắt đầu đi'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập nơi bạn đang đi tới.'), findsOneWidget);
    expect(walks.destination, isNull);

    await tester.enterText(custom, 'Nhà xe khu B');
    await tester.tap(find.text('Bắt đầu đi'));
    await tester.pumpAndSettle();
    expect(walks.destination, 'Nhà xe khu B');
  });
}
