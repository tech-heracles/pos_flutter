// lib/features/sales/presentation/table_sales_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/pos_item.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import 'sales_workspace_mixin.dart';

/// One table's order — reached only by tapping a table on [TablesScreen].
/// Tapping into a table is pure navigation (no write): a table has no
/// "open" state of its own, it's simply occupied for as long as it has an
/// active order. Tapping an item is what actually starts one. Closing it
/// out (Create Invoice or Cancel order) sends the operator straight back
/// to the table picker — a table only frees up once every order on it has
/// been invoiced.
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

  Future<void> _addItem(PosItem item, Ticket? order, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    final user = ref.read(authStateChangesProvider).value;
    if (paired == null) return;
    try {
      await ref.read(salesRepositoryProvider).addOrIncrementOrderItem(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
          currentLines: order?.lines ?? const [],
          itemCode: item.code,
          description: item.description,
          unitPrice: order != null
              ? priceFor(item, order, catalog)
              : priceForCode(item, catalog.defaultCustomerCode, catalog),
          zoneId: _zoneIdFor(catalog),
          label: _tableName(catalog),
          customerCode: catalog.defaultCustomerCode ?? '',
          locationCode: catalog.defaultLocationCode ?? '',
          operatorUid: user?.uid ?? '',
          operatorName: user?.displayName ?? '',
        );
    } on FirebaseException catch (e) {
      // Extremely rare: lost a first-tap race and our fallback merge
      // attempt landed after the winner's order was already committed and
      // rules rejected it as a non-owner write. The stream will correct
      // the UI to show it locked to whoever actually won — nothing else
      // to do here.
      if (e.code != 'permission-denied') rethrow;
    }
  }

  Future<void> _changeQty(Ticket order, TicketLine line, num newQty) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).setOrderItemQty(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
          currentLines: order.lines,
          itemCode: line.itemCode,
          newQty: newQty,
        );
  }

  Future<void> _sendRound(Ticket order) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).sendOrderRound(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
          currentLines: order.lines,
          currentRound: order.currentRound,
        );
  }

  Future<void> _changeCustomer(Ticket order, String customerCode, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    final repo = ref.read(salesRepositoryProvider);
    await repo.updateOrderCustomer(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      tableId: widget.tableId,
      customerCode: customerCode,
    );

    final newLines = order.lines.map((line) {
      final matches = catalog.items.where((i) => i.code == line.itemCode);
      if (matches.isEmpty) return line;
      return TicketLine(
        itemCode: line.itemCode,
        description: line.description,
        unitPrice: priceForCode(matches.first, customerCode, catalog),
        qty: line.qty,
        roundNumber: line.roundNumber,
      );
    }).toList();

    await repo.updateOrderLines(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      tableId: widget.tableId,
      lines: newLines,
    );
  }

  Future<void> _createInvoice() async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).createInvoice(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
        );
    if (mounted) _returnToTables();
  }

  Future<void> _cancelOrder(Ticket order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text('"${order.label}" and its items will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).cancelOrder(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: widget.tableId,
        );
    if (mounted) _returnToTables();
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(salesCatalogProvider);
    final ordersAsync = ref.watch(openOrdersProvider);
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
          return ordersAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.orange)),
            error: (err, _) => Center(
              child: Text('Failed to load order: $err',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (orders) {
              final matches = orders.where((o) => o.tableId == widget.tableId);
              final order = matches.isNotEmpty ? matches.first : null;
              final readOnly = order != null && order.operatorUid != myUid;

              return buildWorkspace(
                selected: order,
                catalog: catalog,
                readOnly: readOnly,
                tableLabel: _tableName(catalog),
                lockedByName: order?.operatorName,
                onItemTap: (item) => _addItem(item, order, catalog),
                onQtyChanged: (line, qty) => _changeQty(order!, line, qty),
                onCustomerChanged: (code) => _changeCustomer(order!, code, catalog),
                onComplete: _createInvoice,
                onCancel: () => _cancelOrder(order!),
                onSendRound: () => _sendRound(order!),
              );
            },
          );
        },
      ),
    );
  }
}
