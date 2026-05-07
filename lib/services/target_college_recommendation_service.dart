import 'package:guidex/models/recommendation.dart';
import 'package:guidex/services/api_service.dart';
import 'package:guidex/services/probability_calculator_service.dart';

/// Target College Recommendation Service
///
/// Recommends BEST colleges based on student's profile (NOT user's desires)
///
/// Differences:
/// - PREFERRED: User chooses → System calculates probability
/// - TARGET: System recommends best matches → System calculates probability
///
/// Algorithm:
/// 1. Fetch all colleges from database
/// 2. Filter by: Category, Cutoff range, Location, Course match
/// 3. Score each college (cutoff proximity, location, course match)
/// 4. Calculate probability using strict algorithm
/// 5. Return TOP 15-20 sorted by probability

class TargetCollegeResult {
  final String collegeName;
  final String courseName;
  final double studentCutoff;
  final double collegeCutoff;
  final int probability;
  final String label;
  final String reason;
  final String district;
  final String collegeType;
  final int collegeRank;
  final String category;
  final double matchScore; // 0-100: How well college matches student profile
  final List<String> matchReasons; // Why this college is recommended

  TargetCollegeResult({
    required this.collegeName,
    required this.courseName,
    required this.studentCutoff,
    required this.collegeCutoff,
    required this.probability,
    required this.label,
    required this.reason,
    required this.district,
    required this.collegeType,
    required this.collegeRank,
    required this.category,
    required this.matchScore,
    required this.matchReasons,
  });

  @override
  String toString() {
    return '''
College: $collegeName
Course: $courseName
Location: $district
Type: $collegeType | Rank: $collegeRank

Student Cutoff: $studentCutoff | College Cutoff: $collegeCutoff
Match Score: $matchScore%
Probability: $probability%
Label: $label

Why recommended:
${matchReasons.map((r) => '• $r').join('\n')}

Reason: $reason
''';
  }
}

class TargetCollegeRecommendationService {
  static const int _defaultReturnCount = 15;

  /// Get target college recommendations based on student profile
  ///
  /// Returns top colleges that best match student's merit + location + interest
  /// NOT based on user's preferences, but on what they can actually get
  static Future<List<TargetCollegeResult>> getTargetCollegeRecommendations({
    required double studentCutoff,
    required String category,
    required String courseInterest,
    String? preferredLocation,
    ApiService? apiService,
    int returnCount = _defaultReturnCount,
  }) async {
    final api = apiService ?? ApiService();

    try {
      // STEP 1: Fetch all colleges for this category
      final result = await api.getRecommendationResult(
        category: category,
        cutoff: studentCutoff,
        preferredCourse: courseInterest,
        district: null, // Get ALL colleges, not filtered by district
        preferredCollegeIds: const [],
        preferredCollegeNames: const [],
      );

      // Combine all colleges from both buckets
      final allColleges = <Recommendation>[
        ...result.preferredColleges,
        ...result.safeColleges,
        ...result.all,
      ];

      // STEP 2: Filter colleges (student can get in or close)
      final filteredColleges = _filterColleges(
        colleges: allColleges,
        studentCutoff: studentCutoff,
        category: category,
        preferredLocation: preferredLocation,
      );

      // STEP 3: Score each college (match quality)
      final scoredColleges = <_ScoredCollege>[];

      for (final college in filteredColleges) {
        final score = _calculateMatchScore(
          college: college,
          studentCutoff: studentCutoff,
          courseInterest: courseInterest,
          preferredLocation: preferredLocation,
        );

        final matchReasons = _getMatchReasons(
          college: college,
          studentCutoff: studentCutoff,
          score: score,
          preferredLocation: preferredLocation,
          courseInterest: courseInterest,
        );

        scoredColleges.add(_ScoredCollege(
          college: college,
          matchScore: score,
          matchReasons: matchReasons,
        ));
      }

      // STEP 4: Sort by match score (descending)
      scoredColleges.sort((a, b) => b.matchScore.compareTo(a.matchScore));

      // STEP 5: Convert to target college results with probabilities
      final targetResults = <TargetCollegeResult>[];

      for (final scored in scoredColleges.take(returnCount)) {
        final college = scored.college;

        // Calculate probability using strict algorithm
        final probResult = ProbabilityCalculatorService.calculateProbability(
          collegeName: college.collegeName,
          courseName: college.courseName,
          studentCutoff: studentCutoff,
          collegeCutoff: college.cutoff > 0 ? college.cutoff : 100.0,
          category: category,
          isPreferredCollege: false, // These are NOT user's preferred choices
          isLocationMatch: preferredLocation != null &&
              college.district != null &&
              college.district!.toLowerCase().trim() ==
                  preferredLocation.toLowerCase().trim(),
          hostelAvailable: true,
        );

        targetResults.add(TargetCollegeResult(
          collegeName: probResult.collegeName,
          courseName: probResult.courseName,
          studentCutoff: studentCutoff,
          collegeCutoff: probResult.collegeCutoff,
          probability: probResult.probability,
          label: probResult.label,
          reason: probResult.reason,
          district: college.district ?? 'Not Specified',
          collegeType: college.collegeType ?? 'Unknown',
          collegeRank: college.collegeRank ?? 0,
          category: category,
          matchScore: scored.matchScore,
          matchReasons: scored.matchReasons,
        ));
      }

      return targetResults;
    } catch (e) {
      throw Exception('Failed to get target college recommendations: $e');
    }
  }

