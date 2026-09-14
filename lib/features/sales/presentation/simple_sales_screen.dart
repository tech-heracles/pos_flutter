// lib/features/sales/presentation/simple_sales_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../operator/application/operator_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/pos_item.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import 'sales_workspace_mixin.dart';

/// Free-form multi-ticket flow (retail/simple mode) — several tickets can
/// be open at once, switched via tabs. BAR/RESTAURANT mode never reaches
/// this screen; see TablesScreen/TableSalesScreen for that flow.
class SimpleSalesScreen extends ConsumerStatefulWidget {
  const SimpleSalesScreen({super.key});

  @override
  ConsumerState<SimpleSalesScreen> createState() => _SimpleSalesScreenState();
}

class _SimpleSalesScreenState extends ConsumerState<SimpleSalesScreen>
    with SalesWorkspaceMixin<SimpleSalesScreen> {
  String? _selectedTicketId;
  bool _creatingTicket = false;

  Future<void> _ensureTicketExists(List<Ticket> tickets, SalesCatalog catalog) async {
    if (tickets.isNotEmpty || _creatingTicket) return;
    _creatingTicket = true;
    await _createTicket(tickets, catalog);
    _creatingTicket = false;
  }

  Future<void> _createTicket(List<Ticket> tickets, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    final user = ref.read(authStateChangesProvider).value;
    if (paired == null) return;

    final id = await ref.read(salesRepositoryProvider).createTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          label: 'Ticket ${tickets.length + 1}',
          customerCode: catalog.defaultCustomerCode ?? '',
          locationCode: catalog.defaultLocationCode ?? '',
          operatorUid: user?.uid ?? '',
          operatorName: user?.displayName ?? '',
        );
    if (mounted) setState(() => _selectedTicketId = id);
  }

  Future<void> _addItem(PosItem item, Ticket ticket, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).addOrIncrementItem(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          currentLines: ticket.lines,
          itemCode: item.code,
          description: item.description,
          unitPrice: priceFor(item, ticket, catalog),
        );
  }

  Future<void> _changeQty(Ticket ticket, TicketLine line, num newQty) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).setItemQty(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          currentLines: ticket.lines,
          itemCode: line.itemCode,
          newQty: newQty,
        );
  }

  Future<void> _changeCustomer(Ticket ticket, String customerCode, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    final repo = ref.read(salesRepositoryProvider);
    await repo.updateTicketCustomer(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      ticketId: ticket.id,
      customerCode: customerCode,
    );

    final newLines = ticket.lines.map((line) {
      final matches = catalog.items.where((i) => i.code == line.itemCode);
      if (matches.isEmpty) return line;
      return TicketLine(
        itemCode: line.itemCode,
        description: line.description,
        unitPrice: priceForCode(matches.first, customerCode, catalog),
        qty: line.qty,
      );
    }).toList();

    await repo.updateTicketLines(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      ticketId: ticket.id,
      lines: newLines,
    );
  }

  Future<void> _completeTicket(Ticket ticket) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).completeTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
        );
    if (mounted) setState(() => _selectedTicketId = null);
  }

  Future<void> _cancelTicket(Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this ticket?'),
        content: Text('"${ticket.label}" and its items will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel ticket'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).cancelTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
        );
    if (mounted) setState(() => _selectedTicketId = null);
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(salesCatalogProvider);
    final ticketsAsync = ref.watch(openTicketsProvider);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(operatorRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
        error: (err, _) => Center(
          child: Text('Failed to load catalog: $err',
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        data: (catalog) {
          return ticketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
            error: (err, _) => Center(
              child: Text('Failed to load tickets: $err',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (tickets) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensureTicketExists(tickets, catalog);
              });

              Ticket? selected;
              if (tickets.isNotEmpty) {
                final matches = tickets.where((t) => t.id == _selectedTicketId);
                selected = matches.isNotEmpty ? matches.first : tickets.first;
              }

              return Column(
                children: [
                  _TicketTabsBar(
                    tickets: tickets,
                    selectedId: selected?.id,
                    onSelect: (id) => setState(() => _selectedTicketId = id),
                    onAdd: () => _createTicket(tickets, catalog),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: buildWorkspace(
                      selected: selected,
                      catalog: catalog,
                      readOnly: false,
                      onItemTap: (item) => _addItem(item, selected!, catalog),
                      onQtyChanged: (line, qty) => _changeQty(selected!, line, qty),
                      onCustomerChanged: (code) => _changeCustomer(selected!, code, catalog),
                      onComplete: () => _completeTicket(selected!),
                      onCancel: () => _cancelTicket(selected!),
                      onSendRound: () {}, // simple mode has no round concept
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TicketTabsBar extends StatelessWidget {
  const _TicketTabsBar({
    required this.tickets,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Ticket> tickets;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final ticket in tickets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${ticket.label} · ${ticket.total.toStringAsFixed(0)}'),
                selected: ticket.id == selectedId,
                onSelected: (_) => onSelect(ticket.id),
              ),
            ),
          ActionChip(
            backgroundColor: AppColors.orange,
            avatar: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              'New',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
