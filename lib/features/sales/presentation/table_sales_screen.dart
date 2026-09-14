// lib/features/sales/presentation/table_sales_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../application/sales_providers.dart';
import '../domain/ticket.dart';
import 'sales_workspace_mixin.dart';

/// One table's order — reached only by tapping a table on [TablesScreen].
/// Closing the ticket out (Complete Sale or Cancel) sends the operator
/// straight back there, and there's no ticket-tabs concept here since a
/// table only ever has the one open ticket claiming it.
class TableSalesScreen extends ConsumerStatefulWidget {
  const TableSalesScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  ConsumerState<TableSalesScreen> createState() => _TableSalesScreenState();
}

class _TableSalesScreenState extends ConsumerState<TableSalesScreen>
    with SalesWorkspaceMixin<TableSalesScreen> {
  void _returnToTables() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  void onTicketClosed(Ticket closed) => _returnToTables();

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(salesCatalogProvider);
    final ticketsAsync = ref.watch(openTicketsProvider);
    final currentTicketMatches =
        ticketsAsync.value?.where((t) => t.id == widget.ticketId) ?? const Iterable.empty();
    final currentLabel = currentTicketMatches.isNotEmpty ? currentTicketMatches.first.label : null;

    return Scaffold(
      appBar: AppBar(title: Text(currentLabel ?? 'Table')),
      body: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
        error: (err, _) => Center(
          child: Text('Failed to load catalog: $err',
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        data: (catalog) {
          if (selectedGroupCode == null && catalog.visibleGroups.isNotEmpty) {
            selectedGroupCode = catalog.visibleGroups.first.code;
          }

          return ticketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
            error: (err, _) => Center(
              child: Text('Failed to load ticket: $err',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (tickets) {
              final matches = tickets.where((t) => t.id == widget.ticketId);
              if (matches.isEmpty) {
                // Completed/cancelled from under us (or a stale deep link) —
                // nothing to show here, so bounce back to the table picker.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _returnToTables();
                });
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                );
              }
              final ticket = matches.first;
              return buildWorkspace(selected: ticket, catalog: catalog);
            },
          );
        },
      ),
    );
  }
}