  /// Filter colleges that student can potentially get into
  static List<Recommendation> _filterColleges({
    required List<Recommendation> colleges,
    required double studentCutoff,
    required String category,
    String? preferredLocation,
  }) {
    return colleges.where((college) {
      // Filter 1: Category must match
      if (college.category.toLowerCase() != category.toLowerCase()) {
        return false;
      }

      // Filter 2: College cutoff should be <= student cutoff + 15 marks
      // (allow some wiggle room for realistic recommendations)
      final difference = studentCutoff - college.cutoff;
      if (difference < -15) {
        return false; // Too difficult
      }

      // Filter 3: Avoid duplicates (normalize college names)
      // (optional - helps if same college appears twice)

      return true;
    }).toList();
  }

  /// Calculate match score (0-100) for a college
  ///
  /// Considers:
  /// - Cutoff proximity (most important - 60% weight)
  /// - Location match (20% weight)
  /// - College rank (10% weight)
  /// - College type (10% weight)
  static double _calculateMatchScore({
    required Recommendation college,
    required double studentCutoff,
    required String courseInterest,
    String? preferredLocation,
  }) {
    double score = 0;

    // Score 1: Cutoff proximity (0-60 points)
    // Perfect score if student cutoff is close to college cutoff
    final difference = studentCutoff - college.cutoff;

    double cutoffScore;
    if (difference >= 10) {
      cutoffScore = 60; // Perfect - can easily get in
    } else if (difference >= 5) {
      cutoffScore = 50; // Very good
    } else if (difference >= 0) {
      cutoffScore = 40; // Good
    } else if (difference >= -5) {
      cutoffScore = 25; // Moderate (slightly below)
    } else if (difference >= -10) {
      cutoffScore = 10; // Weak (below)
    } else {
      cutoffScore = 0; // Very weak (far below)
    }

    score += cutoffScore;

    // Score 2: Location match (0-20 points)
    if (preferredLocation != null && college.district != null) {
      if (college.district!.toLowerCase().trim() ==
          preferredLocation.toLowerCase().trim()) {
        score += 20; // Perfect location match
      } else {
        score += 5; // Slight consideration
      }
    }

    // Score 3: College rank (0-10 points)
    // Higher rank = better college = higher score
    if (college.collegeRank != null && college.collegeRank! > 0) {
      final rankScore = (100 - college.collegeRank!.clamp(1, 100)).toDouble();
      score += (rankScore / 10); // Normalize to 0-10
    }

    // Score 4: College type (0-10 points)
    // Government colleges preferred over private
    if (college.collegeType != null) {
      if (college.collegeType!.toLowerCase().contains('government') ||
          college.collegeType!.toLowerCase().contains('nit') ||
          college.collegeType!.toLowerCase().contains('iit')) {
        score += 10; // Prestigious government/NIT/IIT
      } else if (college.collegeType!.toLowerCase().contains('aided')) {
        score += 7; // Aided colleges
      } else {
        score += 5; // Private colleges
      }
    }

    return score.clamp(0, 100);
  }

  /// Generate reasons why college is recommended
  static List<String> _getMatchReasons({
    required Recommendation college,
    required double studentCutoff,
    required double score,
    String? preferredLocation,
    required String courseInterest,
  }) {
    final reasons = <String>[];

    final difference = studentCutoff - college.cutoff;

    // Reason 1: Cutoff match
    if (difference >= 10) {
      reasons.add('Excellent cutoff match (+${difference.toStringAsFixed(1)})');
    } else if (difference >= 5) {
      reasons.add('Strong cutoff match (+${difference.toStringAsFixed(1)})');
    } else if (difference >= 0) {
      reasons.add('Good cutoff match (+${difference.toStringAsFixed(1)})');
    } else if (difference >= -5) {
      reasons.add('Realistic option (${difference.toStringAsFixed(1)} below)');
    }

    // Reason 2: Location match
    if (preferredLocation != null && college.district != null) {
      if (college.district!.toLowerCase() == preferredLocation.toLowerCase()) {
        reasons.add('Matches your location preference ($preferredLocation)');
      }
    }

    // Reason 3: Course match
    if (college.courseName
        .toLowerCase()
        .contains(courseInterest.toLowerCase())) {
      reasons.add('Offers ${college.courseName} (your interest area)');
    }

    // Reason 4: Reputation
    if (college.collegeType != null) {
      if (college.collegeType!.toLowerCase().contains('nit')) {
        reasons.add('Prestigious NIT college');
      } else if (college.collegeType!.toLowerCase().contains('iit')) {
        reasons.add('Top-tier IIT college');
      } else if (college.collegeType!.toLowerCase().contains('government')) {
        reasons.add('Government college with good reputation');
      }
    }

    // Reason 5: Rank
    if (college.collegeRank != null && college.collegeRank! > 0) {
      reasons.add('Strong college rank (#${college.collegeRank})');
    }

    return reasons.isNotEmpty ? reasons : ['Suitable match for your profile'];
  }
}

/// Internal class to hold scored college data
class _ScoredCollege {
  final Recommendation college;
  final double matchScore;
  final List<String> matchReasons;

  _ScoredCollege({
    required this.college,
    required this.matchScore,
    required this.matchReasons,
  });
}
