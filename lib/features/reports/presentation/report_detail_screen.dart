import 'package:campus_core/campus_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format/formatters.dart';
import '../../../core/network/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../admin/data/admin_repository.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/app_user.dart';
import '../../campus/campus_info.dart';
import '../application/report_providers.dart';
import '../domain/report.dart';
import 'widgets/report_images.dart';
import 'widgets/report_timeline.dart';

class ReportDetailScreen extends ConsumerWidget {
  const ReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportProvider(reportId));
    final user = ref.watch(signedInUserProvider);
    return report.when(
      loading: () => Scaffold(appBar: AppBar(title: const Text('Báo cáo')), body: const SkeletonList(count: 3)),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Báo cáo')),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(reportDetailProvider(reportId))),
      ),
      data: (r) {
        if (r == null || user == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Báo cáo')),
            body: const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Không tìm thấy báo cáo',
              message: 'Báo cáo có thể đã bị xoá hoặc bạn không có quyền xem.',
            ),
          );
        }
        return _ReportDetailView(report: r, user: user);
      },
    );
  }
}

class _ReportDetailView extends ConsumerStatefulWidget {
  const _ReportDetailView({required this.report, required this.user});

  final Report report;
  final AppUser user;

  @override
  ConsumerState<_ReportDetailView> createState() => _ReportDetailViewState();
}

class _ReportDetailViewState extends ConsumerState<_ReportDetailView> {
  final _comment = TextEditingController();
  bool _sendingComment = false;
  bool _busy = false;

  Report get r => widget.report;
  AppUser get user => widget.user;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeStatus(ReportStatus to) async {
    final result = await showFormPage<({String note, bool fake})>(
      context,
      title: ReportStatusMachine.actionLabel(r.status, to),
      child: _StatusNoteSheet(from: r.status, to: to, role: user.role),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(reportRepositoryProvider).changeStatus(r.id, to, note: result.note, fake: result.fake);
      _toast(result.fake ? 'Đã từ chối và đánh dấu báo cáo sai sự thật.' : 'Đã chuyển sang "${to.label}".');
    } on ApiError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Nút chuyển sang [s]: bước hợp lý nhất là nút chính, từ chối là nút viền, còn lại nút phụ.
  Widget _actionButton(ReportStatus s, {required bool primary}) {
    final label = Text(ReportStatusMachine.actionLabel(r.status, s), textAlign: TextAlign.center);
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 10);
    final onPressed = _busy ? null : () => _changeStatus(s);
    if (s == ReportStatus.rejected) {
      return OutlinedButton(style: OutlinedButton.styleFrom(padding: padding), onPressed: onPressed, child: label);
    }
    if (primary) {
      return FilledButton(style: FilledButton.styleFrom(padding: padding), onPressed: onPressed, child: label);
    }
    return FilledButton.tonal(style: FilledButton.styleFrom(padding: padding), onPressed: onPressed, child: label);
  }

