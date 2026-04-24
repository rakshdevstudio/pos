import '../models/models.dart';

abstract class SchoolRepository {
  Future<List<School>> fetchSchools();
  Future<List<School>> getSchools();
}
