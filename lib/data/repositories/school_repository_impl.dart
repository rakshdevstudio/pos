import 'package:dio/dio.dart';
import '../../core/config/supabase_config.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/school_repository.dart';

class SchoolRepositoryImpl implements SchoolRepository {
  static const String _restUrl = '${SupabaseConfig.url}/rest/v1';

  final Dio _dio;

  SchoolRepositoryImpl({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  @override
  Future<List<School>> fetchSchools() async {
    if (!SupabaseConfig.hasAnonKey) {
      throw StateError('SUPABASE_ANON_KEY is missing');
    }

    final response = await _dio.get(
      '$_restUrl/schools',
      queryParameters: {
        'select': 'id,name,branch_id',
        'order': 'name.asc',
      },
      options: Options(headers: _restHeaders),
    );
    final rows = (response.data as List<dynamic>).cast<Map<String, dynamic>>();
    return rows.map((row) => School.fromJson(row)).toList();
  }

  @override
  Future<List<School>> getSchools() => fetchSchools();

  @override
  Future<List<SchoolClass>> fetchClasses(String schoolId) async {
    if (!SupabaseConfig.hasAnonKey) {
      throw StateError('SUPABASE_ANON_KEY is missing');
    }

    final scopedSchoolId = schoolId.trim();
    if (scopedSchoolId.isEmpty) {
      return const [];
    }

    final response = await _dio.get(
      '$_restUrl/classes',
      queryParameters: {
        'select': 'id,school_id,name,code,slug,sort_order,status',
        'school_id': 'eq.$scopedSchoolId',
        'status': 'eq.active',
      },
      options: Options(headers: _restHeaders),
    );

    final rows = (response.data as List<dynamic>).cast<Map<String, dynamic>>();
    final classes = rows.map((row) => SchoolClass.fromJson(row)).toList()
      ..sort((a, b) {
        final orderCompare = (a.sortOrder ?? 1 << 30).compareTo(
          b.sortOrder ?? 1 << 30,
        );
        if (orderCompare != 0) {
          return orderCompare;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return classes;
  }

  @override
  Future<List<SchoolClass>> getClasses(String schoolId) =>
      fetchClasses(schoolId);

  Map<String, String> get _restHeaders => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };
}
