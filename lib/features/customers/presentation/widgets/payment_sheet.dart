import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';

/// Receipt plus whatever the viewer may do with this payment:
/// - owner or cash staff who didn't collect it: record the result of a phone
///   call to the customer;
/// - owner: reverse.
void showPaymentSheet(BuildContext context, CustomerPayment payment, PaymentsController payments, AuthController auth) {
  final user = auth.currentUser!;
  final open = !payment.isReversed;
  final canCall = open && user.can(Permission.reconcileCash) && user.id != payment.collectedById;

  void act(VoidCallback action, String done) => runPaymentAction(context, action, success: done);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Payment receipt', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            PaymentReceipt(payment: payment, businessName: payments.businessName),
            const SizedBox(height: 12),
            if (canCall && !payment.isCustomerConfirmed && !payment.isDisputed) ...[
              Text('Call ${payment.customer.name} (${payment.customer.phone}) and read out: ${formatNpr(payment.amount)} '
                  '${paymentMethodLabel(payment.method).toLowerCase()} on ${formatDate(payment.date)}, collected by ${payment.collectedByName}.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.phone_callback_outlined),
                label: const Text('Customer confirmed on the phone'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  act(() => payments.confirmByPhone(payment, staff: user), 'Recorded as confirmed by phone.');
                },
              ),
            ],
            if (canCall && !payment.isDisputed)
              TextButton.icon(
                icon: const Icon(Icons.phone_disabled_outlined),
                label: const Text('Customer says it is wrong'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final note = await promptText(context, title: 'What did the customer say?', label: 'e.g. paid 500, not 5,000');
                  if (note != null && context.mounted) act(() => payments.disputeOnBehalf(payment, note, staff: user), 'Dispute recorded — review it in Customer Payments.');
                },
              ),
            if (user.role == UserRole.owner && open)
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Undo payment'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final reason = await promptText(
                    context,
                    title: payment.isSettled ? 'Undo and refund ${formatNpr(payment.settledAmount!)}?' : 'Undo this payment?',
                    label: 'Reason (the customer will see it)',
                  );
                  if (reason != null && context.mounted) act(() => payments.reverse(payment, reason, owner: user), 'Payment undone.');
                },
              ),
          ],
        ),
      ),
    ),
  );
}
