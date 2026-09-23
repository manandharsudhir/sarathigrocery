class PartnerLedgerEntry {
  PartnerLedgerEntry({
    required this.id,
    required this.date,
    required this.partnerName,
    required this.amount,
    required this.type,
    this.note = '',
  });

  final String id;
  final DateTime date;
  final String partnerName;
  final double amount;
  final String type;
  final String note;
}
