/// Truth Engine: the immutable case file. Pure data, no game logic here —
/// the Game Engine and Conversation Engine decide what a player can see and
/// when; this layer only holds what is true.
library;

enum FactCategory { timeline, motive, relationships, alibi }

class Fact {
  final String id;
  final String text;
  final bool isLie;

  const Fact({required this.id, required this.text, this.isLie = false});

  factory Fact.fromJson(Map<String, dynamic> json) => Fact(
        id: json['id'] as String,
        text: json['text'] as String,
        isLie: json['isLie'] as bool? ?? false,
      );
}

class EvidenceReaction {
  final String id;
  final String evidenceId;
  final String text;
  final bool isLie;

  const EvidenceReaction({
    required this.id,
    required this.evidenceId,
    required this.text,
    this.isLie = false,
  });

  factory EvidenceReaction.fromJson(Map<String, dynamic> json) => EvidenceReaction(
        id: json['id'] as String,
        evidenceId: json['evidenceId'] as String,
        text: json['text'] as String,
        isLie: json['isLie'] as bool? ?? false,
      );
}

class InitialLie {
  final String id;
  final String text;
  final String contradictedByEvidenceId;

  const InitialLie({
    required this.id,
    required this.text,
    required this.contradictedByEvidenceId,
  });

  factory InitialLie.fromJson(Map<String, dynamic> json) => InitialLie(
        id: json['id'] as String,
        text: json['text'] as String,
        contradictedByEvidenceId: json['contradictedByEvidenceId'] as String,
      );
}

class SuspectFacts {
  final List<Fact> timeline;
  final List<Fact> motive;
  final List<Fact> relationships;
  final List<Fact> alibi;
  final List<EvidenceReaction> evidenceReactions;

  const SuspectFacts({
    required this.timeline,
    required this.motive,
    required this.relationships,
    required this.alibi,
    required this.evidenceReactions,
  });

