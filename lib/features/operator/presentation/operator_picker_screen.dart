// lib/features/operator/presentation/operator_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../pairing/application/pairing_providers.dart';
import '../application/operator_providers.dart';
import '../domain/pos_operator.dart';

class OperatorPickerScreen extends ConsumerStatefulWidget {
  const OperatorPickerScreen({super.key});

  @override
  ConsumerState<OperatorPickerScreen> createState() => _OperatorPickerScreenState();
}

class _OperatorPickerScreenState extends ConsumerState<OperatorPickerScreen> {
  bool _loading = true;
  String? _loadError;
  List<PosOperator> _operators = [];

  PosOperator? _selected;
  String _pin = '';
  bool _signingIn = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _load();
  }

  Future<void> _load() async {
    final paired = ref.read(pairedDeviceProvider).value;
    if (paired == null) return;
    try {
      final operators = await ref.read(operatorRepositoryProvider).listForBusinessUnit(
            companyId: paired.companyId,
            businessUnitId: paired.businessUnitId,
          );
      if (!mounted) return;
      setState(() {
        _operators = operators;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _selectOperator(PosOperator operator) {
    setState(() {
      _selected = operator;
      _pin = '';
      _pinError = null;
    });
  }

  void _onDigit(String digit) {
    if (_selected == null || _signingIn || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _pinError = null;
    });
    if (_pin.length == 6) _submit();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final operator = _selected;
    if (operator == null) return;
    setState(() => _signingIn = true);
    try {
      await ref.read(operatorRepositoryProvider).signIn(email: operator.email, pin: _pin);
      // Router redirects to /home once the auth state change comes through.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinError = 'Incorrect PIN';
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paired = ref.watch(pairedDeviceProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(paired?.businessUnitName ?? 'Select operator')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 32),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load operators: $_loadError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 760;
                    final cards = _buildOperatorGrid();
                    final pad = _buildPinPad();
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: cards),
                          const VerticalDivider(width: 1, color: AppColors.border),
                          Expanded(flex: 2, child: pad),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(child: cards),
                        const Divider(height: 1, color: AppColors.border),
                        Expanded(child: pad),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildOperatorGrid() {
    if (_operators.isEmpty) {
      return const Center(
        child: Text(
          'No operators assigned to this business unit.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1,
      ),
      itemCount: _operators.length,
      itemBuilder: (context, index) {
        final operator = _operators[index];
        final selected = operator.uid == _selected?.uid;
        return _OperatorCard(
          operator: operator,
          selected: selected,
          onTap: () => _selectOperator(operator),
        );
      },
    );
  }

  Widget _buildPinPad() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _selected == null ? 'Pick your name' : _selected!.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = i < _pin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? AppColors.orange : AppColors.surfaceHighest,
                ),
              );
            }),
          ),
          if (_pinError != null) ...[
            const SizedBox(height: 10),
            Text(_pinError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          if (_signingIn) ...[
            const SizedBox(height: 10),
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
            ),
          ],
          const SizedBox(height: 24),
          _NumPad(
            enabled: _selected != null && !_signingIn,
            onDigit: _onDigit,
            onBackspace: _onBackspace,
          ),
        ],
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({
    required this.operator,
    required this.selected,
    required this.onTap,
  });

  final PosOperator operator;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.orange.withValues(alpha: 0.15),
                child: Text(
                  operator.displayName.isNotEmpty
                      ? operator.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                operator.displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumPad extends StatelessWidget {
  const _NumPad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap}) {
      return SizedBox(
        width: 72,
        height: 56,
        child: Material(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? (onTap ?? () => onDigit(label)) : null,
            child: Center(
              child: label == '⌫'
                  ? const Icon(Icons.backspace_outlined, color: AppColors.textPrimary, size: 20)
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('1'),
          const SizedBox(width: 10),
          key('2'),
          const SizedBox(width: 10),
          key('3'),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('4'),
          const SizedBox(width: 10),
          key('5'),
          const SizedBox(width: 10),
          key('6'),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          key('7'),
          const SizedBox(width: 10),
          key('8'),
          const SizedBox(width: 10),
          key('9'),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 72),
          const SizedBox(width: 10),
          key('0'),
          const SizedBox(width: 10),
          key('⌫', onTap: onBackspace),
        ]),
      ],
    );
  }
}
