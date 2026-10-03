import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'poster.dart';

class VehicleListImporter {
  static final Map<String, Set<String>> _headerAliases = {
    'number': {
      'number',
      'no',
      'no.',
      's no',
      'sr no',
      'sl no',
      'serial no',
      'serial number',
      'ref',
      'reference',
      'ref no',
      'ref number',
      'top-left number',
      'top left number',
      'auction number',
      'vehicle number',
      'vehicle no',
      'lot',
      'lot no',
      'lot number',
    },
    'vin': {
      'vin',
      'stock id',
      'stock / id',
      'stock',
      'stockid',
      'stock number',
      'stock no',
      'vehicle id',
      'vehicle identification number',
      'chassis number',
      'chassis no',
      'chassis',
      'id',
    },
    'title': {
      'title',
      'vehicle',
      'vehicle name',
      'vehicle type',
      'description',
      'vehicle description',
      'vehicle details',
      'name',
      'car',
      'type',
    },
    'brandYear': {'brand and year', 'brand year', 'make and year', 'make year'},
    'model': {
      'model',
      'model name',
      'year',
      'model year',
      'manufacture year',
      'vehicle model',
      'make',
      'make model',
      'make and model',
    },
    'brand': {'brand', 'vehicle brand', 'manufacturer', 'make'},
    'price': {
      'price',
      'price usd',
      'price (usd)',
      'usd',
      'amount',
      'asking price',
      'starting price',
      'price in usd',
      'usd price',
      'sale price',
      'auction price',
      'price sold',
    },
    'color': {
      'color',
      'colour',
      'vehicle color',
      'vehicle colour',
      'body color',
      'body colour',
      'exterior color',
    },
  };

  static Future<List<VehicleDetails>> fromBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    final name = fileName.toLowerCase();
    final data = name.endsWith('.xlsx') || _looksLikeZip(bytes)
        ? _excelRows(bytes)
        : _delimitedRows(utf8.decode(bytes, allowMalformed: true));

    if (data.isEmpty) {
      return const [];
    }

    // XLSX files exported by this app have a title and date before the table
    // header. CSV files may also contain leading notes, so locate the row
    // that contains the most known headers instead of assuming row zero.
    final headerIndex = _findHeaderRow(data);
    if (headerIndex == null) {
      return const [];
    }

    final headerRow = data[headerIndex].map((cell) => _clean(cell)).toList();
    final indexMap = _headerIndex(headerRow);
    final vehicleTypeIndex = _vehicleTypeColumnIndex(headerRow);
    final results = <VehicleDetails>[];

    for (final row in data.skip(headerIndex + 1)) {
      if (row.every((cell) => _clean(cell).isEmpty)) continue;

      final vehicle = VehicleDetails(
        number: _cellValue(row, indexMap['number']),
        title: _posterBrandYearValue(
          row,
          headerRow,
          vehicleTypeIndex: vehicleTypeIndex,
        ),
        model: _cellValue(row, vehicleTypeIndex),
        price: _cellValue(row, indexMap['price']),
        color: _cellValue(row, indexMap['color']),
        vin: _cellValue(row, indexMap['vin']),
      );

      if (vehicle.number.isEmpty &&
          vehicle.title.isEmpty &&
          vehicle.model.isEmpty &&
          vehicle.price.isEmpty &&
          vehicle.color.isEmpty &&
          vehicle.vin.isEmpty) {
        continue;
      }

      results.add(vehicle);
    }

