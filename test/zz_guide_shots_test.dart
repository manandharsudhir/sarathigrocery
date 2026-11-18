// TEMPORARY: renders screenshots for the client setup guide. Not a real test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sarathigrocery/app/app.dart';
import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/unit_setup.dart';

const outDir = String.fromEnvironment('SHOTS_DIR');
const fonts = String.fromEnvironment('FONTS_DIR');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File('$fonts/$f').readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']);
    await _font('MaterialIcons', ['MaterialIcons-Regular.otf']);
  });

  testWidgets('guide screenshots', (tester) async {
    final shotKey = GlobalKey();
    final accounts = InMemoryAuthRepository();
    final scope = AppScope(store: InMemoryRemoteStore(), authRepository: accounts);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepaintBoundary(key: shotKey, child: SarathiGroceryApp(scope: scope)));
    await tester.pumpAndSettle();

    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }

    Future<void> shot(String name, {bool unfocus = true}) async {
      if (unfocus) FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await settle();
    }

    Future<void> tapText(String text) => tap(find.text(text).last);
    Finder field(String label) => find.widgetWithText(TextField, label).last;
    Future<void> type(String label, String value) async {
      await tester.ensureVisible(field(label));
      await tester.enterText(field(label), value);
      await tester.pump();
    }

    Future<void> nav(String label) => tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    Future<void> scrollTo(Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      Scrollable.ensureVisible(tester.element(f), alignment: 0.02);
      await tester.pumpAndSettle();
    }

    Future<void> pick(String dropdownLabel, String value) async {
      await tap(find.widgetWithText(DropdownButtonFormField<String>, dropdownLabel).last);
      await tap(find.text(value).last);
    }

    // 1. Sign up.
    await shot('01_login');
    await tapText('New shop? Sign up');
    await type('Email', 'owner@example.com');
    await type('Password (min 8 characters)', 'bakery2026');
    await type('Confirm password', 'bakery2026');
    await shot('02_signup');
    await tapText('Sign Up');
    await shot('03_verify');
    accounts.verifyEmail('owner@example.com');
    await tapText("I've verified");
    await type('Shop name', 'Unique Bakery and Cookies');
    await type('Your name', 'Shop Owner');
    await type('Your phone number', '9800000000');
    await shot('04_shop');
    await tapText('Create Shop');
    await shot('05_dashboard_empty');

    // 2. Settings.
    await nav('More');
    await shot('06_more');
    await tapText('Settings');
    await type('Address', 'New Road, Kathmandu');
    await type('Phone', '01-4000000');
    await shot('07_settings');
    await tapText('Save Settings');
    await scrollTo(find.text('More features'));
    await shot('08_settings_features');
    await tester.pageBack();
    await settle();

    // 3. Products.
    await nav('Inventory');
    await tapText('Add Product');
    await type('Product name', 'Chocolate Chip Cookies');
    await pick('Main unit', 'packet');
    await type('Min. price per packet (optional)', '150');
    await tapText('Add unit');
    await pick('Unit', 'box');
    await tap(find.widgetWithText(DropdownButtonFormField<bool>, 'Size').last);
    await tap(find.text('bigger than packet').last);
    await type('packet in it', '12');
    await type('Min. price per box (optional)', '1700');
    await type('Opening stock (packet)', '40');
    await type('Cost of the stock you already have, per packet', '100');
    await type('Low stock level (packet)', '10');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await shot('09_product_form');
    await scrollTo(find.text('Units'));
    await shot('10_product_units');
    await tapText('Add Product');

    final bread = planUnits('piece', 80, []);
    scope.inventory.createProduct(name: 'White Bread (400 g)', category: 'General', unit: ProductUnit.piece, unitPrice: bread.basePrice, purchasePrice: 55, packs: bread.packs, stockQty: 30, reorderLevel: 8, primaryUnit: 'piece');
    final roll = planUnits('piece', 40, [(name: 'dozen', perPrimary: 12, bigger: true, price: 450)]);
    scope.inventory.createProduct(name: 'Cream Roll', category: 'General', unit: ProductUnit.piece, unitPrice: roll.basePrice, purchasePrice: 25, packs: roll.packs, stockQty: 60, reorderLevel: 12, primaryUnit: 'piece');
    final cake = planUnits('piece', 1200, []);
    scope.inventory.createProduct(name: 'Black Forest Cake (1 lb)', category: 'General', unit: ProductUnit.piece, unitPrice: cake.basePrice, purchasePrice: 800, packs: cake.packs, stockQty: 5, reorderLevel: 2, primaryUnit: 'piece');
    await settle();
    await shot('11_inventory');

    // 4. Customers.
    await nav('More');
    await tapText('Customers');
    await tapText('Add Customer');
    await type('Shop / customer name', 'Hotel Everest Café');
    await type('Phone', '9811111111');
    await type('Location', 'Thamel');
    await type('Credit limit (NPR)', '20000');
    await shot('12_customer_form');
    await tap(find.text('Add Customer').last);
    scope.customers.createCustomer(name: 'Sita Tea Shop', phone: '9822222222', location: 'Baneshwor', creditLimit: 5000, by: scope.auth.currentUser!);
    await settle();
    await shot('13_customers');
    await tester.pageBack();
    await settle();

    // 5. Staff.
    await tapText('Employees');
    await tapText('Add Employee');
    await type('Name', 'Ram');
    await type('Email (used to log in)', 'ram@example.com');
    await type('Phone', '9833333333');
    await type('Temporary password (min 8 characters)', 'welcome123');
    await shot('14_add_employee');
    await tap(find.text('Add Employee').last);
    await settle();
    await shot('15_safeguards');
    await tapText('Not now');
    await shot('16_employees');
    await tester.pageBack();
    await settle();

    // 6. First sale.
    await nav('Sales');
    await shot('17_sales_tab');
    await tapText('New Sale');
    await tapText('Chocolate Chip Cookies');
    await tap(find.byTooltip('One more').first);
    await tapText('Cream Roll');
    await shot('18_new_sale');
    await tapText('Charge');
    await shot('19_checkout');
    await tapText('Complete sale');
    await shot('20_sale_complete');
    await tapText('Done');
    await nav('Dashboard');
    await shot('21_dashboard');
  });
}
