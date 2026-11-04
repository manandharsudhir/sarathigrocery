import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';

/// Collects money against udharo bill [sale]; true once a payment is recorded.
Future<bool> collectOnBill(BuildContext context, Sale sale, SalesController sales, AuthController auth) async {
  var collected = false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => CollectPaymentForm(
      customer: sale.customer!,
      submitLabel: 'Collect',
      billLabel: 'bill',
      orderTotal: sale.total,
      orderAlreadyPaid: sales.paidOn(sale) ?? 0,
      onSubmit: (input) async {
        final payment = sales.collect(sale, input.amount,
            method: input.method, reference: input.reference, signature: input.signature, signedName: input.signedName, collector: auth.currentUser!);
        collected = true;
        return payment.isSettled ? 'Payment recorded.' : 'Payment recorded — hand the ${input.method == PaymentMethod.cash ? 'cash' : 'reference'} to the owner or cash staff.';
      },
    ),
  );
  return collected;
}
