/// A vehicle in the auction list.
///
/// These values intentionally remain separate from [VehicleDetails], whose
/// fields describe the information printed on a poster. Auction-list values
/// are stored exactly as entered so they can be exported without changing the
/// user's wording or formatting.
class AuctionVehicle {
  final String number;
  final String vin;
  final String vehicleType;
  final String year;
  final String mileage;
  final String color;
  final String owner;
  final String redLight;
  final String greenLight;
  final String priceUsd;

  const AuctionVehicle({
    this.number = '',
    this.vin = '',
    this.vehicleType = '',
    this.year = '',
    this.mileage = '',
    this.color = '',
    this.owner = '',
    this.redLight = '',
    this.greenLight = '',
    this.priceUsd = '',
  });

  AuctionVehicle copyWith({
    String? number,
    String? vin,
    String? vehicleType,
    String? year,
    String? mileage,
    String? color,
    String? owner,
    String? redLight,
    String? greenLight,
    String? priceUsd,
  }) => AuctionVehicle(
    number: number ?? this.number,
    vin: vin ?? this.vin,
    vehicleType: vehicleType ?? this.vehicleType,
    year: year ?? this.year,
    mileage: mileage ?? this.mileage,
    color: color ?? this.color,
    owner: owner ?? this.owner,
    redLight: redLight ?? this.redLight,
    greenLight: greenLight ?? this.greenLight,
    priceUsd: priceUsd ?? this.priceUsd,
  );

  Map<String, String> toJson() => {
    'number': number,
    'vin': vin,
    'vehicleType': vehicleType,
    'year': year,
    'mileage': mileage,
    'color': color,
    'owner': owner,
    'redLight': redLight,
    'greenLight': greenLight,
    'priceUsd': priceUsd,
  };

  factory AuctionVehicle.fromJson(Map<String, Object?> json) => AuctionVehicle(
    number: _value(json['number']),
    vin: _value(json['vin']),
    vehicleType: _value(json['vehicleType']),
    year: _value(json['year']),
    mileage: _value(json['mileage']),
    color: _value(json['color']),
    owner: _value(json['owner']),
    redLight: _value(json['redLight']),
    greenLight: _value(json['greenLight']),
    priceUsd: _value(json['priceUsd']),
  );

  static String _value(Object? value) => value?.toString() ?? '';
}

/// A stored auction vehicle, including its database identity and timestamps.
class AuctionVehicleEntry {
  final int id;
  final AuctionVehicle vehicle;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AuctionVehicleEntry({
    required this.id,
    required this.vehicle,
    required this.createdAt,
    required this.updatedAt,
  });
}