    return results;
  }

  static int? _vehicleTypeColumnIndex(List<String> headers) {
    final modelIndex = _explicitModelColumnIndex(headers);
    if (_firstHeaderIndex(headers, _headerAliases['brandYear']!) != null &&
        modelIndex != null) {
      return modelIndex;
    }

    // Prefer an explicitly named Vehicle Type column over generic columns
    // such as Vehicle or Description.
    for (var i = 0; i < headers.length; i++) {
      if (_normalizeHeader(headers[i]) == 'vehicle type') return i;
    }

    // Legacy sheets use Vehicle Type for the model and Model for brand/year.
    final typeHeaders = _headerAliases['title']!;
    for (var i = 0; i < headers.length; i++) {
      if (typeHeaders.contains(_normalizeHeader(headers[i]))) return i;
    }
    return modelIndex;
  }

  static int? _explicitModelColumnIndex(List<String> headers) {
    const modelHeaders = {
      'model',
      'model name',
      'vehicle model',
      'vehicle model name',
      'make model',
      'make and model',
    };
    for (var i = 0; i < headers.length; i++) {
      if (modelHeaders.contains(_normalizeHeader(headers[i]))) return i;
    }
    return null;
  }

  static String _posterBrandYearValue(
    List<String> row,
    List<String> headers, {
    required int? vehicleTypeIndex,
  }) {
    final combinedIndex = _firstHeaderIndex(
      headers,
      _headerAliases['brandYear']!,
    );
    final combined = _cellValue(row, combinedIndex);
    if (combined.isNotEmpty) return combined;

    final explicitModelIndex = _explicitModelColumnIndex(headers);
    if (explicitModelIndex != null && explicitModelIndex != vehicleTypeIndex) {
      final model = _cellValue(row, explicitModelIndex);
      if (model.isNotEmpty) return model;
    }

    final brandIndex = _firstHeaderIndex(headers, _headerAliases['brand']!);
    final yearIndex = _firstHeaderIndex(headers, const {
      'year',
      'model year',
      'manufacture year',
    });
    final brand = _cellValue(row, brandIndex);
    var year = _cellValue(row, yearIndex);
    if (year.isEmpty && vehicleTypeIndex != null) {
      final type = _cellValue(row, vehicleTypeIndex);
      year = RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(type)?.group(0) ?? '';
    }

    return [brand, year].where((part) => part.isNotEmpty).join(' ');
  }

  static int? _firstHeaderIndex(List<String> headers, Set<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(_normalizeHeader(headers[i]))) return i;
    }
    return null;
  }

  static List<List<String>> _excelRows(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
    final sharedStrings = sharedStringsFile == null
        ? const <String>[]
        : _sharedStrings(
            XmlDocument.parse(utf8.decode(sharedStringsFile.readBytes()!)),
          );
    final worksheetFiles = archive.files.where(
      (file) =>
          file.name.startsWith('xl/worksheets/') && file.name.endsWith('.xml'),
    );
    if (worksheetFiles.isEmpty) {
      throw const FormatException('The XLSX file has no worksheets.');
    }

    List<List<String>>? bestRows;
    var bestHeaderCount = 0;
    for (final sheetFile in worksheetFiles) {
      final document = XmlDocument.parse(utf8.decode(sheetFile.readBytes()!));
      final rows = _worksheetRows(document, sharedStrings);
      final headerCount = rows
          .map((row) => _headerIndex(row).length)
          .fold(0, (best, count) => count > best ? count : best);
      if (headerCount > bestHeaderCount) {
        bestRows = rows;
        bestHeaderCount = headerCount;
      }
    }

    return bestRows ?? const [];
  }

  static List<List<String>> _worksheetRows(
    XmlDocument document,
    List<String> sharedStrings,
  ) {
    return _elementsWithLocalName(document, 'row').map((row) {
      final cells = <String>[];
      var nextColumn = 0;
      for (final cell in _childrenWithLocalName(row, 'c')) {
        final reference = cell.getAttribute('r') ?? '';
        final column = reference.isEmpty ? nextColumn : _columnIndex(reference);
        while (cells.length <= column) {
          cells.add('');
        }

        final type = cell.getAttribute('t');
        final value = _childWithLocalName(cell, 'v')?.innerText ?? '';
        cells[column] = _excelCellValue(
          cell,
          type: type,
          value: value,
          sharedStrings: sharedStrings,
        );
        nextColumn = column + 1;
      }
      return cells;
    }).toList();
  }

  static String _excelCellValue(
    XmlElement cell, {
    required String? type,
    required String value,
    required List<String> sharedStrings,
  }) {
    if (type == 's') {
      final index = int.tryParse(value);
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
    }
    if (type == 'inlineStr') {
      return _childWithLocalName(cell, 'is')?.innerText ?? '';
    }
    return value;
  }

  static bool _looksLikeZip(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  }

  static List<String> _sharedStrings(XmlDocument document) {
    return _elementsWithLocalName(document, 'si').map((item) {
      return _elementsWithLocalName(
        item,
        't',
      ).map((text) => text.innerText).join();
    }).toList();
  }

  static Iterable<XmlElement> _elementsWithLocalName(
    XmlNode node,
    String localName,
  ) {
    return node.descendants.whereType<XmlElement>().where(
      (element) => element.localName == localName,
    );
  }

  static Iterable<XmlElement> _childrenWithLocalName(
    XmlNode node,
    String localName,
  ) {
    return node.children.whereType<XmlElement>().where(
      (element) => element.localName == localName,
    );
  }

  static XmlElement? _childWithLocalName(XmlNode node, String localName) {
    for (final child in _childrenWithLocalName(node, localName)) {
      return child;
    }
    return null;
  }

  static int _columnIndex(String reference) {
    final letters = RegExp(r'^[A-Za-z]+').firstMatch(reference)?.group(0);
    if (letters == null || letters.isEmpty) return 0;
    var result = 0;
    for (final letter in letters.toUpperCase().codeUnits) {
      result = result * 26 + letter - 64;
    }
    return result - 1;
  }

  static List<List<String>> _delimitedRows(String text) {
    final withoutBom = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    final lines = const LineSplitter().convert(withoutBom);
    final rows = <List<String>>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final delimiter = _detectDelimiter(line);
      final cells = _parseDelimitedLine(line, delimiter);
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    return rows;
  }

  static String _detectDelimiter(String line) {
    final candidates = [',', ';', '\t', '|'];
    var best = ',';
    var bestCount = -1;
    for (final candidate in candidates) {
      final count = line.split(candidate).length - 1;
      if (count > bestCount) {
        bestCount = count;
        best = candidate;
      }
    }
    return best;
  }

  static List<String> _parseDelimitedLine(String line, String delimiter) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  static Map<String, int> _headerIndex(List<String> headerCells) {
    final result = <String, int>{};
    for (var i = 0; i < headerCells.length; i++) {
      final key = _normalizeHeader(headerCells[i]);
      if (key.isEmpty) continue;
      for (final entry in _headerAliases.entries) {
        if (entry.value.contains(key) || _matchesHeaderAlias(key, entry.key)) {
          // Prefer the first matching column when a workbook has both a
          // current price and a separate sold/auction price column.
          result.putIfAbsent(entry.key, () => i);
          break;
        }
      }
    }
    return result;
  }

  static bool _matchesHeaderAlias(String key, String field) {
    switch (field) {
      case 'number':
        return key == 'vehicle number' ||
            key == 'vehicle no' ||
            key == 'auction no' ||
            key == 'auction number' ||
            ((key.contains('serial') || key.contains('lot')) &&
                (key.contains('no') || key.contains('number')));
      case 'vin':
        return key == 'vin number' ||
            key.contains('vehicle identification') ||
            key.contains('chassis') ||
            key == 'stock number' ||
            key == 'stock no' ||
            key == 'stock';
      case 'title':
        return key == 'description' ||
            key == 'vehicle description' ||
            key == 'vehicle details';
      case 'price':
        return key == 'sale price' ||
            key == 'auction price' ||
            key == 'price sold' ||
            key.contains('price');
      case 'color':
        return key == 'body color' ||
            key == 'body colour' ||
            key == 'vehicle color' ||
            key == 'vehicle colour' ||
            key.contains('color') ||
            key.contains('colour');
      case 'model':
        return key.contains('year') ||
            key == 'make and model' ||
            key == 'make model';
      default:
        return false;
    }
  }

  static int? _findHeaderRow(List<List<String>> rows) {
    int? bestIndex;
    var bestMatchCount = 0;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final matchCount = _headerIndex(
        rows[rowIndex].map(_clean).toList(),
      ).length;
      if (matchCount > bestMatchCount) {
        bestIndex = rowIndex;
        bestMatchCount = matchCount;
      }
    }

    return bestIndex;
  }

  static String _cellValue(List<dynamic> row, int? index) {
    if (index == null || index >= row.length) return '';
    final value = row[index];
    return _clean(value);
  }

  static String _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _normalizeHeader(String value) {
    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return cleaned;
  }
}
