import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

abstract class SaleRepository {
  List<Sale> get sales;

  double get todayRevenue;

  double get totalRevenue;

  double get totalCostOfGoods;

  Sale record({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required bool flaggedForApproval,
    String? createdByUserId,
    String createdByName,
    String? orderId,
    String account,
    double vatAmount,
    bool vatIncluded,
    String? invoiceNumber,
    String? invoiceSeries,
    int? invoiceSeq,
    double exemptAmount,
    String buyerPan,
  });

  List<CreditNote> get creditNotes;

  void addCreditNote(CreditNote note);

  void setStatus(Sale sale, SaleStatus status);
}
