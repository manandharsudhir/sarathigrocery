/// Cash book entry kinds. [moneyIn]/[moneyOut] cover transfers, capital,
/// drawings, loans, dividends and payments for the accountant to classify.
enum CashEntryType { sale, collection, expense, supplierPayment, refund, moneyIn, moneyOut }
