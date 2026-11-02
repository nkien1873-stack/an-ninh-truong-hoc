import 'package:campus_core/campus_core.dart';
import 'package:campus_safety/core/theme/app_theme.dart';
import 'package:campus_safety/features/auth/application/session.dart';
import 'package:campus_safety/features/auth/domain/app_user.dart';
import 'package:campus_safety/features/reports/application/report_providers.dart';
import 'package:campus_safety/features/reports/domain/report.dart';
import 'package:campus_safety/features/reports/domain/report_repository.dart';
import 'package:campus_safety/features/reports/presentation/report_detail_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _RecordingRepository implements ReportRepository {
  String? cancelled;
  String? cancelReason;
  (ReportStatus, String?, bool)? changed;

  @override
  Future<void> cancel(String id, {String? reason}) async {
    cancelled = id;
    cancelReason = reason;
  }

  @override
  Future<void> changeStatus(String id, ReportStatus to, {String? note, bool fake = false}) async =>
      changed = (to, note, fake);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
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

const _guard = AppUser(
  uid: 'g1',
  email: 'hung@gmail.com',
  phone: '0987654321',
  displayName: 'Lê Văn Hùng',
  role: UserRole.guard,
  memberType: MemberType.staff,
  active: true,
  onDuty: true,
);

Report _report({ReportStatus status = ReportStatus.submitted, String? assigneeUid, bool fake = false}) => Report(
      id: 'r1',
      code: 'SC-261102-DUG8',
      type: IncidentType.fire,
      severity: Severity.critical,
      status: status,
      description: 'Cháy ở nhà thi đấu',
      occurredAt: DateTime(2026, 11, 2, 19, 51),
      createdAt: DateTime(2026, 11, 2, 19, 51),
      updatedAt: DateTime(2026, 11, 2, 19, 51),
      emergency: true,
      anonymous: false,
      locationText: 'Nhà thi đấu',
      reporterUid: 'u1',
      reporterName: 'Trần Minh Khoa',
      assigneeUid: assigneeUid,
      assigneeName: assigneeUid == null ? null : 'Lê Văn Hùng',
      fake: fake,
    );

/// Màn có vòng xoay chờ bảo vệ (chạy mãi) nên không dùng pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late _RecordingRepository repo;

  setUp(() => repo = _RecordingRepository());

  Future<void> pump(WidgetTester tester, AppUser viewer, ReportDetail detail) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        signedInUserProvider.overrideWithValue(viewer),
        reportRepositoryProvider.overrideWithValue(repo),
        reportDetailProvider('r1').overrideWith((ref) => Stream.value(detail)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('vi')],
        locale: const Locale('vi'),
        home: const ReportDetailScreen(reportId: 'r1'),
      ),
    ));
    await settle(tester);
  }

  testWidgets('chưa có bảo vệ nhận: người báo thấy đang chờ, chưa nhắn được, có nút Huỷ đỏ', (tester) async {
    await pump(tester, _student, ReportDetail(report: _report()));
    expect(find.text('Đang chờ bảo vệ nhận báo cáo'), findsOneWidget);
    expect(find.text('Nhắn bảo vệ'), findsNothing);
    expect(find.byKey(const Key('call-guard')), findsNothing);

    await tester.tap(find.byKey(const Key('cancel-report')));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Lý do (không bắt buộc)'), 'Đã dập lửa xong');
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await settle(tester);
    expect(repo.cancelled, 'r1');
    expect(repo.cancelReason, 'Đã dập lửa xong');
  });

  testWidgets('bảo vệ đã nhận: hiện tên, số và nút gọi; nhắn được; đang xử lý thì hết nút Huỷ', (tester) async {
    await pump(
      tester,
      _student,
      ReportDetail(
        report: _report(status: ReportStatus.inProgress, assigneeUid: 'g1'),
        assignee: const AssigneeContact(uid: 'g1', displayName: 'Lê Văn Hùng', phone: '0987654321'),
      ),
    );
    expect(find.text('Lê Văn Hùng đã nhận báo cáo'), findsOneWidget);
    expect(find.byKey(const Key('call-guard')), findsOneWidget);
    expect(find.text('Nhắn bảo vệ'), findsOneWidget);
    expect(find.byKey(const Key('cancel-report')), findsNothing);
  });

  testWidgets('bảo vệ từ chối và đánh dấu báo cáo sai sự thật', (tester) async {
    await pump(tester, _guard, ReportDetail(report: _report(status: ReportStatus.received, assigneeUid: 'g1')));
    expect(find.byKey(const Key('cancel-report')), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Từ chối'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Lý do từ chối'), 'Kiểm tra không có cháy');
    await tester.tap(find.byKey(const Key('mark-fake')));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
    await settle(tester);
    expect(repo.changed, (ReportStatus.rejected, 'Kiểm tra không có cháy', true));
  });

  testWidgets('báo cáo đã bị đánh dấu sai sự thật thì có cảnh báo', (tester) async {
    await pump(tester, _student, ReportDetail(report: _report(status: ReportStatus.rejected, fake: true)));
    expect(find.textContaining('bị đánh dấu sai sự thật'), findsOneWidget);
  });
}
