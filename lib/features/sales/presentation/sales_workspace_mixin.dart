// lib/features/sales/presentation/sales_workspace_mixin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
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
  String? selectedLetter;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  num _priceForCode(PosItem item, String? customerCode, SalesCatalog catalog) {
    String? levelFor(String code) {
      final matches = catalog.customers.where((c) => c.code == code);
      return matches.isNotEmpty ? matches.first.priceLevel : null;
    }

    return item.resolvePrice(
      selectedPriceLevel: customerCode != null ? levelFor(customerCode) : null,
      defaultPriceLevel:
          catalog.defaultCustomerCode != null ? levelFor(catalog.defaultCustomerCode!) : null,
    );
  }

  num priceFor(PosItem item, Ticket ticket, SalesCatalog catalog) =>
      _priceForCode(item, ticket.customerCode, catalog);

  List<PosItem> _activeVisibleItems(SalesCatalog catalog) {
    final allowedGroups = catalog.visibleItemGroupCodes;
    return catalog.items
        .where((i) => i.active && (allowedGroups == null || allowedGroups.contains(i.groupCode)))
        .toList();
  }

  /// First letters actually present in the catalog, for the A-Z quick
  /// filter — no point offering a letter with nothing behind it.
  List<String> existingLetters(SalesCatalog catalog) {
    final letters = _activeVisibleItems(catalog)
        .where((i) => i.description.isNotEmpty)
        .map((i) => i.description[0].toUpperCase())
        .toSet()
        .toList();
    letters.sort();
    return letters;
  }

  List<PosItem> visibleItems(SalesCatalog catalog) {
    final active = _activeVisibleItems(catalog);
    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      return active
          .where((i) =>
              i.description.toLowerCase().contains(q) || i.code.toLowerCase().contains(q))
          .toList();
    }
    if (selectedLetter != null) {
      return active
          .where((i) => i.description.toUpperCase().startsWith(selectedLetter!))
          .toList();
    }
    return active
        .where((i) =>
            i.groupCode == selectedGroupCode &&
            (selectedCategoryCode == null || i.categoryCode == selectedCategoryCode))
        .toList();
  }

  /// [ticket] null means no order exists yet for this table — the first
  /// item tapped creates it lazily (see SalesRepository.addOrIncrementItem).
  /// The extra params are only needed for that lazy-create path.
  Future<void> addItem(
    PosItem item,
    Ticket? ticket,
    SalesCatalog catalog, {
    String? tableId,
    String? zoneId,
    String? label,
    String? customerCode,
    String? locationCode,
    String? operatorUid,
    String? operatorName,
  }) async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    await ref.read(salesRepositoryProvider).addOrIncrementItem(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket?.id,
          currentLines: ticket?.lines ?? const [],
          itemCode: item.code,
          description: item.description,
          unitPrice: ticket != null
              ? priceFor(item, ticket, catalog)
              : _priceForCode(item, customerCode, catalog),
          tableId: tableId,
          zoneId: zoneId,
          label: label,
          customerCode: customerCode,
          locationCode: locationCode,
          operatorUid: operatorUid,
          operatorName: operatorName,
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
    final newLines = ticket.lines.map((line) {
      final matches = catalog.items.where((i) => i.code == line.itemCode);
      if (matches.isEmpty) return line;
      return TicketLine(
        itemCode: line.itemCode,
        description: line.description,
        unitPrice: _priceForCode(matches.first, customerCode, catalog),
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

  /// Closes the order out into an invoice — the fiscal document (real
  /// fiscalization is future work, but this is that boundary).
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
        title: const Text('Cancel this order?'),
        content: Text('"${ticket.label}" and its items will be discarded.'),
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
    await ref.read(salesRepositoryProvider).cancelTicket(
          companyId: paired.companyId,
          businessUnitId: paired.businessUnitId,
          ticketId: ticket.id,
          tableId: ticket.tableId,
        );
    if (mounted) onDone();
  }

  /// The item browser + cart, laid out side-by-side on wide screens or as
  /// a browser with a tap-to-open cart sheet on phone.
  ///
  /// [selected] is the order in progress, if any — a table can be open
  /// with no order yet, which is why this (unlike the ticket-keyed
  /// completeTicket/cancelTicket above) accepts a null ticket and still
  /// renders a fully-interactive browser: tapping an item is what creates
  /// the order lazily. [tableLabel]/[lockedByName]/[onLeaveTable] only
  /// apply in that table-open-with-no-order-yet state.
  Widget buildWorkspace({
    required Ticket? selected,
    required SalesCatalog catalog,
    required bool readOnly,
    String? tableLabel,
    String? lockedByName,
    VoidCallback? onLeaveTable,
    void Function(PosItem item)? onAddFirstItem,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final browser = _buildBrowser(catalog, selected, readOnly, onAddFirstItem);

        Widget buildCart({required VoidCallback? closeSheet}) {
          return CartPanel(
            ticket: selected,
            catalog: catalog,
            readOnly: readOnly,
            tableLabel: tableLabel,
            lockedByName: lockedByName,
            onLeaveTable: onLeaveTable,
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
                      selected != null
                          ? '${selected.lines.length} items · ${selected.label}'
                          : (tableLabel ?? 'Cart'),
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
    );
  }

  /// Called once a ticket this workspace was showing gets completed or
  /// cancelled. Override to navigate away (table screen) or just clear the
  /// selection (simple screen, which has other tickets to fall back to).
  void onTicketClosed(Ticket closed);

  Widget _buildBrowser(
    SalesCatalog catalog,
    Ticket? selected,
    bool readOnly,
    void Function(PosItem item)? onAddFirstItem,
  ) {
    final items = visibleItems(catalog);
    final categoriesForGroup = catalog.categories
        .where((c) => c.groupCodes.contains(selectedGroupCode))
        .toList();
    final letters = existingLetters(catalog);

    final searchAndLetters = _SearchAndLetters(
      controller: searchController,
      search: search,
      letters: letters,
      selectedLetter: selectedLetter,
      onSearchChanged: (v) => setState(() => search = v),
      onLetterTap: (letter) => setState(() {
        selectedLetter = selectedLetter == letter ? null : letter;
      }),
    );
    final groupsAndCategories = _GroupsAndCategories(
      groups: catalog.visibleGroups,
      categories: categoriesForGroup,
      selectedGroupCode: selectedGroupCode,
      selectedCategoryCode: selectedCategoryCode,
      dimmed: search.trim().isNotEmpty || selectedLetter != null,
      onGroupTap: (code) => setState(() {
        selectedGroupCode = code;
        selectedCategoryCode = null;
        selectedLetter = null;
        search = '';
        searchController.clear();
      }),
      onCategoryTap: (code) => setState(() => selectedCategoryCode = code),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 480) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 176, child: searchAndLetters),
                    const SizedBox(width: 12),
                    Expanded(child: groupsAndCategories),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchAndLetters,
                  const SizedBox(height: 10),
                  groupsAndCategories,
                ],
              );
            },
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
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
                    final price = selected != null
                        ? priceFor(item, selected, catalog)
                        : _priceForCode(item, null, catalog);
                    return ItemTile(
                      item: item,
                      price: price,
                      onTap: readOnly
                          ? null
                          : () {
                              if (selected == null) {
                                onAddFirstItem?.call(item);
                              } else {
                                addItem(item, selected, catalog);
                              }
                            },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchAndLetters extends StatelessWidget {
  const _SearchAndLetters({
    required this.controller,
    required this.search,
    required this.letters,
    required this.selectedLetter,
    required this.onSearchChanged,
    required this.onLetterTap,
  });

  final TextEditingController controller;
  final String search;
  final List<String> letters;
  final String? selectedLetter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onLetterTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search…',
              isDense: true,
              border: InputBorder.none,
            ),
            onChanged: onSearchChanged,
          ),
          if (letters.isNotEmpty) ...[
            const Divider(height: 12, color: AppColors.border),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final letter in letters)
                  _LetterChip(
                    letter: letter,
                    selected: selectedLetter == letter,
                    onTap: () => onLetterTap(letter),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LetterChip extends StatelessWidget {
  const _LetterChip({required this.letter, required this.selected, required this.onTap});
  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.orange : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupsAndCategories extends StatelessWidget {
  const _GroupsAndCategories({
    required this.groups,
    required this.categories,
    required this.selectedGroupCode,
    required this.selectedCategoryCode,
    required this.dimmed,
    required this.onGroupTap,
    required this.onCategoryTap,
  });

  final List<ItemGroup> groups;
  final List<ItemCategory> categories;
  final String? selectedGroupCode;
  final String? selectedCategoryCode;

  /// True while a search/letter filter is active — groups still work (tap
  /// one to go back to browsing by group) but shouldn't look selected.
  final bool dimmed;
  final ValueChanged<String> onGroupTap;
  final ValueChanged<String?> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final group in groups)
                CompactChip(
                  label: group.description,
                  selected: !dimmed && selectedGroupCode == group.code,
                  onSelected: () => onGroupTap(group.code),
                ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                CompactChip(
                  label: 'All',
                  selected: !dimmed && selectedCategoryCode == null,
                  onSelected: () => onCategoryTap(null),
                ),
                for (final category in categories)
                  CompactChip(
                    label: category.description,
                    selected: !dimmed && selectedCategoryCode == category.code,
                    onSelected: () => onCategoryTap(category.code),
                  ),
              ],
            ),
          ],
        ],
      ),
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
