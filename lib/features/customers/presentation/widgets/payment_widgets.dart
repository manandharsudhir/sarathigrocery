import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';

/// Customer-side verification state.
(String, Color) paymentVerificationVisual(CustomerPayment p) {
  if (p.isReversed) return ('Reversed', Colors.grey);
  if (p.isDisputed) return ('Disputed', Colors.red);
  if (p.confirmedByCode) return ('Confirmed by code', Colors.green);
  if (p.confirmedBySignature) return ('Signed by customer', Colors.green);
  if (p.phoneConfirmedAt != null) return ('Confirmed by phone', Colors.green);
  if (p.customerConfirmedAt != null) return ('Confirmed by customer', Colors.green);
  return ('Awaiting customer confirmation', Colors.amber);
}

/// Business-side state: did the money reach the till / get verified?
(String, Color) paymentSettlementVisual(CustomerPayment p) {
  if (p.isReversed) return ('Reversed', Colors.grey);
  if (!p.isSettled) return (p.method == PaymentMethod.cash ? 'With ${p.collectedByName}' : 'Reference not yet verified', Colors.orange);
  if (p.shortfall > 0) return ('Short by ${formatNpr(p.shortfall)}', Colors.red);
  return (p.method == PaymentMethod.cash ? 'In till' : 'Verified', Colors.teal);
}

class PaymentStatusRow extends StatelessWidget {
  const PaymentStatusRow({super.key, required this.payment, this.showSettlement = true});

  final CustomerPayment payment;
  final bool showSettlement;

  @override
  Widget build(BuildContext context) {
    final (vLabel, vColor) = paymentVerificationVisual(payment);
    final (sLabel, sColor) = paymentSettlementVisual(payment);
    return Wrap(spacing: 6, runSpacing: 4, children: [
      StatusBadge(label: vLabel, color: vColor),
      if (showSettlement && !payment.isReversed) StatusBadge(label: sLabel, color: sColor),
    ]);
  }
}

/// The receipt both sides see.
class PaymentReceipt extends StatelessWidget {
  const PaymentReceipt({super.key, required this.payment, this.businessName});

  final CustomerPayment payment;

  /// When given, a "Share receipt" (PDF) button is shown.
  final String? businessName;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    TableRow row(String k, String v) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(children: [
          row('Received', formatNpr(p.amount)),
          row('Method', '${paymentMethodLabel(p.method)}${p.reference.isEmpty ? '' : ' · ${p.reference}'}'),
          if (p.orderId != null) row('For order ${p.orderId}', formatNpr(p.appliedToOrder)),
          if (p.appliedToPreviousBalance > 0) row('Toward earlier balance', formatNpr(p.appliedToPreviousBalance)),
          row('Balance after', formatNpr(p.balanceAfter)),
          row('Collected by', '${p.collectedByName} · ${formatDate(p.date)}'),
          if (p.isSettled) row(p.method == PaymentMethod.cash ? 'Counted into till by' : 'Verified by', '${p.settledByName} · ${formatNpr(p.settledAmount!)}'),
        ]),
        if (p.phoneConfirmedAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Confirmed by phone call with ${p.phoneConfirmedByName}, ${formatDate(p.phoneConfirmedAt!)}')),
        if (p.isDisputed)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reported${p.disputedByName.isEmpty ? '' : ' via ${p.disputedByName}'}: "${p.disputeNote}"', style: const TextStyle(color: Colors.red)),
          ),
        if (p.isReversed) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reversed by ${p.reversedByName}: ${p.reversalReason}', style: const TextStyle(color: Colors.grey))),
        if (Signature.decode(p.signature) case final signature?) ...[
          const SizedBox(height: 6),
          SignatureView(signature: signature),
          Text('Signed by ${p.signedName}', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        PaymentStatusRow(payment: p),
        if (businessName != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share receipt'),
              onPressed: () async => sharePdf(await paymentReceiptPdf(p, businessName: businessName!), 'receipt-${p.id}.pdf'),
            ),
          ),
      ],
    );
  }
}

/// Everything the collector captured in [CollectPaymentForm].
class CollectInput {
  const CollectInput({required this.amount, required this.method, required this.reference, required this.code, this.signature, this.signedName = ''});

  final double amount;
  final PaymentMethod method;
  final String reference;
  final String code;

  /// Encoded [Signature], or null if the customer didn't sign.
  final String? signature;
  final String signedName;
}

/// What the collector enters: amount, method, reference, and (at the door)
/// the customer's delivery code and/or signature. Shows the receipt split live, so the
/// customer can check it before handing over.
class CollectPaymentForm extends StatefulWidget {
  const CollectPaymentForm({
    super.key,
    required this.customer,
    required this.submitLabel,
    required this.onSubmit,
    this.orderTotal,
    this.orderAlreadyPaid = 0,
    this.askForCode = false,
    this.allowZero = false,
    this.signatureRequired = false,
  });

