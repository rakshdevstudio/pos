import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/school_repository.dart';
import '../remote/api_client.dart';

class SchoolRepositoryImpl implements SchoolRepository {
  static const String _cacheKey = 'schools_cache';
  final ApiClient _apiClient;

  SchoolRepositoryImpl(this._apiClient);

  @override
  Future<List<School>> getSchools() async {
    try {
      final baseUrl = await ApiClient.getBaseUrl();
      final response = await _apiClient.dio.get('$baseUrl/schools');
      final data = response.data as List<dynamic>;
      final schools = data
          .map((e) => School.fromJson(e as Map<String, dynamic>))
          .toList();
      await cacheSchools(schools);
      return schools;
    } catch (_) {
      // Return cached on failure, or mock data if cache is empty
      final cached = getCachedSchools();
      if (cached.isNotEmpty) return cached;
      
      final mockSchools = [
        School(id: 1, name: 'Delhi Public School', address: 'Delhi', city: 'New Delhi'),
        School(id: 2, name: 'Ryan International', address: 'Mumbai', city: 'Mumbai'),
        School(id: 3, name: 'St. Xaviers High', address: 'Bangalore', city: 'Bengaluru'),
      ];
      await cacheSchools(mockSchools);
      return mockSchools;
    }
  }

  @override
  Future<void> cacheSchools(List<School> schools) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(schools.map((s) => s.toJson()).toList());
    await prefs.setString(_cacheKey, json);
  }

  @override
  List<School> getCachedSchools() {
    // Synchronous — loaded at startup from prefs already parsed
    return _cachedSchools;
  }

  List<School> _cachedSchools = [];

  Future<void> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _cachedSchools =
          list.map((e) => School.fromJson(e as Map<String, dynamic>)).toList();
    }
  }
}
