import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sarathigrocery/app/app.dart';
import 'package:sarathigrocery/app/injection.dart';

void main() {
  testWidgets('First run: set up a new business, land on the owner dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(SarathiGroceryApp(scope: AppScope()));
    await tester.pumpAndSettle();

    expect(find.text('Log In'), findsOneWidget);
    await tester.tap(find.text('Set up a new business'));
    await tester.pumpAndSettle();

    Finder field(String label) => find.widgetWithText(TextField, label);
    await tester.enterText(field('Business name'), 'Test Shop');
    await tester.enterText(field('Your name'), 'Owner');
    await tester.enterText(field('Your phone number'), '9800000001');
    await tester.enterText(field('Password (min 8 characters)'), 'password123');
    await tester.enterText(field('Confirm password'), 'password123');
    await tester.tap(find.text('Create Business'));
    await tester.pumpAndSettle();

    expect(find.text('Owner Dashboard'), findsOneWidget);
    expect(find.text("Today's Sales"), findsOneWidget);
    expect(find.textContaining('Verify your phone number'), findsOneWidget);
  });
}
