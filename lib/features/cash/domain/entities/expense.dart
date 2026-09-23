class Expense {
  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note = '',
    this.createdByName = '',
  });

  final String id;
  final DateTime date;
  final String category;
  final double amount;
  final String note;
  final String createdByName;
}
