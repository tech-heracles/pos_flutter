// lib/features/sales/application/sales_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../pairing/application/pairing_providers.dart';
import '../data/sales_repository.dart';
import '../domain/item_category.dart';
import '../domain/item_group.dart';
import '../domain/pos_customer.dart';
import '../domain/pos_item.dart';
import '../domain/pos_location.dart';
import '../domain/ticket.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(FirebaseFirestore.instance),
);

class SalesCatalog {
  const SalesCatalog({
    required this.items,
    required this.groups,
    required this.categories,
    required this.customers,
    required this.locations,
    required this.defaultCustomerCode,
    required this.defaultLocationCode,
  });

  final List<PosItem> items;
  final List<ItemGroup> groups;
  final List<ItemCategory> categories;
  final List<PosCustomer> customers;
  final List<PosLocation> locations;
  final String? defaultCustomerCode;
  final String? defaultLocationCode;

  static const empty = SalesCatalog(
    items: [],
    groups: [],
    categories: [],
    customers: [],
    locations: [],
    defaultCustomerCode: null,
    defaultLocationCode: null,
  );
}

/// Loaded once per session (not paginated) so search/grouping/pricing on
/// the sale screen are instant — see SalesRepository for why.
final salesCatalogProvider = FutureProvider<SalesCatalog>((ref) async {
  final paired = ref.watch(pairedDeviceProvider).value;
  if (paired == null) return SalesCatalog.empty;

  final repo = ref.watch(salesRepositoryProvider);
  final items = await repo.fetchAllItems(paired.companyId);
  final groups = await repo.fetchAllItemGroups(paired.companyId);
  final categories = await repo.fetchAllItemCategories(paired.companyId);
  final customers = await repo.fetchAllCustomers(paired.companyId);
  final locations = await repo.fetchAllLocations(paired.companyId);
  final defaults = await repo.fetchBusinessUnitDefaults(
    companyId: paired.companyId,
    businessUnitId: paired.businessUnitId,
  );

  return SalesCatalog(
    items: items,
    groups: groups,
    categories: categories,
    customers: customers,
    locations: locations,
    defaultCustomerCode: defaults.defaultCustomerCode,
    defaultLocationCode: defaults.defaultLocationCode,
  );
});

final openTicketsProvider = StreamProvider<List<Ticket>>((ref) {
  final paired = ref.watch(pairedDeviceProvider).value;
  if (paired == null) return const Stream.empty();
  return ref.watch(salesRepositoryProvider).watchOpenTickets(
        companyId: paired.companyId,
        businessUnitId: paired.businessUnitId,
      );
});
