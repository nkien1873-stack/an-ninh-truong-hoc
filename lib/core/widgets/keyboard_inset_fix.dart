import 'package:material_ui/material_ui.dart';

/// Sửa khoảng bàn phím bị tính hai lần trên một số máy Android (Samsung, Xiaomi): hệ điều hành đã
/// co cửa sổ app lại cho bàn phím mà vẫn báo `viewInsets.bottom` bằng cả chiều cao bàn phím, nên
/// màn hình bị trừ bàn phím hai lần và để lại khoảng trống lớn phía trên bàn phím.
///
/// Nhớ chiều cao cửa sổ lúc bàn phím đóng; khi bàn phím mở, phần cửa sổ đã bị co được trừ khỏi
/// `viewInsets.bottom`. Máy không co cửa sổ thì không thay đổi gì.
class KeyboardInsetFix extends StatefulWidget {
  const KeyboardInsetFix({super.key, required this.child});

  final Widget child;

  /// Khoảng bàn phím còn phải chừa sau khi trừ phần cửa sổ đã bị hệ điều hành co lại.
  static double effectiveInset({required double reported, required double baselineHeight, required double height}) {
    final shrunk = baselineHeight - height;
    if (shrunk <= 0) return reported;
    return (reported - shrunk).clamp(0.0, reported);
  }

  @override
  State<KeyboardInsetFix> createState() => _KeyboardInsetFixState();
}

class _KeyboardInsetFixState extends State<KeyboardInsetFix> {
  double? _baseline;
  Orientation? _orientation;

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final mq = MediaQuery.of(context);
    final height = view.physicalSize.height / view.devicePixelRatio;
    final reported = mq.viewInsets.bottom;
    // Xoay màn hình thì đo lại từ đầu.
    if (_orientation != mq.orientation) {
      _orientation = mq.orientation;
      _baseline = null;
    }
    if (reported == 0 || _baseline == null) _baseline = height;
    final inset = KeyboardInsetFix.effectiveInset(reported: reported, baselineHeight: _baseline!, height: height);
    if (inset == reported) return widget.child;
    return MediaQuery(
      data: mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: inset)),
      child: widget.child,
    );
  }
}
