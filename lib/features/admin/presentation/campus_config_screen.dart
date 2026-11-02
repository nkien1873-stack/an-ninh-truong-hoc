import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_error.dart';
import '../../../core/widgets/state_views.dart';
import '../../campus/campus_info.dart';
import '../data/admin_repository.dart';

/// Tên trường, số trực an ninh (nút "Gọi trực") và danh sách khu vực cho form báo cáo.
class CampusConfigScreen extends ConsumerStatefulWidget {
  const CampusConfigScreen({super.key});

  @override
  ConsumerState<CampusConfigScreen> createState() => _CampusConfigScreenState();
}

class _CampusConfigScreenState extends ConsumerState<CampusConfigScreen> {
  final _name = TextEditingController();
  final _hotline = TextEditingController();
  final _newBuilding = TextEditingController();
  List<String> _buildings = [];
  String? _addError;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _hotline.dispose();
    _newBuilding.dispose();
    super.dispose();
  }

  void _fill(CampusInfo info) {
    if (_loaded) return;
    _loaded = true;
    _name.text = info.campusName;
    _hotline.text = info.hotline ?? '';
    _buildings = [...info.buildings];
  }

  void _add() {
    final name = _newBuilding.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      setState(() => _addError = 'Nhập tên khu vực.');
      return;
    }
    if (_buildings.any((b) => b.toLowerCase() == name.toLowerCase())) {
      setState(() => _addError = 'Khu vực này đã có.');
      return;
    }
    setState(() {
      _buildings = [..._buildings, name];
      _addError = null;
      _newBuilding.clear();
    });
  }

  void _remove(String name) => setState(() => _buildings = _buildings.where((b) => b != name).toList());

  Future<void> _save() async {
    final buildings = _buildings;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Nhập tên trường.');
      return;
    }
    if (buildings.isEmpty) {
      setState(() => _error = 'Cần ít nhất một khu vực.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).updateCampus(
            campusName: _name.text.trim(),
            hotline: _hotline.text.trim().isEmpty ? null : _hotline.text.trim(),
            buildings: buildings,
          );
      refreshCampus(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu cấu hình trường.')));
        Navigator.pop(context);
      }
    } on ApiError catch (e) {
      setState(() => _error = e.fieldErrors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(campusInfoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình trường')),
      body: info.when(
        loading: () => const SkeletonList(count: 3),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(campusInfoProvider)),
        data: (data) {
          _fill(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên trường')),
              const SizedBox(height: 16),
              TextField(
                controller: _hotline,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số trực an ninh'),
              ),
              const SizedBox(height: 24),
              Text('Khu vực (${_buildings.length})', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final b in _buildings)
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(b),
                        trailing: IconButton(
                          tooltip: 'Xoá $b',
                          onPressed: () => _remove(b),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    if (_buildings.isEmpty)
                      const ListTile(leading: Icon(Icons.info_outline_rounded), title: Text('Chưa có khu vực nào.')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('new-building'),
                      controller: _newBuilding,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      onChanged: (_) {
                        if (_addError != null) setState(() => _addError = null);
                      },
                      decoration: InputDecoration(labelText: 'Thêm khu vực', errorText: _addError),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonalIcon(
                      key: const Key('add-building'),
                      onPressed: _add,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Thêm'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[const SizedBox(height: 12), InlineError(_error!)],
              const SizedBox(height: 16),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu…' : 'Lưu')),
            ],
          );
        },
      ),
    );
  }
}
