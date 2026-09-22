import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'auction_excel_export.dart';
import 'auction_vehicle.dart';
import 'poster_history.dart';
import 'studio_ui.dart';
import 'vehicle_number_sort.dart';

class AuctionVehiclesScreen extends StatefulWidget {
  final PosterHistory history;
  final bool embedded;

  const AuctionVehiclesScreen({
    super.key,
    required this.history,
    this.embedded = false,
  });

  @override
  State<AuctionVehiclesScreen> createState() => _AuctionVehiclesScreenState();
}

class _AuctionVehiclesScreenState extends State<AuctionVehiclesScreen> {
  late Future<List<AuctionVehicleEntry>> _entries;
  final _search = TextEditingController();
  bool _busy = false;
  String _query = '';
  bool _numberAscending = true;

  @override
  void initState() {
    super.initState();
    _entries = widget.history.listAuctionVehicles();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    final entries = widget.history.listAuctionVehicles();
    setState(() {
      _entries = entries;
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _openVehicleForm(
    List<AuctionVehicleEntry> entries, {
    AuctionVehicleEntry? entry,
  }) async {
    if (_busy) return;
    final usedNumbers = <String>{
      for (final item in entries)
        if (item.id != entry?.id) item.vehicle.number.trim(),
    };
    final vehicle = await showModalBottomSheet<AuctionVehicle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AuctionVehicleForm(
        initial: entry?.vehicle ?? AuctionVehicle(number: _nextNumber(entries)),
        usedNumbers: usedNumbers,
        editing: entry != null,
      ),
    );
    if (!mounted || vehicle == null) return;

    setState(() => _busy = true);
    try {
      if (entry == null) {
        await widget.history.createAuctionVehicle(vehicle);
      } else {
        await widget.history.updateAuctionVehicle(entry.id, vehicle);
      }
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entry == null
                ? 'Auction vehicle added.'
                : 'Auction vehicle updated.',
          ),
        ),
      );
    } catch (error) {
      _showError('Could not save auction vehicle: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _nextNumber(List<AuctionVehicleEntry> entries) {
    var greatest = 0;
    for (final entry in entries) {
      final value = int.tryParse(entry.vehicle.number.trim());
      if (value != null && value > greatest) greatest = value;
    }
    return '${greatest + 1}';
  }

  Future<void> _deleteVehicle(AuctionVehicleEntry entry) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StudioConfirmDialog(
        title: 'Delete auction vehicle?',
        message:
            'Remove No. ${entry.vehicle.number} (${entry.vehicle.vehicleType}) from this auction list?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete',
        icon: Icons.delete_outline_rounded,
        confirmIcon: Icons.delete_outline_rounded,
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.history.deleteAuctionVehicle(entry.id);
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Auction vehicle removed.')));
    } catch (error) {
      _showError('Could not remove auction vehicle: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(List<AuctionVehicleEntry> entries) async {
    if (_busy || entries.isEmpty) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final bytes = AuctionExcelExporter.export(
        entries,
        date: now,
        numberAscending: _numberAscending,
      );
      final name =
          'auction-list-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.xlsx';
      const type = XTypeGroup(
        label: 'Excel workbook',
        extensions: ['xlsx'],
        mimeTypes: [
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ],
      );
      final file = XFile.fromData(
        bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: name,
      );
      String message;
      if (kIsWeb) {
        await file.saveTo(name);
        message = 'Excel download started. Check your browser downloads.';
      } else if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        final directory = await getTemporaryDirectory();
        final exportDirectory = Directory(
          '${directory.path}/auction-list-exports',
        );
        await exportDirectory.create(recursive: true);
        final exportFile = File('${exportDirectory.path}/$name');
        await exportFile.writeAsBytes(bytes, flush: true);
        if (!mounted) return;

        Rect? shareOrigin;
        final renderObject = context.findRenderObject();
        if (renderObject is RenderBox) {
          shareOrigin =
              renderObject.localToGlobal(Offset.zero) & renderObject.size;
        }
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                exportFile.path,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ),
            ],
            fileNameOverrides: [name],
            title: 'Auction List',
            subject: 'Auction List',
            text: 'Auction List',
            sharePositionOrigin: shareOrigin ?? const Rect.fromLTWH(0, 0, 1, 1),
          ),
        );
        message = 'Excel file shared.';
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: [type],
        );
        if (location == null) return;
        await file.saveTo(location.path);
        message = 'Auction list Excel file saved.';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      _showError('Could not export the auction list: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AuctionVehicleEntry> _filtered(List<AuctionVehicleEntry> entries) {
    final visible = entries.where((entry) {
      final vehicle = entry.vehicle;
      return [
        vehicle.number,
        vehicle.vin,
        vehicle.vehicleType,
        vehicle.year,
        vehicle.mileage,
        vehicle.color,
        vehicle.owner,
        vehicle.redLight,
        vehicle.greenLight,
        vehicle.priceUsd,
      ].join(' ').toLowerCase().contains(_query);
    }).toList();
    visible.sort((a, b) {
      final comparison = compareVehicleNumbers(
        a.vehicle.number,
        b.vehicle.number,
        ascending: _numberAscending,
      );
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
    return visible;
  }

  Widget _summary(int count) => StudioCard(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xfff2e5dc),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.directions_car_filled_outlined,
            size: 20,
            color: StudioColors.accent,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Vehicles saved',
              style: TextStyle(fontSize: 10, color: StudioColors.muted),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _toolbar(List<AuctionVehicleEntry> entries, bool wide) => StudioCard(
    padding: const EdgeInsets.all(14),
    child: wide
        ? Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 12),
              _sortControl(),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy || entries.isEmpty
                    ? null
                    : () => _export(entries),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Export Excel'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _busy ? null : () => _openVehicleForm(entries),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add vehicle'),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchField(),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: _sortControl()),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || entries.isEmpty
                          ? null
                          : () => _export(entries),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export Excel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _openVehicleForm(entries),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add vehicle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
  );

  Widget _searchField() => TextField(
    controller: _search,
    enabled: !_busy,
    onChanged: (value) => setState(() => _query = value.toLowerCase().trim()),
    decoration: InputDecoration(
      hintText: 'Search by vehicle, VIN, owner or No.…',
      prefixIcon: const Icon(Icons.search_rounded, size: 19),
      fillColor: const Color(0xfff6f6f3),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () => setState(() {
                _search.clear();
                _query = '';
              }),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
    ),
  );

  Widget _sortControl() => DropdownButtonHideUnderline(
    child: DropdownButton<bool>(
      value: _numberAscending,
      borderRadius: BorderRadius.circular(16),
      style: const TextStyle(color: StudioColors.ink, fontSize: 12),
      items: const [
        DropdownMenuItem(value: true, child: Text('Number: low to high')),
        DropdownMenuItem(value: false, child: Text('Number: high to low')),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() => _numberAscending = value!),
    ),
  );

  Widget _empty(List<AuctionVehicleEntry> entries) => StudioCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xffe9eae4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              entries.isEmpty
                  ? Icons.add_road_outlined
                  : Icons.search_off_rounded,
              color: StudioColors.muted,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            entries.isEmpty
                ? 'Add your first auction vehicle'
                : 'No matching vehicles',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          Text(
            entries.isEmpty
                ? 'Enter the auction details, then export an Excel list in the supplied format.'
                : 'Try another search or clear the current filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: StudioColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : entries.isEmpty
                ? () => _openVehicleForm(entries)
                : () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
            icon: Icon(
              entries.isEmpty
                  ? Icons.add_rounded
                  : Icons.filter_alt_off_outlined,
            ),
            label: Text(entries.isEmpty ? 'Add vehicle' : 'Clear filter'),
          ),
        ],
      ),
    ),
  );

  Widget _table(List<AuctionVehicleEntry> entries) => StudioCard(
    padding: const EdgeInsets.all(8),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: StudioColors.muted,
        ),
        dataTextStyle: const TextStyle(fontSize: 12, color: StudioColors.ink),
        columnSpacing: 22,
        horizontalMargin: 14,
        columns: const [
          DataColumn(label: Text('NO.')),
          DataColumn(label: Text('VIN')),
          DataColumn(label: Text('VEHICLE TYPE')),
          DataColumn(label: Text('YEAR')),
          DataColumn(label: Text('MILEAGE')),
          DataColumn(label: Text('COLOR')),
          DataColumn(label: Text('OWNER')),
          DataColumn(label: Text('RED LIGHT')),
          DataColumn(label: Text('GREEN LIGHT')),
          DataColumn(label: Text('PRICE (USD)')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final entry in entries)
            DataRow.byIndex(
              index: entry.id,
              cells: [
                DataCell(Text(entry.vehicle.number)),
                DataCell(Text(entry.vehicle.vin)),
                DataCell(Text(entry.vehicle.vehicleType)),
                DataCell(Text(entry.vehicle.year)),
                DataCell(Text(entry.vehicle.mileage)),
                DataCell(Text(entry.vehicle.color)),
                DataCell(Text(entry.vehicle.owner)),
                DataCell(Text(_currency(entry.vehicle.redLight))),
                DataCell(Text(_currency(entry.vehicle.greenLight))),
                DataCell(Text(_currency(entry.vehicle.priceUsd))),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Edit vehicle ${entry.vehicle.number}',
                        onPressed: _busy
                            ? null
                            : () => _openVehicleForm(entries, entry: entry),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Delete vehicle ${entry.vehicle.number}',
                        onPressed: _busy ? null : () => _deleteVehicle(entry),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: StudioColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _cards(List<AuctionVehicleEntry> entries) => Column(
    children: [
      for (final entry in entries) ...[
        _vehicleCard(entry, entries),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget _vehicleCard(
    AuctionVehicleEntry entry,
    List<AuctionVehicleEntry> entries,
  ) {
    final vehicle = entry.vehicle;
    return StudioCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xfff2e5dc),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'NO. ${vehicle.number}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xffac5639),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Edit vehicle ${vehicle.number}',
                onPressed: _busy
                    ? null
                    : () => _openVehicleForm(entries, entry: entry),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Delete vehicle ${vehicle.number}',
                onPressed: _busy ? null : () => _deleteVehicle(entry),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${vehicle.vehicleType}  •  ${vehicle.year}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            vehicle.vin,
            style: const TextStyle(fontSize: 11, color: StudioColors.muted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Color', vehicle.color),
              _chip('Owner', vehicle.owner),
              if (vehicle.mileage.isNotEmpty) _chip('Mileage', vehicle.mileage),
              if (vehicle.redLight.isNotEmpty)
                _chip('Red light', _currency(vehicle.redLight)),
              if (vehicle.greenLight.isNotEmpty)
                _chip('Green light', _currency(vehicle.greenLight)),
              if (vehicle.priceUsd.isNotEmpty)
                _chip('Price', _currency(vehicle.priceUsd)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xfff5f5f2),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: StudioColors.line),
    ),
    child: Text(
      '$label: $value',
      style: const TextStyle(fontSize: 10, color: StudioColors.muted),
    ),
  );

  String _currency(String value) {
    final amount = int.tryParse(
      value.trim().replaceAll(r'$', '').replaceAll(',', '').replaceAll(' ', ''),
    );
    if (amount == null) return value;
    final digits = amount.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
    }
    return '${amount < 0 ? '-' : ''}\$${groups.join(',')}';
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<AuctionVehicleEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: StudioCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: StudioColors.muted,
                  ),
                  const SizedBox(height: 12),
                  const Text('Could not load auction vehicles.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final entries = snapshot.data!;
        final visible = _filtered(entries);
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 880;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                wide ? 28 : 16,
                16,
                wide ? 28 : 16,
                28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: StudioHeading(
                          title: 'Auction\nvehicle list.',
                          subtitle:
                              'Add sale details for each vehicle and export a ready-to-share Excel list.',
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 20),
                        _summary(entries.length),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const StudioBadge(
                        label: 'AUCTION INVENTORY',
                        icon: Icons.gavel_outlined,
                      ),
                      const Spacer(),
                      Text(
                        '${visible.length} of ${entries.length} vehicle${entries.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: StudioColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _toolbar(entries, wide),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    _empty(entries)
                  else if (wide)
                    _table(visible)
                  else
                    _cards(visible),
                ],
              ),
            );
          },
        );
      },
    );
    if (widget.embedded) return body;
    return StudioShell(
      section: 'Auction List',
      busy: _busy,
      onEditor: () => Navigator.of(context).popUntil((route) => route.isFirst),
      child: body,
    );
  }
}

