import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../billing/billing_providers.dart';
import '../billing/billing_service.dart';
import '../core/theme.dart';
import '../tier/tier_providers.dart';
import '../tier/tier_service.dart';

enum _SignUpMethod { google, apple, facebook, email }

/// Both tiers are sold as two independent Play Console subscription
/// products per tier (e.g. lite_monthly / lite_annual) -- see
/// BillingService's product id constants.
enum _BillingPeriod { monthly, annual }

/// Shown either proactively (a guest taps "Register" on Case Files) or as a
/// forced prompt once a guest has used up their free cases. Free is the
/// only tier that's actually selectable right now -- Lite/Premium show
/// their planned pricing and a comparison table, but tapping either just
/// informs the player and points them at Free in the meantime.
class RegistrationScreen extends ConsumerStatefulWidget {
  final String? reason;
  const RegistrationScreen({super.key, this.reason});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  bool _registering = false;
  bool _deletingAccount = false;
  final Set<UserTier> _purchasingTiers = {};
  _BillingPeriod _billingPeriod = _BillingPeriod.monthly;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      final user = state.session?.user;
      if (user == null || user.isAnonymous || !mounted) return;
      await ref.read(tierGateServiceProvider).createProfile(UserTier.free);
      ref.invalidate(userTierProvider);
      ref.invalidate(guestSolvedCountProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registered! Enjoy Detective Daily.')),
      );
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _pickRegistrationMethod() async {
    final choice = await showModalBottomSheet<_SignUpMethod>(
      context: context,
      backgroundColor: kSurfaceCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Continue with', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.g_mobiledata, size: 32),
              title: const Text('Google'),
              onTap: () => Navigator.pop(ctx, _SignUpMethod.google),
            ),
            ListTile(
              leading: const Icon(Icons.apple),
              title: const Text('Apple'),
              onTap: () => Navigator.pop(ctx, _SignUpMethod.apple),
            ),
            ListTile(
              leading: const Icon(Icons.facebook),
              title: const Text('Facebook'),
              onTap: () => Navigator.pop(ctx, _SignUpMethod.facebook),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email address'),
              onTap: () => Navigator.pop(ctx, _SignUpMethod.email),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _SignUpMethod.google:
        await _registerWithOAuth(OAuthProvider.google);
      case _SignUpMethod.apple:
        await _registerWithOAuth(OAuthProvider.apple);
      case _SignUpMethod.facebook:
        await _registerWithOAuth(OAuthProvider.facebook);
      case _SignUpMethod.email:
        await _promptForEmail();
    }
  }

