// lib/features/sales/presentation/home_gate_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../application/sales_providers.dart';
import 'simple_sales_screen.dart';
import 'tables_screen.dart';

/// Routes to the right home screen once the catalog (and with it, the
/// business unit's sales mode) has loaded.
class HomeGateScreen extends ConsumerWidget {
  const HomeGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(salesCatalogProvider);
    return catalogAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
      ),
      error: (err, _) => Scaffold(
        body: Center(
          child: Text('Failed to load: $err',
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      data: (catalog) =>
          catalog.isTablesMode ? const TablesScreen() : const SimpleSalesScreen(),
    );
  }
}
