/// Local recognition keeps imports and manual entry available offline.
class VehicleBrand {
  static final yearPattern = RegExp(r'\b(?:19|20)\d{2}\b');
  static final _mercedesClassPattern = RegExp(
    r'\b[abcegs][ -]?class\b',
    caseSensitive: false,
  );

  static final _brands = <String, RegExp>{
    'MERCEDES-BENZ': RegExp(
      r'\b(?:mercedes(?:[ -]?benz)?|benz|[abcegs][ -]?\d{3}|(?:cla|cls|gla|glb|glc|gle|gls|slk|slc)[ -]?\d{0,3})\b|بنز',
      caseSensitive: false,
    ),
    'LEXUS': RegExp(r'\blexus\b|لکسیز|لکسوس', caseSensitive: false),
    'TOYOTA': RegExp(
      r'\b(?:toyota|toytoa|prius|priuc|corolla|crolla|camry|land[ -]?cruiser|prado|4[ -]?runner|rav[ -]?4|hilux|highlander|yaris|avalon|tacoma|tundra|sequoia|sienna|fortuner|hiace|aqua)\b|تویوتا|پریوس|کرولا|لندکروزر',
      caseSensitive: false,
    ),
    'NISSAN': RegExp(
      r'\b(?:nissan|altima|maxima|sentra|patrol|x[ -]?trail)\b',
      caseSensitive: false,
    ),
    'HONDA': RegExp(
      r'\b(?:honda|civic|accord|cr[ -]?v)\b',
      caseSensitive: false,
    ),
    'BMW': RegExp(r'\bbmw\b', caseSensitive: false),
    'HYUNDAI': RegExp(
      r'\b(?:hyundai|elantra|sonata|tucson|santa fe)\b',
      caseSensitive: false,
    ),
    'KIA': RegExp(r'\b(?:kia|sportage|sorento|optima)\b', caseSensitive: false),
  };

  static String fromModel(String model) {
    for (final entry in _brands.entries) {
      if (entry.value.hasMatch(model)) return entry.key;
    }
    // A known model takes priority over an ambiguous trim such as "S Class".
    if (_mercedesClassPattern.hasMatch(model)) return 'MERCEDES-BENZ';
    return '';
  }

  /// Preserve an explicit brand; fill a missing brand from the model.
  static String complete(String brandYear, String model) {
    final current = brandYear.trim();
    if (current.replaceAll(yearPattern, '').trim().isNotEmpty) return current;
    final brand = fromModel(model);
    final year = yearPattern.firstMatch('$current $model')?.group(0) ?? '';
    return [brand, year].where((part) => part.isNotEmpty).join(' ');
  }
}