class _AuctionVehicleForm extends StatefulWidget {
  final AuctionVehicle initial;
  final Set<String> usedNumbers;
  final bool editing;

  const _AuctionVehicleForm({
    required this.initial,
    required this.usedNumbers,
    required this.editing,
  });

  @override
  State<_AuctionVehicleForm> createState() => _AuctionVehicleFormState();
}

class _AuctionVehicleFormState extends State<_AuctionVehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    'number': TextEditingController(text: widget.initial.number),
    'vin': TextEditingController(text: widget.initial.vin),
    'vehicleType': TextEditingController(text: widget.initial.vehicleType),
    'year': TextEditingController(text: widget.initial.year),
    'mileage': TextEditingController(text: widget.initial.mileage),
    'color': TextEditingController(text: widget.initial.color),
    'owner': TextEditingController(text: widget.initial.owner),
    'redLight': TextEditingController(text: widget.initial.redLight),
    'greenLight': TextEditingController(text: widget.initial.greenLight),
    'priceUsd': TextEditingController(text: widget.initial.priceUsd),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _number(String? value) {
    final required = _required(value, 'No.');
    if (required != null) return required;
    final number = int.tryParse(value!.trim());
    if (number == null || number <= 0) return 'Enter a positive whole number.';
    if (widget.usedNumbers.contains(value.trim())) {
      return 'This No. is already in the auction list.';
    }
    return null;
  }

  String? _year(String? value) {
    final required = _required(value, 'Year');
    if (required != null) return required;
    final year = int.tryParse(value!.trim());
    if (year == null || year < 1886 || year > 2100) {
      return 'Enter a valid four-digit year.';
    }
    return null;
  }

  String? _vin(String? value) {
    final required = _required(value, 'VIN');
    if (required != null) return required;
    if (value!.trim().length != 17) return 'A VIN must contain 17 characters.';
    return null;
  }

  String? _wholeDollar(String? value, String label) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value
        .trim()
        .replaceAll(r'$', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    final amount = int.tryParse(cleaned);
    if (amount == null || amount < 0) {
      return 'Enter a whole-dollar amount of 0 or more.';
    }
    return null;
  }

  String? _mileage(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '').replaceAll(' ', '');
    final mileage = int.tryParse(cleaned);
    if (mileage == null || mileage < 0) {
      return 'Enter a whole-number mileage of 0 or more.';
    }
    return null;
  }

  String _value(String key) => _controllers[key]!.text.trim();

  String _wholeDollarValue(String key) =>
      _value(key).replaceAll(r'$', '').replaceAll(',', '').replaceAll(' ', '');

  String _wholeNumberValue(String key) =>
      _value(key).replaceAll(',', '').replaceAll(' ', '');

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      AuctionVehicle(
        number: _value('number'),
        vin: _value('vin').toUpperCase(),
        vehicleType: _value('vehicleType'),
        year: _value('year'),
        mileage: _wholeNumberValue('mileage'),
        color: _value('color'),
        owner: _value('owner'),
        redLight: _wholeDollarValue('redLight'),
        greenLight: _wholeDollarValue('greenLight'),
        priceUsd: _wholeDollarValue('priceUsd'),
      ),
    );
  }

  Widget _field({
    required String key,
    required String label,
    required String hint,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.words,
    int maxLength = 60,
    bool currency = false,
    bool isRequired = true,
  }) => TextFormField(
    controller: _controllers[key],
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    keyboardType: keyboardType,
    textCapitalization: capitalization,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: isRequired ? '$label *' : '$label (optional)',
      hintText: hint,
      prefixText: currency ? '\$ ' : null,
      counterText: '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fields = [
      _field(
        key: 'number',
        label: 'No.',
        hint: '1',
        validator: _number,
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 8,
      ),
      _field(
        key: 'vin',
        label: 'VIN',
        hint: 'JTDKN3DU0A0231040',
        validator: _vin,
        capitalization: TextCapitalization.characters,
        maxLength: 17,
      ),
      _field(
        key: 'vehicleType',
        label: 'Vehicle Type',
        hint: 'Prius',
        validator: (value) => _required(value, 'Vehicle Type'),
      ),
      _field(
        key: 'year',
        label: 'Year',
        hint: '2010',
        validator: _year,
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 4,
      ),
      _field(
        key: 'mileage',
        label: 'Mileage',
        hint: '52,000',
        validator: _mileage,
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 12,
        isRequired: false,
      ),
      _field(
        key: 'color',
        label: 'Color',
        hint: 'White',
        validator: (value) => _required(value, 'Color'),
        maxLength: 30,
      ),
      _field(
        key: 'owner',
        label: 'Owner',
        hint: 'Outside',
        validator: (value) => _required(value, 'Owner'),
      ),
      _field(
        key: 'redLight',
        label: 'Red Light Price',
        hint: '6500',
        validator: (value) => _wholeDollar(value, 'Red Light Price'),
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 12,
        currency: true,
        isRequired: false,
      ),
      _field(
        key: 'greenLight',
        label: 'Green Light Price',
        hint: '7000',
        validator: (value) => _wholeDollar(value, 'Green Light Price'),
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 12,
        currency: true,
        isRequired: false,
      ),
      _field(
        key: 'priceUsd',
        label: 'Price (USD)',
        hint: '6500',
        validator: (value) => _wholeDollar(value, 'Price (USD)'),
        keyboardType: TextInputType.number,
        capitalization: TextCapitalization.none,
        maxLength: 12,
        currency: true,
        isRequired: false,
      ),
    ];
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .92,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Material(
              color: const Color(0xfff8f8f5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xfff2e5dc),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.directions_car_filled_outlined,
                            color: StudioColors.accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.editing
                                    ? 'Edit auction vehicle'
                                    : 'Add auction vehicle',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Fields marked * are required. Mileage and prices are optional.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: StudioColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                      child: Form(
                        key: _formKey,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              for (final field in fields)
                                SizedBox(
                                  width: constraints.maxWidth >= 600
                                      ? (constraints.maxWidth - 14) / 2
                                      : constraints.maxWidth,
                                  child: field,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: StudioColors.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _submit,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: Text(
                              widget.editing ? 'Save changes' : 'Add vehicle',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
