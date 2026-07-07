import 'package:shared_preferences/shared_preferences.dart';

const kCaseFilesTutorialKey = 'seen_case_files_tutorial_v1';
const kHomeShellTutorialKey = 'seen_home_shell_tutorial_v1';
const kInterrogationTutorialKey = 'seen_interrogation_tutorial_v1';
const kEvidenceBoardTutorialKey = 'seen_evidence_board_tutorial_v1';

class OnboardingPrefs {
  static Future<bool> hasSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  static Future<void> markSeen(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
