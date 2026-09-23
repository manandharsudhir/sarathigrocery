import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.controller});

  final InventoryController controller;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'New category'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _add, child: const Text('Add')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: widget.controller.categories.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final category = widget.controller.categories[index];
                return ListTile(
                  title: Text(category),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      if (!widget.controller.deleteCategory(category)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"$category" is used by a product and cannot be deleted.')),
                        );
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _add() {
    if (_controller.text.trim().isEmpty) return;
    widget.controller.addCategory(_controller.text.trim());
    _controller.clear();
    setState(() {});
  }
}
