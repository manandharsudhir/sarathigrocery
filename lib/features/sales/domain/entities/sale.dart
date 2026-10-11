import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

class Sale {
  Sale({
    required this.id,
    required this.date,
    required this.items,
    required this.isCredit,
    this.customer,
    this.flaggedForApproval = false,
    this.status = SaleStatus.completed,
    this.createdByUserId,
    this.createdByName = '',
    this.orderId,
    this.account = 'cash',
    this.vatAmount = 0,
    this.vatIncluded = true,
    this.invoiceNumber,
    this.invoiceSeries,
    this.invoiceSeq,
    this.exemptAmount = 0,
    this.buyerPan = '',
  });

  final String id;
  final DateTime date;
  final List<SaleItem> items;
  final bool isCredit;
  final Customer? customer;
  bool flaggedForApproval;
  SaleStatus status;
  final String? createdByUserId;
  final String createdByName;

  /// Set when this sale is the invoice for a delivered customer order.
  final String? orderId;

  /// Money account a paid (non-credit) sale went into.
  final String account;

  /// VAT on this sale (0 when the shop isn't VAT-registered), inside the
  /// line prices when [vatIncluded], else added on top.
  final double vatAmount;
  final bool vatIncluded;

  /// Tax invoice number (VAT shops), e.g. `2082/83-0012`, from counter
  /// [invoiceSeries] at [invoiceSeq].
  final String? invoiceNumber;
  final String? invoiceSeries;
  final int? invoiceSeq;

  /// Part of [total] on VAT-exempt goods.
  final double exemptAmount;

  /// The customer's PAN when billed.
  final String buyerPan;

  double get linesTotal => items.fold(0, (sum, i) => sum + i.lineTotal);
  double get total => linesTotal + (vatIncluded ? 0 : vatAmount);

  /// Sales income: what the customer pays minus the VAT collected for IRD.
  double get netSales => total - vatAmount;

  /// Sales value VAT was charged on (excluding the VAT).
  double get taxableAmount => netSales - exemptAmount;
  double get costOfGoods => items.fold(0.0, (sum, i) => sum + i.cost);
}
