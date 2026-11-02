import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/services/image_service.dart';
import 'package:campus_safety/core/services/location_service.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/core/widgets/keyboard_inset_fix.dart';
import 'package:campus_safety/features/auth/application/session.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/campus/campus_info.dart';
import 'package:campus_safety/features/reports/application/emergency_draft.dart';
import 'package:campus_safety/features/reports/application/report_providers.dart';
import 'package:campus_safety/features/reports/domain/report.dart';
import 'package:campus_safety/features/reports/presentation/emergency_sheet.dart';
import 'package:campus_safety/features/reports/presentation/widgets/report_timeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'new_report_screen_test.dart' show FakeImageService, FakeReportRepository;

/// GPS trả kết quả khi test gọi [complete] / [fail].
class ControlledLocation implements LocationService {
  // Tạo Completer khi app gọi current() (cùng zone với app) để lỗi tới được catch của app cả khi
  // chạy trên máy thật, nơi frame không chạy trong zone của test.
  Completer<LocationFix>? _completer;
  Completer<LocationFix> get _fix => _completer ??= Completer<LocationFix>();

  void complete() => _fix.complete(const LocationFix(latitude: 21.0285, longitude: 105.8542, accuracyMeters: 12));

  void fail() => _fix.completeError(const LocationException('GPS đang tắt. Bật Vị trí trong cài đặt máy.'));

  @override
  Future<LocationFix> current() => _fix.future;

  @override
  Future<void> openSettings() async {}
}

const _student = AppUser(
  uid: 'u1',
  email: 'khoa@gmail.com',
  phone: '0912345678',
  displayName: 'Trần Minh Khoa',
  role: UserRole.reporter,
  memberType: MemberType.student,
  active: true,
  onDuty: false,
);

