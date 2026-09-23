import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';

int? _ms(DateTime? d) => d == null ? null : toMillis(d);

void _mergePayment(CustomerPayment p, Json j) {
  p
    ..customerConfirmedAt = fromMillisOrNull(j['customerConfirmedAt'])
    ..disputedAt = fromMillisOrNull(j['disputedAt'])
    ..disputeNote = j['disputeNote'] ?? ''
    ..settledAt = fromMillisOrNull(j['settledAt'])
    ..settledAmount = (j['settledAmount'] as num?)?.toDouble()
    ..settledById = j['settledById']
    ..settledByName = j['settledByName'] ?? ''
    ..reversedAt = fromMillisOrNull(j['reversedAt'])
    ..reversedByName = j['reversedByName'] ?? ''
    ..reversalReason = j['reversalReason'] ?? '';
}

class PaymentRepositoryImpl implements PaymentRepository {
  PaymentRepositoryImpl(CustomerRepositoryImpl customers)
      : _payments = SyncedCollection<CustomerPayment>(
          'customerPayments',
          idOf: (p) => p.id,
          toJson: (p) => {
            'date': toMillis(p.date),
            'customerId': p.customer.id,
            'amount': p.amount,
            'method': p.method.name,
            'reference': p.reference,
            'orderId': p.orderId,
            'appliedToOrder': p.appliedToOrder,
            'balanceAfter': p.balanceAfter,
            'collectedById': p.collectedById,
            'collectedByName': p.collectedByName,
            'deliveryCode': p.deliveryCode,
            'customerConfirmedAt': _ms(p.customerConfirmedAt),
            'disputedAt': _ms(p.disputedAt),
            'disputeNote': p.disputeNote,
            'settledAt': _ms(p.settledAt),
            'settledAmount': p.settledAmount,
            'settledById': p.settledById,
            'settledByName': p.settledByName,
            'reversedAt': _ms(p.reversedAt),
            'reversedByName': p.reversedByName,
            'reversalReason': p.reversalReason,
          },
          fromJson: (j) {
            final customer = customers.byId(j['customerId']);
            if (customer == null) return null;
            final p = CustomerPayment(
              id: j['id'],
              date: fromMillis(j['date']),
              customer: customer,
              amount: toDouble(j['amount']),
              method: PaymentMethod.values.byName(j['method']),
              reference: j['reference'] ?? '',
              orderId: j['orderId'],
              appliedToOrder: toDouble(j['appliedToOrder']),
              balanceAfter: toDouble(j['balanceAfter']),
              collectedById: j['collectedById'] ?? '',
              collectedByName: j['collectedByName'] ?? '',
              deliveryCode: j['deliveryCode'],
            );
            _mergePayment(p, j);
            return p;
          },
          merge: _mergePayment,
        );

  final SyncedCollection<CustomerPayment> _payments;

  List<SyncedCollection<Object?>> get collections => [_payments];

  @override
  List<CustomerPayment> get payments => _payments.items;

  @override
  void add(CustomerPayment payment) => _payments.add(payment);

  @override
  void update(CustomerPayment payment) => _payments.save(payment);
}
