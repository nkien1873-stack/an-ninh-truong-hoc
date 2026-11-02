import 'dart:async';

import 'package:campus_core/campus_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_error.dart';
import '../../../core/router/role_navigation.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/session.dart';
import '../../campus/campus_info.dart';
import '../../campus/hotline_button.dart';
import '../application/emergency_draft.dart';
import '../application/report_submitter.dart';
import '../domain/report.dart';
import 'widgets/submit_result_view.dart';

/// Mở màn khẩn cấp (chạm 1). Gửi bằng nút "Gửi cảnh báo ngay" (chạm 2). [restore] là bản nháp
/// đang dở lần trước (người dùng bấm Home và Android đã đóng app ở nền).
///
/// Dùng màn toàn trang thay cho bottom sheet: Scaffold tự co lại khi bàn phím mở, còn bottom sheet
/// trên một số máy Android (Xiaomi) bị tính khoảng bàn phím hai lần, để lại khoảng trống lớn.
Future<void> showEmergencySheet(BuildContext context, {EmergencyDraft? restore}) async {
  unawaited(HapticFeedback.heavyImpact());
  if (!context.mounted) return;
  // Navigator gốc: phủ cả thanh điều hướng dưới, không lồng trong khung của các tab.
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => EmergencySheet(restore: restore),
  ));
}

class EmergencySheet extends ConsumerStatefulWidget {
  const EmergencySheet({super.key, this.restore});

  final EmergencyDraft? restore;

