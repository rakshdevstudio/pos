import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/order_repository_impl.dart';

enum SyncState { idle, syncing, done, offline }

class SyncNotifier extends StateNotifier<SyncState> {
  final OrderRepositoryImpl _orderRepo;
  final Ref _ref;
  StreamSubscription? _connectivitySub;
  Timer? _retryTimer;

  SyncNotifier(this._orderRepo, this._ref) : super(SyncState.idle) {
    _listenToConnectivity();
  }

  void _listenToConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        syncPendingOrders();
      } else {
        state = SyncState.offline;
      }
    });
  }

  Future<void> syncPendingOrders() async {
    final pending = await _orderRepo.getPendingOrders();
    if (pending.isEmpty) {
      state = SyncState.done;
      return;
    }

    state = SyncState.syncing;
    int failures = 0;

    for (final order in pending) {
      final success = await _orderRepo.syncOrder(order);
      if (!success) failures++;
    }

    state = failures == 0 ? SyncState.done : SyncState.offline;

    // Refresh provider tally after sync
    _ref.read(pendingOrdersCountProvider.notifier).refresh();

    if (failures > 0) {
      // Schedule retry in 30 seconds
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 30), syncPendingOrders);
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(OrderRepositoryImpl(ApiClient()), ref);
});

class PendingOrdersCountNotifier extends StateNotifier<int> {
  final OrderRepositoryImpl _repo;

  PendingOrdersCountNotifier(this._repo) : super(0) {
    refresh();
  }

  Future<void> refresh() async {
    state = await _repo.getPendingOrdersCount();
  }

  void setCount(int val) {
    state = val;
  }
}

final pendingOrdersCountProvider = StateNotifierProvider<PendingOrdersCountNotifier, int>((ref) {
  return PendingOrdersCountNotifier(OrderRepositoryImpl(ApiClient()));
});
