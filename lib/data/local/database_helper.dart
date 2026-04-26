import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for all local SQLite persistence.
///
/// Tables:
///   orders            – offline-first order queue
///   products_cache    – per-school product cache with TTL timestamp
///   customers_cache   – phone-keyed customer lookup cache
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const int _version = 1;
  static const String _dbName = 'illume_pos.db';

  // Migration flag key (SharedPreferences)
  static const String _migrationDoneKey = 'db_migration_v1_done';

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE orders (
        offline_id      TEXT    PRIMARY KEY,
        school_id       TEXT    NOT NULL,
        customer_json   TEXT    NOT NULL,
        items_json      TEXT    NOT NULL,
        subtotal        REAL    NOT NULL,
        discount_amount REAL    NOT NULL DEFAULT 0,
        total           REAL    NOT NULL,
        payment_method  TEXT    NOT NULL,
        created_at      TEXT    NOT NULL,
        updated_at      TEXT    NOT NULL,
        sync_status     TEXT    NOT NULL DEFAULT 'pending',
        remote_id       INTEGER,
        retry_count     INTEGER NOT NULL DEFAULT 0,
        last_error      TEXT,
        device_id       TEXT,
        schema_version  INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE products_cache (
        school_id     INTEGER PRIMARY KEY,
        products_json TEXT    NOT NULL,
        cached_at     TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers_cache (
        phone         TEXT    PRIMARY KEY,
        customer_json TEXT    NOT NULL,
        cached_at     TEXT    NOT NULL
      )
    ''');

    // Performance indexes
    await db.execute(
      'CREATE INDEX idx_orders_status ON orders(sync_status)',
    );
    await db.execute(
      'CREATE INDEX idx_orders_created ON orders(created_at)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here, versioned by oldVersion
  }

  // ── Order CRUD ────────────────────────────────────────────────────────────

  Future<void> insertOrder(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'orders',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore, // idempotent
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOrders() async {
    final db = await database;
    return db.query(
      'orders',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC', // oldest first
    );
  }

  Future<int> getPendingOrdersCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM orders WHERE sync_status = 'pending'",
    );
    return Sqf.firstIntValue(result) ?? 0;
  }

  Future<Map<String, dynamic>?> getOrder(String offlineId) async {
    final db = await database;
    final rows = await db.query(
      'orders',
      where: 'offline_id = ?',
      whereArgs: [offlineId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteOrder(String offlineId) async {
    final db = await database;
    await db.delete(
      'orders',
      where: 'offline_id = ?',
      whereArgs: [offlineId],
    );
  }

  Future<void> markSynced(String offlineId, int? remoteId) async {
    final db = await database;
    await db.update(
      'orders',
      {
        'sync_status': 'synced',
        if (remoteId != null) 'remote_id': remoteId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'offline_id = ?',
      whereArgs: [offlineId],
    );
  }

  Future<void> markFailed(String offlineId, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE orders
      SET sync_status   = 'failed',
          retry_count   = retry_count + 1,
          last_error    = ?,
          updated_at    = ?
      WHERE offline_id  = ?
    ''', [error, DateTime.now().toIso8601String(), offlineId]);
  }

  /// Reset failed orders back to pending so the sync engine retries them.
  Future<void> requeueFailedOrders() async {
    final db = await database;
    await db.update(
      'orders',
      {
        'sync_status': 'pending',
        'updated_at': DateTime.now().toIso8601String()
      },
      where: "sync_status = 'failed' AND retry_count < 5",
    );
  }

  // ── Products cache ────────────────────────────────────────────────────────

  Future<void> cacheProducts(int schoolId, String json) async {
    final db = await database;
    await db.insert(
      'products_cache',
      {
        'school_id': schoolId,
        'products_json': json,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getProductsCache(int schoolId) async {
    final db = await database;
    final rows = await db.query(
      'products_cache',
      where: 'school_id = ?',
      whereArgs: [schoolId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ── Customers cache ───────────────────────────────────────────────────────

  Future<void> cacheCustomer(String phone, Map<String, dynamic> json) async {
    final db = await database;
    await db.insert(
      'customers_cache',
      {
        'phone': phone,
        'customer_json': jsonEncode(json),
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> searchCustomersCache(String phone) async {
    final db = await database;
    final rows = await db.query(
      'customers_cache',
      where: 'phone LIKE ?',
      whereArgs: ['$phone%'],
      limit: 5,
    );
    return rows
        .map((r) =>
            jsonDecode(r['customer_json'] as String) as Map<String, dynamic>)
        .toList();
  }

  // ── Migration: SharedPreferences → SQLite ─────────────────────────────────

  /// Migrates any orders sitting in the old SharedPreferences queue.
  /// Runs at most once (guarded by a pref flag), wrapped in a transaction.
  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationDoneKey) == true) return;

    const oldKey = 'pending_orders';
    final raw = prefs.getString(oldKey);
    if (raw == null) {
      await prefs.setBool(_migrationDoneKey, true);
      return;
    }

    List<dynamic> oldOrders = [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) oldOrders = decoded;
    } catch (_) {
      // Corrupt data — skip safely
    }

    if (oldOrders.isEmpty) {
      await prefs.setBool(_migrationDoneKey, true);
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final entry in oldOrders) {
        try {
          // Old format: { version: 1, payload: { ... } }
          final payload = (entry is Map && entry['payload'] != null)
              ? entry['payload'] as Map<String, dynamic>
              : entry as Map<String, dynamic>;

          await txn.insert(
            'orders',
            {
              'offline_id': payload['offline_id'] ?? '',
              'school_id': payload['school_id'] ?? 0,
              'customer_json':
                  jsonEncode(payload['customer'] ?? {'is_walk_in': true}),
              'items_json': jsonEncode(payload['items'] ?? []),
              'subtotal': (payload['subtotal'] ?? 0).toDouble(),
              'discount_amount': (payload['discount_amount'] ?? 0).toDouble(),
              'total': (payload['total'] ?? 0).toDouble(),
              'payment_method': payload['payment_method'] ?? 'cash',
              'created_at': payload['created_at'] ?? now,
              'updated_at': now,
              'sync_status': 'pending',
              'retry_count': 0,
              'schema_version': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } catch (_) {
          // Skip malformed entries — don't break the transaction
        }
      }
    });

    // Mark migration complete and clean up old key
    await prefs.setBool(_migrationDoneKey, true);
    await prefs.remove(oldKey);
  }
}

/// Alias to avoid importing sqflite directly in non-data files.
class Sqf {
  static int? firstIntValue(List<Map<String, dynamic>> result) {
    if (result.isEmpty) return null;
    final val = result.first.values.first;
    if (val is int) return val;
    return null;
  }
}
