import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sarathigrocery/app/app.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_screen.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/vat_books_screen.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/presentation/pages/cash_screen.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/unit_setup.dart';
import 'package:sarathigrocery/features/inventory/presentation/pages/product_form_screen.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';

import 'sign_up.dart';

void main() {
  testWidgets('First run: set up a new business, land on the owner dashboard', (WidgetTester tester) async {
    final accounts = InMemoryAuthRepository();
    await tester.pumpWidget(SarathiGroceryApp(scope: AppScope(store: InMemoryRemoteStore(), authRepository: accounts)));
    await tester.pumpAndSettle();

    expect(find.text('Log In'), findsOneWidget);
    await tester.tap(find.text('New shop? Sign up'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.widgetWithText(TextField, label);
    Future<void> next(String button) async {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    await tester.enterText(field('Email'), 'owner@shop.test');
    await tester.enterText(field('Password (min 8 characters)'), 'password123');
    await tester.enterText(field('Confirm password'), 'password123');
    await next('Sign Up');
    await next("I've verified");
    expect(find.textContaining('Not verified yet'), findsOneWidget);
    accounts.verifyEmail('owner@shop.test');
    await next("I've verified");
    await tester.enterText(field('Shop name'), 'Test Shop');
    await tester.enterText(field('Your name'), 'Owner');
    await tester.enterText(field('Your phone number'), '9800000001');
    await next('Create Shop');

    expect(find.text('Owner Dashboard'), findsOneWidget);
    expect(find.text("Today's Sales"), findsOneWidget);
  });

  testWidgets('Staff with cash & accounts get the money sections and a More tab', (WidgetTester tester) async {
    final store = InMemoryRemoteStore();
    final accounts = InMemoryAuthRepository();
    final owner = AppScope(store: store, authRepository: accounts);
    await tester.runAsync(() async {
      await signUp(owner, accounts, phone: '9800000001', password: 'password123');
      await owner.employees.createEmployeeAccount(name: 'Sita', email: testEmail('9800000002'), phone: '9800000002', password: 'password123', role: UserRole.employee, userName: 'Owner');
      owner.employees.setCashAccess(owner.employees.employees.firstWhere((u) => u.phone == '9800000002'), true, userName: 'Owner');
      await pumpEventQueue();
    });
    final staff = AppScope(store: store, authRepository: accounts.forDevice());
    await tester.runAsync(() => staff.auth.login(testEmail('9800000002'), 'password123'));

    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(SarathiGroceryApp(scope: staff));
    await tester.pumpAndSettle();

    expect(find.text('Hi, Sita'), findsOneWidget);
    expect(find.text('Cash in Hand'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Customers'), findsNothing);
  });

  testWidgets('Accounts, Money and VAT books render every tab with data', (WidgetTester tester) async {
    final store = InMemoryRemoteStore();
    final accounts = InMemoryAuthRepository();
    final owner = AppScope(store: store, authRepository: accounts);
    await tester.runAsync(() async {
      await signUp(owner, accounts, phone: '9800000001', password: 'password123', sampleData: true);
      owner.settings.setVat(registered: true, pan: '601234567', rate: 13, pricesIncludeVat: true);
      owner.cash.capitalIn('Owner', 200000, 'cash', userName: 'Owner');
      final p = owner.inventory.products.first;
      await owner.sales.sell(items: [SaleItem(product: p, qty: 1, unitPrice: p.unitPrice)], isCredit: false, userName: 'Owner');
      await pumpEventQueue();
    });
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> showAndTapTabs(Widget screen, List<String> tabs) async {
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
      for (final tab in tabs) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    }

    await showAndTapTabs(AccountingScreen(controller: owner.accounting, auth: owner.auth, suppliers: owner.suppliers),
        ['Profit & Loss', 'Balance Sheet', 'Trial Balance', 'Journal', 'Simple']);
    expect(find.text('Books balanced'), findsOneWidget);
    await showAndTapTabs(CashScreen(controller: owner.cash, accounting: owner.accounting, auth: owner.auth), ['Expenses', 'Owners & loans', 'Money in & out']);
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(find.text('Capital put in'), findsOneWidget);
    await showAndTapTabs(VatBooksScreen(sales: owner.sales, purchasing: owner.purchasing, cash: owner.cash, userName: 'Owner'), ['Sales Book', 'Purchase Book', 'Summary']);
  });

  testWidgets('Product form shows units against the main unit and saves them', (WidgetTester tester) async {
    final store = InMemoryRemoteStore();
    final accounts = InMemoryAuthRepository();
    final owner = AppScope(store: store, authRepository: accounts);
    await tester.runAsync(() => signUp(owner, accounts, phone: '9800000001', password: 'password123'));
    final plan = planUnits('sack', 4800, [(name: 'kg', perPrimary: 60, bigger: false, price: 85)]);
    final flour = owner.inventory.createProduct(
        name: 'Flour', category: 'General', unit: ProductUnit.kg, unitPrice: plan.basePrice, purchasePrice: 75, packs: plan.packs, stockQty: 0, reorderLevel: 120, primaryUnit: 'sack');
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: ProductFormScreen(controller: owner.inventory, auth: owner.auth, settings: owner.settings, product: flour)));
    await tester.pumpAndSettle();
    expect(find.text('1 sack = 60 kg'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cost per sack'), findsNothing, reason: 'cost comes from purchases');
    expect(find.text('Average cost from purchases: NPR 4,500 / sack'), findsOneWidget);
    expect(find.text('Correct cost'), findsOneWidget, reason: 'owner can fix a wrong cost');
    await tester.enterText(find.widgetWithText(TextField, 'Min. price per sack (optional)'), '4900');
    await tester.scrollUntilVisible(find.text('Save Changes'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(flour.sellUnit('sack').price, 4900);
    expect(flour.purchasePrice, 75, reason: 'unchanged: 4,500 per sack ÷ 60 kg');
    expect(flour.reorderLevel, 120);
  });

  testWidgets('New product asks for cost only for stock already on hand', (WidgetTester tester) async {
    final accounts = InMemoryAuthRepository();
    final owner = AppScope(authRepository: accounts);
    await tester.runAsync(() => signUp(owner, accounts, phone: '9800000001', password: 'password123'));
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: ProductFormScreen(controller: owner.inventory, auth: owner.auth, settings: owner.settings)));
    await tester.pumpAndSettle();
    Finder costField() => find.widgetWithText(TextField, 'Cost of the stock you already have, per kg');
    expect(costField(), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Opening stock (kg)'), '20');
    await tester.pumpAndSettle();
    expect(costField(), findsOneWidget);
  });
}
