enum CashEntryType { opening, sale, collection, expense, deposit, supplierPayment, refund }

/// Where the money is. `deposit` moves cash → bank (two entries).
enum LedgerAccount { cash, bank, wallet }

String ledgerAccountLabel(LedgerAccount a) => switch (a) {
      LedgerAccount.cash => 'Cash',
      LedgerAccount.bank => 'Bank',
      LedgerAccount.wallet => 'Wallet',
    };
