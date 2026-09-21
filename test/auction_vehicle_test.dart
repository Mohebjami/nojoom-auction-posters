import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/poster_history.dart';

void main() {
  const firstVehicle = AuctionVehicle(
    number: '1',
    vin: 'JTDKN3DU0A0231040',
    vehicleType: 'Prius',
    year: '2010',
    mileage: '125000',
    color: 'White',
    owner: 'Outside',
    redLight: '6500',
    greenLight: '7000',
    priceUsd: '6400',
  );

  test(
    'Auction vehicles persist independently and retain their timestamps',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'auction-vehicles',
      );
      addTearDown(database.close);
      final history = PosterHistory(openDatabase: () async => database);

      final id = await history.createAuctionVehicle(firstVehicle);
      final firstList = await history.listAuctionVehicles();
      expect(firstList, hasLength(1));
      expect(firstList.single.id, id);
      expect(firstList.single.vehicle.toJson(), firstVehicle.toJson());
      final createdAt = firstList.single.createdAt;

      const updatedVehicle = AuctionVehicle(
        number: '1',
        vin: 'JTDKN3DU0A0231040',
        vehicleType: 'Prius Prime',
        year: '2010',
        mileage: '126500',
        color: 'White',
        owner: 'Outside',
        redLight: '6600',
        greenLight: '7100',
        priceUsd: '6500',
      );
      await history.updateAuctionVehicle(id, updatedVehicle);
      final updated = (await history.listAuctionVehicles()).single;
      expect(updated.vehicle.toJson(), updatedVehicle.toJson());
      expect(updated.createdAt, createdAt);

      await history.deleteAuctionVehicle(id);
      expect(await history.listAuctionVehicles(), isEmpty);
      await expectLater(
        history.updateAuctionVehicle(id, firstVehicle),
        throwsStateError,
      );
    },
  );

  test(
    'Mileage and prices are optional, including for existing stored data',
    () {
      const optionalValues = AuctionVehicle(
        number: '2',
        vin: 'JTEBU5JR3E5152433',
        vehicleType: '4Runner',
        year: '2014',
        color: 'White',
        owner: 'Outside',
      );

      expect(optionalValues.toJson(), containsPair('mileage', ''));
      expect(optionalValues.toJson(), containsPair('redLight', ''));
      expect(optionalValues.toJson(), containsPair('greenLight', ''));
      expect(optionalValues.toJson(), containsPair('priceUsd', ''));

      final vehicleWithMileage = AuctionVehicle.fromJson({
        'number': '2',
        'vin': 'JTEBU5JR3E5152433',
        'vehicleType': '4Runner',
        'year': '2014',
        'mileage': '183500',
        'color': 'White',
        'owner': 'Outside',
      });
      expect(vehicleWithMileage.mileage, '183500');

      final legacyVehicle = AuctionVehicle.fromJson({
        'number': '3',
        'vin': '1HGCM82633A004352',
        'vehicleType': 'Accord',
        'year': '2003',
        'color': 'Silver',
        'owner': 'Outside',
      });

      expect(legacyVehicle.mileage, isEmpty);
      expect(legacyVehicle.redLight, isEmpty);
      expect(legacyVehicle.greenLight, isEmpty);
      expect(legacyVehicle.priceUsd, isEmpty);
    },
  );
}
