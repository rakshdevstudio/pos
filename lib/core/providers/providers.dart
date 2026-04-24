import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/database_helper.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../data/repositories/school_repository_impl.dart';

/// Singleton ApiClient — single Dio instance per app lifetime.
final apiClientProvider = Provider<ApiClient>((_) => ApiClient());

/// Singleton DatabaseHelper — one SQLite connection.
final dbProvider = Provider<DatabaseHelper>((_) => DatabaseHelper.instance);

/// Order repository — uses single ApiClient + DB instances.
final orderRepoProvider = Provider<OrderRepositoryImpl>((ref) {
  return OrderRepositoryImpl(
    ref.read(apiClientProvider),
    ref.read(dbProvider),
  );
});

/// Product repository — singleton preserves in-memory SKU index.
final productRepoProvider = Provider<ProductRepositoryImpl>((ref) {
  return ProductRepositoryImpl(
    ref.read(apiClientProvider),
    ref.read(dbProvider),
  );
});

/// School repository.
final schoolRepoProvider = Provider<SchoolRepositoryImpl>((ref) {
  return SchoolRepositoryImpl(ref.read(apiClientProvider));
});

/// Customer repository.
final customerRepoProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(
    ref.read(apiClientProvider),
    ref.read(dbProvider),
  );
});