  Future<void> _cancel() async {
    final reason = await showFormPage<String>(
      context,
      title: 'Huỷ báo cáo ${r.code}',
      child: _CancelSheet(report: r),
    );
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(reportRepositoryProvider).cancel(r.id, reason: reason);
      _toast('Đã huỷ báo cáo ${r.code}.');
    } on ApiError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(String uid) async {
    setState(() => _busy = true);
    try {
      await ref.read(reportRepositoryProvider).assign(r.id, uid);
      _toast('Đã phân công.');
    } on ApiError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAssignee() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssigneeSheet(currentUid: r.assigneeUid),
    );
    if (picked != null) await _assign(picked);
  }

  Future<void> _sendComment() async {
    final text = _comment.text;
    final error = validateComment(text);
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _sendingComment = true);
    try {
      await ref.read(reportRepositoryProvider).comment(r.id, text);
      _comment.clear();
    } on ApiError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = ref.watch(reportEventsProvider(r.id));
    final isOwner = !user.role.isStaff || r.reporterUid == user.uid ||
        (events.value?.any((e) => e.type == ReportEventType.created && e.actorUid == user.uid) ?? false);
    final canAct = Permissions.canChangeStatus(user.actor, assigneeUid: r.assigneeUid);
    final next = canAct ? ReportStatusMachine.nextStatuses(r.status, user.role).toList() : const <ReportStatus>[];
    // Như gọi xe: người báo chỉ nhắn được khi đã có bảo vệ nhận báo cáo (backend cũng chặn).
    final ownerOnly = isOwner && !user.role.isStaff;
    final waitingForGuard = ownerOnly && r.status.isOpen && r.assigneeUid == null;
    final canComment = Permissions.canComment(user.actor, isOwner: isOwner) && !waitingForGuard;
    final canCancel = isOwner && ReportStatusMachine.canCancel(r.status);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        title: Text(r.code, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        actions: [
          if (canCancel)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                key: const Key('cancel-report'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _busy ? null : _cancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Huỷ'),
              ),
            ),
        ],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (r.emergency)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: context.palette.emergency, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.sos_rounded, color: context.palette.onEmergency, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Báo cáo KHẨN CẤP',
                    style: theme.textTheme.titleSmall?.copyWith(color: context.palette.onEmergency),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(incidentIcon(r.type), size: 28, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(r.type.label, style: theme.textTheme.headlineSmall)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(r.status, large: true),
              // Khẩn cấp luôn ở mức cao nhất: banner phía trên đã nói, không lặp lại.
              if (!r.emergency) SeverityBadge(r.severity, large: true),
            ],
          ),
          if (r.fake) ...[
            const SizedBox(height: 12),
            InfoNote(
              'Báo cáo này bị đánh dấu sai sự thật. Báo sai ${FakeReportPolicy.lockThreshold} lần thì tài khoản bị khoá.',
              icon: Icons.report_gmailerrorred_rounded,
            ),
          ],
          if (ownerOnly && r.status.isOpen) ...[
            const SizedBox(height: 12),
            _GuardContactCard(report: r),
          ],
          const SizedBox(height: 16),
          _InfoRow(icon: Icons.schedule_rounded, text: 'Xảy ra lúc ${formatDateTime(r.occurredAt)}'),
          _InfoRow(icon: Icons.outbox_rounded, text: 'Gửi lúc ${formatDateTime(r.createdAt)}'),
          _InfoRow(
            icon: Icons.place_outlined,
            text: r.locationText,
            action: r.hasCoordinates
                ? TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse('https://www.google.com/maps/search/?api=1&query=${r.latitude},${r.longitude}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Mở bản đồ'),
                  )
                : null,
          ),
          if (r.hasCoordinates && r.accuracyMeters != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 8),
              child: Text('GPS sai số khoảng ${r.accuracyMeters!.round()} m', style: muted),
            ),
          const SizedBox(height: 16),
          const SectionTitle('Mô tả'),
          Text(r.description, style: theme.textTheme.bodyLarge),
          if (r.imagePaths.isNotEmpty) ...[
            const SizedBox(height: 24),
            SectionTitle('Ảnh (${r.imagePaths.length})'),
            ReportImages(paths: r.imagePaths),
          ],
          const SizedBox(height: 24),
          const SectionTitle('Người báo'),
          _ReporterSection(report: r, viewer: user, isOwner: isOwner),
          if (user.role.isStaff) ...[
            const SizedBox(height: 24),
            const SectionTitle('Xử lý'),
            _AssignmentSection(
              report: r,
              viewer: user,
              onAssignSelf: () => _assign(user.uid),
              onPick: _pickAssignee,
            ),
            if (next.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Mọi lựa chọn trên một hàng (chữ dài thì xuống dòng trong nút) để nút "Từ chối" không
              // rơi xuống dòng dưới, bị ô nhắn tin che khi bàn phím mở.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    for (final (i, s) in next.indexed) Expanded(child: _actionButton(s, primary: i == 0)),
                  ],
                ),
              ),
            ] else if (!canAct && r.status.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Báo cáo đang do ${r.assigneeName ?? 'người khác'} xử lý.', style: muted),
              ),
          ],
          if (r.lastNote != null && !user.role.isStaff) ...[
            const SizedBox(height: 16),
            InfoNote(
              r.status == ReportStatus.cancelled ? 'Lý do huỷ: ${r.lastNote}' : 'Ghi chú mới nhất của bảo vệ: ${r.lastNote}',
              icon: Icons.sticky_note_2_outlined,
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('Lịch sử và trao đổi'),
          events.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorMessage(e), style: muted),
            data: (items) => ReportTimeline(
              events: items,
              currentUid: user.uid,
              viewerIsAnonymousReporter: isOwner && r.anonymous,
            ),
          ),
        ],
      ),
      bottomNavigationBar: canComment
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: ReportLimits.maxCommentLength,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: user.role.isStaff ? 'Nhắn người báo' : 'Nhắn bảo vệ',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: 'Gửi',
                      onPressed: _sendingComment ? null : _sendComment,
                      icon: _sendingComment
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

