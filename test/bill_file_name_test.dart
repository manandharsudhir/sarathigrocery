import 'package:flutter_test/flutter_test.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pdf/invoice_pdf.dart';

void main() {
  final day = DateTime(2025, 11, 3); // 2082-07-17 BS
  test('customer, BS date, payment, number; unsafe characters replaced', () {
    final c = Customer(id: 'C1', name: 'Ram/Shyam Stores', phone: '', location: '', creditLimit: 0);
    final sale = Sale(id: 'S1', date: day, items: [], isCredit: false, customer: c, account: 'wallet:eSewa');
    expect(billFileName(sale, null), 'Ram-Shyam Stores 2082-07-17 eSewa S1.pdf');
  });
  test('walk-in on credit', () {
    final sale = Sale(id: 'S2', date: day, items: [], isCredit: true);
    expect(billFileName(sale, null), 'Walk-in 2082-07-17 Credit S2.pdf');
  });
  test('amount in words uses lakh/crore', () {
    expect(amountInWords(156000.23), 'One Lakh Fifty-Six Thousand Rupees and Twenty-Three Paisa only');
    expect(amountInWords(1250000000), 'One Hundred Twenty-Five Crore Rupees only');
    expect(amountInWords(0.5), 'Zero Rupees and Fifty Paisa only');
  });
}
