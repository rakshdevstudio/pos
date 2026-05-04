import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/held_bill_draft.dart';

class HeldBillService {
  static const String _draftKey = 'held_bill_drafts_v1';

  const HeldBillService();

  Future<List<HeldBillDraft>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      final drafts = decoded
          .whereType<Map<String, dynamic>>()
          .map(HeldBillDraft.fromJson)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return drafts;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveDraft(HeldBillDraft draft) async {
    final drafts = [...await getDrafts()];
    final index = drafts.indexWhere((candidate) => candidate.id == draft.id);
    if (index >= 0) {
      drafts[index] = draft;
    } else {
      drafts.add(draft);
    }
    await _persist(drafts);
  }

  Future<void> deleteDraft(String draftId) async {
    final drafts = [...await getDrafts()]
      ..removeWhere((draft) => draft.id == draftId);
    await _persist(drafts);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  Future<void> _persist(List<HeldBillDraft> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey,
      jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
    );
  }
}