/// Thẻ liên hệ cho người báo, như ứng dụng gọi xe: chờ bảo vệ nhận, rồi hiện tên và nút gọi.
class _GuardContactCard extends ConsumerWidget {
  const _GuardContactCard({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (report.assigneeUid == null) {
      return const Card(
        child: ListTile(
          leading: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          title: Text('Đang chờ bảo vệ nhận báo cáo'),
          subtitle: Text('Khi bảo vệ nhận, bạn sẽ gọi hoặc nhắn trực tiếp được với họ.'),
        ),
      );
    }
    final contact = ref.watch(assigneeContactProvider(report.id)).value;
    final phone = contact?.phone;
    final onCard = TextStyle(color: theme.colorScheme.onPrimaryContainer);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.verified_user_rounded, color: theme.colorScheme.onPrimaryContainer),
        title: Text('${contact?.displayName ?? report.assigneeName ?? 'Bảo vệ'} đã nhận báo cáo', style: onCard),
        subtitle: Text(
          phone == null
              ? 'Nhắn bảo vệ ở ô bên dưới.'
              : '${VietnamPhone.tryParse(phone)?.display ?? phone}. Gọi hoặc nhắn ở ô bên dưới.',
          style: onCard,
        ),
        trailing: phone == null
            ? null
            : IconButton.filled(
                key: const Key('call-guard'),
                tooltip: 'Gọi bảo vệ',
                onPressed: () => callHotline(phone),
                icon: const Icon(Icons.call_rounded),
              ),
      ),
    );
  }
}

/// Xác nhận huỷ báo cáo, kèm lý do (không bắt buộc). Trả về lý do (có thể rỗng).
class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.report});

  final Report report;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Bảo vệ sẽ được báo là bạn đã huỷ. Báo cáo vẫn được lưu với trạng thái "Đã huỷ" để tra cứu.'),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              minLines: 1,
              maxLines: 3,
              maxLength: ReportStatusMachine.maxCancelReasonLength,
              decoration: const InputDecoration(labelText: 'Lý do (không bắt buộc)', hintText: 'Ví dụ: đã tìm thấy đồ'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('confirm-cancel'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, _reason.text.trim()),
              child: const Text('Huỷ báo cáo'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Không huỷ')),
          ],
        );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ?action,
        ],
      ),
    );
  }
}

class _ReporterSection extends ConsumerWidget {
  const _ReporterSection({required this.report, required this.viewer, required this.isOwner});

  final Report report;
  final AppUser viewer;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    if (isOwner) {
      return Text(
        report.anonymous ? 'Bạn (ẩn danh với bảo vệ)' : 'Bạn',
        style: theme.textTheme.bodyLarge,
      );
    }
    if (!report.anonymous) {
      final phone = report.reporterPhone;
      return Card(
        child: ListTile(
          leading: const Icon(Icons.person_outline_rounded),
          title: Text(report.reporterName ?? 'Chưa có tên'),
          subtitle: Text([
            if (report.reporterMemberType != null) report.reporterMemberType!.label,
            if (phone != null) VietnamPhone.tryParse(phone)?.display ?? phone,
          ].join(', ')),
          trailing: phone == null
              ? null
              : IconButton(
                  tooltip: 'Gọi người báo',
                  onPressed: () => callHotline(phone),
                  icon: const Icon(Icons.call_rounded),
                ),
        ),
      );
    }
    // Ẩn danh: bảo vệ không thấy gì; quản trị đọc được tài liệu private.
    if (!Permissions.canSeeReporterContact(viewer.actor, anonymous: true, isOwner: false)) {
      return Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text('Người báo ẩn danh. Trao đổi qua mục bên dưới.', style: muted)),
        ],
      );
    }
    final contact = ref.watch(reporterContactProvider(report.id)).value;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.visibility_off_outlined),
        title: Text(contact == null ? 'Người báo ẩn danh' : (contact.displayName.isEmpty ? 'Chưa có tên' : contact.displayName)),
        subtitle: Text(contact == null
            ? 'Đang tải danh tính (chỉ quản trị xem được).'
            : '${VietnamPhone.tryParse(contact.phone)?.display ?? contact.phone}. Chỉ quản trị thấy thông tin này.'),
      ),
    );
  }
}

class _AssignmentSection extends StatelessWidget {
  const _AssignmentSection({
    required this.report,
    required this.viewer,
    required this.onAssignSelf,
    required this.onPick,
  });

