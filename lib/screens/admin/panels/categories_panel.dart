import 'package:flutter/material.dart';
import '../../../models/category.dart';
import '../../../services/content_service.dart';
import '../../../widgets/admin/admin_shared.dart';

class CategoriesPanel extends StatefulWidget {
  const CategoriesPanel({super.key});

  @override
  State<CategoriesPanel> createState() => _CategoriesPanelState();
}

class _CategoriesPanelState extends State<CategoriesPanel> {
  bool _loading = true;
  String? _error;
  List<Category> _categories = [];

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
      _categories = await ContentService.getCategories(onlyEnabled: false);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load categories.';
        _loading = false;
      });
    }
  }

  Future<void> _openEditor({Category? category}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryEditorDialog(category: category),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Category c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete Category',
      message: 'Delete "${c.name}"?',
    );
    if (!ok) return;
    try {
      await ContentService.deleteCategory(c.id);
      if (mounted) showSuccess(context, 'Category deleted.');
      _load();
    } catch (e) {
      if (mounted) showError(context, 'Failed to delete category.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Categories',
      action: FilledButton.icon(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Category'),
      ),
      child: _loading
          ? const LoadingBox()
          : _error != null
          ? ErrorBox(message: _error!, onRetry: _load)
          : Card(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Slug')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _categories.map((c) {
                    return DataRow(
                      cells: [
                        DataCell(Text(c.name)),
                        DataCell(Text(c.slug)),
                        DataCell(StatusChip(enabled: c.enabled)),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _openEditor(category: c),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                onPressed: () => _delete(c),
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

class _CategoryEditorDialog extends StatefulWidget {
  final Category? category;
  const _CategoryEditorDialog({this.category});

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    _descCtrl = TextEditingController(text: widget.category?.description ?? '');
    _enabled = widget.category?.enabled ?? true;
  }

  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final category = Category(
        id: widget.category?.id ?? '',
        name: _nameCtrl.text.trim(),
        slug: _slugify(_nameCtrl.text.trim()),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        enabled: _enabled,
        sortOrder: 0,
      );
      if (widget.category == null) {
        await ContentService.createCategory(category);
      } else {
        await ContentService.updateCategory(
          widget.category!.id,
          category.toInsertMap(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) showError(context, 'Failed to save category.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.category == null ? 'New Category' : 'Edit Category',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                CheckboxListTile(
                  value: _enabled,
                  title: const Text('Enabled'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _enabled = v ?? true),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
