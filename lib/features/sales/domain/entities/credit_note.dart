import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';

/// Cancels or returns a tax-invoiced [sale] (the invoice itself is never
/// changed). Numbered in its own series, reported in the Sales Book.
class CreditNote {
  CreditNote({
    required this.id,
    required this.date,
    required this.sale,
    required this.number,
    required this.series,
    required this.seq,
    required this.reason,
    this.byName = '',
  });

  final String id;
  final DateTime date;
  final Sale sale;
  final String number;
  final String series;
  final int seq;
  final String reason;
  final String byName;

  double get total => sale.total;
  double get vatAmount => sale.vatAmount;
  double get exemptAmount => sale.exemptAmount;
}
