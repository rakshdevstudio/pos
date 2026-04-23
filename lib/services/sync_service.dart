import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/api_client.dart';
import '../data/repositories/order_repository_impl.dart';

enum SyncState { idle, syncing, done, offline }

class SyncNotifier extends StateNotifier<SyncState> {
  final OrderRepositoryImpl _orderRepo;
  StreamSubscription? _connectivitySub;
  Timer? _retryTimer;

  SyncNotifier(this._orderRepo) : super(SyncState.idle) {
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
  return SyncNotifier(OrderRepositoryImpl(ApiClient()));
});
