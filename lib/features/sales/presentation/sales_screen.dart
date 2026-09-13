// lib/features/sales/presentation/sales_screen.dart
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
import 'cart_panel.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  String? _selectedTicketId;
  String? _selectedGroupCode;
  String? _selectedCategoryCode;
  final _searchController = TextEditingController();
  String _search = '';
  bool _creatingTicket = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

    // Transactional: re-reads lines fresh from the server rather than from
    // the (possibly stale) `ticket` passed in, so rapid taps can't clobber
    // each other's writes.
    await ref.read(salesRepositoryProvider).addOrIncrementItem(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          itemCode: item.code,
          description: item.description,
          unitPrice: _priceFor(item, ticket, catalog),
        );
  }

  num _priceFor(PosItem item, Ticket ticket, SalesCatalog catalog) {
    String? levelFor(String code) {
      final matches = catalog.customers.where((c) => c.code == code);
      return matches.isNotEmpty ? matches.first.priceLevel : null;
    }

    return item.resolvePrice(
      selectedPriceLevel: levelFor(ticket.customerCode),
      defaultPriceLevel:
          catalog.defaultCustomerCode != null ? levelFor(catalog.defaultCustomerCode!) : null,
    );
  }

  Future<void> _changeQty(Ticket ticket, TicketLine line, num newQty) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;

    await ref.read(salesRepositoryProvider).setItemQty(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          itemCode: line.itemCode,
          newQty: newQty,
        );
  }

  Future<void> _changeCustomer(Ticket ticket, String customerCode, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;

    final repo = ref.read(salesRepositoryProvider);
    await repo.updateCustomer(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      ticketId: ticket.id,
      customerCode: customerCode,
    );

    // Re-price existing lines against the newly selected customer's level.
    final repriced = Ticket(
      id: ticket.id,
      status: ticket.status,
      label: ticket.label,
      customerCode: customerCode,
      locationCode: ticket.locationCode,
      lines: const [],
      operatorUid: ticket.operatorUid,
      operatorName: ticket.operatorName,
    );
    final newLines = ticket.lines.map((line) {
      final matches = catalog.items.where((i) => i.code == line.itemCode);
      if (matches.isEmpty) return line;
      return TicketLine(
        itemCode: line.itemCode,
        description: line.description,
        unitPrice: _priceFor(matches.first, repriced, catalog),
        qty: line.qty,
      );
    }).toList();

    await repo.updateLines(
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

  List<PosItem> _visibleItems(SalesCatalog catalog) {
    final active = catalog.items.where((i) => i.active);
    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      return active
          .where((i) =>
              i.description.toLowerCase().contains(q) || i.code.toLowerCase().contains(q))
          .toList();
    }
    return active
        .where((i) =>
            i.groupCode == _selectedGroupCode &&
            (_selectedCategoryCode == null || i.categoryCode == _selectedCategoryCode))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDeviceProvider).value;
    final catalogAsync = ref.watch(salesCatalogProvider);
    final ticketsAsync = ref.watch(openTicketsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(paired?.businessUnitName ?? 'AVEC Operations'),
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
          if (_selectedGroupCode == null && catalog.groups.isNotEmpty) {
            _selectedGroupCode = catalog.groups.first.code;
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final browser = _buildBrowser(catalog, selected);
                        final cart = CartPanel(
                          ticket: selected,
                          catalog: catalog,
                          onQtyChanged: (line, qty) => _changeQty(selected!, line, qty),
                          onCustomerChanged: (code) => _changeCustomer(selected!, code, catalog),
                          onComplete: () => _completeTicket(selected!),
                          onCancel: () => _cancelTicket(selected!),
                        );

                        if (constraints.maxWidth > 760) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 3, child: browser),
                              const VerticalDivider(width: 1, color: AppColors.border),
                              SizedBox(width: 380, child: cart),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Expanded(child: browser),
                            const Divider(height: 1, color: AppColors.border),
                            InkWell(
                              onTap: () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: AppColors.surface,
                                builder: (_) => SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.85,
                                  child: cart,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${selected?.lines.length ?? 0} items · ${selected?.label ?? ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      (selected?.total ?? 0).toStringAsFixed(2),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, color: AppColors.orange),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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

  Widget _buildBrowser(SalesCatalog catalog, Ticket? selected) {
    final items = _visibleItems(catalog);
    final categoriesForGroup = catalog.categories
        .where((c) => c.groupCodes.contains(_selectedGroupCode))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search items…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        if (_search.trim().isEmpty) ...[
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final group in catalog.groups)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(group.description),
                      selected: _selectedGroupCode == group.code,
                      onSelected: (_) => setState(() {
                        _selectedGroupCode = group.code;
                        _selectedCategoryCode = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (categoriesForGroup.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _selectedCategoryCode == null,
                      onSelected: (_) => setState(() => _selectedCategoryCode = null),
                    ),
                  ),
                  for (final category in categoriesForGroup)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category.description),
                        selected: _selectedCategoryCode == category.code,
                        onSelected: (_) =>
                            setState(() => _selectedCategoryCode = category.code),
                      ),
                    ),
                ],
              ),
            ),
        ],
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('No items', style: TextStyle(color: AppColors.textSecondary)),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final price =
                        selected != null ? _priceFor(item, selected, catalog) : item.basePrice;
                    return _ItemTile(
                      item: item,
                      price: price,
                      onTap: selected == null ? null : () => _addItem(item, selected, catalog),
                    );
                  },
                ),
        ),
      ],
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
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('New'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.price, required this.onTap});
  final PosItem item;
  final num price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(
                price.toStringAsFixed(2),
                style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
