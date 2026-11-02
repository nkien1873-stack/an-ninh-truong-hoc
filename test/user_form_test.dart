import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/admin/data/admin_repository.dart';
import 'package:campus_safety/features/admin/presentation/campus_config_screen.dart';
import 'package:campus_safety/features/admin/presentation/users_screen.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/campus/campus_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _RecordingAdmin implements AdminRepository {
  Map<String, Object?>? updated;
  List<String>? buildings;

  @override
  Future<AppUser> updateUser(
    String uid, {
    UserRole? role,
    bool? active,
    bool? onDuty,
    String? displayName,
    MemberType? memberType,
    int? fakeReports,
    int? failedLogins,
  }) async {
    updated = {'role': role, 'active': active, 'memberType': memberType, 'failedLogins': failedLogins};
    return _user();
  }

  @override
  Future<void> updateCampus({required String campusName, required String? hotline, required List<String> buildings}) async =>
      this.buildings = buildings;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

AppUser _user({int fake = 0, bool active = true, int failedLogins = 0, DateTime? lockedUntil}) => AppUser(
      uid: 'u9',
      email: 'doduu49@gmail.com',
      phone: '',
      displayName: 'Duy',
      role: UserRole.reporter,
      memberType: MemberType.student,
      active: active,
      onDuty: false,
      fakeReports: fake,
      failedLogins: failedLogins,
      loginLockedUntil: lockedUntil,
    );

void main() {
  late _RecordingAdmin admin;

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    admin = _RecordingAdmin();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(admin),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử', hotline: '0932189062', buildings: ['Toà A1', 'Thư viện']),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Widget form(AppUser u) => Scaffold(body: SingleChildScrollView(child: UserFormSheet(existing: u)));

  testWidgets('giữ vai trò "Người báo" và ô Đối tượng', (tester) async {
    await pump(tester, form(_user()));
    expect(find.text('Người báo'), findsOneWidget);
    expect(find.text('Đối tượng'), findsOneWidget);
  });

  testWidgets('một dòng "Số lần cảnh báo" = số lần đăng nhập sai; chỉnh bằng trừ/cộng rồi lưu', (tester) async {
    await pump(tester, form(_user(failedLogins: 2)));
    expect(find.text('Số lần cảnh báo'), findsOneWidget);
    expect(find.text('Đăng nhập sai liên tiếp'), findsNothing, reason: 'đã gộp vào một dòng');
    expect(find.text('2/5'), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('warning-minus')));
      await tester.pump();
    }
    expect(find.text('0/5'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('warning-minus'))).onPressed, isNull, reason: 'không xuống dưới 0');

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('warning-plus')));
      await tester.pump();
    }
    expect(find.text('5/5'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('warning-plus'))).onPressed, isNull, reason: 'không vượt 5');
    expect(find.text('Đủ 5 lần: tạm khoá đăng nhập 15 phút.'), findsOneWidget);

    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(admin.updated!['failedLogins'], 5);
  });

  testWidgets('đang tạm khoá vì sai mật khẩu 5 lần: hiện 5/5, giờ hết khoá, bấm mở khoá là về 0', (tester) async {
    await pump(tester, form(_user(lockedUntil: DateTime(2026, 11, 2, 23, 15))));
    expect(find.text('5/5'), findsOneWidget);
    expect(find.textContaining('Đang tạm khoá đăng nhập tới 23:15'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unlock-login')));
    await tester.pumpAndSettle();
    expect(admin.updated!['failedLogins'], 0);
    expect(find.text('0/5'), findsOneWidget);
    expect(find.byKey(const Key('unlock-login')), findsNothing);
    expect(find.text('Đã mở khoá đăng nhập.'), findsOneWidget);
  });

  testWidgets('bảo vệ, quản trị không có dòng cảnh báo nhưng vẫn mở khoá được khi bị tạm khoá', (tester) async {
    await pump(tester, form(_user(lockedUntil: DateTime(2026, 11, 2, 23, 15))));
    expect(find.byKey(const Key('warning-count')), findsOneWidget);
    await tester.tap(find.text('Bảo vệ'));
    await tester.pump();
    expect(find.byKey(const Key('warning-count')), findsNothing);
    expect(find.byKey(const Key('unlock-login')), findsOneWidget);
  });

  testWidgets('khu vực: thêm, chặn trùng, xoá từng mục rồi lưu', (tester) async {
    await pump(tester, const CampusConfigScreen());
    expect(find.text('Khu vực (2)'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-building')), '  thư viện ');
    await tester.tap(find.byKey(const Key('add-building')));
    await tester.pump();
    expect(find.text('Khu vực này đã có.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('new-building')), 'Nhà xe khu B');
    await tester.tap(find.byKey(const Key('add-building')));
    await tester.pump();
    expect(find.text('Khu vực (3)'), findsOneWidget);

    await tester.tap(find.byTooltip('Xoá Toà A1'));
    await tester.pump();
    expect(find.text('Toà A1'), findsNothing);

    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(admin.buildings, ['Thư viện', 'Nhà xe khu B']);
  });
}
