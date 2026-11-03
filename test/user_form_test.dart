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
    updated = {'role': role, 'active': active, 'memberType': memberType, 'fakeReports': fakeReports, 'failedLogins': failedLogins};
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

  bool lockOn(WidgetTester t) => t.widget<SwitchListTile>(find.byKey(const Key('lock-account'))).value;
  bool lockEnabled(WidgetTester t) => t.widget<SwitchListTile>(find.byKey(const Key('lock-account'))).onChanged != null;

  Future<void> tapKey(WidgetTester t, String key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await t.tap(find.byKey(Key(key)));
      await t.pump();
    }
  }

  testWidgets('"Số lần cảnh báo" là số lần báo tin giả (0 đến 3); lên 3 thì tự bật khoá và không tắt được', (tester) async {
    await pump(tester, form(_user(fake: 1)));
    expect(find.text('Số lần cảnh báo'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(lockOn(tester), isFalse);

    await tapKey(tester, 'warning-plus', 2);
    expect(find.text('3/3'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('warning-plus'))).onPressed, isNull, reason: 'không vượt 3');
    expect(lockOn(tester), isTrue, reason: 'đủ 3 cảnh báo thì tự bật khoá');
    expect(lockEnabled(tester), isFalse, reason: 'đang 3 cảnh báo thì không tắt khoá được');
    expect(find.textContaining('Giảm số lần cảnh báo xuống dưới 3'), findsOneWidget);

    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(admin.updated!['fakeReports'], 3);
    expect(admin.updated!['active'], isFalse);
  });

  testWidgets('muốn mở khoá phải giảm cảnh báo xuống dưới 3 rồi mới tắt được khoá', (tester) async {
    await pump(tester, form(_user(fake: 3, active: false)));
    expect(lockOn(tester), isTrue);
    expect(lockEnabled(tester), isFalse);

    await tapKey(tester, 'warning-minus');
    expect(find.text('2/3'), findsOneWidget);
    expect(lockOn(tester), isTrue, reason: 'giảm cảnh báo không tự mở khoá');
    expect(lockEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('lock-account')));
    await tester.pump();
    expect(lockOn(tester), isFalse);
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(admin.updated!['fakeReports'], 2);
    expect(admin.updated!['active'], isTrue);
  });

  testWidgets('bật khoá tay khi chưa đủ cảnh báo', (tester) async {
    await pump(tester, form(_user()));
    await tester.tap(find.byKey(const Key('lock-account')));
    await tester.pump();
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(admin.updated!['active'], isFalse);
  });

  testWidgets('tạm khoá vì sai mật khẩu 5 lần là việc riêng: có nút mở khoá đăng nhập', (tester) async {
    await pump(tester, form(_user(lockedUntil: DateTime(2026, 11, 2, 23, 15))));
    expect(find.textContaining('Đang tạm khoá đăng nhập tới 23:15'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-login')));
    await tester.pumpAndSettle();
    expect(admin.updated!['failedLogins'], 0);
    expect(find.byKey(const Key('unlock-login')), findsNothing);
  });

  testWidgets('bảo vệ, quản trị không có dòng cảnh báo', (tester) async {
    await pump(tester, form(_user()));
    expect(find.byKey(const Key('warning-count')), findsOneWidget);
    await tester.tap(find.text('Bảo vệ'));
    await tester.pump();
    expect(find.byKey(const Key('warning-count')), findsNothing);
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
