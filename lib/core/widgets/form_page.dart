import 'package:material_ui/material_ui.dart';

/// Mở một form có ô nhập chữ thành màn toàn trang, trả về giá trị form gửi qua `Navigator.pop`.
///
/// Không dùng bottom sheet cho form có bàn phím: trên một số máy Android (Xiaomi) sheet bị tính
/// khoảng bàn phím hai lần, để lại khoảng trống lớn và che mất nút. Scaffold tự co lại đúng.
Future<T?> showFormPage<T>(BuildContext context, {required String title, required Widget child}) =>
    // Navigator gốc: phủ cả thanh điều hướng dưới, không lồng trong khung của các tab.
    Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: child,
          ),
        ),
      ),
    ));
