import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';

class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Invoice ${sale.id}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Sarathi Grocery', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Text('Wholesale Grocery & FMCG'),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Invoice #${sale.id}'),
              Text(formatDate(sale.date)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Customer: ${sale.customer?.name ?? 'Walk-in customer'}'),
          Text('Status: ${sale.status.name}${sale.flaggedForApproval ? ' (needs approval)' : ''}'),
          const Divider(height: 32),
          ...sale.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(item.product.name)),
                    Expanded(child: Text('x${item.qty}', textAlign: TextAlign.center)),
                    Expanded(flex: 2, child: Text(formatNpr(item.lineTotal), textAlign: TextAlign.right)),
                  ],
                ),
              )),
          const Divider(height: 32),
          _totalRow('Subtotal', sale.subtotal),
          _totalRow('Discount (${sale.discountPercent.toStringAsFixed(0)}%)', -sale.discountAmount),
          _totalRow('Total', sale.total, bold: true),
          _totalRow('Paid', sale.isCredit ? 0 : sale.total),
          _totalRow('Remaining', sale.isCredit ? sale.total : 0),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatNpr(amount), style: style),
        ],
      ),
    );
  }
}
