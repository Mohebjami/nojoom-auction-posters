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
      'ref',
      'reference',
      'ref no',
      'top-left number',
      'top left number',
    },
    'vin': {
      'vin',
      'stock id',
      'stock / id',
      'stock',
      'stockid',
      'vehicle id',
      'id',
    },
    'title': {'title', 'vehicle', 'vehicle name', 'name', 'car'},
    'model': {'model', 'year', 'vehicle model', 'make', 'make model'},
    'price': {'price', 'price usd', 'price (usd)', 'usd', 'amount'},
    'color': {'color', 'colour', 'vehicle color'},
  };

  static Future<List<VehicleDetails>> fromBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    final name = fileName.toLowerCase();
    final data = name.endsWith('.xlsx')
        ? _excelRows(bytes)
        : _delimitedRows(utf8.decode(bytes, allowMalformed: true));

    if (data.isEmpty) {
      return const [];
    }

    final headerRow = data.first.map((cell) => _clean(cell)).toList();
    final indexMap = _headerIndex(headerRow);
    final results = <VehicleDetails>[];

    for (final row in data.skip(1)) {
      if (row.every((cell) => _clean(cell).isEmpty)) continue;

      final vehicle = VehicleDetails(
        number: _cellValue(row, indexMap['number']),
        title: _cellValue(row, indexMap['title']),
        model: _cellValue(row, indexMap['model']),
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

  static List<List<String>> _excelRows(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
    final sharedStrings = sharedStringsFile == null
        ? const <String>[]
        : _sharedStrings(
            XmlDocument.parse(utf8.decode(sharedStringsFile.readBytes()!)),
          );
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml');
    if (sheetFile == null) {
      throw const FormatException('The XLSX file has no first worksheet.');
    }

    final document = XmlDocument.parse(utf8.decode(sheetFile.readBytes()!));
    return document.findAllElements('row').map((row) {
      final cells = <String>[];
      for (final cell in row.findElements('c')) {
        final reference = cell.getAttribute('r') ?? '';
        final column = _columnIndex(reference);
        while (cells.length <= column) {
          cells.add('');
        }

        final type = cell.getAttribute('t');
        final value = cell.getElement('v')?.innerText ?? '';
        cells[column] = type == 's'
            ? (int.tryParse(value) != null &&
                      int.parse(value) < sharedStrings.length
                  ? sharedStrings[int.parse(value)]
                  : value)
            : type == 'inlineStr'
            ? cell.getElement('is')?.innerText ?? ''
            : value;
      }
      return cells;
    }).toList();
  }

  static List<String> _sharedStrings(XmlDocument document) {
    return document.findAllElements('si').map((item) {
      return item.findAllElements('t').map((text) => text.innerText).join();
    }).toList();
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
        if (entry.value.contains(key)) {
          result[entry.key] = i;
          break;
        }
      }
    }
    return result;
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
