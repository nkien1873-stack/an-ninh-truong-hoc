import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/auth/application/session.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/campus/campus_info.dart';
import 'package:campus_safety/features/settings/presentation/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const student = AppUser(
    uid: 'u1',
    email: 'khoa@gmail.com',
    phone: '',
    username: 'khoa.tran',
    displayName: 'Trần Minh Khoa',
    role: UserRole.reporter,
    memberType: MemberType.student,
    active: true,
    onDuty: false,
  );

  test('chữ viết tắt lấy từ hai từ cuối của họ tên', () {
    expect(initialsOf('Đỗ Hồng Anh Duy'), 'AD');
    expect(initialsOf('kien'), 'K');
    expect(initialsOf('  '), '?');
  });

  testWidgets('hồ sơ gọn chỉ hiện họ tên; bấm vào xem đầy đủ, sửa được, không tự đổi Sinh viên/Giảng viên', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử', hotline: null, buildings: []),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    // Thẻ hồ sơ gọn: chữ viết tắt, họ tên, email; bấm vào mới thấy đầy đủ và sửa được.
    expect(find.text('MK'), findsOneWidget);
    expect(find.text('khoa.tran'), findsNothing);

    await tester.tap(find.text('Trần Minh Khoa'));
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ'), findsOneWidget);
    expect(find.text('khoa.tran'), findsOneWidget);
    expect(find.text('khoa@gmail.com'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Họ và tên'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.textContaining('do quản trị xác nhận'), findsNothing, reason: 'đã bỏ chú thích');
    expect(find.text('Người báo, Sinh viên'), findsOneWidget);
  });
}
