import '../models/models.dart';

abstract class SchoolRepository {
  Future<List<School>> fetchSchools();
  Future<List<School>> getSchools();
  Future<List<SchoolClass>> fetchClasses(String schoolId);
  Future<List<SchoolClass>> getClasses(String schoolId);
}
