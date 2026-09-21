import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'auction_vehicle.dart';

/// Builds a self-contained XLSX workbook using the same auction-list layout
/// as the supplied reference: a title and date, the blue auction table, red
/// and green light columns, and blank sale/remarks columns for auction day.
abstract final class AuctionExcelExporter {
  static const _headers = [
    'No.',
    'VIN',
    'Vehicle Type',
    'Year',
    'Mileage',
    'Color',
    'Owner',
    'Red Light',
    'Green Light',
    'Price (USD)',
    'Auction Price\n(Sold)',
    'Remarks',
  ];

  static Uint8List export(List<AuctionVehicleEntry> entries, {DateTime? date}) {
    final exportedAt = date ?? DateTime.now();
    final rows = List<AuctionVehicleEntry>.of(entries)..sort(_compareEntries);
    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypesXml))
      ..add(ArchiveFile.string('_rels/.rels', _rootRelationshipsXml))
      ..add(ArchiveFile.string('docProps/app.xml', _appPropertiesXml))
      ..add(
        ArchiveFile.string(
          'docProps/core.xml',
          _corePropertiesXml(exportedAt.toUtc()),
        ),
      )
      ..add(ArchiveFile.string('xl/workbook.xml', _workbookXml(rows.length)))
      ..add(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _workbookRelationshipsXml,
        ),
      )
      ..add(ArchiveFile.string('xl/styles.xml', _stylesXml))
      ..add(
        ArchiveFile.string(
          'xl/worksheets/sheet1.xml',
          _worksheetXml(rows, exportedAt),
        ),
      )
      ..add(
        ArchiveFile.string('xl/worksheets/sheet2.xml', _sourceSheetXml(rows)),
      );
    return ZipEncoder().encodeBytes(archive, modified: exportedAt);
  }

  static int _compareEntries(AuctionVehicleEntry a, AuctionVehicleEntry b) {
    final aNumber = int.tryParse(a.vehicle.number.trim());
    final bNumber = int.tryParse(b.vehicle.number.trim());
    if (aNumber != null && bNumber != null) {
      final comparison = aNumber.compareTo(bNumber);
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    }
    if (aNumber != null) return -1;
    if (bNumber != null) return 1;
    return a.vehicle.number.toLowerCase().compareTo(
      b.vehicle.number.toLowerCase(),
    );
  }

  static String _worksheetXml(
    List<AuctionVehicleEntry> entries,
    DateTime exportedAt,
  ) {
    final lastRow = 3 + entries.length;
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<dimension ref="A1:L$lastRow"/>'
      '<sheetViews><sheetView workbookViewId="0">'
      '<pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A4" sqref="A4"/>'
      '</sheetView></sheetViews>'
      '<sheetFormatPr defaultRowHeight="13.8"/>'
      '<cols>'
      '<col min="1" max="1" width="3.7" customWidth="1"/>'
      '<col min="2" max="2" width="21" customWidth="1"/>'
      '<col min="3" max="3" width="17.7" customWidth="1"/>'
      '<col min="4" max="4" width="4.9" customWidth="1"/>'
      '<col min="5" max="5" width="10" customWidth="1"/>'
      '<col min="6" max="6" width="6.1" customWidth="1"/>'
      '<col min="7" max="7" width="15.9" customWidth="1"/>'
      '<col min="8" max="8" width="8.6" customWidth="1"/>'
      '<col min="9" max="9" width="10.3" customWidth="1"/>'
      '<col min="10" max="10" width="10.5" customWidth="1"/>'
      '<col min="11" max="11" width="11.4" customWidth="1"/>'
      '<col min="12" max="12" width="8" customWidth="1"/>'
      '</cols><sheetData>',
    );

    buffer.write('<row r="1" ht="25.2" customHeight="1">');
    buffer.write(_textCell('A1', 1, 'Auction List'));
    for (final column in const [
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
    ]) {
      buffer.write(
        _blankCell(
          '$column'
          '1',
          2,
        ),
      );
    }
    buffer.write(_blankCell('L1', 3));
    buffer.write('</row>');

    buffer.write('<row r="2" ht="14.4" customHeight="1">');
    buffer.write(
      _textCell(
        'A2',
        4,
        'Date: ${exportedAt.month}/${exportedAt.day}/${exportedAt.year}',
      ),
    );
    buffer.write(_blankCell('B2', 5));
    for (final column in const ['C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K']) {
      buffer.write(
        _blankCell(
          '$column'
          '2',
          5,
        ),
      );
    }
    buffer.write(_blankCell('L2', 6));
    buffer.write('</row>');

    buffer.write('<row r="3" ht="40.8" customHeight="1">');
    for (var index = 0; index < _headers.length; index++) {
      final style = switch (index) {
        0 => 7,
        7 => 9,
        8 => 10,
        10 => 11,
        11 => 12,
        _ => 8,
      };
      buffer.write(_textCell('${_columnName(index)}3', style, _headers[index]));
    }
    buffer.write('</row>');

    for (var index = 0; index < entries.length; index++) {
      final row = index + 4;
      final vehicle = entries[index].vehicle;
      final light = index.isEven;
      final last = index == entries.length - 1;
      final styles = _rowStyles(light: light, last: last);
      buffer.write('<row r="$row">');
      buffer.write(_integerCell('A$row', styles.first, vehicle.number));
      buffer.write(_textCell('B$row', styles.core, vehicle.vin));
      buffer.write(_textCell('C$row', styles.core, vehicle.vehicleType));
      buffer.write(_integerCell('D$row', styles.core, vehicle.year));
      buffer.write(_integerCell('E$row', styles.core, vehicle.mileage));
      buffer.write(_textCell('F$row', styles.core, vehicle.color));
      buffer.write(_textCell('G$row', styles.core, vehicle.owner));
      buffer.write(_currencyCell('H$row', styles.currency, vehicle.redLight));
      buffer.write(_currencyCell('I$row', styles.currency, vehicle.greenLight));
      buffer.write(_currencyCell('J$row', styles.currency, vehicle.priceUsd));
      buffer.write(_blankCell('K$row', styles.currency));
      buffer.write(_blankCell('L$row', styles.last));
      buffer.write('</row>');
    }

    buffer.write('</sheetData>');
    buffer.write(
      '<mergeCells count="2"><mergeCell ref="A1:L1"/><mergeCell ref="A2:B2"/></mergeCells>',
    );
    buffer.write(
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
      '<pageSetup orientation="landscape" scale="95"/>'
      '</worksheet>',
    );
    return buffer.toString();
  }

  static _RowStyles _rowStyles({required bool light, required bool last}) {
    if (light && !last) return const _RowStyles(13, 14, 15, 16);
    if (!light && !last) return const _RowStyles(17, 18, 19, 20);
    if (light) return const _RowStyles(21, 22, 23, 24);
    return const _RowStyles(25, 26, 27, 28);
  }

  static String _sourceSheetXml(List<AuctionVehicleEntry> entries) {
    final owners = <String>{
      'Outside',
      'AWTAR',
      'Farhan Shakib',
      for (final entry in entries)
        if (entry.vehicle.owner.trim().isNotEmpty) entry.vehicle.owner.trim(),
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<dimension ref="A1:A${owners.length}"/>'
      '<sheetData>',
    );
    for (var index = 0; index < owners.length; index++) {
      final row = index + 1;
      buffer.write(
        '<row r="$row">${_textCell('A$row', 0, owners[index])}</row>',
      );
    }
    buffer.write('</sheetData></worksheet>');
    return buffer.toString();
  }

  static String _textCell(String address, int style, String value) {
    if (value.trim().isEmpty) return _blankCell(address, style);
    return '<c r="$address" s="$style" t="inlineStr"><is><t xml:space="preserve">${_escape(value)}</t></is></c>';
  }

  static String _blankCell(String address, int style) =>
      '<c r="$address" s="$style"/>';

  static String _integerCell(String address, int style, String value) {
    final number = int.tryParse(value.trim());
    if (number == null) return _textCell(address, style, value);
    return '<c r="$address" s="$style"><v>$number</v></c>';
  }

  static String _currencyCell(String address, int style, String value) {
    final normalised = value
        .trim()
        .replaceAll(r'$', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    final amount = int.tryParse(normalised);
    if (amount == null) return _textCell(address, style, value);
    return '<c r="$address" s="$style"><v>$amount</v></c>';
  }

  static String _columnName(int index) => String.fromCharCode(65 + index);

  static String _escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _corePropertiesXml(DateTime exportedAt) {
    final created = exportedAt.toIso8601String();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>Auction List</dc:title><dc:creator>Vehicle Poster</dc:creator>'
        '<cp:lastModifiedBy>Vehicle Poster</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">$created</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">$created</dcterms:modified>'
        '</cp:coreProperties>';
  }

  static String _workbookXml(int count) {
    final lastRow = count + 3;
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<bookViews><workbookView/></bookViews>'
        '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/>'
        '<sheet name="Sounce" sheetId="2" state="hidden" r:id="rId2"/></sheets>'
        '<definedNames>'
        '<definedName name="_xlnm.Print_Area" localSheetId="0">Sheet1!\$A\$1:\$L\$$lastRow</definedName>'
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">Sheet1!\$1:\$3</definedName>'
        '</definedNames><calcPr calcId="0"/></workbook>';
  }

  static const _contentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
      '</Types>';

  static const _rootRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  static const _workbookRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static const _appPropertiesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>Vehicle Poster</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>'
      '<HeadingPairs><vt:vector size="2" baseType="variant"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>2</vt:i4></vt:variant></vt:vector></HeadingPairs>'
      '<TitlesOfParts><vt:vector size="2" baseType="lpstr"><vt:lpstr>Sheet1</vt:lpstr><vt:lpstr>Sounce</vt:lpstr></vt:vector></TitlesOfParts>'
      '</Properties>';

  static const _stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;\$&quot;#,##0"/></numFmts>'
      '<fonts count="2">'
      '<font><sz val="11"/><color indexed="8"/><name val="Times New Roman"/><family val="1"/></font>'
      '<font><sz val="20"/><color indexed="8"/><name val="Times New Roman"/><family val="1"/></font>'
      '</fonts>'
      '<fills count="7">'
      '<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF4BACC6"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFC8E5F1"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF8AC7E5"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFF0000"/><bgColor indexed="64"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF00B050"/><bgColor indexed="64"/></patternFill></fill>'
      '</fills>'
      '<borders count="16">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="medium"/><right/><top style="medium"/><bottom/><diagonal/></border>'
      '<border><left/><right/><top style="medium"/><bottom/><diagonal/></border>'
      '<border><left/><right style="medium"/><top style="medium"/><bottom/><diagonal/></border>'
      '<border><left style="medium"/><right/><top/><bottom style="medium"/><diagonal/></border>'
      '<border><left/><right/><top/><bottom style="medium"/><diagonal/></border>'
      '<border><left/><right style="medium"/><top/><bottom style="medium"/><diagonal/></border>'
      '<border><left style="medium"/><right style="thin"/><top style="medium"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="thin"/><right style="thin"/><top style="medium"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="thin"/><right style="medium"/><top style="medium"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="medium"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="thin"/><right style="medium"/><top style="thin"/><bottom style="thin"/><diagonal/></border>'
      '<border><left style="medium"/><right style="thin"/><top style="thin"/><bottom style="medium"/><diagonal/></border>'
      '<border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="medium"/><diagonal/></border>'
      '<border><left style="thin"/><right style="medium"/><top style="thin"/><bottom style="medium"/><diagonal/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="29">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="3" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="4" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="5" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="6" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="7" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="8" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="9" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="5" borderId="9" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="6" borderId="9" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="9" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="2" borderId="10" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="11" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="12" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="11" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="4" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="12" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="13" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="14" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="3" borderId="14" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="3" borderId="15" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="13" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="14" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="164" fontId="0" fillId="4" borderId="14" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="4" borderId="15" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '<dxfs count="0"/><tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>'
      '</styleSheet>';
}

class _RowStyles {
  final int first;
  final int core;
  final int currency;
  final int last;

  const _RowStyles(this.first, this.core, this.currency, this.last);
}
