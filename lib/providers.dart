// lib/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/tv_service.dart';
import 'services/tv_discovery_service.dart';
import 'services/distance_service.dart';
import 'services/guardian_service.dart';
import 'services/voice_service.dart';

final tvServiceProvider =
    ChangeNotifierProvider<TvService>((_) => TvService());

final discoveryServiceProvider =
    ChangeNotifierProvider<TvDiscoveryService>((_) => TvDiscoveryService());

final distanceServiceProvider =
    ChangeNotifierProvider<DistanceService>((_) => DistanceService());

final guardianServiceProvider = ChangeNotifierProvider<GuardianService>((ref) =>
    GuardianService(
      tv: ref.watch(tvServiceProvider),
      distance: ref.watch(distanceServiceProvider),
    ));

final voiceServiceProvider = ChangeNotifierProvider<VoiceService>((ref) =>
    VoiceService(
      onCommand: ref.read(guardianServiceProvider).handleVoiceCommand,
    ));
