// lib/core/di/injection_container.dart
import 'package:get_it/get_it.dart';
import '../services/camera_service.dart';
import '../services/api_service.dart';
import '../../../app/router/app_router.dart';

final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Core Services
  getIt.registerLazySingleton<CameraService>(() => CameraService.instance);
  getIt.registerLazySingleton<ApiService>(() => ApiService());
  
  // Router
  getIt.registerLazySingleton<AppRouter>(() => AppRouter());
}