  Future<void> _registerWithOAuth(OAuthProvider provider) async {
    setState(() => _registering = true);
    try {
      await ref.read(tierGateServiceProvider).registerWithProvider(provider);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start registration: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _promptForEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register with email'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'you@example.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    setState(() => _registering = true);
    try {
      await ref.read(tierGateServiceProvider).registerWithEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check $email for a confirmation link.')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send the link: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, solved-case history, ratings, and plan. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await ref.read(tierGateServiceProvider).deleteAccount();
      if (!mounted) return;
      ref.invalidate(userTierProvider);
      ref.invalidate(guestSolvedCountProvider);
      Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() => _deletingAccount = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete account. Please try again.')),
        );
      }
    }
  }

  /// Kicks off Play's purchase sheet for [tier]/[productId]. The tier is
  /// only ever granted asynchronously, once the app-root PurchaseListener
  /// hears back from Play and the server verifies the purchase -- this
  /// method just starts that flow and reports whether it *could* be
  /// started.
  Future<void> _purchaseTier(UserTier tier, String productId) async {
    final billing = ref.read(billingServiceProvider);
    if (!await billing.isAvailable()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Play Store billing is not available on this device.')),
        );
      }
      return;
    }

    final products = ref.read(subscriptionProductsProvider).valueOrNull ?? const [];
    ProductDetails? product;
    for (final candidate in products) {
      if (candidate.id == productId) {
        product = candidate;
        break;
      }
    }
    if (product == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This plan is not available for purchase yet. Please try again soon.')),
        );
      }
      return;
    }

    setState(() => _purchasingTiers.add(tier));
    try {
      await billing.buy(product);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start purchase: $err')));
      }
    } finally {
      if (mounted) setState(() => _purchasingTiers.remove(tier));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTier = ref.watch(userTierProvider).valueOrNull;
    // Watched (not just read) so the products load as soon as this screen
    // opens, ready by the time a Lite/Premium card is tapped.
    ref.watch(subscriptionProductsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.reason != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kAccentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kAccentAmber.withValues(alpha: 0.4)),
                ),
                child: Text(widget.reason!, style: const TextStyle(color: kAccentAmber)),
              ),
              const SizedBox(height: 16),
            ],
            Text('Choose your plan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Registering saves your progress to your account and unlocks daily new cases.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            _TierCard(
              name: 'Free',
              priceLabel: 'Free forever',
              blurb: '1 new case per day, plus every case already in your list.',
              busy: _registering,
              isCurrentPlan: currentTier == UserTier.free,
              onTap: _pickRegistrationMethod,
              highlight: true,
            ),
            const SizedBox(height: 16),
            Center(
              child: SegmentedButton<_BillingPeriod>(
                segments: const [
                  ButtonSegment(value: _BillingPeriod.monthly, label: Text('Monthly')),
                  ButtonSegment(value: _BillingPeriod.annual, label: Text('Annual')),
                ],
                selected: {_billingPeriod},
                onSelectionChanged: (selection) => setState(() => _billingPeriod = selection.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_billingPeriod == _BillingPeriod.monthly) ...[
              _TierCard(
                name: 'Detective Daily · Lite',
                priceLabel: '₹10/mo',
                blurb: '3 new cases per day.',
                busy: _purchasingTiers.contains(UserTier.lite),
                isCurrentPlan: currentTier == UserTier.lite,
                onTap: () => _purchaseTier(UserTier.lite, kLiteMonthlyProductId),
              ),
              const SizedBox(height: 12),
              _TierCard(
                name: 'Detective Daily · Premium',
                priceLabel: '₹20/mo',
                blurb: 'Unlimited new cases, anytime.',
                busy: _purchasingTiers.contains(UserTier.premium),
                isCurrentPlan: currentTier == UserTier.premium,
                onTap: () => _purchaseTier(UserTier.premium, kPremiumMonthlyProductId),
              ),
            ] else ...[
              _TierCard(
                name: 'Detective Daily · Lite',
                regularPrice: '₹2388/yr',
                priceLabel: '₹120/yr',
                showLaunchOffer: true,
                blurb: '3 new cases per day.',
                busy: _purchasingTiers.contains(UserTier.lite),
                isCurrentPlan: currentTier == UserTier.lite,
                onTap: () => _purchaseTier(UserTier.lite, kLiteAnnualProductId),
              ),
              const SizedBox(height: 12),
              _TierCard(
                name: 'Detective Daily · Premium',
                regularPrice: '₹3588/yr',
                priceLabel: '₹240/yr',
                showLaunchOffer: true,
                blurb: 'Unlimited new cases, anytime.',
                busy: _purchasingTiers.contains(UserTier.premium),
                isCurrentPlan: currentTier == UserTier.premium,
                onTap: () => _purchaseTier(UserTier.premium, kPremiumAnnualProductId),
              ),
            ],
            const SizedBox(height: 24),
            Text('Compare plans', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ComparisonTable(billingPeriod: _billingPeriod),
            if (_billingPeriod == _BillingPeriod.annual) ...[
              const SizedBox(height: 6),
              const Text('* Launch offer pricing', style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
            if (currentTier != null) ...[
              const SizedBox(height: 32),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _deletingAccount ? null : _confirmDeleteAccount,
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  child: _deletingAccount
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Delete account'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final String name;
  final String priceLabel;
  final String blurb;
  final bool busy;
  final bool highlight;
  final bool isCurrentPlan;
  final VoidCallback onTap;

  /// Struck-through "regular" price shown alongside [priceLabel] when
  /// [showLaunchOffer] is true -- e.g. the annual plans' undiscounted
  /// yearly-equivalent of the monthly launch price.
  final String? regularPrice;
  final bool showLaunchOffer;

  const _TierCard({
    required this.name,
    required this.priceLabel,
    required this.blurb,
    required this.busy,
    required this.isCurrentPlan,
    required this.onTap,
    this.highlight = false,
    this.regularPrice,
    this.showLaunchOffer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight ? const BorderSide(color: kAccentBlue, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (showLaunchOffer) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kAccentAmber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'LAUNCH OFFER',
                        style: TextStyle(color: kAccentAmber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (regularPrice != null) ...[
                        Text(
                          regularPrice!,
                          style: const TextStyle(color: Colors.white38, decoration: TextDecoration.lineThrough),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        priceLabel,
                        style: const TextStyle(color: kAccentAmber, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(blurb, style: const TextStyle(color: Colors.white60)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: FilledButton(
                onPressed: (busy || isCurrentPlan) ? null : onTap,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isCurrentPlan ? 'Current Plan' : 'Update Plan',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.billingPeriod});

  final _BillingPeriod billingPeriod;

  @override
  Widget build(BuildContext context) {
    final priceRow = billingPeriod == _BillingPeriod.monthly
        ? ('Price', 'Free', '₹10/mo', '₹20/mo')
        : ('Price', 'Free', '₹120/yr*', '₹240/yr*');
    final rows = [
      ('New cases / day', '1', '3', 'Unlimited'),
      ('Get New Case anytime', 'No', 'No', 'Yes'),
      priceRow,
    ];
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.4),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
        },
        children: [
          const TableRow(
            children: [
              SizedBox.shrink(),
              _HeaderCell('Free'),
              _HeaderCell('Lite'),
              _HeaderCell('Premium'),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(row.$1, style: const TextStyle(color: Colors.white70)),
                ),
                _ValueCell(row.$2),
                _ValueCell(row.$3),
                _ValueCell(row.$4),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
}

class _ValueCell extends StatelessWidget {
  final String value;
  const _ValueCell(this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
}
