import 'package:go_router/go_router.dart';

import '../ui/exercise_screen.dart';
import '../ui/home_page.dart';
import '../ui/record_etalon_screen.dart';
import '../ui/senior_exercise_screen.dart';

class AppRoutes {
  static const String home = '/';
  static const String exercise = '/exercise';
  static const String seniorExercise = '/senior-exercise';
  static const String recordEtalon = '/record-etalon';
}

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.exercise,
        builder: (context, state) => const ExerciseScreen(),
      ),
      GoRoute(
        path: AppRoutes.seniorExercise,
        builder: (context, state) => const SeniorExerciseScreen(),
      ),
      GoRoute(
        path: AppRoutes.recordEtalon,
        builder: (context, state) => const RecordEtalonScreen(),
      ),
    ],
  );
}
