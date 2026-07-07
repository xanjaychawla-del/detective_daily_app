import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme.dart';
import '../tier/tier_providers.dart';
import '../tier/tier_service.dart';

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

  Future<void> _registerFree() async {
    setState(() => _registering = true);
    try {
      await ref.read(tierGateServiceProvider).registerWithGoogle();
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

  void _showNotYetAvailable(String tierName) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tierName),
        content: Text(
          "Detective Daily $tierName isn't active yet -- we'll let you know the moment it launches. "
          'Register for Free for now to keep investigating.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              price: '',
              priceLabel: 'Free forever',
              blurb: '1 new case per day, plus every case already in your list.',
              busy: _registering,
              onTap: _registerFree,
              ctaLabel: 'Continue with Google',
              highlight: true,
            ),
            const SizedBox(height: 12),
            _TierCard(
              name: 'Detective Daily · Lite',
              price: '₹199',
              priceLabel: '₹99/mo',
              blurb: '3 new cases per day.',
              busy: false,
              onTap: () => _showNotYetAvailable('Lite'),
              ctaLabel: 'Select Lite',
            ),
            const SizedBox(height: 12),
            _TierCard(
              name: 'Detective Daily · Premium',
              price: '₹299',
              priceLabel: '₹199/mo',
              blurb: 'Unlimited new cases, anytime.',
              busy: false,
              onTap: () => _showNotYetAvailable('Premium'),
              ctaLabel: 'Select Premium',
            ),
            const SizedBox(height: 24),
            Text('Compare plans', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _ComparisonTable(),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final String name;
  final String price;
  final String priceLabel;
  final String blurb;
  final bool busy;
  final bool highlight;
  final String ctaLabel;
  final VoidCallback onTap;

  const _TierCard({
    required this.name,
    required this.price,
    required this.priceLabel,
    required this.blurb,
    required this.busy,
    required this.ctaLabel,
    required this.onTap,
    this.highlight = false,
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (price.isNotEmpty) ...[
                        Text(
                          price,
                          style: const TextStyle(
                            color: Colors.white38,
                            decoration: TextDecoration.lineThrough,
                          ),
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
            FilledButton(
              onPressed: busy ? null : onTap,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(ctaLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('New cases / day', '1', '3', 'Unlimited'),
      ('Get New Case anytime', 'No', 'No', 'Yes'),
      ('Price', 'Free', '₹99/mo', '₹199/mo'),
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
