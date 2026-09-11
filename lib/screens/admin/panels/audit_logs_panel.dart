import 'package:flutter/material.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class AuditLogsPanel extends StatefulWidget {
  const AuditLogsPanel({super.key});

  @override
  State<AuditLogsPanel> createState() => _AuditLogsPanelState();
}

class _AuditLogsPanelState extends State<AuditLogsPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

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
      _logs = await ContentService.getAuditLogs();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load audit logs.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Audit Logs',
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Card(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Timestamp')),
                    DataColumn(label: Text('Action')),
                    DataColumn(label: Text('Entity')),
                    DataColumn(label: Text('Metadata')),
                  ],
                  rows: _logs.map((log) {
                    final createdAt = DateTime.tryParse(
                      log['created_at'] as String? ?? '',
                    );
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            createdAt != null
                                ? '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                                : '—',
                          ),
                        ),
                        DataCell(Text(log['action'] as String? ?? '')),
                        DataCell(
                          Text(
                            '${log['entity_type'] ?? '—'} ${log['entity_id'] != null ? '(${(log['entity_id'] as String).substring(0, 8)}...)' : ''}',
                          ),
                        ),
                        DataCell(
                          Text(
                            log['metadata']?.toString() ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
