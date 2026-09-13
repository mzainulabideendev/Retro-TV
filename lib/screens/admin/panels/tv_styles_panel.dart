import 'package:flutter/material.dart';
import '../../../models/tv_style.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class TvStylesPanel extends StatefulWidget {
  const TvStylesPanel({super.key});

  @override
  State<TvStylesPanel> createState() => _TvStylesPanelState();
}

class _TvStylesPanelState extends State<TvStylesPanel> {
  bool _loading = true;
  String? _error;
  List<TvStyle> _styles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _styles = await ContentService.getTvStyles(onlyEnabled: false);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load TV styles.';
        _loading = false;
      });
    }
  }

  Future<void> _toggle(TvStyle s) async {
    try {
      await ContentService.updateTvStyle(s.id, {'enabled': !s.enabled});
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to update style.');
    }
  }

  Future<void> _delete(TvStyle s) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete TV Style',
      message: 'Delete "${s.name}"?',
    );
    if (!ok) return;
    try {
      await ContentService.deleteTvStyle(s.id);
      if (mounted) showSuccess(context, 'Style deleted.');
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to delete style.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'TV Styles',
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Card(
              child: ResponsiveTableScroll(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Preview')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Era')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _styles.map((s) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            width: 36,
                            height: 26,
                            decoration: BoxDecoration(
                              color: s.bodyColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        DataCell(Text(s.name)),
                        DataCell(Text(s.era ?? '—')),
                        DataCell(StatusChip(enabled: s.enabled)),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  s.enabled
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                ),
                                onPressed: () => _toggle(s),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: () => _delete(s),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }
}