void main() {
  Future<void> pumpSheet(WidgetTester tester, FakeReportRepository repo, ControlledLocation location) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(_student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(
            campusName: 'Trường thử nghiệm',
            hotline: '0243 868 1234',
            buildings: ['Toà A1', 'Bãi xe'],
          ),
        ),
        reportRepositoryProvider.overrideWithValue(repo),
        imageServiceProvider.overrideWithValue(FakeImageService()),
        locationServiceProvider.overrideWithValue(location),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: const Scaffold(body: EmergencySheet()),
      ),
    ));
    await tester.pump();
  }

  testWidgets('bấm gửi khi GPS chưa xong: chờ GPS rồi gửi, không báo lỗi', (tester) async {
    final repo = FakeReportRepository();
    final location = ControlledLocation();
    await pumpSheet(tester, repo, location);

    expect(find.text('Đang lấy vị trí GPS…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('send-emergency')));
    await tester.pump();
    expect(find.text('Đang lấy vị trí rồi gửi…'), findsOneWidget);
    expect(repo.submitted, isNull);

    location.complete();
    await tester.pumpAndSettle();

    final sent = repo.submitted!;
    expect(sent.emergency, isTrue);
    expect(sent.latitude, 21.0285);
    expect(sent.effectiveSeverity, Severity.critical);
    expect(find.text('Đã gửi cảnh báo khẩn cấp'), findsOneWidget);
    expect(find.text('SC-261019-K7Q4'), findsOneWidget);
  });

  testWidgets('GPS lỗi và chưa chọn khu vực: báo cách xử lý, không gửi', (tester) async {
    final repo = FakeReportRepository();
    final location = ControlledLocation();
    await pumpSheet(tester, repo, location);

    location.fail();
    await tester.pumpAndSettle();
    expect(find.text('GPS đang tắt. Bật Vị trí trong cài đặt máy.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('send-emergency')));
    await tester.pumpAndSettle();
    expect(repo.submitted, isNull);
    expect(find.textContaining('Chọn khu vực rồi gửi lại'), findsOneWidget);
    // Nút gọi trực luôn hiện trong sheet.
    expect(find.textContaining('Gọi trực an ninh'), findsOneWidget);
  });

  testWidgets('bàn phím mở khi nhập ghi chú: không tràn màn hình, vẫn thấy ô ghi chú và nút gửi', (tester) async {
    // Cỡ máy thật trong ảnh lỗi (900x2000 px). Trên máy đó phần trống dưới sheet còn lớn hơn
    // bàn phím, nên thử với khoảng trống rất ít: chỉ khoảng 1/4 màn hình cho sheet.
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 2.5;
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 60);
    tester.view.viewInsets = const FakeViewPadding(bottom: 1450);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(_student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử nghiệm', hotline: '0932189062', buildings: ['Toà A1']),
        ),
        reportRepositoryProvider.overrideWithValue(FakeReportRepository()),
        imageServiceProvider.overrideWithValue(FakeImageService()),
        locationServiceProvider.overrideWithValue(ControlledLocation()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showEmergencySheet(context), child: const Text('SOS')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('SOS'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(TextField, 'Ghi chú ngắn'));
    await tester.ensureVisible(find.byKey(const Key('send-emergency')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('máy thật (900x2000, bàn phím 742 px), mở từ tab trong khung có thanh điều hướng: không có khoảng trống',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 2.5;
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 60);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(_student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử nghiệm', hotline: '0932189062', buildings: ['Toà A1']),
        ),
        reportRepositoryProvider.overrideWithValue(FakeReportRepository()),
        imageServiceProvider.overrideWithValue(FakeImageService()),
        locationServiceProvider.overrideWithValue(ControlledLocation()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        // Như HomeShell: trang chủ nằm trong Navigator riêng của khung có thanh điều hướng dưới.
        // Khung này đã tự co lại khi bàn phím mở; mở SOS bên trong nó là bị trừ bàn phím hai lần.
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) =>
                  TextButton(onPressed: () => showEmergencySheet(context), child: const Text('SOS')),
            ),
          ),
          bottomNavigationBar: const SizedBox(height: 80, child: Text('Thanh điều hướng')),
        ),
      ),
    ));
    await tester.tap(find.text('SOS'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Chạm vào ô ghi chú: bàn phím bật lên.
    final note = find.widgetWithText(TextField, 'Ghi chú ngắn');
    await tester.ensureVisible(note);
    await tester.showKeyboard(note);
    tester.view.viewInsets = const FakeViewPadding(bottom: 742);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    const keyboardTop = (2000 - 742) / 2.5;
    final noteBox = tester.getRect(note);
    final send = tester.getRect(find.byKey(const Key('send-emergency')));
    expect(noteBox.bottom, lessThanOrEqualTo(send.top), reason: 'ô ghi chú nằm trên nút gửi, không bị che');
    expect(noteBox.top, greaterThan(0), reason: 'ô ghi chú hiện trên màn hình');
    expect(send.bottom, lessThanOrEqualTo(keyboardTop), reason: 'nút gửi không bị bàn phím che');
    // Lỗi cũ: giữa nội dung và bàn phím có khoảng trống cao bằng cả bàn phím (~300 dp). Giờ chỉ còn
    // lề của khung nút (12 dp) và vùng an toàn (24 dp, máy thật bỏ đi khi bàn phím mở).
    expect(keyboardTop - send.bottom, lessThan(50), reason: 'không còn khoảng trống lớn trên bàn phím');
    // ignore: avoid_print
    print('ghi chu ${noteBox.top.round()}-${noteBox.bottom.round()}, nut gui ${send.top.round()}-${send.bottom.round()}, '
        'mep ban phim ${keyboardTop.round()} (dp)');
  });

  test('khoảng bàn phím: trừ phần cửa sổ hệ điều hành đã co lại', () {
    // Máy bình thường: cửa sổ giữ nguyên, chừa đủ bàn phím.
    expect(KeyboardInsetFix.effectiveInset(reported: 297, baselineHeight: 800, height: 800), 297);
    // Samsung/Xiaomi: cửa sổ đã co 297 dp cho bàn phím, không chừa thêm nữa.
    expect(KeyboardInsetFix.effectiveInset(reported: 297, baselineHeight: 800, height: 503), 0);
    // Co một phần thì chỉ chừa phần còn lại.
    expect(KeyboardInsetFix.effectiveInset(reported: 297, baselineHeight: 800, height: 700), 197);
  });

  testWidgets('máy co cửa sổ cho bàn phím mà vẫn báo khoảng bàn phím (Samsung, Xiaomi): không bị trừ hai lần',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 2.5;
    tester.view.padding = const FakeViewPadding(top: 100, bottom: 60);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(_student),
        campusInfoProvider.overrideWith(
          (ref) async => const CampusInfo(campusName: 'Trường thử nghiệm', hotline: '0932189062', buildings: ['Toà A1']),
        ),
        reportRepositoryProvider.overrideWithValue(FakeReportRepository()),
        imageServiceProvider.overrideWithValue(FakeImageService()),
        locationServiceProvider.overrideWithValue(ControlledLocation()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        builder: (context, child) => KeyboardInsetFix(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => showEmergencySheet(context), child: const Text('SOS')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('SOS'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final note = find.widgetWithText(TextField, 'Ghi chú ngắn');
    await tester.ensureVisible(note);
    await tester.showKeyboard(note);
    // Đúng như máy thật: cửa sổ app bị co còn 1258 px VÀ vẫn báo bàn phím 742 px.
    tester.view.physicalSize = const Size(900, 2000 - 742);
    tester.view.viewInsets = const FakeViewPadding(bottom: 742);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    const windowBottom = (2000 - 742) / 2.5;
    final send = tester.getRect(find.byKey(const Key('send-emergency')));
    expect(send.bottom, lessThanOrEqualTo(windowBottom));
    expect(windowBottom - send.bottom, lessThan(50), reason: 'nút gửi nằm sát bàn phím, không có khoảng trống');
    expect(tester.getRect(note).bottom, lessThanOrEqualTo(send.top));
  });

  group('bản nháp SOS khi bấm Home', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('lưu, đọc lại; quá 15 phút thì bỏ', () async {
      final store = EmergencyDraftStore();
      final at = DateTime(2026, 11, 2, 19, 58);
      final draft = EmergencyDraft(uid: 'u1', type: IncidentType.fire, building: 'Toà A1', note: 'Khói ở tầng 3', anonymous: true, savedAt: at);
      await store.save(draft);
      final back = (await store.load('u1', now: at.add(const Duration(minutes: 5))))!;
      expect((back.type, back.building, back.note, back.anonymous), (IncidentType.fire, 'Toà A1', 'Khói ở tầng 3', true));
      expect(await store.load('u1', now: at.add(const Duration(minutes: 16))), isNull);
      expect(await store.load('u1', now: at), isNull, reason: 'bản nháp quá hạn đã bị xoá');

      await store.save(draft);
      expect(await store.load('u2', now: at), isNull, reason: 'người khác đăng nhập máy này không thấy');
      expect(await store.load('u1', now: at), isNull, reason: 'và bản nháp đã bị xoá');
    });

    testWidgets('mở lại từ bản nháp giữ nguyên lựa chọn; người dùng tự đóng thì xoá bản nháp', (tester) async {
      final store = EmergencyDraftStore();
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          signedInUserProvider.overrideWithValue(_student),
          campusInfoProvider.overrideWith(
            (ref) async => const CampusInfo(campusName: 'Trường thử nghiệm', hotline: '0243 868 1234', buildings: ['Toà A1']),
          ),
          reportRepositoryProvider.overrideWithValue(FakeReportRepository()),
          imageServiceProvider.overrideWithValue(FakeImageService()),
          locationServiceProvider.overrideWithValue(ControlledLocation()),
          emergencyDraftStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('vi')],
          locale: const Locale('vi'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEmergencySheet(
                  context,
                  restore: EmergencyDraft(
                    uid: 'u1',
                    type: IncidentType.fight,
                    building: 'Toà A1',
                    note: 'Hai nhóm đánh nhau',
                    anonymous: true,
                    savedAt: DateTime.now(),
                  ),
                ),
                child: const Text('SOS'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('SOS'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Hai nhóm đánh nhau'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, IncidentType.fight.label)).selected, isTrue);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, IncidentType.fire.label));
      await tester.pump(const Duration(milliseconds: 300));
      expect((await store.load('u1'))!.type, IncidentType.fire);

      // Người dùng bấm Back để đóng sheet.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(await store.load('u1'), isNull);
    });
  });

  group('ReportTimeline', () {
    final events = [
      ReportEventItem(
        id: 'e1',
        type: ReportEventType.comment,
        createdAt: DateTime(2026, 10, 19, 9),
        actorName: 'Người báo (ẩn danh)',
        actorRole: UserRole.reporter,
        note: 'Họ đi về phía cổng sau.',
      ),
    ];

    Future<void> pumpTimeline(WidgetTester tester, {required bool anonymousOwner}) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ReportTimeline(events: events, currentUid: 'u1', viewerIsAnonymousReporter: anonymousOwner),
          ),
        ));

    testWidgets('người báo ẩn danh thấy bình luận của mình là "Bạn"', (tester) async {
      await pumpTimeline(tester, anonymousOwner: true);
      expect(find.text('Bạn'), findsOneWidget);
    });

    testWidgets('bảo vệ thấy "Người báo (ẩn danh)"', (tester) async {
      await pumpTimeline(tester, anonymousOwner: false);
      expect(find.text('Người báo (ẩn danh)'), findsOneWidget);
      expect(find.text('Bạn'), findsNothing);
    });
  });
}
