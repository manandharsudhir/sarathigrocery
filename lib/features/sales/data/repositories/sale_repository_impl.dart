import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/data/repositories/product_repository_impl.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl(ProductRepositoryImpl products, CustomerRepositoryImpl customers)
      : _sales = SyncedCollection<Sale>(
          'sales',
          idOf: (s) => s.id,
          toJson: (s) => {
            'date': toMillis(s.date),
            'items': [
              for (final i in s.items) {'productId': i.product.id, 'qty': i.qty, 'unitPrice': i.unitPrice, 'unit': i.unit, 'size': i.size, 'unitCost': i.unitCost},
            ],
            'isCredit': s.isCredit,
            'customerId': s.customer?.id,
            'flaggedForApproval': s.flaggedForApproval,
            'status': s.status.name,
            'createdByUserId': s.createdByUserId,
            'createdByName': s.createdByName,
            'orderId': s.orderId,
            'account': s.account,
            'vatAmount': s.vatAmount,
            'vatIncluded': s.vatIncluded,
            'invoiceNumber': s.invoiceNumber,
            'invoiceSeries': s.invoiceSeries,
            'invoiceSeq': s.invoiceSeq,
            'exemptAmount': s.exemptAmount,
            'buyerPan': s.buyerPan,
          },
          fromJson: (j) {
            final items = <SaleItem>[];
            for (final i in (j['items'] as List? ?? const [])) {
              final product = products.byId(i['productId']);
              if (product == null) return null;
              items.add(SaleItem(
                product: product,
                qty: toDouble(i['qty']),
                unitPrice: toDouble(i['unitPrice']),
                unit: i['unit'],
                size: i['size'] == null ? 1 : toDouble(i['size']),
                unitCost: (i['unitCost'] as num?)?.toDouble(),
              ));
            }
            final customer = customers.byId(j['customerId']);
            if (j['customerId'] != null && customer == null) return null;
            return Sale(
              id: j['id'],
              date: fromMillis(j['date']),
              items: items,
              isCredit: j['isCredit'] ?? false,
              customer: customer,
              flaggedForApproval: j['flaggedForApproval'] ?? false,
              status: SaleStatus.values.byName(j['status'] ?? SaleStatus.completed.name),
              createdByUserId: j['createdByUserId'],
              createdByName: j['createdByName'] ?? '',
              orderId: j['orderId'],
              account: j['account'] ?? 'cash',
              vatAmount: toDouble(j['vatAmount']),
              vatIncluded: j['vatIncluded'] ?? true,
              invoiceNumber: j['invoiceNumber'],
              invoiceSeries: j['invoiceSeries'],
              invoiceSeq: (j['invoiceSeq'] as num?)?.toInt(),
              exemptAmount: toDouble(j['exemptAmount']),
              buyerPan: j['buyerPan'] ?? '',
            );
          },
          merge: (s, j) => s
            ..flaggedForApproval = j['flaggedForApproval'] ?? false
            ..status = SaleStatus.values.byName(j['status'] ?? SaleStatus.completed.name),
        );

  final SyncedCollection<Sale> _sales;

  late final _creditNotes = SyncedCollection<CreditNote>(
    'creditNotes',
    idOf: (n) => n.id,
    toJson: (n) => {
      'date': toMillis(n.date),
      'saleId': n.sale.id,
      'number': n.number,
      'series': n.series,
      'seq': n.seq,
      'reason': n.reason,
      'byName': n.byName,
    },
    fromJson: (j) {
      final sale = _sales.byId(j['saleId']);
      if (sale == null) return null;
      return CreditNote(
        id: j['id'],
        date: fromMillis(j['date']),
        sale: sale,
        number: j['number'] ?? '',
        series: j['series'] ?? '',
        seq: toInt(j['seq']),
        reason: j['reason'] ?? '',
        byName: j['byName'] ?? '',
      );
    },
  );

  List<SyncedCollection<Object?>> get collections => [_sales, _creditNotes];

  @override
  List<CreditNote> get creditNotes => _creditNotes.items;

  @override
  void addCreditNote(CreditNote note) => _creditNotes.add(note);

  @override
  List<Sale> get sales => _sales.items;

  @override
  double get todayRevenue {
    final today = DateTime.now();
    return sales
        .where((s) => s.status == SaleStatus.completed && s.date.year == today.year && s.date.month == today.month && s.date.day == today.day)
        .fold(0.0, (sum, s) => sum + s.total);
  }

  @override
  double get totalRevenue => sales.where((s) => s.status == SaleStatus.completed).fold(0.0, (sum, s) => sum + s.total);

  @override
  double get totalCostOfGoods => sales.where((s) => s.status == SaleStatus.completed).fold(0.0, (sum, s) => sum + s.costOfGoods);

  @override
  Sale record({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required bool flaggedForApproval,
    String? createdByUserId,
    String createdByName = '',
    String? orderId,
    String account = 'cash',
    double vatAmount = 0,
    bool vatIncluded = true,
    String? invoiceNumber,
    String? invoiceSeries,
    int? invoiceSeq,
    double exemptAmount = 0,
    String buyerPan = '',
  }) {
    final sale = Sale(
      id: nextId('S'),
      date: DateTime.now(),
      items: items,
      isCredit: isCredit,
      customer: customer,
      flaggedForApproval: flaggedForApproval,
      createdByUserId: createdByUserId,
      createdByName: createdByName,
      orderId: orderId,
      account: account,
      vatAmount: vatAmount,
      vatIncluded: vatIncluded,
      invoiceNumber: invoiceNumber,
      invoiceSeries: invoiceSeries,
      invoiceSeq: invoiceSeq,
      exemptAmount: exemptAmount,
      buyerPan: buyerPan,
    );
    _sales.add(sale);
    return sale;
  }

  @override
  void setStatus(Sale sale, SaleStatus status) {
    sale.status = status;
    _sales.save(sale);
  }
}
