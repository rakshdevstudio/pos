import '../models/models.dart';

abstract class SchoolRepository {
  Future<List<School>> getSchools();
  Future<void> cacheSchools(List<School> schools);
  List<School> getCachedSchools();
}
