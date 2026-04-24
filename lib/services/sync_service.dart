import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/providers/providers.dart';
import '../data/repositories/order_repository_impl.dart';

enum SyncState { idle, syncing, done, offline }

class SyncNotifier extends StateNotifier<SyncState> with WidgetsBindingObserver {
  final OrderRepositoryImpl _orderRepo;
  final Ref _ref;

  StreamSubscription? _connectivitySub;
  Timer? _retryTimer;

  /// Future-based mutex — if a sync is in progress, new callers
  /// await the same Future instead of spawning a duplicate.
  Future<void>? _syncFuture;

  SyncNotifier(this._orderRepo, this._ref) : super(SyncState.idle) {
    WidgetsBinding.instance.addObserver(this);
    _listenToConnectivity();
    // Kick off initial sync on startup
    syncPendingOrders();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncPendingOrders();
    }
  }

  // ── Connectivity ───────────────────────────────────────────────────────────

  void _listenToConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        syncPendingOrders();
      } else {
        if (state != SyncState.syncing) {
          state = SyncState.offline;
        }
      }
    });
  }

  // ── Public sync entry point (mutex-locked) ─────────────────────────────────

  Future<void> syncPendingOrders() {
    _syncFuture ??= _runSync().whenComplete(() => _syncFuture = null);
    return _syncFuture!;
  }

  // ── Core sync loop ─────────────────────────────────────────────────────────

  Future<void> _runSync() async {
    final pending = await _orderRepo.getPendingOrders();
    if (pending.isEmpty) {
      state = SyncState.done;
      await _refreshCount();
      return;
    }

    state = SyncState.syncing;
    bool hadFailure = false;
    int failRetryCount = 0; // track retry_count of failed order for backoff

    for (final order in pending) {
      final success = await _orderRepo.syncOrder(order);
      if (!success) {
        hadFailure = true;
        // Use the order's retry_count from DB for backoff calculation
        // (we approximate here; the DB is the source of truth)
        failRetryCount++;
        // Stop on first failure — don't batch-fail remaining orders
        break;
      }
    }

    state = hadFailure ? SyncState.offline : SyncState.done;
    await _refreshCount();

    if (hadFailure) {
      _scheduleRetry(failRetryCount);
    }
  }

  // ── Exponential backoff ────────────────────────────────────────────────────

  /// delay = min(2^retryCount × 5s, 5 minutes)
  void _scheduleRetry(int retryCount) {
    _retryTimer?.cancel();
    final seconds = min(pow(2, retryCount) * 5, 300).toInt();
    _retryTimer = Timer(Duration(seconds: seconds), syncPendingOrders);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _refreshCount() async {
    final count = await _orderRepo.getPendingOrdersCount();
    _ref.read(pendingOrdersCountProvider.notifier).setCount(count);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref.read(orderRepoProvider), ref);
});

class PendingOrdersCountNotifier extends StateNotifier<int> {
  final OrderRepositoryImpl _repo;

  PendingOrdersCountNotifier(this._repo) : super(0) {
    refresh();
  }

  Future<void> refresh() async {
    state = await _repo.getPendingOrdersCount();
  }

  void setCount(int val) => state = val;
}

final pendingOrdersCountProvider =
    StateNotifierProvider<PendingOrdersCountNotifier, int>((ref) {
  return PendingOrdersCountNotifier(ref.read(orderRepoProvider));
});
