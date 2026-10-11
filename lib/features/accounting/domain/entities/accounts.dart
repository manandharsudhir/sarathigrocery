/// The chart of accounts. Accounts are plain string ids: a fixed core set,
/// plus families keyed by a name after a colon (`capital:Ram`,
/// `expense:Rent`, `bank:NIC Asia`). There is no accounts collection — an
/// account exists once something is posted to it, and the core ones always.
enum AccountType {
  asset('Assets'),
  liability('Liabilities'),
  equity('Owners\' money'),
  income('Income'),
  expense('Costs and expenses');

  const AccountType(this.label);

  final String label;

  /// Assets and costs grow with debits; the rest with credits.
  bool get debitNormal => this == asset || this == expense;
}

abstract final class Acc {
  // Money (the cash book's accounts; also `bank:<name>`, `wallet:<name>`).
  static const cash = 'cash';
  static const bank = 'bank';
  static const wallet = 'wallet';

  // Other assets.
  static const collectors = 'collectors';
  static const stock = 'stock';
  static const receivables = 'receivables';
  static const deposits = 'deposits';
  static const vatInput = 'vatInput';
  static const toClassify = 'toClassify';

  // Liabilities.
  static const payables = 'payables';
  static const vatPayable = 'vatPayable';

  // Owners' money.
  static const retained = 'retainedEarnings';
  static const dividends = 'dividends';

  /// Capital with no owner named yet (before Settings → Owners is filled in).
  static const capitalUnassigned = 'capital';

  // Income and costs.
  static const sales = 'sales';
  static const cogs = 'cogs';
  static const stockLoss = 'stockLoss';
  static const cashShortage = 'cashShortage';

  static String capital(String person) => 'capital:$person';
  static String drawings(String person) => 'drawings:$person';
  static String loan(String lender) => 'loan:$lender';
  static String expense(String category) => 'expense:$category';

  static const core = [
    cash, bank, wallet, collectors, stock, receivables, deposits, vatInput, toClassify,
    payables, vatPayable, retained, dividends, sales, cogs, stockLoss, cashShortage,
  ];

  static bool isMoney(String id) => id == cash || id == bank || id == wallet || id.startsWith('bank:') || id.startsWith('wallet:');

  /// cash / bank / wallet: what kind of money account [id] is.
  static String moneyKind(String id) => id.split(':').first;
}

String _family(String id) => id.contains(':') ? id.substring(0, id.indexOf(':')) : '';
String _key(String id) => id.contains(':') ? id.substring(id.indexOf(':') + 1) : id;

AccountType accountType(String id) {
  if (Acc.isMoney(id)) return AccountType.asset;
  switch (_family(id)) {
    case 'capital' || 'drawings':
      return AccountType.equity;
    case 'loan':
      return AccountType.liability;
    case 'expense':
      return AccountType.expense;
  }
  return switch (id) {
    Acc.payables || Acc.vatPayable => AccountType.liability,
    Acc.retained || Acc.dividends || Acc.capitalUnassigned => AccountType.equity,
    Acc.sales => AccountType.income,
    Acc.cogs || Acc.stockLoss || Acc.cashShortage => AccountType.expense,
    _ => AccountType.asset,
  };
}

/// Plain-language name for [id].
String accountName(String id) {
  switch (_family(id)) {
    case 'bank' || 'wallet':
      return _key(id);
    case 'capital':
      return 'Capital – ${_key(id)}';
    case 'drawings':
      return 'Drawings – ${_key(id)}';
    case 'loan':
      return 'Loan from ${_key(id)}';
    case 'expense':
      return _key(id);
  }
  return switch (id) {
    Acc.cash => 'Cash',
    Acc.bank => 'Bank',
    Acc.wallet => 'Wallet',
    Acc.collectors => 'Money with collectors',
    Acc.stock => 'Stock (at cost)',
    Acc.receivables => 'Customers owe (udharo)',
    Acc.deposits => 'Deposits',
    Acc.vatInput => 'VAT paid on purchases',
    Acc.toClassify => 'To classify (for accountant)',
    Acc.payables => 'Owed to suppliers',
    Acc.vatPayable => 'VAT collected on sales',
    Acc.retained => 'Retained earnings',
    Acc.dividends => 'Dividends paid',
    Acc.capitalUnassigned => 'Owner\'s capital',
    Acc.sales => 'Sales',
    Acc.cogs => 'Cost of goods sold',
    Acc.stockLoss => 'Stock loss / gain',
    Acc.cashShortage => 'Cash shortage',
    _ => id,
  };
}

/// Cash, Bank, Wallet, then the shop's named banks/wallets.
List<String> moneyAccountIds(List<String> named) => [Acc.cash, Acc.bank, Acc.wallet, ...named];

/// Expense categories every shop starts with (Settings adds more).
const kExpenseCategories = ['Rent', 'Salary', 'Transport', 'Utilities', 'Packaging', 'Interest', 'Tea/Misc'];
