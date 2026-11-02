import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Những gì người dùng đã chọn trong sheet khẩn cấp nhưng chưa gửi.
class EmergencyDraft {
  const EmergencyDraft({
    required this.uid,
    required this.type,
    required this.note,
    required this.anonymous,
    required this.savedAt,
    this.building,
  });

  factory EmergencyDraft.fromJson(Map<String, Object?> j) => EmergencyDraft(
        uid: (j['uid'] as String?) ?? '',
        type: IncidentType.fromWire(j['type'] as String?),
        building: j['building'] as String?,
        note: (j['note'] as String?) ?? '',
        anonymous: j['anonymous'] == true,
        savedAt: DateTime.tryParse((j['savedAt'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Tài khoản đã mở sheet; máy dùng chung thì người khác đăng nhập không thấy bản nháp này.
  final String uid;
  final IncidentType type;
  final String? building;
  final String note;
  final bool anonymous;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
        'uid': uid,
        'type': type.wire,
        'building': building,
        'note': note,
        'anonymous': anonymous,
        'savedAt': savedAt.toIso8601String(),
      };
}

/// Giữ sheet khẩn cấp đang mở dở qua lúc người dùng bấm Home: Android có thể đóng app ở nền, mở
/// lại thì app chạy từ đầu. Bản nháp chỉ bị xoá khi gửi xong hoặc người dùng tự đóng sheet.
class EmergencyDraftStore {
  static const _key = 'emergency_draft_v1';

  /// Quá lâu thì không mở lại nữa (sự cố đã qua hoặc người dùng đã gọi điện).
  static const maxAge = Duration(minutes: 15);

  /// Bản nháp của [uid], nếu còn hạn. Bản nháp của tài khoản khác hoặc quá hạn thì bị xoá.
  Future<EmergencyDraft?> load(String uid, {DateTime? now}) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return null;
      final draft = EmergencyDraft.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
      if (draft.uid != uid || (now ?? DateTime.now()).difference(draft.savedAt) > maxAge) {
        await clear();
        return null;
      }
      return draft;
    } on Object {
      return null;
    }
  }

  Future<void> save(EmergencyDraft draft) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(draft.toJson()));
    } on Object {
      // Không lưu được thì chỉ mất khả năng mở lại.
    }
  }

  Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } on Object {
      // Bỏ qua.
    }
  }
}

final emergencyDraftStoreProvider = Provider<EmergencyDraftStore>((ref) => EmergencyDraftStore());
