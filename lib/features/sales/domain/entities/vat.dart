import 'package:sarathigrocery/core/utils/bs_date.dart';

/// A VAT-registered shop's terms: the rate (%) and whether typed prices
/// already include it. Null = not registered (no VAT anywhere).
typedef VatTerms = ({double rate, bool included});

/// VAT on a bill whose lines total [taxable] (VAT-able goods) and [exempt].
/// Inclusive prices contain the VAT; exclusive ones get it added on top.
double vatOn(double taxable, VatTerms? terms) {
  if (terms == null || terms.rate <= 0) return 0;
  final vat = terms.included ? taxable * terms.rate / (100 + terms.rate) : taxable * terms.rate / 100;
  return (vat * 100).roundToDouble() / 100;
}

/// A numbered bill (tax invoice or credit note): [series] is the counter
/// (`invoice-2082`), [seq] its next number, [number] what is printed.
typedef BillNumber = ({String series, int seq, String number});

/// Counter id and printed number for [kind] (`invoice` / `credit`) in the
/// fiscal year containing [date]: e.g. `2082/83-0007`.
({String series, String Function(int seq) format}) billSeries(String kind, DateTime date) {
  final fy = BsDate.fromAd(date).fiscalYear;
  return (
    series: '$kind-$fy',
    format: (seq) => '${kind == 'credit' ? 'CN ' : ''}${BsDate.fiscalYearLabel(fy)}-${seq.toString().padLeft(4, '0')}',
  );
}