  final Customer customer;
  final String submitLabel;

  /// Null = counter payment not tied to an order.
  final double? orderTotal;
  final double orderAlreadyPaid;
  final bool askForCode;

  /// Delivery on credit: 0 is a valid "paid nothing now".
  final bool allowZero;

  /// Customer has no app to confirm later: they must sign here.
  final bool signatureRequired;

  /// Returns a message to show on success (then the sheet closes), or
  /// throws [PaymentException].
  final Future<String> Function(CollectInput input) onSubmit;

  @override
  State<CollectPaymentForm> createState() => _CollectPaymentFormState();
}

class _CollectPaymentFormState extends State<CollectPaymentForm> {
  late final _amount = TextEditingController(text: widget.orderTotal == null ? '' : (widget.orderTotal! - widget.orderAlreadyPaid).toStringAsFixed(0));
  final _reference = TextEditingController();
  final _code = TextEditingController();
  final _signedName = TextEditingController();
  Signature? _signature;
  late bool _showSignature = widget.signatureRequired;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;
  String? _error;

  double get _value => double.tryParse(_amount.text.trim()) ?? 0;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_value < 0 || (_value == 0 && !widget.allowZero)) throw PaymentException('Enter the amount received.');
      final code = _code.text.trim();
      if (widget.askForCode && _value > 0 && code.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(code)) {
        throw PaymentException('The delivery code is 6 digits. Leave it empty if the customer cannot give it.');
      }
      if (widget.signatureRequired && _signature == null) throw PaymentException('${widget.customer.name} has no app — they must sign below.');
      if (_signature != null && _signedName.text.trim().isEmpty) throw PaymentException('Enter the name of the person who signed.');
      final message = await widget.onSubmit(CollectInput(
        amount: _value,
        method: _method,
        reference: _reference.text,
        code: _code.text,
        signature: _signature?.encode(),
        signedName: _signedName.text,
      ));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    } on PaymentException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final orderDue = widget.orderTotal == null ? 0.0 : (widget.orderTotal! - widget.orderAlreadyPaid).clamp(0.0, double.infinity);
    final toOrder = _value < orderDue ? _value : orderDue;
    final toEarlier = _value - toOrder;
    // Delivering adds the order to the balance first.
    final balanceBefore = widget.customer.outstandingBalance + (widget.allowZero ? orderDue : 0);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.submitLabel} · ${widget.customer.name}', style: Theme.of(context).textTheme.titleMedium),
            Text('Balance before: ${formatNpr(balanceBefore)}${widget.orderTotal == null ? '' : ' (incl. this order ${formatNpr(orderDue)})'}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: widget.allowZero ? 'Amount received now (0 = on credit)' : 'Amount received (NPR)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(paymentMethodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
              ],
            ),
            if (_method != PaymentMethod.cash) ...[
              const SizedBox(height: 8),
              TextField(controller: _reference, decoration: InputDecoration(labelText: _method == PaymentMethod.cheque ? 'Cheque number' : 'Transaction / reference id')),
            ],
            if (widget.askForCode && _value > 0) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: "Customer's delivery code (optional)",
                  helperText: 'The customer reads it from the order in their app once they agree the amount.\nWithout it, the customer confirms the payment in their app later.',
                  helperMaxLines: 3,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_showSignature) ...[
              Text(widget.signatureRequired ? 'Customer signature (required — no app)' : 'Customer signature', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SignaturePad(onChanged: (sig) => setState(() => _signature = sig)),
              TextField(controller: _signedName, decoration: const InputDecoration(labelText: 'Name of person signing')),
            ] else
              TextButton.icon(onPressed: () => setState(() => _showSignature = true), icon: const Icon(Icons.draw_outlined), label: const Text('Customer signs instead / as well')),
            if (_value > 0) ...[
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    [
                      if (widget.orderTotal != null) '${formatNpr(toOrder)} for this order',
                      if (toEarlier > 0) '${formatNpr(toEarlier)} toward earlier balance',
                      'Balance after: ${formatNpr(balanceBefore - _value)}',
                    ].join('\n'),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for free text (dispute note, reversal reason, counted amount).
Future<String?> promptText(BuildContext context, {required String title, required String label, String initial = '', TextInputType? keyboardType}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, keyboardType: keyboardType, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Runs [action], showing a [PaymentException] as a snackbar.
void runPaymentAction(BuildContext context, VoidCallback action, {String? success}) {
  final messenger = ScaffoldMessenger.of(context);
  try {
    action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
  } on PaymentException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
