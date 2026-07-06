/// AI Adapter: takes one Truth Engine fact and phrases it naturally through
/// the local narration proxy (see server/). Never invents anything, never
/// decides game logic -- and if the proxy is unreachable, it falls back to
/// showing the raw fact text so the game stays playable rather than stuck.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class SpokenLine {
  final String role; // 'suspect' history entries only, for voice continuity
  final String text;

  const SpokenLine({required this.role, required this.text});

  Map<String, String> toJson() => {'role': role, 'text': text};
}

class AiAdapterService {
  final http.Client _client;
  final Uri _narrateUri;

  AiAdapterService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _narrateUri = Uri.parse(
          baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8787'),
        ).replace(path: '/api/narrate');

  Future<String> narrate({
    required String suspectName,
    required String persona,
    required String fact,
    required String category,
    List<SpokenLine> history = const [],
  }) async {
    try {
      final response = await _client
          .post(
            _narrateUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'suspectName': suspectName,
              'persona': persona,
              'fact': fact,
              'category': category,
              'history': history.map((h) => h.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = (body['reply'] as String?)?.trim();
        if (reply != null && reply.isNotEmpty) return reply;
      }
    } catch (_) {
      // Network error, timeout, or malformed response -- fall through to
      // the raw-fact fallback below rather than blocking play.
    }
    return fact;
  }
}

final aiAdapterServiceProvider = Provider<AiAdapterService>((ref) => AiAdapterService());
