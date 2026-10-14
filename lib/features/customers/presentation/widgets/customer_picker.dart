import 'package:flutter/material.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';

/// Searchable customer field (by name or phone) with a clear button.
/// The filter works on the field's text, so a picked or mistyped name hides
/// everyone else until cleared.
class CustomerPicker extends StatefulWidget {
  const CustomerPicker({super.key, required this.customers, required this.selected, required this.onSelected, required this.label, this.walkInLabel});

  final List<Customer> customers;
  final Customer? selected;
  final ValueChanged<Customer?> onSelected;
  final String label;

  /// When set, a first entry with this label selects no customer.
  final String? walkInLabel;

  @override
  State<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<CustomerPicker> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.onSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: DropdownMenu<Customer?>(
          controller: _text,
          initialSelection: widget.selected,
          label: Text(widget.label),
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          dropdownMenuEntries: [
            if (widget.walkInLabel != null) DropdownMenuEntry(value: null, label: widget.walkInLabel!),
            for (final c in widget.customers) DropdownMenuEntry(value: c, label: c.phone.isEmpty ? c.name : '${c.name} · ${c.phone}'),
          ],
          onSelected: widget.onSelected,
        ),
      ),
      ListenableBuilder(
        listenable: _text,
        builder: (context, _) => _text.text.isEmpty && widget.selected == null
            ? const SizedBox.shrink()
            : IconButton(tooltip: 'Clear customer', icon: const Icon(Icons.clear), onPressed: _clear),
      ),
    ]);
  }
}
