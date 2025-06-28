// lib/core/di/injection_container.dart
import 'package:get_it/get_it.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import your repository interface and implementation
import '../../features/home/domain/repositories/home_repository.dart';
import '../../features/home/data/repositories/home_repository_impl.dart';
import '../../features/home/presentation/bloc/home_bloc.dart';

// Import auth service and bloc
import 'package:scan_master/core/services/auth_service.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  //! Features - Auth
  // BLoC
  sl.registerFactory(() => AuthBloc(authService: sl()));
  
  // Services
  sl.registerLazySingleton(() => AuthService());

  //! Features - Home
  // BLoC
  sl.registerFactory(() => HomeBloc(homeRepository: sl()));
  
  // Repository
  sl.registerLazySingleton<HomeRepository>(
    () => HomeRepositoryImpl(
      storage: sl(),
      firestore: sl(),
      auth: sl(),
    ),
  );

  //! External - Firebase instances
  sl.registerLazySingleton(() => FirebaseAuth.instance);
  sl.registerLazySingleton(() => FirebaseFirestore.instance);
  sl.registerLazySingleton(() => FirebaseStorage.instance);
}