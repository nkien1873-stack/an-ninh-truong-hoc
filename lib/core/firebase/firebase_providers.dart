import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/server_url.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Lý do app vừa tự đăng xuất (tài khoản bị khoá, phiên bị thu hồi), hiện ở trang đăng nhập.
class SignOutNotice extends Notifier<String?> {
  @override
  String? build() => null;

  /// [keepExisting]: giữ lời nhắn cụ thể hơn đã có (ví dụ "bị khoá do báo sai").
  void set(String message, {bool keepExisting = false}) {
    if (keepExisting && state != null) return;
    state = message;
  }

  void clear() => state = null;
}

final signOutNoticeProvider = NotifierProvider<SignOutNotice, String?>(SignOutNotice.new);

final messagingProvider = Provider<FirebaseMessaging>((ref) => FirebaseMessaging.instance);

/// Trạng thái đăng nhập Firebase Auth (custom token do backend cấp sau khi xác thực OTP).
final authStateProvider = StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).authStateChanges());

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return ApiClient(
    baseUrl: ref.watch(serverUrlProvider),
    idToken: () async {
      try {
        return await auth.currentUser?.getIdToken();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'network-request-failed') throw ApiError.network();
        // Phiên đã bị thu hồi hoặc tài khoản đã xoá: về màn đăng nhập.
        await auth.signOut();
        return null;
      }
    },
    // Quản trị khoá tài khoản (hoặc bị khoá vì báo sai) thì backend thu hồi phiên: tự đăng xuất máy này.
    onSessionExpired: () async {
      if (auth.currentUser == null) return;
      ref.read(signOutNoticeProvider.notifier).set(
            'Bạn đã bị đăng xuất: phiên đăng nhập đã kết thúc hoặc tài khoản đã bị khoá. Liên hệ quản trị nếu cần.',
            keepExisting: true,
          );
      await auth.signOut();
    },
  );
});
