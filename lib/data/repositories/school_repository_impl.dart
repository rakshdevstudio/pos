import 'package:supabase/supabase.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/school_repository.dart';

class SchoolRepositoryImpl implements SchoolRepository {
  final SupabaseClient _client;

  SchoolRepositoryImpl({SupabaseClient? client})
      : _client = client ??
            SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);

  @override
  Future<List<School>> fetchSchools() async {
    if (!SupabaseConfig.hasAnonKey) {
      throw StateError('SUPABASE_ANON_KEY is missing');
    }

    final rows = await _client.from('schools').select('id, name, branch_id');
    return rows.map((row) => School.fromJson(row)).toList();
  }

  @override
  Future<List<School>> getSchools() => fetchSchools();

  @override
  Future<List<SchoolClass>> fetchClasses(String schoolId) async {
    if (!SupabaseConfig.hasAnonKey) {
      throw StateError('SUPABASE_ANON_KEY is missing');
    }

    final rows = await _client
        .from('classes')
        .select('id, school_id, name, code, slug, sort_order, status')
        .eq('school_id', schoolId)
        .eq('status', 'active')
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return rows.map((row) => SchoolClass.fromJson(row)).toList();
  }

  @override
  Future<List<SchoolClass>> getClasses(String schoolId) =>
      fetchClasses(schoolId);
}
