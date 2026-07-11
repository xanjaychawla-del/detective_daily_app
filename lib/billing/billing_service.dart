import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Play Console product ids for the two monthly subscription tiers --
/// these must match exactly what's created under Monetize > Products >
/// Subscriptions.
const kLiteMonthlyProductId = 'lite_monthly';
const kPremiumMonthlyProductId = 'premium_monthly';
const kSubscriptionProductIds = {kLiteMonthlyProductId, kPremiumMonthlyProductId};

/// Wraps `in_app_purchase` for Detective Daily's two monthly subscriptions,
/// mirroring TierGateService's shape (plain class over SupabaseClient).
/// Purchases are granted server-side only -- this class never flips
/// `profiles.tier` itself, it just drives the Play purchase flow and hands
/// the result to `verify-subscription-purchase`.
class BillingService {
  BillingService(this._iap, this._client);

  final InAppPurchase _iap;
  final SupabaseClient _client;

  /// Real-time purchase updates -- must be subscribed to once, for the
  /// whole app lifetime, not just while a purchase screen is mounted. See
  /// PurchaseListener.
  Stream<List<PurchaseDetails>> get purchaseUpdates => _iap.purchaseStream;

  Future<bool> isAvailable() => _iap.isAvailable();

  /// Returns whichever subscription products Play Console actually has
  /// live. Doesn't throw just because a product id isn't found yet (e.g.
  /// before the Play Console products are created) -- only throws on a
  /// genuine query failure.
  Future<List<ProductDetails>> fetchProducts() async {
    final response = await _iap.queryProductDetails(kSubscriptionProductIds);
    if (response.error != null && response.productDetails.isEmpty) {
      throw Exception('Could not load subscription plans: ${response.error!.message}');
    }
    return response.productDetails;
  }

  /// Kicks off Play's purchase sheet for [product]. The actual tier grant
  /// happens asynchronously via [purchaseUpdates] once Play reports the
  /// purchase, never synchronously here.
  Future<void> buy(ProductDetails product) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Sign in before subscribing.');
    }

    // Tying the purchase to our own user id here is what lets the server
    // reject a purchase token that doesn't actually belong to the caller
    // (see verify-subscription-purchase's obfuscatedExternalAccountId check).
    final offerToken = product is GooglePlayProductDetails ? product.offerToken : null;
    final purchaseParam = GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: userId,
      offerToken: offerToken,
    );
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Verifies [purchase] server-side and grants the tier. Only completes
  /// the purchase with Play on success -- on failure, Play redelivers the
  /// same purchase via [purchaseUpdates] on the next app launch, so a
  /// failed/interrupted verification never silently loses the purchase.
  Future<void> verifyAndCompletePurchase(PurchaseDetails purchase) async {
    final response = await _client.functions.invoke(
      'verify-subscription-purchase',
      body: {
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
      },
    );
    final data = response.data;
    if (data is! Map || data['ok'] != true) {
      final error = data is Map ? data['error'] : 'unknown_error';
      throw Exception('Subscription verification failed: $error');
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Recovers subscriptions on a reinstall/new device -- delivered through
  /// [purchaseUpdates] with `PurchaseStatus.restored`.
  Future<void> restorePurchases() {
    return _iap.restorePurchases(applicationUserName: _client.auth.currentUser?.id);
  }
}
