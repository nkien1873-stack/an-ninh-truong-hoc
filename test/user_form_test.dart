import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/admin/presentation/users_screen.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

AppUser _user({int fake = 0, bool active = true}) => AppUser(
      uid: 'u9',
      email: 'doduu49@gmail.com',
      phone: '',
      displayName: 'Duy',
      role: UserRole.reporter,
      memberType: MemberType.student,
      active: active,
      onDuty: false,
      fakeReports: fake,
    );

void main() {
  Future<void> pump(WidgetTester tester, AppUser user) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: Scaffold(body: SingleChildScrollView(child: UserFormSheet(existing: user))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sửa tài khoản hiện số lần báo sai trên ngưỡng khoá', (tester) async {
    await pump(tester, _user(fake: 2));
    expect(find.text('Số lần báo cáo sai sự thật'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('Đủ 3 lần thì tài khoản tự bị khoá.'), findsOneWidget);
  });

  testWidgets('tài khoản đã tự khoá vì báo sai: hướng dẫn cách mở khoá', (tester) async {
    await pump(tester, _user(fake: 3, active: false));
    expect(find.text('3/3'), findsOneWidget);
    expect(find.textContaining('Đã tự khoá vì báo sai 3 lần'), findsOneWidget);
  });
}
