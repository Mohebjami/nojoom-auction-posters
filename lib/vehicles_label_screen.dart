import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';

import 'auction_vehicle.dart';
import 'poster.dart';
import 'poster_history.dart';
import 'studio_ui.dart';
import 'vehicle_number_sort.dart';

class _VehicleLabelEntry {
  final int id;
  final AuctionVehicle vehicle;
  final bool isAuctionVehicle;

  const _VehicleLabelEntry({
    required this.id,
    required this.vehicle,
    required this.isAuctionVehicle,
  });
}

class VehiclesLabelScreen extends StatefulWidget {
  final PosterHistory history;
  const VehiclesLabelScreen({super.key, required this.history});

  @override
  State<VehiclesLabelScreen> createState() => _VehiclesLabelScreenState();
}

class _VehiclesLabelScreenState extends State<VehiclesLabelScreen> {
  static final _yearPattern = RegExp(r'\b(?:19|20)\d{2}\b');
  static const _persianColors = <String, String>{
    'black': 'سیاه',
    'white': 'سفید',
    'silver': 'نقره‌ای',
    'gray': 'خاکستری',
    'grey': 'خاکستری',
    'red': 'سرخ',
    'blue': 'آبی',
    'green': 'سبز',
    'yellow': 'زرد',
    'brown': 'قهوه‌ای',
    'beige': 'بژ',
    'gold': 'طلایی',
    'champagne': 'شامپاینی',
    'pearl': 'مرواریدی',
    'orange': 'نارنجی',
    'maroon': 'عنابی',
    'purple': 'بنفش',
    'pink': 'صورتی',
    'navy': 'سرمه‌ای',
    'ash': 'طوسی',
    'metallic': 'متالیک',
    'dark': 'تیره',
    'light': 'روشن',
  };

  late Future<List<_VehicleLabelEntry>> _entries;
  Future<String>? _template;
  bool _busy = false;
  bool _numberAscending = true;

  @override
  void initState() {
    super.initState();
    _entries = _loadVehicles();
  }

  Future<List<_VehicleLabelEntry>> _loadVehicles() async {
    final saved = await widget.history.list();
    final auction = await widget.history.listAuctionVehicles();
    final all = <_VehicleLabelEntry>[
      for (final entry in saved)
        _VehicleLabelEntry(
          id: entry.id,
          isAuctionVehicle: false,
          vehicle: AuctionVehicle(
            number: entry.vehicle.number,
            vin: entry.vehicle.vin,
            // Posters store brand/year in title and the model in model.
            // Older label edits stored these fields in the opposite order.
            vehicleType:
                _yearPattern.hasMatch(entry.vehicle.model) &&
                    entry.vehicle.model
                        .replaceAll(_yearPattern, '')
                        .trim()
                        .isEmpty
                ? entry.vehicle.title
                : entry.vehicle.model,
            year:
                _yearPattern
                    .firstMatch('${entry.vehicle.title} ${entry.vehicle.model}')
                    ?.group(0) ??
                '',
            color: entry.vehicle.color,
            priceUsd: entry.vehicle.price,
          ),
        ),
      for (final entry in auction)
        _VehicleLabelEntry(
          id: entry.id,
          vehicle: entry.vehicle,
          isAuctionVehicle: true,
        ),
    ];
    final seen = <String>{};
    return all.where((entry) {
      final vehicle = entry.vehicle;
      final key =
          '${vehicle.number.trim().toLowerCase()}|${vehicle.vin.trim().toLowerCase()}';
      return key == '|' || seen.add(key);
    }).toList();
  }

  void _reload() => setState(() {
    _entries = _loadVehicles();
  });

  Future<String> _loadTemplate() =>
      _template ??= rootBundle.loadString('assets/vehicles_label.svg');

