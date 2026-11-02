import 'package:campus_core/campus_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_error.dart';
import '../../../core/settings/theme_mode_controller.dart';
import '../../../core/widgets/form_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_scaffold.dart' show PasswordField;
import '../../auth/presentation/profile_setup_screen.dart' show validateOptionalPhone;
import '../../campus/campus_info.dart';

/// Cài đặt: hồ sơ, trạng thái trực (bảo vệ/quản trị), giao diện sáng/tối, ngôn ngữ, đăng xuất.
/// Hai chữ đầu của hai từ cuối trong họ tên ("Đỗ Hồng Anh Duy" → "AD"), viết hoa.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final picked = words.length == 1 ? words : words.sublist(words.length - 2);
  return picked.map((w) => w.characters.first.toUpperCase()).join();
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _savingDuty = false;

  Future<void> _toggleDuty(bool value) async {
    setState(() => _savingDuty = true);
    try {
      await ref.read(authRepositoryProvider).updateProfile(onDuty: value);
    } on ApiError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingDuty = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Máy này sẽ ngừng nhận thông báo của tài khoản. Báo cáo đã gửi không bị ảnh hưởng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok == true) await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(signedInUserProvider);
    final mode = ref.watch(themeModeProvider);
    final campus = ref.watch(campusInfoProvider).value;
    final theme = Theme.of(context);
    if (user == null) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Kiểu ứng dụng sinh viên: chữ viết tắt, "Họ tên (MSSV)", email; bấm vào để xem đủ và sửa.
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: Text(initialsOf(user.nameOrEmail), style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                )),
              ),
              title: Text(
                user.studentId.isEmpty ? user.nameOrEmail : '${user.nameOrEmail} (${user.studentId})',
                style: theme.textTheme.titleMedium,
              ),
              subtitle: Text(user.email),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showFormPage<void>(context, title: 'Hồ sơ', child: _EditProfileSheet(user: user)),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text('Đổi mật khẩu'),
              subtitle: const Text('Cần nhập mật khẩu hiện tại.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showFormPage<void>(context, title: 'Đổi mật khẩu', child: const _ChangePasswordSheet()),
            ),
          ),
          if (user.role.isStaff) ...[
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                value: user.onDuty,
                onChanged: _savingDuty ? null : _toggleDuty,
                secondary: Icon(user.onDuty ? Icons.shield_rounded : Icons.shield_outlined),
                title: const Text('Đang trực'),
                subtitle: const Text('Bật để nhận cảnh báo ngay khi có sự cố mới.'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SectionTitle('Giao diện'),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('Theo máy'), icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(value: ThemeMode.light, label: Text('Sáng'), icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Tối'), icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {mode},
            onSelectionChanged: (v) => ref.read(themeModeProvider.notifier).set(v.first),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Ngôn ngữ'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.language_rounded),
              title: Text('Tiếng Việt'),
              subtitle: Text('Ngôn ngữ mặc định của ứng dụng'),
              trailing: Icon(Icons.check_rounded),
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Về ứng dụng'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text(AppConfig.appName),
              subtitle: Text([
                if (campus != null && campus.campusName.isNotEmpty) campus.campusName,
                'Đăng nhập bằng tên đăng nhập và mật khẩu; mã xác nhận gửi qua email',
              ].join('\n')),
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});

  final AppUser user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _name = TextEditingController(text: widget.user.displayName);
  late final _phone = TextEditingController(text: widget.user.phone);
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            displayName: _name.text.trim(),
            phone: _phone.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final theme = Theme.of(context);
    Widget info(IconData icon, String label, String value) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          subtitle: Text(value, style: theme.textTheme.bodyLarge),
        );
    return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (u.username.isNotEmpty) info(Icons.alternate_email_rounded, 'Tên đăng nhập', u.username),
            if (u.studentId.isNotEmpty) info(Icons.school_outlined, 'Mã số sinh viên', u.studentId),
            info(Icons.mail_outline_rounded, 'Email', u.email),
            info(
              Icons.badge_outlined,
              'Vai trò',
              u.role == UserRole.reporter ? '${u.role.label}, ${u.memberType.label}' : u.role.label,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: ProfileLimits.maxNameLength,
              decoration: const InputDecoration(labelText: 'Họ và tên', counterText: ''),
              validator: ProfileLimits.validateDisplayName,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ .\-]'))],
              decoration: const InputDecoration(
                labelText: 'Số điện thoại (không bắt buộc)',
                hintText: '0912 345 678',
              ),
              validator: validateOptionalPhone,
            ),
            if (_error != null) ...[const SizedBox(height: 12), InlineError(_error!)],
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu…' : 'Lưu')),
          ],
        ),
      );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(_current.text, _next.text);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(const SnackBar(content: Text('Đã đổi mật khẩu.')));
      }
    } on ApiError catch (e) {
      setState(() {
        _fieldErrors = e.fieldErrors;
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _current,
                label: 'Mật khẩu hiện tại',
                errorText: _fieldErrors['currentPassword'],
                validator: (v) => (v ?? '').isEmpty ? 'Nhập mật khẩu hiện tại.' : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _next,
                label: 'Mật khẩu mới',
                autofillHints: const [AutofillHints.newPassword],
                errorText: _fieldErrors['newPassword'],
                validator: PasswordPolicy.validate,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Nhập lại mật khẩu mới',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                validator: (v) => v != _next.text ? 'Mật khẩu nhập lại không khớp.' : null,
              ),
              if (_error != null) ...[const SizedBox(height: 12), InlineError(_error!)],
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu…' : 'Đổi mật khẩu')),
            ],
          ),
        );
  }
}