  final Report report;
  final AppUser viewer;
  final VoidCallback onAssignSelf;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final canPick = viewer.role == UserRole.admin && report.status.isOpen;
    // "Tiếp nhận"/"Bắt đầu xử lý" đã tự nhận việc khi báo cáo còn "Đã gửi", nên chỉ hiện
    // "Nhận xử lý" ở các trạng thái sau (ví dụ quản trị mở lại báo cáo chưa có người giữ).
    final canTake = viewer.role == UserRole.guard &&
        report.status.isOpen &&
        report.status != ReportStatus.submitted &&
        Permissions.canAssign(viewer.actor, targetUid: viewer.uid, currentAssigneeUid: report.assigneeUid) &&
        report.assigneeUid != viewer.uid;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.assignment_ind_outlined),
        title: Text(report.assigneeName == null ? 'Chưa phân công' : 'Người xử lý: ${report.assigneeName}'),
        subtitle: report.closedAt != null ? Text('Đóng lúc ${formatDateTime(report.closedAt!)}') : null,
        trailing: canPick
            ? TextButton(onPressed: onPick, child: Text(report.assigneeUid == null ? 'Phân công' : 'Đổi'))
            : canTake
                ? TextButton(onPressed: onAssignSelf, child: const Text('Nhận xử lý'))
                : null,
      ),
    );
  }
}

/// Xác nhận chuyển trạng thái, kèm ghi chú (bắt buộc khi từ chối). Khi từ chối có thể đánh dấu
/// báo cáo sai sự thật. Trả về ghi chú (có thể rỗng) và dấu báo sai.
class _StatusNoteSheet extends StatefulWidget {
  const _StatusNoteSheet({required this.from, required this.to, required this.role});

  final ReportStatus from;
  final ReportStatus to;
  final UserRole role;

  @override
  State<_StatusNoteSheet> createState() => _StatusNoteSheetState();
}

class _StatusNoteSheetState extends State<_StatusNoteSheet> {
  final _note = TextEditingController();
  String? _error;
  bool _fake = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    final error = ReportStatusMachine.validate(
      from: widget.from,
      to: widget.to,
      role: widget.role,
      note: _note.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (note: _note.text.trim(), fake: _fake));
  }

  @override
  Widget build(BuildContext context) {
    final rejecting = widget.to == ReportStatus.rejected;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Người báo sẽ nhận thông báo về trạng thái "${widget.to.label}".'),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            autofocus: rejecting,
            minLines: 2,
            maxLines: 5,
            maxLength: ReportStatusMachine.maxNoteLength,
            decoration: InputDecoration(
              labelText: rejecting ? 'Lý do từ chối' : 'Ghi chú (không bắt buộc)',
              errorText: _error,
            ),
          ),
          if (rejecting)
            CheckboxListTile(
              key: const Key('mark-fake'),
              contentPadding: EdgeInsets.zero,
              value: _fake,
              onChanged: (v) => setState(() => _fake = v ?? false),
              title: const Text('Báo cáo sai sự thật (tin giả)'),
              subtitle: const Text(
                'Người báo bị đánh dấu ${FakeReportPolicy.lockThreshold} lần sẽ tự động bị khoá tài khoản.',
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _confirm, child: const Text('Xác nhận')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        ],
      );
  }
}

/// Chọn bảo vệ/quản trị để giao việc (chỉ quản trị).
class _AssigneeSheet extends ConsumerWidget {
  const _AssigneeSheet({required this.currentUid});

  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: staff.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(error: e),
          data: (list) {
            final active = list.where((u) => u.active).toList()
              ..sort((a, b) {
                if (a.onDuty != b.onDuty) return a.onDuty ? -1 : 1;
                return a.nameOrEmail.compareTo(b.nameOrEmail);
              });
            if (active.isEmpty) {
              return const EmptyState(
                icon: Icons.group_off_outlined,
                title: 'Chưa có bảo vệ',
                message: 'Tạo tài khoản bảo vệ ở Quản lý > Tài khoản.',
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Giao cho', style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final u in active)
                  ListTile(
                    enabled: u.uid != currentUid,
                    leading: Icon(u.onDuty ? Icons.shield_rounded : Icons.shield_outlined),
                    title: Text(u.nameOrEmail),
                    subtitle: Text('${u.role.label}${u.onDuty ? ', đang trực' : ''}'),
                    trailing: u.uid == currentUid ? const Text('Đang giữ') : null,
                    onTap: () => Navigator.pop(context, u.uid),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
