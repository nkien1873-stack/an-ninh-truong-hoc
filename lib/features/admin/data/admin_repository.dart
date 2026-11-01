import 'package:campus_core/campus_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/app_user.dart';
import '../../campus/campus_info.dart';

/// Quản trị: đọc danh sách tài khoản từ Firestore (Rules chỉ cho quản trị đọc),
/// mọi thao tác ghi đi qua backend.
class AdminRepository {
  AdminRepository(this._db, this._api);

  final FirebaseFirestore _db;
  final ApiClient _api;

  List<AppUser> _users(QuerySnapshot<Map<String, dynamic>> s) {
    final list = s.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.nameOrEmail.toLowerCase().compareTo(b.nameOrEmail.toLowerCase()));
    return list;
  }

  Stream<List<AppUser>> watchUsers(UserRole role) =>
      _db.collection('users').where('role', isEqualTo: role.wire).limit(1000).snapshots().map(_users);

  /// Bảo vệ và quản trị (để phân công).
  Stream<List<AppUser>> watchStaff() => _db
      .collection('users')
      .where('role', whereIn: [UserRole.guard.wire, UserRole.admin.wire])
      .snapshots()
      .map(_users);

  Future<AppUser> createUser({
    required String email,
    String? phone,
    required String displayName,
    required UserRole role,
    MemberType? memberType,
    bool onDuty = false,
  }) async {
    final res = await _api.post('/admin/users', {
      'email': email,
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone,
      'displayName': displayName,
      'role': role.wire,
      if (memberType != null) 'memberType': memberType.wire,
      'onDuty': onDuty,
    });
    return AppUser.fromApi(res['user']! as Map<String, Object?>);
  }

  /// Xoá tài khoản (báo cáo người đó đã gửi vẫn giữ).
  Future<void> deleteUser(String uid) => _api.delete('/admin/users/$uid');

  Future<AppUser> updateUser(
    String uid, {
    UserRole? role,
    bool? active,
    bool? onDuty,
    String? displayName,
    MemberType? memberType,
  }) async {
    final res = await _api.patch('/admin/users/$uid', {
      if (role != null) 'role': role.wire,
      'active': ?active,
      'onDuty': ?onDuty,
      'displayName': ?displayName,
      if (memberType != null) 'memberType': memberType.wire,
    });
    return AppUser.fromApi(res['user']! as Map<String, Object?>);
  }

  Future<void> updateCampus({
    required String campusName,
    required String? hotline,
    required List<String> buildings,
  }) async {
    await _api.put('/admin/config', {
      'campusName': campusName,
      'hotline': hotline ?? '',
      'buildings': buildings,
    });
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(firestoreProvider), ref.watch(apiClientProvider)),
);

final usersByRoleProvider = StreamProvider.autoDispose.family<List<AppUser>, UserRole>(
  (ref, role) => ref.watch(adminRepositoryProvider).watchUsers(role),
);

final staffProvider = StreamProvider.autoDispose<List<AppUser>>((ref) => ref.watch(adminRepositoryProvider).watchStaff());

/// Làm mới cấu hình trường sau khi quản trị sửa.
void refreshCampus(WidgetRef ref) => ref.invalidate(campusInfoProvider);
