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

  Future<Map<String, PlayStatus>> fetchPlayStatuses(String deviceId) async {
    final rows = await _client
        .from('plays')
        .select('case_id, status')
        .eq('device_id', deviceId);
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['case_id'] as String:
            _playStatusFromDb(row['status'] as String),
    };
  }

  Future<void> setPlayStatus(
    String deviceId,
    String caseId,
    PlayStatus status,
  ) async {
    await _client.from('plays').upsert(
      {
        'device_id': deviceId,
        'case_id': caseId,
        'status': _playStatusToDb(status),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'device_id, case_id',
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
}
