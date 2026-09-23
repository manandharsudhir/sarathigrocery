import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
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
    required double discountPercent,
    required bool isCredit,
    Customer? customer,
    required bool flaggedForApproval,
    String? createdByUserId,
    String createdByName,
  });

  void setStatus(Sale sale, SaleStatus status);
}