  Future<void> _deleteLabel(_VehicleLabelEntry entry) async {
    if (_busy) return;
    final vehicle = entry.vehicle;
    final recordType = entry.isAuctionVehicle
        ? 'auction vehicle'
        : 'saved poster';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StudioConfirmDialog(
        title: 'Delete label and saved item?',
        message:
            'Remove the label for No. ${vehicle.number}? This will also delete the associated $recordType.',
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
      if (entry.isAuctionVehicle) {
        await widget.history.deleteAuctionVehicle(entry.id);
      } else {
        await widget.history.delete(entry.id);
      }
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Label and saved item deleted.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete label: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAllLabels() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const StudioConfirmDialog(
        title: 'Delete all vehicle labels?',
        message:
            'This also permanently deletes all saved posters and auction vehicles shown in this list, including their poster photos.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Delete all',
        icon: Icons.delete_sweep_outlined,
        confirmIcon: Icons.delete_sweep_outlined,
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final savedPosters = await widget.history.list();
      final auctionVehicles = await widget.history.listAuctionVehicles();
      await widget.history.deleteMany(savedPosters.map((entry) => entry.id));
      for (final entry in auctionVehicles) {
        await widget.history.deleteAuctionVehicle(entry.id);
      }
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All vehicle labels deleted.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete all labels: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editLabel(_VehicleLabelEntry entry) async {
    if (_busy) return;
    final queue = [
      entry,
      ...followingVehicleEntries(
        await _entries,
        entry,
        numberOf: (item) => item.vehicle.number,
        sameEntry: (item, current) =>
            item.id == current.id &&
            item.isAuctionVehicle == current.isAuctionVehicle,
      ),
    ];
    for (final current in queue) {
      if (!mounted || !await _editOneLabel(current)) return;
    }
  }

  Future<bool> _editOneLabel(_VehicleLabelEntry entry) async {
    final vehicle = entry.vehicle;
    final year = vehicle.year.trim().isNotEmpty
        ? vehicle.year.trim()
        : _yearPattern.firstMatch(vehicle.vehicleType)?.group(0) ?? '';
    final updated = await showDialog<AuctionVehicle>(
      context: context,
      builder: (context) =>
          _VehicleLabelEditDialog(initial: vehicle.copyWith(year: year)),
    );
    if (updated == null || !mounted) return false;

    setState(() => _busy = true);
    try {
      if (entry.isAuctionVehicle) {
        await widget.history.updateAuctionVehicle(
          entry.id,
          vehicle.copyWith(
            number: updated.number,
            vin: updated.vin,
            vehicleType: updated.vehicleType,
            year: updated.year,
            color: updated.color,
            priceUsd: updated.priceUsd,
          ),
        );
      } else {
        final draft = await widget.history.load(entry.id);
        final originalBrandYear = draft.vehicle.title;
        final brandYear = _yearPattern.hasMatch(originalBrandYear)
            ? originalBrandYear.replaceAll(_yearPattern, updated.year)
            : [
                originalBrandYear,
                updated.year,
              ].where((part) => part.trim().isNotEmpty).join(' ');
        await widget.history.save(
          VehicleDetails(
            number: updated.number,
            title: brandYear.trim(),
            model: updated.vehicleType,
            price: updated.priceUsd,
            color: updated.color,
            vin: updated.vin,
          ),
          draft.photos,
          id: entry.id,
          templateSvg: draft.templateSvg,
          templateName: draft.templateName,
          section: draft.section,
        );
      }
      if (!mounted) return false;
      _reload();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vehicle label updated.')));
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update label: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _vehicleType(String input) {
    return input
        .replaceAll(_yearPattern, '')
        .replaceAll(
          RegExp(r'\b(?:Priuc|Prius)\s+C\b', caseSensitive: false),
          'پرویوس C',
        )
        .replaceAll(
          RegExp(r'\b(?:Priuc|Prius)\b', caseSensitive: false),
          'پرویوس',
        )
        .replaceAll(
          RegExp(r'\b(?:Crolla|Corolla)\b', caseSensitive: false),
          'کرولا',
        )
        .replaceAll(RegExp(r'\b4Runner\b', caseSensitive: false), 'فوررنر')
        .replaceAll(RegExp(r'\blexus\b', caseSensitive: false), 'لکسوس')
        .replaceAll(RegExp(r'\bLimited\b', caseSensitive: false), 'لمیتد')
        .replaceAll(RegExp(r'\b(?:Toyota|Toytoa)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,;/|–—-]+|[,;/|–—-]+$'), '')
        .trim();
  }

  String _svg(AuctionVehicle vehicle, String source) {
    final doc = XmlDocument.parse(source);
    final sourceType = vehicle.vehicleType;
    final year = vehicle.year.trim().isNotEmpty
        ? vehicle.year.trim()
        : _yearPattern.firstMatch(sourceType)?.group(0) ?? '';
    final values = {
      'field-title': _vehicleType(sourceType),
      'field-vin': vehicle.vin,
      'field-price': vehicle.priceUsd,
      'field-color': _persianColor(vehicle.color),
      'field-year': year,
      'main-number': vehicle.number,
    };
    for (final text in doc.findAllElements('text')) {
      final id = text.getAttribute('id');
      if (id != null && values.containsKey(id)) {
        text.children
          ..clear()
          ..add(XmlText(values[id]!));
      }
    }
    return doc.toXmlString(pretty: true);
  }

  String _persianColor(String input) {
    final color = input.trim();
    if (color.isEmpty) return color;
    return color.replaceAllMapped(RegExp(r'[A-Za-z]+'), (match) {
      final word = match.group(0)!;
      return _persianColors[word.toLowerCase()] ?? _latinToPersian(word);
    });
  }

  String _latinToPersian(String input) {
    final value = input
        .toLowerCase()
        .replaceAll('ph', 'f')
        .replaceAll('sh', 'ش')
        .replaceAll('ch', 'چ')
        .replaceAll('th', 'ث')
        .replaceAll('kh', 'خ')
        .replaceAll('gh', 'غ')
        .replaceAll('oo', 'و')
        .replaceAll('ee', 'ی')
        .replaceAll('ai', 'ای')
        .replaceAll('ay', 'ی')
        .replaceAll('ou', 'و')
        .replaceAll('ck', 'ک');
    final result = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      final next = i + 1 < value.length ? value[i + 1] : '';
      result.write(switch (char) {
        'a' => 'ا',
        'b' => 'ب',
        'c' => next.isNotEmpty && 'eiy'.contains(next) ? 'س' : 'ک',
        'd' => 'د',
        'e' => 'ی',
        'f' => 'ف',
        'g' => next.isNotEmpty && 'eiy'.contains(next) ? 'ج' : 'گ',
        'h' => 'ه',
        'i' => 'ی',
        'j' => 'ج',
        'k' => 'ک',
        'l' => 'ل',
        'm' => 'م',
        'n' => 'ن',
        'o' => 'و',
        'p' => 'پ',
        'q' => 'ق',
        'r' => 'ر',
        's' => 'س',
        't' => 'ت',
        'u' => 'و',
        'v' => 'و',
        'w' => 'و',
        'x' => 'اکس',
        'y' => 'ی',
        'z' => 'ز',
        '0' => '۰',
        '1' => '۱',
        '2' => '۲',
        '3' => '۳',
        '4' => '۴',
        '5' => '۵',
        '6' => '۶',
        '7' => '۷',
        '8' => '۸',
        '9' => '۹',
        _ => char,
      });
    }
    return result.toString();
  }

  Widget _labelPreview(AuctionVehicle vehicle, String year) {
    const gold = Color(0xffbd9136);
    const paper = Color(0xfffffdf7);
    final rows = <(String, String)>[
      ('نوع موتر', _vehicleType(vehicle.vehicleType)),
      ('شاسی', vehicle.vin),
      ('قیمت', vehicle.priceUsd),
      ('رنگ', _persianColor(vehicle.color)),
      ('مدل', year),
    ];
    return Container(
      width: 116,
      height: 148,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: gold, width: 1.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          const Text(
            'NOJOOM CARS AUCTION',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 5.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .35,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 23,
            width: 42,
            decoration: BoxDecoration(
              color: const Color(0xff11110f),
              border: Border.all(color: gold, width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Text(
              vehicle.number,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xffffdf84),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: paper,
                border: Border.all(color: gold, width: .8),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < rows.length; index++)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: index == rows.length - 1
                              ? null
                              : const Border(
                                  bottom: BorderSide(
                                    color: Color(0xffd9c596),
                                    width: .5,
                                  ),
                                ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 27,
                              child: Text(
                                rows[index].$1,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  color: Color(0xff695128),
                                  fontSize: 5.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                rows[index].$2,
                                textDirection: index == 0
                                    ? TextDirection.rtl
                                    : null,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xff171813),
                                  fontFamily: index == 2 ? 'Arial' : null,
                                  fontSize: index == 2 ? 9 : 5.8,
                                  fontWeight: index == 2
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(AuctionVehicle vehicle) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = _svg(vehicle, await _loadTemplate());
      final safeNumber = vehicle.number.trim().replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final name =
          'vehicle_label_${safeNumber.isEmpty ? 'vehicle' : safeNumber}.svg';
      await _saveExport(utf8.encode(data), name, 'image/svg+xml');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export label: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveExport(
    List<int> bytes,
    String name,
    String mimeType,
  ) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          subject: name,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } else {
      final location = await getSaveLocation(suggestedName: name);
      if (location == null) return;
      await XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: mimeType,
        name: name,
      ).saveTo(location.path);
    }
  }

  Future<void> _exportAll(List<_VehicleLabelEntry> entries) async {
    if (_busy || entries.isEmpty) return;
    setState(() => _busy = true);
    try {
      final template = await _loadTemplate();
      final archive = Archive();
      for (var index = 0; index < entries.length; index++) {
        final vehicle = entries[index].vehicle;
        final safeNumber = vehicle.number.trim().replaceAll(
          RegExp(r'[^A-Za-z0-9_-]'),
          '_',
        );
        archive.add(
          ArchiveFile.string(
            'vehicle_label_${index + 1}_${safeNumber.isEmpty ? 'vehicle' : safeNumber}.svg',
            _svg(vehicle, template),
          ),
        );
      }
      await _saveExport(
        ZipEncoder().encodeBytes(archive),
        'vehicle_labels.zip',
        'application/zip',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export labels: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_VehicleLabelEntry>>(
    future: _entries,
    builder: (context, snapshot) {
      final entries = [...?snapshot.data];
      entries.sort((a, b) {
        final comparison = compareVehicleNumbers(
          a.vehicle.number,
          b.vehicle.number,
          ascending: _numberAscending,
        );
        if (comparison != 0) return comparison;
        final sourceComparison = (a.isAuctionVehicle ? 1 : 0).compareTo(
          b.isAuctionVehicle ? 1 : 0,
        );
        return sourceComparison != 0 ? sourceComparison : a.id.compareTo(b.id);
      });
      final canShowEntries =
          !snapshot.hasError &&
          snapshot.connectionState == ConnectionState.done &&
          entries.isNotEmpty;

      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const StudioHeading(
                          title: 'Vehicle labels.',
                          subtitle:
                              'Print-ready labels. Every vehicle, clearly presented.',
                        ),
                        const SizedBox(height: 20),
                        if (canShowEntries)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<bool>(
                                    value: _numberAscending,
                                    items: const [
                                      DropdownMenuItem(
                                        value: true,
                                        child: Text('No.: low to high'),
                                      ),
                                      DropdownMenuItem(
                                        value: false,
                                        child: Text('No.: high to low'),
                                      ),
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              setState(
                                                () => _numberAscending = value,
                                              );
                                            }
                                          },
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _exportAll(entries),
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Export all labels (ZIP)'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _deleteAllLabels,
                                  icon: const Icon(Icons.delete_sweep_outlined),
                                  label: const Text('Delete all'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xffac5639),
                                    side: const BorderSide(
                                      color: Color(0xffac5639),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }

                if (!canShowEntries) {
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Could not load vehicle labels.'),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return const StudioCard(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No saved vehicles yet. Add vehicles in Auction List.',
                      ),
                    ),
                  );
                }

                final entry = entries[index - 1];
                final vehicle = entry.vehicle;
                final year = vehicle.year.trim().isNotEmpty
                    ? vehicle.year.trim()
                    : _yearPattern.firstMatch(vehicle.vehicleType)?.group(0) ??
                          '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: StudioCard(
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final details = Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _labelPreview(vehicle, year),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No. ${vehicle.number}  ·  ${_vehicleType(vehicle.vehicleType)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    [year, _persianColor(vehicle.color)]
                                        .where((value) => value.isNotEmpty)
                                        .join('  ·  '),
                                    style: const TextStyle(
                                      color: StudioColors.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    vehicle.vin,
                                    style: const TextStyle(
                                      color: StudioColors.muted,
                                      fontSize: 12,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        final actions = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _export(vehicle),
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 18,
                              ),
                              label: const Text('Export SVG'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _editLabel(entry),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit'),
                            ),
                            IconButton.outlined(
                              tooltip: 'Delete label',
                              onPressed: _busy
                                  ? null
                                  : () => _deleteLabel(entry),
                              style: IconButton.styleFrom(
                                foregroundColor: const Color(0xffac5639),
                                minimumSize: const Size(48, 48),
                              ),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                              ),
                            ),
                          ],
                        );
                        if (constraints.maxWidth < 700) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              details,
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(height: 1),
                              ),
                              actions,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: details),
                            const SizedBox(width: 24),
                            actions,
                          ],
                        );
                      },
                    ),
                  ),
                );
              }, childCount: canShowEntries ? entries.length + 1 : 2),
            ),
          ),
          if (_busy) const SliverToBoxAdapter(child: LinearProgressIndicator()),
        ],
      );
    },
  );
}

