// lib/features/pairing/presentation/setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../common_widgets/app_logo.dart';
import '../application/pairing_providers.dart';
import '../data/pairing_repository.dart';
import '../domain/paired_device.dart';

enum _Step { pickUnit, enterCode }

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _codeController = TextEditingController();

  _Step _step = _Step.pickUnit;
  bool _loadingCompanies = true;
  bool _loadingUnits = false;
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  List<NamedOption> _companies = [];
  List<NamedOption> _units = [];
  NamedOption? _selectedCompany;
  NamedOption? _selectedUnit;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    try {
      final companies = await ref.read(pairingRepositoryProvider).listCompanies();
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _loadingCompanies = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load companies: ${e.toString()}';
        _loadingCompanies = false;
      });
    }
  }

  Future<void> _onCompanySelected(NamedOption? company) async {
    setState(() {
      _selectedCompany = company;
      _selectedUnit = null;
      _units = [];
    });
    if (company == null) return;

    setState(() => _loadingUnits = true);
    try {
      final units = await ref.read(pairingRepositoryProvider).listBusinessUnits(company.id);
      if (!mounted) return;
      setState(() {
        _units = units;
        _loadingUnits = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load business units: ${e.toString()}';
        _loadingUnits = false;
      });
    }
  }

  Future<void> _sendCode() async {
    final company = _selectedCompany;
    final unit = _selectedUnit;
    if (company == null || unit == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(pairingRepositoryProvider).requestPairing(
            companyId: company.id,
            businessUnitId: unit.id,
          );
      if (!mounted) return;
      setState(() => _step = _Step.enterCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not send code: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final company = _selectedCompany;
    final unit = _selectedUnit;
    if (company == null || unit == null) return;

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(pairingRepositoryProvider).verifyPairing(
            companyId: company.id,
            businessUnitId: unit.id,
            code: _codeController.text.trim(),
          );
      await ref.read(pairedDeviceProvider.notifier).setPaired(
            PairedDevice(
              companyId: company.id,
              companyName: company.name,
              businessUnitId: unit.id,
              businessUnitName: unit.name,
            ),
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Invalid code: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo()),
                  const SizedBox(height: 20),
                  Text(
                    'Set up this device',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _step == _Step.pickUnit
                        ? _buildPickUnitStep()
                        : _buildEnterCodeStep(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickUnitStep() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
        if (_loadingCompanies)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
          )
        else
          DropdownButtonFormField<NamedOption>(
            initialValue: _selectedCompany,
            decoration: const InputDecoration(labelText: 'Company'),
            dropdownColor: AppColors.surfaceHigh,
            items: _companies
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: _onCompanySelected,
          ),
        const SizedBox(height: 14),
        if (_loadingUnits)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
              ),
            ),
          )
        else
          DropdownButtonFormField<NamedOption>(
            initialValue: _selectedUnit,
            decoration: const InputDecoration(labelText: 'Business unit'),
            dropdownColor: AppColors.surfaceHigh,
            items: _units
                .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                .toList(),
            onChanged: _selectedCompany == null
                ? null
                : (v) => setState(() => _selectedUnit = v),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: (_selectedCompany != null && _selectedUnit != null && !_sending)
              ? _sendCode
              : null,
          child: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send code'),
        ),
      ],
    );
  }

  Widget _buildEnterCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _verifying ? null : () => setState(() => _step = _Step.pickUnit),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('Change business unit'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We emailed a 6-digit code to the Admin/Supervisors of '
          '"${_selectedUnit?.name}". Enter it below.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 4),
          decoration: const InputDecoration(labelText: 'Code', counterText: ''),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _verifying ? null : _verifyCode,
          child: _verifying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sending ? null : _sendCode,
          child: const Text('Resend code'),
        ),
      ],
    );
  }
}