  factory SuspectFacts.fromJson(Map<String, dynamic> json) => SuspectFacts(
        timeline: (json['timeline'] as List).map((e) => Fact.fromJson(e as Map<String, dynamic>)).toList(),
        motive: (json['motive'] as List).map((e) => Fact.fromJson(e as Map<String, dynamic>)).toList(),
        relationships:
            (json['relationships'] as List).map((e) => Fact.fromJson(e as Map<String, dynamic>)).toList(),
        alibi: (json['alibi'] as List).map((e) => Fact.fromJson(e as Map<String, dynamic>)).toList(),
        evidenceReactions: (json['evidenceReactions'] as List)
            .map((e) => EvidenceReaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  List<Fact> byCategory(FactCategory category) => switch (category) {
        FactCategory.timeline => timeline,
        FactCategory.motive => motive,
        FactCategory.relationships => relationships,
        FactCategory.alibi => alibi,
      };
}

class BackgroundCheckResult {
  final bool flagged;
  final String text;

  const BackgroundCheckResult({required this.flagged, required this.text});

  factory BackgroundCheckResult.fromJson(Map<String, dynamic> json) => BackgroundCheckResult(
        flagged: json['flagged'] as bool? ?? false,
        text: json['text'] as String,
      );
}

class Suspect {
  final String id;
  final String name;
  final String role;
  final String persona;
  final SuspectFacts facts;
  final BackgroundCheckResult backgroundCheck;
  final InitialLie? initialLie;

  // Demographic profile -- drives which narration voice this suspect gets
  // (see supabase/functions/_shared/google-tts.ts's country/sex-based
  // voice pools) as well as being flavor for future roster UI. age/country
  // fall back to 0/'' for older case rows generated before this field
  // existed rather than failing to parse.
  final int age;
  final String sex;
  final String gender;
  final String ethnicity;
  final String country;

  const Suspect({
    required this.id,
    required this.name,
    required this.role,
    required this.persona,
    required this.facts,
    required this.backgroundCheck,
    this.initialLie,
    this.age = 0,
    this.sex = '',
    this.gender = '',
    this.ethnicity = '',
    this.country = '',
  });

  factory Suspect.fromJson(Map<String, dynamic> json) => Suspect(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        persona: json['persona'] as String,
        facts: SuspectFacts.fromJson(json['facts'] as Map<String, dynamic>),
        backgroundCheck: BackgroundCheckResult.fromJson(json['backgroundCheck'] as Map<String, dynamic>),
        initialLie:
            json['initialLie'] == null ? null : InitialLie.fromJson(json['initialLie'] as Map<String, dynamic>),
        age: json['age'] as int? ?? 0,
        sex: json['sex'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        ethnicity: json['ethnicity'] as String? ?? '',
        country: json['country'] as String? ?? '',
      );
}

class Evidence {
  final String id;
  final String suspectId;
  final String label;
  final String description;
  final int unlockCost;

  const Evidence({
    required this.id,
    required this.suspectId,
    required this.label,
    required this.description,
    required this.unlockCost,
  });

  factory Evidence.fromJson(Map<String, dynamic> json) => Evidence(
        id: json['id'] as String,
        suspectId: json['suspectId'] as String,
        label: json['label'] as String,
        description: json['description'] as String,
        unlockCost: json['unlockCost'] as int,
      );
}

enum TimelineEntryType { confirmed, claimed }

class TimelineEntry {
  final String time;
  final TimelineEntryType type;
  final String text;
  final String? suspectId;

  const TimelineEntry({
    required this.time,
    required this.type,
    required this.text,
    this.suspectId,
  });

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => TimelineEntry(
        time: json['time'] as String,
        type: (json['type'] as String) == 'confirmed' ? TimelineEntryType.confirmed : TimelineEntryType.claimed,
        text: json['text'] as String,
        suspectId: json['suspectId'] as String?,
      );
}

class Solution {
  final String culpritId;
  final String narrative;

  const Solution({required this.culpritId, required this.narrative});

  factory Solution.fromJson(Map<String, dynamic> json) => Solution(
        culpritId: json['culpritId'] as String,
        narrative: json['narrative'] as String,
      );
}

class CaseCosts {
  final int unlockEvidence;
  final int backgroundCheck;
  final int wrongAccusation;

  const CaseCosts({
    required this.unlockEvidence,
    required this.backgroundCheck,
    required this.wrongAccusation,
  });

  factory CaseCosts.fromJson(Map<String, dynamic> json) => CaseCosts(
        unlockEvidence: json['unlockEvidence'] as int,
        backgroundCheck: json['backgroundCheck'] as int,
        wrongAccusation: json['wrongAccusation'] as int,
      );
}

class Case {
  final String id;
  final String title;
  final String briefing;
  final int startingFocus;
  final CaseCosts costs;
  final List<Suspect> suspects;
  final List<Evidence> evidence;
  final List<TimelineEntry> timeline;
  final Solution solution;

  const Case({
    required this.id,
    required this.title,
    required this.briefing,
    required this.startingFocus,
    required this.costs,
    required this.suspects,
    required this.evidence,
    required this.timeline,
    required this.solution,
  });

  factory Case.fromJson(Map<String, dynamic> json) => Case(
        id: json['id'] as String,
        title: json['title'] as String,
        briefing: json['briefing'] as String,
        startingFocus: json['startingFocus'] as int,
        costs: CaseCosts.fromJson(json['costs'] as Map<String, dynamic>),
        suspects: (json['suspects'] as List).map((e) => Suspect.fromJson(e as Map<String, dynamic>)).toList(),
        evidence: (json['evidence'] as List).map((e) => Evidence.fromJson(e as Map<String, dynamic>)).toList(),
        timeline: (json['timeline'] as List).map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>)).toList(),
        solution: Solution.fromJson(json['solution'] as Map<String, dynamic>),
      );

  Suspect suspectById(String id) => suspects.firstWhere((s) => s.id == id);

  List<Evidence> evidenceForSuspect(String suspectId) =>
      evidence.where((e) => e.suspectId == suspectId).toList();
}
