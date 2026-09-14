// lib/features/sales/presentation/sales_workspace_mixin.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../application/sales_providers.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
import '../domain/pos_item.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';
import 'cart_panel.dart';

/// The responsive item-browser + cart layout and the filtering logic
/// behind it, shared between [SimpleSalesScreen] and [TableSalesScreen].
/// Pure UI/filtering only — each screen owns its own item-tap/qty/
/// customer/complete/cancel actions (they hit different Firestore
/// collections: free-form `tickets` vs table-keyed `orders`/`invoices`)
/// and passes them in as callbacks.
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

  num priceForCode(PosItem item, String? customerCode, SalesCatalog catalog) {
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
      priceForCode(item, ticket.customerCode, catalog);

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

  /// All active filters combine (AND) rather than override each other —
  /// search, a letter, a group and a category can all narrow the result
  /// together.
  List<PosItem> visibleItems(SalesCatalog catalog) {
    var items = _activeVisibleItems(catalog);
    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      items = items
          .where((i) =>
              i.description.toLowerCase().contains(q) || i.code.toLowerCase().contains(q))
          .toList();
    }
    if (selectedLetter != null) {
      items = items.where((i) => i.description.toUpperCase().startsWith(selectedLetter!)).toList();
    }
    if (selectedGroupCode != null) {
      items = items.where((i) => i.groupCode == selectedGroupCode).toList();
    }
    if (selectedCategoryCode != null) {
      items = items.where((i) => i.categoryCode == selectedCategoryCode).toList();
    }
    return items;
  }

  /// The item browser + cart, laid out side-by-side on wide screens or as
  /// a browser with a tap-to-open cart sheet on phone.
  Widget buildWorkspace({
    required Ticket? selected,
    required SalesCatalog catalog,
    required bool readOnly,
    required void Function(PosItem item) onItemTap,
    required void Function(TicketLine line, num newQty) onQtyChanged,
    required void Function(String customerCode) onCustomerChanged,
    required VoidCallback onComplete,
    required VoidCallback onCancel,
    required VoidCallback onSendRound,
    String? tableLabel,
    String? lockedByName,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final browser = _buildBrowser(catalog, selected, readOnly, onItemTap);

        Widget buildCart({required VoidCallback? closeSheet}) {
          return CartPanel(
            ticket: selected,
            catalog: catalog,
            readOnly: readOnly,
            tableLabel: tableLabel,
            lockedByName: lockedByName,
            onQtyChanged: onQtyChanged,
            onCustomerChanged: onCustomerChanged,
            onComplete: () {
              closeSheet?.call();
              onComplete();
            },
            onCancel: () {
              closeSheet?.call();
              onCancel();
            },
            onSendRound: onSendRound,
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

  Widget _buildBrowser(
    SalesCatalog catalog,
    Ticket? selected,
    bool readOnly,
    void Function(PosItem item) onItemTap,
  ) {
    final items = visibleItems(catalog);
    final categoriesForGroup = selectedGroupCode == null
        ? const <ItemCategory>[]
        : catalog.categories.where((c) => c.groupCodes.contains(selectedGroupCode)).toList();
    final letters = existingLetters(catalog);

    final searchAndLetters = _SearchAndLetters(
      controller: searchController,
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
      onGroupTap: (code) => setState(() {
        selectedGroupCode = code;
        selectedCategoryCode = null;
      }),
      onCategoryTap: (code) => setState(() => selectedCategoryCode = code),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 460) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 158, child: searchAndLetters),
                    const SizedBox(width: 8),
                    Expanded(child: groupsAndCategories),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchAndLetters,
                  const SizedBox(height: 6),
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
                        : priceForCode(item, null, catalog);
                    return ItemTile(
                      item: item,
                      price: price,
                      onTap: readOnly ? null : () => onItemTap(item),
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
    required this.letters,
    required this.selectedLetter,
    required this.onSearchChanged,
    required this.onLetterTap,
  });

  final TextEditingController controller;
  final List<String> letters;
  final String? selectedLetter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onLetterTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 16),
              prefixIconConstraints: BoxConstraints(minWidth: 30),
              hintText: 'Search…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        if (letters.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final letter in letters)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: _LetterChip(
                      letter: letter,
                      selected: selectedLetter == letter,
                      onTap: () => onLetterTap(letter),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
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
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 10.5,
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
    required this.onGroupTap,
    required this.onCategoryTap,
  });

  final List<ItemGroup> groups;
  final List<ItemCategory> categories;
  final String? selectedGroupCode;
  final String? selectedCategoryCode;
  final ValueChanged<String?> onGroupTap;
  final ValueChanged<String?> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 26,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: CompactChip(
                  label: 'All',
                  selected: selectedGroupCode == null,
                  onSelected: () => onGroupTap(null),
                ),
              ),
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: CompactChip(
                    label: group.description,
                    selected: selectedGroupCode == group.code,
                    onSelected: () => onGroupTap(group.code),
                  ),
                ),
            ],
          ),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: CompactChip(
                    label: 'All',
                    selected: selectedCategoryCode == null,
                    onSelected: () => onCategoryTap(null),
                  ),
                ),
                for (final category in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: CompactChip(
                      label: category.description,
                      selected: selectedCategoryCode == category.code,
                      onSelected: () => onCategoryTap(category.code),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Small-footprint ChoiceChip used for the group/category rows — the
/// default ChoiceChip padding/density ate too much vertical space.
class CompactChip extends StatelessWidget {
  const CompactChip({super.key, required this.label, required this.selected, required this.onSelected});
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 7),
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
