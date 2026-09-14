// lib/features/sales/presentation/cart_panel.dart
import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../application/sales_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_line.dart';

class CartPanel extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.ticket,
    required this.catalog,
    required this.readOnly,
    required this.onQtyChanged,
    required this.onCustomerChanged,
    required this.onComplete,
    required this.onCancel,
    required this.onSendRound,
    this.tableLabel,
    this.lockedByName,
    this.isOnline = true,
  });

  final Ticket? ticket;
  final SalesCatalog catalog;

  /// True when this table belongs to another operator — the whole cart
  /// becomes look-but-don't-touch.
  final bool readOnly;
  final void Function(TicketLine line, num newQty) onQtyChanged;
  final void Function(String customerCode) onCustomerChanged;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onSendRound;

  /// Non-null only for a table context (BAR/RESTAURANT). A table can be
  /// open with no order yet — [ticket] is then null but this still lets
  /// the cart show "table open" instead of the generic empty state.
  final String? tableLabel;
  final String? lockedByName;

  /// False only when this device has lost its Firestore connection. Every
  /// other action here queues fine offline and syncs later, but closing a
  /// table out into an invoice is a real transaction (see
  /// SalesRepository.createInvoice) — it can't be queued, so the button is
  /// disabled instead of tapping into a silent hang.
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    if (t == null) {
      if (tableLabel == null) {
        return const Center(
          child: Text('No active ticket', style: TextStyle(color: AppColors.textSecondary)),
        );
      }
      // Table has no order yet — tapping an item is what starts one, so
      // there's nothing to lock and nothing to "leave"; going back is just
      // navigation.
      return const Center(
        child: Text('No order yet — tap an item to start', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final matchingLocations = catalog.locations.where((l) => l.code == t.locationCode);
    final locationName =
        matchingLocations.isNotEmpty ? matchingLocations.first.description : t.locationCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readOnly) _LockBanner(name: t.operatorName),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A table-bound ticket's label is just the table name, which
              // the screen's AppBar already shows — repeating it here would
              // be redundant. Free-form tickets still need it since the
              // cart is the only place that says which one is selected.
              if (t.tableId == null) ...[
                Text(t.label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: catalog.customers.any((c) => c.code == t.customerCode)
                    ? t.customerCode
                    : null,
                decoration: const InputDecoration(labelText: 'Customer'),
                dropdownColor: AppColors.surfaceHigh,
                items: catalog.customers
                    .map((c) => DropdownMenuItem(value: c.code, child: Text(c.description)))
                    .toList(),
                onChanged: readOnly
                    ? null
                    : (v) {
                        if (v != null) onCustomerChanged(v);
                      },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    locationName,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: t.lines.isEmpty
              ? const Center(
                  child: Text('No items yet', style: TextStyle(color: AppColors.textMuted)),
                )
              : _CartLines(
                  ticket: t,
                  onQtyChanged: readOnly ? null : onQtyChanged,
                ),
        ),
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    t.total.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Only table-bound tickets (BAR/RESTAURANT mode) queue orders —
              // a free-form ticket has no "sent" concept to distinguish.
              if (t.tableId != null) ...[
                OutlinedButton.icon(
                  onPressed: (!readOnly && t.hasPendingLines) ? onSendRound : null,
                  icon: const Icon(Icons.outbound, size: 18),
                  label: Text(t.currentRound == 0 ? 'Send order' : 'Send new order'),
                ),
                const SizedBox(height: 10),
              ],
              // Simple-mode "complete" is a plain status flip and works
              // fine offline; a table's Create Invoice is a real
              // transaction (the fiscal boundary) and needs connectivity.
              _createInvoiceButton(
                enabled: !readOnly && t.lines.isNotEmpty && (t.tableId == null || isOnline),
                blockedByOffline: t.tableId != null && !isOnline,
                onComplete: onComplete,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: readOnly ? null : onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Cancel order'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _createInvoiceButton({
    required bool enabled,
    required bool blockedByOffline,
    required VoidCallback onComplete,
  }) {
    final button = FilledButton(
      onPressed: enabled ? onComplete : null,
      child: const Text('Create Invoice'),
    );
    if (!blockedByOffline) return button;
    return Tooltip(message: 'Offline — reconnect to close out this table', child: button);
  }
}

class _LockBanner extends StatelessWidget {
  const _LockBanner({required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.error.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Locked — being served by ${(name == null || name!.isEmpty) ? 'another operator' : name}',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLines extends StatelessWidget {
  const _CartLines({required this.ticket, required this.onQtyChanged});
  final Ticket ticket;

  /// null (read-only cart) forces every line to render non-editable,
  /// regardless of pending/sent status.
  final void Function(TicketLine line, num newQty)? onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final isTableTicket = ticket.tableId != null;
    final pendingLines = isTableTicket
        ? ticket.lines.where((l) => l.isPending).toList()
        : ticket.lines;
    final sentByRound = <int, List<TicketLine>>{};
    if (isTableTicket) {
      for (final line in ticket.lines.where((l) => !l.isPending)) {
        sentByRound.putIfAbsent(line.roundNumber, () => []).add(line);
      }
    }
    final sortedRounds = sentByRound.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final round in sortedRounds) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Order $round · sent',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final line in sentByRound[round]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CartLineRow(line: line, onQtyChanged: null),
            ),
        ],
        if (isTableTicket && pendingLines.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 6, top: sortedRounds.isEmpty ? 0 : 4),
            child: const Text(
              'New — not sent yet',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
              ),
            ),
          ),
        for (final line in pendingLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CartLineRow(
              line: line,
              onQtyChanged: onQtyChanged == null ? null : (q) => onQtyChanged!(line, q),
            ),
          ),
      ],
    );
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({required this.line, required this.onQtyChanged});
  final TicketLine line;

  /// null for an already-sent line — its quantity is locked into that
  /// round's history, shown as plain text instead of a stepper.
  final ValueChanged<num>? onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final editable = onQtyChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.description,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              Text(
                '${line.unitPrice.toStringAsFixed(2)} each',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (editable)
          Row(
            children: [
              _StepperButton(icon: Icons.remove, onTap: () => onQtyChanged!(line.qty - 1)),
              SizedBox(
                width: 28,
                child: Text(
                  '${line.qty}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _StepperButton(icon: Icons.add, onTap: () => onQtyChanged!(line.qty + 1)),
            ],
          )
        else
          SizedBox(
            width: 28,
            child: Text(
              '${line.qty}×',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted),
            ),
          ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            line.lineTotal.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppColors.textPrimary),
      ),
    );
  }
}