class _VehicleLabelEditDialog extends StatefulWidget {
  final AuctionVehicle initial;

  const _VehicleLabelEditDialog({required this.initial});

  @override
  State<_VehicleLabelEditDialog> createState() =>
      _VehicleLabelEditDialogState();
}

class _VehicleLabelEditDialogState extends State<_VehicleLabelEditDialog> {
  late final _controllers = <String, TextEditingController>{
    'number': TextEditingController(text: widget.initial.number),
    'vehicleType': TextEditingController(text: widget.initial.vehicleType),
    'year': TextEditingController(text: widget.initial.year),
    'vin': TextEditingController(text: widget.initial.vin),
    'priceUsd': TextEditingController(text: widget.initial.priceUsd),
    'color': TextEditingController(text: widget.initial.color),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(String key, String label, {TextInputType? keyboardType}) =>
      TextField(
        controller: _controllers[key],
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
      );

  void _save() {
    String value(String key) => _controllers[key]!.text.trim();
    Navigator.pop(
      context,
      widget.initial.copyWith(
        number: value('number'),
        vehicleType: value('vehicleType'),
        year: value('year'),
        vin: value('vin'),
        priceUsd: value('priceUsd'),
        color: value('color'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit vehicle label'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _field('number', 'No.')),
                const SizedBox(width: 14),
                Expanded(
                  child: _field(
                    'year',
                    'Year / Model',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            _field('vehicleType', 'Vehicle type'),
            _field('vin', 'Chassis / VIN'),
            Row(
              children: [
                Expanded(child: _field('priceUsd', 'Price')),
                const SizedBox(width: 14),
                Expanded(child: _field('color', 'Color')),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save changes')),
    ],
  );
}
