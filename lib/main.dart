import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:guidex/app_routes.dart';
import 'package:guidex/onboardingscreen.dart';
import 'package:guidex/login_page.dart';
import 'package:guidex/signup_page.dart';
import 'package:guidex/user_category_page.dart';
import 'package:guidex/screens/analysis_test_page.dart';
import 'package:guidex/screens/analysis_results_page.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/models/recommendation_result.dart';
import 'package:guidex/services/auth/auth_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final String initialRoute = await _resolveInitialRoute();
  runApp(MyApp(initialRoute: initialRoute));
}

Future<String> _resolveInitialRoute() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final bool hasSession = await AuthScope.controller.restoreSession();
    return hasSession ? AppRoutes.userCategory : AppRoutes.onboarding;
  } catch (_) {
    return AppRoutes.onboarding;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.initialRoute});

  final String initialRoute;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nextep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: initialRoute,
      routes: {
        AppRoutes.onboarding: (context) => const OnboardingScreen(),
        AppRoutes.login: (context) => const LoginPage(),
        AppRoutes.signup: (context) => const SignUpPage(),
        AppRoutes.userCategory: (context) => const UserCategoryPage(),
        AppRoutes.analysisTest: (context) => const AnalysisTestPage(),
        AppRoutes.analysisResults: (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;

          return AnalysisResultsPage(
            name: args?['name'] as String?,
            cutoff: (args?['cutoff'] as num?)?.toDouble(),
            category: args?['category'] as String?,
            selectedCourses: (args?['selectedCourses'] as List?)
                ?.map((e) => e.toString())
                .toList(),
            interest: args?['interest'] as String?,
            district: args?['district'] as String?,
            preferredCollegeIds: (args?['preferredCollegeIds'] as List?)
                ?.map((e) => e.toString())
                .toList(),
            preferredColleges: (args?['preferredColleges'] as List?)
                ?.map((e) => e.toString())
                .toList(),
            prefetchedResult:
                args?['prefetchedResult'] as RecommendationResult?,
            prefetchedRecommendations:
                (args?['prefetchedRecommendations'] as List?)
                    ?.whereType<Recommendation>()
                    .toList(),
            prefetchError: args?['prefetchError'] as String?,
          );
        },
      },
    );
  }
}
