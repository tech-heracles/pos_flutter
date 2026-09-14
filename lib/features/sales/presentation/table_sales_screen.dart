// lib/features/sales/presentation/table_sales_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/pos_item.dart';
import '../domain/ticket.dart';
import 'sales_workspace_mixin.dart';

/// One table's session — reached only by tapping a table on [TablesScreen].
/// A table can be open here with no order yet (just seated); tapping an
/// item is what starts the order. Closing it out (Create Invoice or
/// Cancel order) or leaving an empty table sends the operator straight
/// back to the table picker — a table only frees up once every order on
/// it has been invoiced.
class TableSalesScreen extends ConsumerStatefulWidget {
  const TableSalesScreen({super.key, required this.tableId});
  final String tableId;

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

  Future<void> _leaveTable() async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).leaveEmptyTable(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
        );
    if (mounted) _returnToTables();
  }

  Future<void> _addFirstItem(PosItem item, SalesCatalog catalog, String zoneId) async {
    final user = ref.read(authStateChangesProvider).value;
    final claim = ref.read(tableClaimProvider(widget.tableId)).value;
    if (user == null || claim == null) return;
    await addItem(
      item,
      null,
      catalog,
      tableId: widget.tableId,
      zoneId: zoneId,
      label: _tableName(catalog),
      customerCode: claim.customerCode,
      locationCode: claim.locationCode,
      operatorUid: user.uid,
      operatorName: user.displayName ?? '',
    );
  }

  String _tableName(SalesCatalog catalog) {
    for (final zone in catalog.zones) {
      for (final table in zone.tables) {
        if (table.id == widget.tableId) return table.name;
      }
    }
    return 'Table';
  }

  String? _zoneIdFor(SalesCatalog catalog) {
    for (final zone in catalog.zones) {
      if (zone.tables.any((t) => t.id == widget.tableId)) return zone.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(salesCatalogProvider);
    final ticketsAsync = ref.watch(openTicketsProvider);
    final claimAsync = ref.watch(tableClaimProvider(widget.tableId));
    final myUid = ref.watch(authStateChangesProvider).value?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(catalogAsync.value != null ? _tableName(catalogAsync.value!) : 'Table'),
      ),
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
          final zoneId = _zoneIdFor(catalog);

          return claimAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
            error: (err, _) => Center(
              child: Text('Failed to load table: $err',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (claim) {
              if (claim == null) {
                // Freed from under us (invoiced/left elsewhere, or our own
                // action already navigated) — nothing to show here.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _returnToTables();
                });
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                );
              }

              return ticketsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator(color: AppColors.orange)),
                error: (err, _) => Center(
                  child: Text('Failed to load order: $err',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
                data: (tickets) {
                  final matches = tickets.where((t) => t.tableId == widget.tableId);
                  final ticket = matches.isNotEmpty ? matches.first : null;
                  final readOnly = claim.operatorUid != myUid;

                  return buildWorkspace(
                    selected: ticket,
                    catalog: catalog,
                    readOnly: readOnly,
                    tableLabel: _tableName(catalog),
                    lockedByName: claim.operatorName,
                    onLeaveTable: _leaveTable,
                    onAddFirstItem: zoneId == null
                        ? null
                        : (item) => _addFirstItem(item, catalog, zoneId),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
