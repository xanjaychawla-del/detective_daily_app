import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../case_repository/case_repository_providers.dart';
import 'billing_service.dart';

final billingServiceProvider = Provider<BillingService>(
  (ref) => BillingService(InAppPurchase.instance, ref.watch(supabaseClientProvider)),
);

final subscriptionProductsProvider = FutureProvider<List<ProductDetails>>((ref) async {
  return ref.watch(billingServiceProvider).fetchProducts();
});
