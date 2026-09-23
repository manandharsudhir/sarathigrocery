import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';

void _mergeCustomer(Customer c, Json j) {
  c
    ..name = j['name'] ?? ''
    ..phone = j['phone'] ?? ''
    ..location = j['location'] ?? ''
    ..creditLimit = toDouble(j['creditLimit'])
    ..outstandingBalance = toDouble(j['outstandingBalance'])
    ..lastPaymentDate = fromMillisOrNull(j['lastPaymentDate'])
    ..defaultDiscountPercent = toDouble(j['defaultDiscountPercent']);
}

class CustomerRepositoryImpl implements CustomerRepository {
  final _customers = SyncedCollection<Customer>(
    'customers',
    idOf: (c) => c.id,
    toJson: (c) => {
      'name': c.name,
      'phone': c.phone,
      'location': c.location,
      'creditLimit': c.creditLimit,
      'outstandingBalance': c.outstandingBalance,
      'lastPaymentDate': c.lastPaymentDate == null ? null : toMillis(c.lastPaymentDate!),
      'defaultDiscountPercent': c.defaultDiscountPercent,
      'openingBalance': c.openingBalance,
    },
    fromJson: (j) {
      final c = Customer(id: j['id'], name: '', phone: '', location: '', creditLimit: 0, openingBalance: (j['openingBalance'] as num?)?.toDouble());
      _mergeCustomer(c, j);
      return c;
    },
    merge: _mergeCustomer,
    counters: {'outstandingBalance'},
  );

  List<SyncedCollection<Object?>> get collections => [_customers];

  @override
  List<Customer> get customers => _customers.items;

  Customer? byId(String? id) => _customers.byId(id);

  @override
  Customer create({required String name, required String phone, required String location, required double creditLimit, double defaultDiscountPercent = 0, double openingBalance = 0}) {
    final customer = Customer(
      id: nextId('C'),
      name: name,
      phone: phone,
      location: location,
      creditLimit: creditLimit,
      defaultDiscountPercent: defaultDiscountPercent,
      outstandingBalance: openingBalance,
      openingBalance: openingBalance,
    );
    _customers.add(customer);
    return customer;
  }

  @override
  void update(Customer customer) => _customers.save(customer);

  @override
  double get totalOutstanding => customers.fold(0.0, (sum, c) => sum + c.outstandingBalance);

  @override
  void applyBalanceChange(Customer customer, double delta, {DateTime? paymentDate}) {
    customer.outstandingBalance += delta;
    _customers.increment(customer, {'outstandingBalance': delta});
    if (paymentDate != null) {
      customer.lastPaymentDate = paymentDate;
      _customers.save(customer);
    }
  }
}
