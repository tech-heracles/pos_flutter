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
    required this.onQtyChanged,
    required this.onCustomerChanged,
    required this.onComplete,
    required this.onCancel,
  });

  final Ticket? ticket;
  final SalesCatalog catalog;
  final void Function(TicketLine line, num newQty) onQtyChanged;
  final void Function(String customerCode) onCustomerChanged;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    if (t == null) {
      return const Center(
        child: Text('No active ticket', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final matchingLocations = catalog.locations.where((l) => l.code == t.locationCode);
    final locationName =
        matchingLocations.isNotEmpty ? matchingLocations.first.description : t.locationCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: catalog.customers.any((c) => c.code == t.customerCode)
                    ? t.customerCode
                    : null,
                decoration: const InputDecoration(labelText: 'Customer'),
                dropdownColor: AppColors.surfaceHigh,
                items: catalog.customers
                    .map((c) => DropdownMenuItem(value: c.code, child: Text(c.description)))
                    .toList(),
                onChanged: (v) {
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
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: t.lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final line = t.lines[index];
                    return _CartLineRow(
                      line: line,
                      onQtyChanged: (q) => onQtyChanged(line, q),
                    );
                  },
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
              FilledButton(
                onPressed: t.lines.isEmpty ? null : onComplete,
                child: const Text('Complete Sale'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Cancel ticket'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({required this.line, required this.onQtyChanged});
  final TicketLine line;
  final ValueChanged<num> onQtyChanged;

  @override
  Widget build(BuildContext context) {
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
        Row(
          children: [
            _StepperButton(icon: Icons.remove, onTap: () => onQtyChanged(line.qty - 1)),
            SizedBox(
              width: 28,
              child: Text(
                '${line.qty}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _StepperButton(icon: Icons.add, onTap: () => onQtyChanged(line.qty + 1)),
          ],
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
