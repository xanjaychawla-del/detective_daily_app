/// AI Adapter: takes one Truth Engine fact and phrases it naturally through
/// the narrate Supabase Edge Function. Never invents anything, never
/// decides game logic -- and if the function is unreachable, it falls back
/// to showing the raw fact text so the game stays playable rather than stuck.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpokenLine {
  final String role; // 'suspect' history entries only, for voice continuity
  final String text;

  const SpokenLine({required this.role, required this.text});

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class AiAdapterService {
  final SupabaseClient _client;

  AiAdapterService(this._client);

  Future<String> narrate({
    required String suspectName,
    required String persona,
    required String fact,
    required String category,
    List<SpokenLine> history = const [],
  }) async {
    try {
      final response = await _client.functions.invoke(
        'narrate',
        body: {
          'suspectName': suspectName,
          'persona': persona,
          'fact': fact,
          'category': category,
          'history': history.map((h) => h.toJson()).toList(),
        },
      ).timeout(const Duration(seconds: 20));

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final reply = (data['reply'] as String?)?.trim();
        if (reply != null && reply.isNotEmpty) return reply;
      }
    } catch (_) {
      // Network error, timeout, or malformed response -- fall through to
      // the raw-fact fallback below rather than blocking play.
    }
    return fact;
  }
}

final aiAdapterServiceProvider = Provider<AiAdapterService>(
  (ref) => AiAdapterService(Supabase.instance.client),
);
