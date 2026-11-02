import 'package:campus_core/campus_core.dart';

/// Hồ sơ người dùng.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.phone,
    this.username = '',
    this.studentId = '',
    this.fakeReports = 0,
    this.failedLogins = 0,
    this.loginLockedUntil,
    required this.displayName,
    required this.role,
    required this.memberType,
    required this.active,
    required this.onDuty,
  });

  /// Từ JSON `user` trả về bởi backend (`/me`, `/auth/otp/verify`).
  factory AppUser.fromApi(Map<String, Object?> j) => AppUser(
        uid: j['uid']! as String,
        email: (j['email'] as String?) ?? '',
        username: (j['username'] as String?) ?? '',
        studentId: (j['studentId'] as String?) ?? '',
        fakeReports: (j['fakeReports'] as num?)?.toInt() ?? 0,
        failedLogins: (j['failedLogins'] as num?)?.toInt() ?? 0,
        loginLockedUntil: DateTime.tryParse((j['loginLockedUntil'] as String?) ?? '')?.toLocal(),
        phone: (j['phone'] as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        role: UserRole.fromWire(j['role'] as String?),
        memberType: MemberType.fromWire(j['memberType'] as String?),
        active: j['active'] != false,
        onDuty: j['onDuty'] == true,
      );

  final String uid;

  /// Email đã xác nhận khi đăng ký.
  final String email;

  /// Tên đăng nhập, rỗng với tài khoản quản trị tạo trước mà chưa đăng ký.
  final String username;

  /// Mã số sinh viên, rỗng nếu không phải sinh viên hoặc tài khoản tạo trước khi có MSSV.
  final String studentId;

  /// Số báo cáo bị đánh dấu sai sự thật.
  final int fakeReports;

  /// Số lần nhập sai mật khẩu liên tiếp (chỉ quản trị nhận được).
  final int failedLogins;

  /// Đang tạm khoá đăng nhập vì nhập sai nhiều lần thì tới lúc này mới thử lại được.
  final DateTime? loginLockedUntil;

  /// Số liên hệ dạng `0xxxxxxxxx`, rỗng nếu chưa nhập.
  final String phone;
  final String displayName;
  final UserRole role;
  final MemberType memberType;
  final bool active;
  final bool onDuty;

  Actor get actor => Actor(uid: uid, role: role, active: active);

  bool get profileComplete => displayName.trim().isNotEmpty;

  String get phoneDisplay => VietnamPhone.tryParse(phone)?.display ?? phone;

  bool get hasPhone => phone.isNotEmpty;

  /// Tên hiển thị, hoặc email khi chưa nhập tên.
  String get nameOrEmail => profileComplete ? displayName : email;
}
