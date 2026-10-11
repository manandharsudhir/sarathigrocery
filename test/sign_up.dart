import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';

/// Tests name people by a phone number; their login email is derived from it.
String testEmail(String phone) => '$phone@shop.test';

/// Owner sign-up as the app does it: email + password → verify email
/// ([InMemoryAuthRepository.verifyEmail] stands in for the link) → shop.
/// Already signed in (a login with no shop yet), it skips to the verify step.
/// True if the shop opened.
Future<bool> signUp(AppScope scope, InMemoryAuthRepository auth, {required String phone, required String password, String shop = 'Test Shop', String owner = 'Owner', bool sampleData = false}) async {
  final email = testEmail(phone);
  if (!scope.auth.signedIn) await scope.auth.signUp(email, password);
  auth.verifyEmail(email);
  await scope.auth.confirmEmailVerified();
  return scope.auth.setUpBusiness(businessName: shop, ownerName: owner, phone: phone, includeSampleData: sampleData);
}

/// Order lines of whole base units at each product's minimum price.
List<OrderItem> atMinimum(Map<Product, num> qtys) => [for (final e in qtys.entries) OrderItem(product: e.key, qty: e.value.toDouble(), price: e.key.unitPrice)];
