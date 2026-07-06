import 'package:supabase_flutter/supabase_flutter.dart';

import '../truth_engine/models.dart';

enum PlayStatus { unopened, inProgress, solved, gaveUp }

PlayStatus _playStatusFromDb(String value) => switch (value) {
      'in_progress' => PlayStatus.inProgress,
      'solved' => PlayStatus.solved,
      'gave_up' => PlayStatus.gaveUp,
      _ => PlayStatus.unopened,
    };

String _playStatusToDb(PlayStatus status) => switch (status) {
      PlayStatus.unopened => 'unopened',
      PlayStatus.inProgress => 'in_progress',
      PlayStatus.solved => 'solved',
      PlayStatus.gaveUp => 'gave_up',
    };

class CaseRatingStats {
  final double average;
  final int count;

  const CaseRatingStats({required this.average, required this.count});
}

class CaseRepositoryService {
  CaseRepositoryService(this._client);

  final SupabaseClient _client;

  Case _caseFromRow(Map<String, dynamic> row) => Case.fromJson({
        'id': row['id'],
        'title': row['title'],
        'briefing': row['briefing'],
        'startingFocus': row['starting_focus'],
        'costs': row['costs'],
        'suspects': row['suspects'],
        'evidence': row['evidence'],
        'timeline': row['timeline'],
        'solution': row['solution'],
      });

  Future<List<Case>> fetchCases() async {
    final rows = await _client.from('cases').select().order('created_at');
    return (rows as List)
        .map((row) => _caseFromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, PlayStatus>> fetchPlayStatuses() async {
    final userId = _client.auth.currentUser!.id;
    final rows = await _client
        .from('plays')
        .select('case_id, status')
        .eq('user_id', userId);
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['case_id'] as String:
            _playStatusFromDb(row['status'] as String),
    };
  }

  Future<void> setPlayStatus(String caseId, PlayStatus status) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('plays').upsert(
      {
        'user_id': userId,
        'case_id': caseId,
        'status': _playStatusToDb(status),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id, case_id',
    );
  }

  Future<Case> generateNewCase() async {
    final response = await _client.functions.invoke('generate-case');
    final data = response.data;
    if (data is! Map<String, dynamic> || data['ok'] != true || data['case'] == null) {
      throw Exception('Case generation failed: ${data is Map ? data['error'] : 'unknown_error'}');
    }
    return Case.fromJson(data['case'] as Map<String, dynamic>);
  }

  Future<Map<String, CaseRatingStats>> fetchRatingStats() async {
    final rows = await _client.from('case_rating_stats').select();
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['case_id'] as String: CaseRatingStats(
          average: (row['avg_rating'] as num).toDouble(),
          count: row['rating_count'] as int,
        ),
    };
  }

  Future<void> submitRating(String caseId, int rating) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('case_ratings').upsert(
      {
        'user_id': userId,
        'case_id': caseId,
        'rating': rating,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id, case_id',
    );
  }
}
