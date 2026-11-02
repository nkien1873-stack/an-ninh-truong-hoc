import 'package:campus_core/campus_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/network/api_error.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/profile_setup_screen.dart' show validateOptionalPhone;
import '../../auth/application/session.dart';
import '../../auth/domain/app_user.dart';
import '../data/admin_repository.dart';

class _RoleTab extends Notifier<UserRole> {
  @override
  UserRole build() => UserRole.guard;

  void set(UserRole r) => state = r;
}

final _roleTabProvider = NotifierProvider<_RoleTab, UserRole>(_RoleTab.new);

/// Quản lý tài khoản: danh sách theo vai trò, tìm kiếm, tạo trước, phân quyền, khoá.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(AppUser u, String q) {
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return u.displayName.toLowerCase().contains(q.toLowerCase()) ||
        u.email.contains(q.toLowerCase()) ||
        (digits.length >= 3 && u.phone.contains(digits.startsWith('84') ? '0${digits.substring(2)}' : digits));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(_roleTabProvider);
    final users = ref.watch(usersByRoleProvider(role));
    final me = ref.watch(signedInUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFormPage<void>(context, title: 'Thêm tài khoản', child: UserFormSheet(initialRole: role)),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Thêm tài khoản'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(value: UserRole.guard, label: Text('Bảo vệ')),
                  ButtonSegment(value: UserRole.admin, label: Text('Quản trị')),
                  ButtonSegment(value: UserRole.reporter, label: Text('Người báo')),
                ],
                selected: {role},
                onSelectionChanged: (v) => ref.read(_roleTabProvider.notifier).set(v.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Tìm theo tên, email hoặc số điện thoại',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xoá tìm kiếm',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () => const SkeletonList(),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(usersByRoleProvider(role))),
              data: (list) {
                final filtered = list.where((u) => _matches(u, _search.text.trim())).toList();
                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.person_search_outlined,
                    title: list.isEmpty ? 'Chưa có tài khoản ${role.label.toLowerCase()}' : 'Không tìm thấy',
                    message: list.isEmpty ? 'Bấm "Thêm tài khoản" để tạo.' : 'Thử từ khoá khác.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = filtered[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          !u.active
                              ? Icons.lock_outline_rounded
                              : u.onDuty
                                  ? Icons.shield_rounded
                                  : Icons.person_outline_rounded,
                        ),
                        title: Text(u.profileComplete ? u.displayName : 'Chưa có tên'),
                        subtitle: Text([
                          if (u.username.isEmpty) 'Chưa kích hoạt' else '@${u.username}',
                          if (u.studentId.isNotEmpty) 'MSSV ${u.studentId}',
                          u.email,
                          if (u.hasPhone) u.phoneDisplay,
                          if (u.fakeReports > 0) 'Báo sai ${u.fakeReports}/${FakeReportPolicy.lockThreshold} lần',
                          if (u.failedLogins > 0) 'Đăng nhập sai ${u.failedLogins}/${LoginPolicy.maxFailures}',
                          if (!u.active) 'Đã khoá',
                          if (u.onDuty) 'Đang trực',
                          if (u.uid == me?.uid) 'Bạn',
                        ].join(', ')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showFormPage<void>(
                          context,
                          title: 'Sửa tài khoản',
                          child: UserFormSheet(existing: u, isSelf: u.uid == me?.uid),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tạo mới hoặc sửa tài khoản.
class UserFormSheet extends ConsumerStatefulWidget {
  const UserFormSheet({super.key, this.existing, this.initialRole = UserRole.guard, this.isSelf = false});

  final AppUser? existing;
  final UserRole initialRole;
  final bool isSelf;

  @override
  ConsumerState<UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<UserFormSheet> {
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _name = TextEditingController(text: widget.existing?.displayName ?? '');
  late UserRole _role = widget.existing?.role ?? widget.initialRole;
  late bool _active = widget.existing?.active ?? true;
  late bool _onDuty = widget.existing?.onDuty ?? false;
  late MemberType _memberType = widget.existing?.memberType ?? MemberType.staff;
  // Số lần cảnh báo = số lần đăng nhập sai liên tiếp; đang tạm khoá thì coi như đủ 5.
  late int _failedLogins = _initialFailedLogins;
  late bool _loginLocked = widget.existing?.loginLockedUntil != null;
  bool _unlocking = false;

  int get _initialFailedLogins {
    final e = widget.existing;
    if (e == null) return 0;
    return e.loginLockedUntil != null ? LoginPolicy.maxFailures : e.failedLogins;
  }
  final _formKey = GlobalKey<FormState>();
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    try {
      if (_isNew) {
        await repo.createUser(
          email: _email.text,
          phone: _phone.text,
          displayName: _name.text.trim(),
          role: _role,
          memberType: _memberType,
          onDuty: _role.isStaff && _onDuty,
        );
      } else {
        final e = widget.existing!;
        await repo.updateUser(
          e.uid,
          displayName: _name.text.trim() != e.displayName ? _name.text.trim() : null,
          role: _role != e.role ? _role : null,
          active: _active != e.active ? _active : null,
          onDuty: _onDuty != e.onDuty ? (_role.isStaff && _onDuty) : null,
          memberType: _memberType != e.memberType ? _memberType : null,
          failedLogins: _failedLogins != _initialFailedLogins ? _failedLogins : null,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mở khoá đăng nhập ngay (tài khoản bị tạm khoá vì nhập sai mật khẩu 5 lần).
  Future<void> _unlockLogin() async {
    setState(() {
      _unlocking = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).updateUser(widget.existing!.uid, failedLogins: 0);
      if (!mounted) return;
      setState(() {
        _loginLocked = false;
        _failedLogins = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã mở khoá đăng nhập.')));
    } on ApiError catch (e) {
      setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    final who = e.profileComplete ? e.displayName : e.email;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded),
        title: const Text('Xoá tài khoản?'),
        content: Text(
          'Xoá vĩnh viễn tài khoản "$who" (${e.email}). Người này không đăng nhập được nữa và phải đăng ký lại. '
          'Các báo cáo họ đã gửi vẫn được giữ.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).deleteUser(e.uid);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text('Đã xoá tài khoản $who.')));
      }
    } on ApiError catch (err) {
      setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                enabled: _isNew,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: _isNew ? EmailAddress.validate : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                enabled: _isNew,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Số điện thoại (không bắt buộc)'),
                validator: _isNew ? validateOptionalPhone : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Họ tên'),
                validator: ProfileLimits.validateDisplayName,
              ),
              const SizedBox(height: 16),
              Text('Vai trò', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<UserRole>(
                segments: [
                  for (final r in UserRole.values)
                    ButtonSegment(value: r, label: Text(r.label), enabled: !widget.isSelf || r == UserRole.admin),
                ],
                selected: {_role},
                onSelectionChanged: (v) => setState(() => _role = v.first),
              ),
              if (_role == UserRole.reporter) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<MemberType>(
                  initialValue: _memberType,
                  decoration: const InputDecoration(labelText: 'Đối tượng'),
                  items: [for (final m in MemberType.values) DropdownMenuItem(value: m, child: Text(m.label))],
                  onChanged: (v) => setState(() => _memberType = v ?? _memberType),
                ),
              ],
              if (_role.isStaff)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _onDuty,
                  onChanged: (v) => setState(() => _onDuty = v),
                  title: const Text('Đang trực'),
                  subtitle: const Text('Nhận cảnh báo khi có sự cố mới.'),
                ),
              // Chỉ người báo có mục "Số lần cảnh báo"; bảo vệ, quản trị bị tạm khoá thì vẫn mở khoá được.
              if (!_isNew && !widget.isSelf && _role == UserRole.reporter) ...[
                const SizedBox(height: 8),
                _WarningStepper(
                  value: _failedLogins,
                  // Đang tạm khoá sẵn thì khung đỏ bên dưới đã nói, không lặp lại.
                  showLockNote: !_loginLocked,
                  onChanged: (v) => setState(() => _failedLogins = v),
                ),
              ],
              if (!_isNew && !widget.isSelf && _loginLocked) ...[
                const SizedBox(height: 8),
                InlineError(
                  'Đang tạm khoá đăng nhập tới ${formatTime(widget.existing!.loginLockedUntil!)} '
                  'vì nhập sai mật khẩu ${LoginPolicy.maxFailures} lần.',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('unlock-login'),
                  onPressed: _unlocking || _saving ? null : _unlockLogin,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(_unlocking ? 'Đang mở khoá…' : 'Mở khoá đăng nhập'),
                ),
              ],
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: widget.isSelf ? null : (v) => setState(() => _active = v),
                  title: const Text('Cho phép đăng nhập'),
                  subtitle: Text(widget.isSelf
                      ? 'Bạn không thể tự khoá tài khoản của mình.'
                      : 'Tắt để khoá tài khoản và đăng xuất khỏi mọi thiết bị.'),
                ),
              if (_error != null) ...[const SizedBox(height: 12), InlineError(_error!)],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Đang lưu…' : (_isNew ? 'Tạo tài khoản' : 'Lưu thay đổi')),
              ),
              if (!_isNew && !widget.isSelf) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Xoá tài khoản'),
                ),
              ],
            ],
          ),
        );
  }
}

/// "Số lần cảnh báo": số lần nhập sai mật khẩu liên tiếp, quản trị chỉnh bằng nút trừ/cộng (0 đến
/// [LoginPolicy.maxFailures]). Lưu ở mức tối đa là tạm khoá đăng nhập; thấp hơn là mở khoá.
class _WarningStepper extends StatelessWidget {
  const _WarningStepper({required this.value, required this.showLockNote, required this.onChanged});

  final int value;
  final bool showLockNote;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const limit = LoginPolicy.maxFailures;
    final color = value == 0 ? theme.colorScheme.onSurface : theme.colorScheme.error;
    return Column(
      key: const Key('warning-count'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Số lần cảnh báo', style: theme.textTheme.titleSmall)),
            IconButton.outlined(
              key: const Key('warning-minus'),
              tooltip: 'Bớt một lần',
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '$value/$limit',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: color),
              ),
            ),
            IconButton.outlined(
              key: const Key('warning-plus'),
              tooltip: 'Thêm một lần',
              onPressed: value < limit ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (value >= limit && showLockNote)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Đủ $limit lần: tạm khoá đăng nhập ${LoginPolicy.lockDuration.inMinutes} phút.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
