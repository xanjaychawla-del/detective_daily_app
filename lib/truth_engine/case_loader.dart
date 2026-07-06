import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

Future<Case> loadCase(String assetPath) async {
  final raw = await rootBundle.loadString(assetPath);
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return Case.fromJson(json);
}
