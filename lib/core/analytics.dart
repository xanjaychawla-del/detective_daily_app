import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps FirebaseAnalytics so a call site never has to worry about Firebase
/// having failed to initialize (see main.dart) -- logging an event is
/// never allowed to crash gameplay.
class Analytics {
  Future<void> logEvent({required String name, Map<String, Object>? parameters}) async {
    try {
      await FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters);
    } catch (err) {
      debugPrint('Analytics event "$name" not logged: $err');
    }
  }
}

final analyticsProvider = Provider<Analytics>((ref) => Analytics());
