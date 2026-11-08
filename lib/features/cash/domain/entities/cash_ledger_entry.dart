import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';

/// One line of the cash book: money in or out of one money [account]
/// (`cash`, `bank`, `wallet`, or a named `bank:…`/`wallet:…`).
class CashLedgerEntry {
  CashLedgerEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.amount,
    required this.note,
    this.reference = '',
    this.account = 'cash',
    this.journalId = '',
    this.reverses,
  });

  final String id;
  final DateTime date;
  final CashEntryType type;
  final double amount;
  final String note;
  final String reference;
  final String account;

  /// The journal entry this line was booked with ('' on lines from before
  /// the link existed: [CashRepository.journalFor] finds those by match).
  final String journalId;

  /// Set on a correction: this line undoes line [reverses] (same type,
  /// negative amount, so every total nets out by itself).
  final String? reverses;
  bool get isReversal => reverses != null;

  bool get isOutflow => switch (type) {
        CashEntryType.expense || CashEntryType.supplierPayment || CashEntryType.refund || CashEntryType.moneyOut => true,
        _ => false,
      };

  double get signedAmount => isOutflow ? -amount : amount;
}
