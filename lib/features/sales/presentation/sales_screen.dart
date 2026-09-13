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
import '../domain/zone.dart';
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
  String? _selectedZoneId;
  final _searchController = TextEditingController();
  String _search = '';
  bool _creatingTicket = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureTicketExists(List<Ticket> tickets, SalesCatalog catalog) async {
    // Tables mode: tables ARE the tickets — nothing to auto-create until
    // the operator taps one.
    if (catalog.isTablesMode) return;
    if (tickets.isNotEmpty || _creatingTicket) return;
    _creatingTicket = true;
    await _createTicket(tickets, catalog);
    _creatingTicket = false;
  }

  Future<void> _createTicket(
    List<Ticket> tickets,
    SalesCatalog catalog, {
    String? tableId,
    String? zoneId,
    String? label,
  }) async {
    final paired = ref.read(pairedDeviceProvider).value;
    final user = ref.read(authStateChangesProvider).value;
    if (paired == null) return;

    final id = await ref.read(salesRepositoryProvider).createTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          label: label ?? 'Ticket ${tickets.length + 1}',
          customerCode: catalog.defaultCustomerCode ?? '',
          locationCode: catalog.defaultLocationCode ?? '',
          operatorUid: user?.uid ?? '',
          operatorName: user?.displayName ?? '',
          tableId: tableId,
          zoneId: zoneId,
        );
    if (mounted) setState(() => _selectedTicketId = id);
  }

  Future<void> _onTableTap(
    Zone zone,
    ZoneTable table,
    List<Ticket> tickets,
    SalesCatalog catalog,
  ) async {
    // Already visible locally (from the same stream the picker renders
    // from) — no need to touch the claim doc, this also covers tickets
    // created before table claiming existed and never got one.
    final existing = tickets.where((t) => t.tableId == table.id);
    if (existing.isNotEmpty) {
      setState(() => _selectedTicketId = existing.first.id);
      return;
    }

    final paired = ref.read(pairedDeviceProvider).value;
    final user = ref.read(authStateChangesProvider).value;
    if (paired == null || user == null) return;

    // Looks free locally, but another operator's tap could be racing this
    // one right now — the actual claim goes through an atomic transaction
    // rather than trusting this snapshot, so only one of them wins.
    final result = await ref.read(salesRepositoryProvider).claimOrJoinTable(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          tableId: table.id,
          zoneId: zone.id,
          tableName: table.name,
          customerCode: catalog.defaultCustomerCode ?? '',
          locationCode: catalog.defaultLocationCode ?? '',
          operatorUid: user.uid,
          operatorName: user.displayName ?? '',
        );
    if (!mounted) return;
    setState(() => _selectedTicketId = result.ticketId);
    if (!result.claimedByMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${table.name} is already being served by ${result.ownerName}'),
        ),
      );
    }
  }

  Future<void> _addItem(PosItem item, Ticket ticket, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;

    // Optimistic write off the ticket state this screen already has (from
    // the same stream it renders from) — see SalesRepository for why this
    // is both correct and instant, unlike the transactional round trip it
    // replaced.
    await ref.read(salesRepositoryProvider).addOrIncrementItem(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          currentLines: ticket.lines,
          itemCode: item.code,
          description: item.description,
          unitPrice: _priceFor(item, ticket, catalog),
        );
  }

  Future<void> _sendRound(Ticket ticket) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).sendRound(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          currentLines: ticket.lines,
          currentRound: ticket.currentRound,
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
          currentLines: ticket.lines,
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
          tableId: ticket.tableId,
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
          tableId: ticket.tableId,
        );
    if (mounted) setState(() => _selectedTicketId = null);
  }

  List<PosItem> _visibleItems(SalesCatalog catalog) {
    final allowedGroups = catalog.visibleItemGroupCodes;
    final active = catalog.items.where(
      (i) => i.active && (allowedGroups == null || allowedGroups.contains(i.groupCode)),
    );
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

  /// A table-bound ticket is exclusive to the operator who claimed it —
  /// everyone else can look (see totals/items) but not touch it.
  bool _isLockedForMe(Ticket ticket, String? myUid) {
    return ticket.tableId != null && ticket.operatorUid != myUid;
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDeviceProvider).value;
    final myUid = ref.watch(authStateChangesProvider).value?.uid;
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
          final visibleGroups = catalog.visibleGroups;
          if (_selectedGroupCode == null && visibleGroups.isNotEmpty) {
            _selectedGroupCode = visibleGroups.first.code;
          }
          if (catalog.isTablesMode && _selectedZoneId == null && catalog.zones.isNotEmpty) {
            _selectedZoneId = catalog.zones.first.id;
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
              if (catalog.isTablesMode) {
                // Don't fall back to an arbitrary open table — stay
                // unselected until the operator actually taps one.
                if (_selectedTicketId != null) {
                  final matches = tickets.where((t) => t.id == _selectedTicketId);
                  selected = matches.isNotEmpty ? matches.first : null;
                }
              } else if (tickets.isNotEmpty) {
                final matches = tickets.where((t) => t.id == _selectedTicketId);
                selected = matches.isNotEmpty ? matches.first : tickets.first;
              }

              return Column(
                children: [
                  if (catalog.isTablesMode)
                    _ZoneTableBar(
                      zones: catalog.zones,
                      tickets: tickets,
                      selectedZoneId: _selectedZoneId,
                      selectedTicketId: selected?.id,
                      onZoneSelect: (id) => setState(() => _selectedZoneId = id),
                      onTableTap: (zone, table) => _onTableTap(zone, table, tickets, catalog),
                    )
                  else
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
                        final readOnly = selected != null && _isLockedForMe(selected, myUid);
                        final browser = _buildBrowser(catalog, selected, readOnly);
                        final cart = CartPanel(
                          ticket: selected,
                          catalog: catalog,
                          readOnly: readOnly,
                          onQtyChanged: (line, qty) => _changeQty(selected!, line, qty),
                          onCustomerChanged: (code) => _changeCustomer(selected!, code, catalog),
                          onComplete: () => _completeTicket(selected!),
                          onCancel: () => _cancelTicket(selected!),
                          onSendRound: () => _sendRound(selected!),
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
                            if (selected == null)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'Select a table to start an order',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              )
                            else
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
                                        '${selected.lines.length} items · ${selected.label}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        selected.total.toStringAsFixed(2),
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

  Widget _buildBrowser(SalesCatalog catalog, Ticket? selected, bool readOnly) {
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
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final group in catalog.visibleGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CompactChip(
                      label: group.description,
                      selected: _selectedGroupCode == group.code,
                      onSelected: () => setState(() {
                        _selectedGroupCode = group.code;
                        _selectedCategoryCode = null;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          if (categoriesForGroup.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _CompactChip(
                      label: 'All',
                      selected: _selectedCategoryCode == null,
                      onSelected: () => setState(() => _selectedCategoryCode = null),
                    ),
                  ),
                  for (final category in categoriesForGroup)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _CompactChip(
                        label: category.description,
                        selected: _selectedCategoryCode == category.code,
                        onSelected: () =>
                            setState(() => _selectedCategoryCode = category.code),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                      onTap: (selected == null || readOnly)
                          ? null
                          : () => _addItem(item, selected, catalog),
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

/// Small-footprint ChoiceChip used for the group/category rows — the
/// default ChoiceChip padding/density ate too much vertical space when
/// there are many groups.
class _CompactChip extends StatelessWidget {
  const _CompactChip({required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
    );
  }
}

class _ZoneTableBar extends StatelessWidget {
  const _ZoneTableBar({
    required this.zones,
    required this.tickets,
    required this.selectedZoneId,
    required this.selectedTicketId,
    required this.onZoneSelect,
    required this.onTableTap,
  });

  final List<Zone> zones;
  final List<Ticket> tickets;
  final String? selectedZoneId;
  final String? selectedTicketId;
  final ValueChanged<String> onZoneSelect;
  final void Function(Zone zone, ZoneTable table) onTableTap;

  @override
  Widget build(BuildContext context) {
    if (zones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No zones/tables configured for this business unit yet — add them in Manager.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    final zone = zones.firstWhere((z) => z.id == selectedZoneId, orElse: () => zones.first);
    final ticketByTable = {
      for (final t in tickets)
        if (t.tableId != null) t.tableId!: t,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              for (final z in zones)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CompactChip(
                    label: z.name,
                    selected: z.id == zone.id,
                    onSelected: () => onZoneSelect(z.id),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 64,
          child: zone.tables.isEmpty
              ? const Center(
                  child: Text(
                    'No tables in this zone',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    for (final table in zone.tables)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TableTile(
                          table: table,
                          ticket: ticketByTable[table.id],
                          selected: ticketByTable[table.id]?.id == selectedTicketId,
                          onTap: () => onTableTap(zone, table),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.table,
    required this.ticket,
    required this.selected,
    required this.onTap,
  });

  final ZoneTable table;
  final Ticket? ticket;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occupied = ticket != null;
    final bg = selected
        ? AppColors.orange
        : occupied
            ? AppColors.orange.withValues(alpha: 0.15)
            : AppColors.surface;
    final fg = selected ? Colors.white : AppColors.textPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.orange : AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                table.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: fg),
              ),
              const SizedBox(height: 2),
              Text(
                occupied
                    ? '${ticket!.operatorName.isEmpty ? '?' : ticket!.operatorName} · ${ticket!.total.toStringAsFixed(0)}'
                    : 'Free',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: occupied ? fg : AppColors.textMuted),
              ),
            ],
          ),
        ),
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
