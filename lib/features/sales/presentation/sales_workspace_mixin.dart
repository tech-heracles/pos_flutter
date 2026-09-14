// lib/features/sales/presentation/sales_workspace_mixin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/pos_item.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import 'cart_panel.dart';

/// Item add/qty/customer/complete/cancel actions and the responsive
/// browser+cart layout, shared between [SimpleSalesScreen] (many
/// free-form tickets, tabs on top) and [TableSalesScreen] (exactly one
/// table-bound ticket, no tabs) — the only real difference between the
/// two screens is what sits above this workspace and what "done" means.
mixin SalesWorkspaceMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final searchController = TextEditingController();
  String search = '';
  String? selectedGroupCode;
  String? selectedCategoryCode;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  bool isLockedForMe(Ticket ticket, String? myUid) {
    return ticket.tableId != null && ticket.operatorUid != myUid;
  }

  num priceFor(PosItem item, Ticket ticket, SalesCatalog catalog) {
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

  List<PosItem> visibleItems(SalesCatalog catalog) {
    final allowedGroups = catalog.visibleItemGroupCodes;
    final active = catalog.items.where(
      (i) => i.active && (allowedGroups == null || allowedGroups.contains(i.groupCode)),
    );
    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      return active
          .where((i) =>
              i.description.toLowerCase().contains(q) || i.code.toLowerCase().contains(q))
          .toList();
    }
    return active
        .where((i) =>
            i.groupCode == selectedGroupCode &&
            (selectedCategoryCode == null || i.categoryCode == selectedCategoryCode))
        .toList();
  }

  Future<void> addItem(PosItem item, Ticket ticket, SalesCatalog catalog) async {
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

  Future<void> changeQty(Ticket ticket, TicketLine line, num newQty) async {
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

  Future<void> sendRound(Ticket ticket) async {
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

  Future<void> changeCustomer(Ticket ticket, String customerCode, SalesCatalog catalog) async {
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
      tableId: ticket.tableId,
      zoneId: ticket.zoneId,
      currentRound: ticket.currentRound,
    );
    final newLines = ticket.lines.map((line) {
      final matches = catalog.items.where((i) => i.code == line.itemCode);
      if (matches.isEmpty) return line;
      return TicketLine(
        itemCode: line.itemCode,
        description: line.description,
        unitPrice: priceFor(matches.first, repriced, catalog),
        qty: line.qty,
        roundNumber: line.roundNumber,
      );
    }).toList();

    await repo.updateLines(
      companyId: paired.companyId,
      businessUnitId: paired.businessUnitId,
      ticketId: ticket.id,
      lines: newLines,
    );
  }

  Future<void> completeTicket(Ticket ticket, {required VoidCallback onDone}) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).completeTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          tableId: ticket.tableId,
        );
    if (mounted) onDone();
  }

  Future<void> cancelTicket(Ticket ticket, {required VoidCallback onDone}) async {
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
    if (mounted) onDone();
  }

  /// The item browser + cart, laid out side-by-side on wide screens or as
  /// a browser with a tap-to-open cart sheet on phone. [onEmptySelection]
  /// renders in place of the browser/cart when [selected] is null (e.g.
  /// "pick a table" for the table screen).
  Widget buildWorkspace({
    required Ticket? selected,
    required SalesCatalog catalog,
    Widget? onEmptySelection,
  }) {
    final myUid = ref.watch(authStateChangesProvider).value?.uid;
    final readOnly = selected != null && isLockedForMe(selected, myUid);

    if (selected == null && onEmptySelection != null) {
      return onEmptySelection;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final browser = _buildBrowser(catalog, selected, readOnly);

        Widget buildCart({required VoidCallback? closeSheet}) {
          return CartPanel(
            ticket: selected,
            catalog: catalog,
            readOnly: readOnly,
            onQtyChanged: (line, qty) => changeQty(selected!, line, qty),
            onCustomerChanged: (code) => changeCustomer(selected!, code, catalog),
            onComplete: () {
              closeSheet?.call();
              completeTicket(selected!, onDone: () => onTicketClosed(selected));
            },
            onCancel: () {
              closeSheet?.call();
              cancelTicket(selected!, onDone: () => onTicketClosed(selected));
            },
            onSendRound: () => sendRound(selected!),
          );
        }

        if (constraints.maxWidth > 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: browser),
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(width: 380, child: buildCart(closeSheet: null)),
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
                  builder: (sheetContext) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.85,
                    // Closing the sheet is synchronous and happens before the
                    // async complete/cancel write even starts, so it can
                    // never linger showing a now-stale ticket after the
                    // operator has already confirmed — see the mixin doc.
                    child: buildCart(closeSheet: () => Navigator.of(sheetContext).pop()),
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
    );
  }

  /// Called once a ticket this workspace was showing gets completed or
  /// cancelled. Override to navigate away (table screen) or just clear the
  /// selection (simple screen, which has other tickets to fall back to).
  void onTicketClosed(Ticket closed);

  Widget _buildBrowser(SalesCatalog catalog, Ticket? selected, bool readOnly) {
    final items = visibleItems(catalog);
    final categoriesForGroup = catalog.categories
        .where((c) => c.groupCodes.contains(selectedGroupCode))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search items…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        if (search.trim().isEmpty) ...[
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final group in catalog.visibleGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CompactChip(
                      label: group.description,
                      selected: selectedGroupCode == group.code,
                      onSelected: () => setState(() {
                        selectedGroupCode = group.code;
                        selectedCategoryCode = null;
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
                    child: CompactChip(
                      label: 'All',
                      selected: selectedCategoryCode == null,
                      onSelected: () => setState(() => selectedCategoryCode = null),
                    ),
                  ),
                  for (final category in categoriesForGroup)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CompactChip(
                        label: category.description,
                        selected: selectedCategoryCode == category.code,
                        onSelected: () => setState(() => selectedCategoryCode = category.code),
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
                        selected != null ? priceFor(item, selected, catalog) : item.basePrice;
                    return ItemTile(
                      item: item,
                      price: price,
                      onTap: (selected == null || readOnly)
                          ? null
                          : () => addItem(item, selected, catalog),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Small-footprint ChoiceChip used for the group/category/zone rows — the
/// default ChoiceChip padding/density ate too much vertical space.
class CompactChip extends StatelessWidget {
  const CompactChip({super.key, required this.label, required this.selected, required this.onSelected});
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

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.price, required this.onTap});
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
