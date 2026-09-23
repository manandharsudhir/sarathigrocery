import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';

class CashLedgerEntry {
  CashLedgerEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.note,
    this.reference = '',
  });

  final String id;
  final DateTime date;
  final CashEntryType type;
  final double amount;
  final String note;
  final String reference;
}
