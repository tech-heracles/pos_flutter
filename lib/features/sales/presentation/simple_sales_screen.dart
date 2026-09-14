// lib/features/sales/presentation/simple_sales_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../operator/application/operator_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/ticket.dart';
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

  @override
  void onTicketClosed(Ticket closed) {
    setState(() => _selectedTicketId = null);
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
          if (selectedGroupCode == null && catalog.visibleGroups.isNotEmpty) {
            selectedGroupCode = catalog.visibleGroups.first.code;
          }

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