  @override
  ConsumerState<EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<EmergencySheet> {
  static const _quickTypes = [
    IncidentType.fight,
    IncidentType.fire,
    IncidentType.theft,
    IncidentType.suspicious,
    IncidentType.other,
  ];

  final _note = TextEditingController();
  IncidentType _type = IncidentType.other;
  String? _building;
  bool _anonymous = false;

  LocationFix? _location;
  String? _locationError;
  bool _locating = true;
  Future<void>? _locationRequest;

  bool _sending = false;
  String? _error;
  SubmitReportResult? _result;

  @override
  void initState() {
    super.initState();
    final restore = widget.restore;
    if (restore != null) {
      _type = restore.type;
      _building = restore.building;
      _note.text = restore.note;
      _anonymous = restore.anonymous;
    }
    _note.addListener(_saveDraft);
    _saveDraft();
    // Lấy GPS ngay khi mở để tiết kiệm thời gian.
    _locationRequest = _locate();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Lưu lựa chọn hiện tại để mở lại được nếu app bị đóng khi đang ở nền.
  void _saveDraft() {
    final uid = ref.read(signedInUserProvider)?.uid;
    if (_result != null || uid == null) return;
    unawaited(ref.read(emergencyDraftStoreProvider).save(EmergencyDraft(
          uid: uid,
          type: _type,
          building: _building,
          note: _note.text,
          anonymous: _anonymous,
          savedAt: DateTime.now(),
        )));
  }

  void _update(VoidCallback change) {
    setState(change);
    _saveDraft();
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final fix = await ref.read(locationServiceProvider).current();
      if (mounted) setState(() => _location = fix);
    } on LocationException catch (e) {
      if (mounted) setState(() => _locationError = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _send() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    // Bấm gửi khi GPS còn đang lấy: chờ thêm, không bắt người dùng bấm lại.
    final pending = _locationRequest;
    if (_locating && pending != null) {
      await pending.timeout(const Duration(seconds: 15), onTimeout: () {});
    }
    if (!mounted) return;
    if (_location == null && _building == null) {
      setState(() {
        _sending = false;
        _error = 'Chưa có vị trí GPS. Chọn khu vực rồi gửi lại, hoặc gọi trực an ninh.';
      });
      return;
    }
    try {
      final result = await ref.read(reportSubmitterProvider).submit(
            ReportDraft(
              type: _type,
              severity: Severity.critical,
              description: _note.text,
              occurredAt: DateTime.now(),
              building: _building,
              latitude: _location?.latitude,
              longitude: _location?.longitude,
              accuracyMeters: _location?.accuracyMeters,
              anonymous: _anonymous,
              emergency: true,
            ),
            images: const [],
            uploaderUid: user.uid,
          );
      unawaited(HapticFeedback.heavyImpact());
      unawaited(ref.read(emergencyDraftStoreProvider).clear());
      if (mounted) setState(() => _result = result);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final buildings = ref.watch(campusInfoProvider).value?.buildings ?? const <String>[];
    final result = _result;
    // Đọc từ hệ thống (KeyboardInsetFix có thể đã đưa viewInsets về 0 khi máy tự co cửa sổ).
    // MediaQuery.of để vẽ lại khi bàn phím mở/đóng hoặc cửa sổ đổi cỡ.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0 || View.of(context).viewInsets.bottom > 0;

    // Nội dung cuộn ở trên, nút hành động ghim ở chân màn để luôn thấy "Gửi cảnh báo ngay"
    // mà không cần cuộn, kể cả khi bàn phím đang mở, máy màn nhỏ hoặc cỡ chữ lớn.
    final Widget body;
    final Widget footer;
    if (result != null) {
      body = Column(
        key: const ValueKey('done'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text('Đã gửi cảnh báo khẩn cấp', style: theme.textTheme.titleLarge),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SubmitResultView(result: result),
        ],
      );
      footer = Column(
        key: const ValueKey('footer-done'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HotlineButton(filled: true),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.report(result.id));
            },
            child: const Text('Xem báo cáo và trao đổi'),
          ),
        ],
      );
    } else {
      body = Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cảnh báo gửi ngay tới bảo vệ trực trên ứng dụng. Các mục dưới đây không bắt buộc.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _LocationStatus(
            locating: _locating,
            location: _location,
            error: _locationError,
            onRetry: () => _locationRequest = _locate(),
          ),
          const SizedBox(height: 16),
          Text('Loại sự cố', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _quickTypes)
                ChoiceChip(
                  avatar: Icon(incidentIcon(t), size: 18),
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => _update(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _building,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Khu vực (nếu biết)'),
            items: [for (final b in buildings) DropdownMenuItem(value: b, child: Text(b))],
            onChanged: (v) => _update(() {
              _building = v;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            minLines: 1,
            maxLength: ReportLimits.maxEmergencyNoteLength,
            decoration: const InputDecoration(labelText: 'Ghi chú ngắn', counterText: ''),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: (v) => _update(() => _anonymous = v),
            title: const Text('Gửi ẩn danh'),
            subtitle: const Text('Bảo vệ không thấy tên và số điện thoại của bạn.'),
          ),
        ],
      );
      footer = Column(
        key: const ValueKey('footer-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[InlineError(_error!), const SizedBox(height: 8)],
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: FilledButton.icon(
              key: const Key('send-emergency'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.emergency,
                foregroundColor: palette.onEmergency,
                textStyle: theme.textTheme.titleMedium,
                minimumSize: const Size.fromHeight(64),
              ),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: palette.onEmergency),
                    )
                  : const Icon(Icons.campaign_rounded),
              label: Text(
                !_sending
                    ? 'Gửi cảnh báo ngay'
                    : _locating
                        ? 'Đang lấy vị trí rồi gửi…'
                        : 'Đang gửi cảnh báo…',
              ),
            ),
          ),
          // Bàn phím đang mở thì chỉ giữ nút gửi để còn chỗ cho ô đang nhập.
          if (!keyboardOpen) ...[const SizedBox(height: 8), const HotlineButton()],
        ],
      );
    }

    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);
    // Người dùng tự đóng màn (nút X, nút Back) thì bỏ bản nháp. App bị đóng ở nền hoặc điều hướng
    // gỡ màn này thì không có lần "pop" này, nên bản nháp còn để mở lại.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(ref.read(emergencyDraftStoreProvider).clear());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.sos_rounded, color: palette.emergencyText),
              const SizedBox(width: 8),
              Text(result == null ? 'Báo khẩn cấp' : 'Đã gửi'),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: AnimatedSwitcher(duration: duration, child: body),
              ),
            ),
            Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: AnimatedSwitcher(duration: duration, child: footer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({
    required this.locating,
    required this.location,
    required this.error,
    required this.onRetry,
  });

  final bool locating;
  final LocationFix? location;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget leading;
    final String text;
    if (locating) {
      leading = const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5));
      text = 'Đang lấy vị trí GPS…';
    } else if (location != null) {
      leading = Icon(Icons.my_location_rounded, color: theme.colorScheme.primary);
      text = 'Đã có vị trí GPS (sai số khoảng ${location!.accuracyMeters.round()} m)';
    } else {
      leading = Icon(Icons.location_off_rounded, color: theme.colorScheme.error);
      text = error ?? 'Chưa có vị trí GPS.';
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            if (!locating && location == null) TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
