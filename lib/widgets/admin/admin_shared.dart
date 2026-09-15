import 'package:flutter/material.dart';

/// Shared building blocks for admin CRUD panels: page scaffold, confirm
/// dialog, snackbar helpers, loading/error states.

class AdminPageScaffold extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget child;

  const AdminPageScaffold({
    super.key,
    required this.title,
    this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final small = constraints.maxWidth < 600;
        final pad = small ? 12.0 : 24.0;
        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: 20),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
  );
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
  );
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Overflow-safe container for wide widgets like [DataTable]. It stretches
/// the child to fill the available panel width on wide screens and, when the
/// content is wider than the screen (small phones), scrolls it horizontally
/// instead of painting the classic overflow stripes.
class ResponsiveTableScroll extends StatelessWidget {
  final Widget child;

  const ResponsiveTableScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SingleChildScrollView(child: child),
          ),
        );
      },
    );
  }
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorBox({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// A compact dropdown used to filter admin tables. A null [value] means
/// "All" (no filtering). [onChanged] with null resets the filter.
class AdminFilterDropdown<T> extends StatefulWidget {
  final T? value;
  final String label;
  final String allLabel;
  final List<T> options;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const AdminFilterDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.itemLabel,
    required this.onChanged,
    this.allLabel = 'All',
  });

  @override
  State<AdminFilterDropdown<T>> createState() => _AdminFilterDropdownState<T>();
}

class _AdminFilterDropdownState<T> extends State<AdminFilterDropdown<T>> {
  T? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.value;
  }

  @override
  void didUpdateWidget(AdminFilterDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _selected = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final sel =
        _selected != null && widget.options.contains(_selected)
            ? _selected
            : null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        border: const OutlineInputBorder(),
        labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: sel,
          isExpanded: true,
          hint: Text(
            widget.allLabel,
            style: const TextStyle(color: Colors.black45, fontSize: 13),
          ),
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text(
                widget.allLabel,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            ...widget.options.map(
              (o) => DropdownMenuItem<T>(
                value: o,
                child: Text(
                  widget.itemLabel(o),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() => _selected = v);
            widget.onChanged(v);
          },
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final bool enabled;
  const StatusChip({super.key, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        enabled ? 'Enabled' : 'Disabled',
        style: TextStyle(
          color: enabled ? Colors.green.shade900 : Colors.red.shade900,
          fontSize: 11,
        ),
      ),
      backgroundColor: enabled ? Colors.green.shade100 : Colors.red.shade100,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
