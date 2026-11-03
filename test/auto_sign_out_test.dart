import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/firebase/firebase_providers.dart';
import 'package:campus_safety/core/network/api_error.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/auth/application/session.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/auth/presentation/login_screen.dart';
import 'package:campus_safety/features/campus/campus_info.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AppUser _user({bool active = true}) => AppUser(
      uid: 'u1',
      email: 'khoa@gmail.com',
      phone: '',
      displayName: 'Khoa',
      role: UserRole.reporter,
      memberType: MemberType.student,
      active: active,
      onDuty: false,
    );

void main() {
  Session sessionWith(AsyncValue<AppUser?> profile) {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWithValue(AsyncData<User?>(_FakeUser())),
      currentUserProvider.overrideWithValue(profile),
    ]);
    addTearDown(c.dispose);
    return c.read(sessionProvider);
  }

  test('vừa đăng nhập, hồ sơ chưa tải xong (còn rỗng) thì đang tải, KHÔNG tự đăng xuất', () {
    expect(sessionWith(const AsyncData(null)), isA<SessionLoading>());
    expect(sessionWith(const AsyncLoading<AppUser?>()), isA<SessionLoading>());
  });

  test('bị khoá thì phiên "locked" (app tự đăng xuất); lỗi mạng thì không', () {
    Matcher blocked({required bool locked}) =>
        isA<SessionBlocked>().having((s) => s.locked, 'locked', locked);

    expect(
      sessionWith(AsyncError(const ApiError(code: 'forbidden', statusCode: 403, message: 'khoá'), StackTrace.empty)),
      blocked(locked: true),
    );
    expect(sessionWith(AsyncData(_user(active: false))), blocked(locked: true));
    expect(sessionWith(AsyncError(ApiError.network(), StackTrace.empty)), blocked(locked: false));
    expect(sessionWith(AsyncData(_user())), isA<SessionReady>());
  });

  test('đang lỗi mạng rồi mới biết bị khoá vẫn tự đăng xuất, nhưng chỉ một lần', () {
    const network = SessionBlocked('mạng');
    const locked = SessionBlocked('khoá', locked: true);
    expect(shouldAutoSignOut(const SessionLoading(), locked), isTrue);
    expect(shouldAutoSignOut(network, locked), isTrue);
    expect(shouldAutoSignOut(locked, locked), isFalse);
    expect(shouldAutoSignOut(const SessionLoading(), network), isFalse);
  });

  test('lời nhắn đăng xuất: giữ lời nhắn cụ thể hơn khi lỗi 401 tới sau', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notice = c.read(signOutNoticeProvider.notifier);
    notice.set('Tài khoản đã bị khoá. Bạn đã được đăng xuất khỏi máy này.');
    notice.set('Phiên đăng nhập đã kết thúc.', keepExisting: true);
    expect(c.read(signOutNoticeProvider), startsWith('Tài khoản đã bị khoá.'));
    notice.clear();
    expect(c.read(signOutNoticeProvider), isNull);
  });

  testWidgets('trang đăng nhập hiện lý do vừa bị đăng xuất', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      campusInfoProvider.overrideWith((ref) async => const CampusInfo(campusName: 'T', hotline: null, buildings: [])),
    ]);
    addTearDown(c.dispose);
    c.read(signOutNoticeProvider.notifier).set('Tài khoản đã bị khoá. Bạn đã được đăng xuất khỏi máy này.');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: const LoginScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Tài khoản đã bị khoá. Bạn đã được đăng xuất khỏi máy này.'), findsOneWidget);
  });
}
