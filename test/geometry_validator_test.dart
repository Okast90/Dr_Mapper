import 'package:dji_mapper/core/geometry_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('GeometryValidator Tests', () {
    test('Valid convex polygon is detected as valid', () {
      final square = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8520, 2.3500),
        const LatLng(48.8520, 2.3520),
        const LatLng(48.8500, 2.3520),
      ];

      final result = GeometryValidator.validatePolygon(square);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
      expect(result.areaSquareMeters, greaterThan(1000.0));
      expect(result.intersectionPoints, isEmpty);
    });

    test('L-shaped polygon is valid', () {
      final lShape = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8530, 2.3500),
        const LatLng(48.8530, 2.3515),
        const LatLng(48.8515, 2.3515),
        const LatLng(48.8515, 2.3530),
        const LatLng(48.8500, 2.3530),
      ];

      final result = GeometryValidator.validatePolygon(lShape);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('Self-intersecting figure-8 / bowtie polygon is detected as error', () {
      // 0:(0,0) -> 1:(1,1) -> 2:(0,1) -> 3:(1,0) -> crossing between [0-1] and [2-3]
      final bowtie = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8520, 2.3520),
        const LatLng(48.8520, 2.3500),
        const LatLng(48.8500, 2.3520),
      ];

      final result = GeometryValidator.validatePolygon(bowtie);
      expect(result.isValid, isFalse);
      expect(result.hasErrors, isTrue);
      expect(result.issues.any((i) => i.type == GeometryIssueType.selfIntersection), isTrue);
      expect(result.intersectionPoints.isNotEmpty, isTrue);
    });

    test('Collinear 3-point polygon is detected as zero area / collinear error', () {
      final linePoly = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8510, 2.3500),
        const LatLng(48.8520, 2.3500),
      ];

      final result = GeometryValidator.validatePolygon(linePoly);
      expect(result.isValid, isFalse);
      expect(result.issues.any((i) => i.type == GeometryIssueType.collinearOrZeroArea), isTrue);
    });

    test('Ultra-acute needle spike (< 15°) is flagged as warning', () {
      final needlePoly = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8600, 2.3501), // Very sharp needle vertex
        const LatLng(48.8500, 2.3502),
      ];

      final result = GeometryValidator.validatePolygon(needlePoly);
      expect(result.issues.any((i) => i.type == GeometryIssueType.acuteNeedleSpike), isTrue);
    });

    test('Duplicate consecutive vertices are flagged', () {
      final duplicatePoly = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8500, 2.3500), // Exact duplicate
        const LatLng(48.8520, 2.3500),
        const LatLng(48.8520, 2.3520),
      ];

      final result = GeometryValidator.validatePolygon(duplicatePoly);
      expect(result.issues.any((i) => i.type == GeometryIssueType.duplicatePoints), isTrue);
    });

    test('repairPolygon fixes self-intersecting polygon into valid convex polygon', () {
      final bowtie = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8520, 2.3520),
        const LatLng(48.8520, 2.3500),
        const LatLng(48.8500, 2.3520),
      ];

      final repaired = GeometryValidator.repairPolygon(bowtie);
      final valRepaired = GeometryValidator.validatePolygon(repaired);
      expect(valRepaired.isValid, isTrue);
      expect(valRepaired.hasErrors, isFalse);
      expect(valRepaired.intersectionPoints, isEmpty);
    });

    test('Corridor validator detects hairpin turnaround', () {
      final hairpinCenterline = [
        const LatLng(48.8500, 2.3500),
        const LatLng(48.8550, 2.3500),
        const LatLng(48.8501, 2.35005), // Sharp reversal back along almost same track
      ];

      final result = GeometryValidator.validateCorridor(hairpinCenterline);
      expect(result.issues.any((i) => i.type == GeometryIssueType.corridorHairpinOrCross), isTrue);
    });
  });
}
