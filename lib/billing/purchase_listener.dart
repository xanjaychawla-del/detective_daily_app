import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../tier/tier_providers.dart';
import 'billing_providers.dart';

/// Subscribes to BillingService.purchaseUpdates for the app's entire
/// lifetime -- Play can deliver a purchase update on the *next app launch*
/// if the app was killed mid-payment, or if server verification failed and
/// the purchase was deliberately left uncompleted (see
/// BillingService.verifyAndCompletePurchase). Scoping this to any one
/// screen (e.g. RegistrationScreen) would miss those redeliveries, so the
/// owner must be the app root (see DetectiveDailyApp) and subscribe as
/// early as possible, before the first frame.
class PurchaseListener {
  PurchaseListener(this._ref, this._messengerKey);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  void start() {
    _subscription = _ref
        .read(billingServiceProvider)
        .purchaseUpdates
        .listen(_handleUpdates, onError: (Object error) => _showMessage('Store connection error: $error'));
  }

  void dispose() {
    _subscription?.cancel();
  }

  Future<void> _handleUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(purchase);
          break;
        case PurchaseStatus.error:
          _showMessage(_friendlyError(purchase.error));
          break;
        case PurchaseStatus.canceled:
          break;
      }
    }
  }

  Future<void> _verify(PurchaseDetails purchase) async {
    try {
      await _ref.read(billingServiceProvider).verifyAndCompletePurchase(purchase);
      _ref.invalidate(userTierProvider);
      _showMessage('Subscription active -- thank you!');
    } catch (_) {
      _showMessage('Could not confirm your subscription. Please try again or contact support.');
    }
  }

  String _friendlyError(IAPError? error) {
    final message = error?.message.toLowerCase() ?? '';
    if (message.contains('already') && message.contains('own')) {
      return 'You already have an active subscription for this plan.';
    }
    return 'Purchase could not be completed. Please try again.';
  }

  void _showMessage(String message) {
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }
}
