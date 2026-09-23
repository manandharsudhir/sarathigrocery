import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';

class CashLedgerEntry {
  CashLedgerEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.note,
    this.reference = '',
    this.account = LedgerAccount.cash,
  });

  final String id;
  final DateTime date;
  final CashEntryType type;
  final double amount;
  final String note;
  final String reference;
  final LedgerAccount account;

  /// Money leaving [account]. A deposit leaves cash but arrives in the bank.
  bool get isOutflow => switch (type) {
        CashEntryType.expense || CashEntryType.supplierPayment || CashEntryType.refund => true,
        CashEntryType.deposit => account == LedgerAccount.cash,
        _ => false,
      };

  double get signedAmount => isOutflow ? -amount : amount;
}
