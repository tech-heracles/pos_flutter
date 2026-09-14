// lib/features/connectivity/presentation/offline_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../application/connectivity_providers.dart';

/// Thin heads-up shown whenever this device has fallen back to its local
/// Firestore cache. Orders keep working — every write in this app queues
/// locally and syncs once reconnected — so this is informational, except
/// on the table-sales screen, which also uses [isOnlineProvider] directly
/// to gate Create Invoice (the one action that truly can't be queued).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    if (isOnline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.orange.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 15, color: AppColors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — working from this device, will sync automatically',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.orange),
            ),
          ),
        ],
      ),
    );
  }
}
