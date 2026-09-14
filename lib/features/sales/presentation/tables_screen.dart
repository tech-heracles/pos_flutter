// lib/features/sales/presentation/tables_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../auth/application/auth_providers.dart';
import '../../operator/application/operator_providers.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/sales_providers.dart';
import '../domain/ticket.dart';
import '../domain/zone.dart';

/// BAR/RESTAURANT mode home: pick a zone, then a table. Tapping a table
/// claims it (or joins it if it's already yours) and pushes the
/// single-table sales page — this screen shows nothing else, so there's
/// no leftover cart/browser state to reset when the operator comes back
/// to it after closing a table out.
class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  String? _selectedZoneId;

  Future<void> _onTableTap(Zone zone, ZoneTable table, SalesCatalog catalog) async {
    final paired = ref.read(pairedDeviceProvider).value;
    final user = ref.read(authStateChangesProvider).value;
    if (paired == null || user == null) return;

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
    if (!result.claimedByMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${table.name} is already being served by ${result.ownerName}'),
        ),
      );
    }
    context.push('/home/table/${result.ticketId}');
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
          if (catalog.zones.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No zones/tables configured for this business unit yet — add them in Manager.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          if (_selectedZoneId == null ||
              !catalog.zones.any((z) => z.id == _selectedZoneId)) {
            _selectedZoneId = catalog.zones.first.id;
          }
          final zone = catalog.zones.firstWhere((z) => z.id == _selectedZoneId);

          return ticketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.orange)),
            error: (err, _) => Center(
              child: Text('Failed to load tables: $err',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            data: (tickets) {
              final ticketByTable = {
                for (final t in tickets)
                  if (t.tableId != null) t.tableId!: t,
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      children: [
                        for (final z in catalog.zones)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(z.name),
                              selected: z.id == zone.id,
                              onSelected: (_) => setState(() => _selectedZoneId = z.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: zone.tables.isEmpty
                        ? const Center(
                            child: Text(
                              'No tables in this zone',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 170,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.15,
                            ),
                            itemCount: zone.tables.length,
                            itemBuilder: (context, index) {
                              final table = zone.tables[index];
                              return _TableCard(
                                table: table,
                                ticket: ticketByTable[table.id],
                                onTap: () => _onTableTap(zone, table, catalog),
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
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.ticket, required this.onTap});
  final ZoneTable table;
  final Ticket? ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occupied = ticket != null;
    return Material(
      color: occupied ? AppColors.orange.withValues(alpha: 0.12) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: occupied ? AppColors.orange : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                occupied ? Icons.people_alt_rounded : Icons.table_bar_outlined,
                color: occupied ? AppColors.orange : AppColors.textMuted,
                size: 26,
              ),
              const Spacer(),
              Text(
                table.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                occupied
                    ? '${ticket!.operatorName.isEmpty ? '?' : ticket!.operatorName} · ${ticket!.total.toStringAsFixed(0)}'
                    : 'Free',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: occupied ? AppColors.orange : AppColors.textMuted,
                  fontWeight: occupied ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
