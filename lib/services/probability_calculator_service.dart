import 'package:guidex/models/recommendation.dart';

/// Probability Calculator Service - STRICT ALGORITHM
///
/// Generates accurate admission probability based on:
/// 1. Cutoff difference (MOST IMPORTANT - >80% influence)
/// 2. Location match (optional - max 5% adjustment)
/// 3. Hostel availability (optional - max 5% adjustment)
/// 4. Preferred college selection (optional - max 5% adjustment)

class ProbabilityResult {
  final String collegeName;
  final String courseName;
  final double studentCutoff;
  final double collegeCutoff;
  final int probability;
  final String label;
  final String reason;
  final double cutoffDifference;
  final String category;

  ProbabilityResult({
    required this.collegeName,
    required this.courseName,
    required this.studentCutoff,
    required this.collegeCutoff,
    required this.probability,
    required this.label,
    required this.reason,
    required this.cutoffDifference,
    required this.category,
  });

  @override
  String toString() {
    return '''
College: $collegeName
Course: $courseName
Category: $category
Student Cutoff: $studentCutoff
College Cutoff: $collegeCutoff
Cutoff Difference: $cutoffDifference
Probability: $probability%
Label: $label
Reason: $reason
''';
  }
}

class ProbabilityCalculatorService {
  /// Calculate probability for a single college
  ///
  /// STRICT RULES:
  /// - difference >= 5 → 90-95%
  /// - difference 0-5 → 70-85%
  /// - difference -2 to 0 → 40-60%
  /// - difference -5 to -2 → 15-40%
  /// - difference -10 to -5 → 5-15%
  /// - difference < -10 → 0-5% (Almost impossible)
  static ProbabilityResult calculateProbability({
    required String collegeName,
    required String courseName,
    required double studentCutoff,
    required double collegeCutoff,
    required String category,
    bool isPreferredCollege = false,
    bool isLocationMatch = false,
    bool hostelAvailable = false,
  }) {
    // Step 1: Calculate cutoff difference (PRIMARY FACTOR)
    final double difference = studentCutoff - collegeCutoff;

    // Step 2: Assign base probability based on difference (>80% influence)
    int baseProbability = _assignBaseProbability(difference);

    // Step 3: Apply optional adjustments (max 5% each, total max 15%)
    int adjustedProbability = baseProbability;

    // Adjustment 1: Preferred college selection (+3% to +5%)
    if (isPreferredCollege) {
      adjustedProbability += 3;
    }

    // Adjustment 2: Location match (+2% to +3%)
    if (isLocationMatch) {
      adjustedProbability += 2;
    }

    // Adjustment 3: Hostel availability (+2% to +3%)
    if (hostelAvailable) {
      adjustedProbability += 2;
    }

    // Cap at 100% maximum
    if (adjustedProbability > 100) {
      adjustedProbability = 100;
    }

    // Step 4: Assign label based on probability
    final String label = _assignLabel(adjustedProbability);

    // Step 5: Generate detailed reason
    final String reason = _generateReason(
      difference: difference,
      studentCutoff: studentCutoff,
      collegeCutoff: collegeCutoff,
      baseProbability: baseProbability,
      adjustedProbability: adjustedProbability,
      isPreferredCollege: isPreferredCollege,
      isLocationMatch: isLocationMatch,
      hostelAvailable: hostelAvailable,
    );

    return ProbabilityResult(
      collegeName: collegeName,
      courseName: courseName,
      studentCutoff: studentCutoff,
      collegeCutoff: collegeCutoff,
      probability: adjustedProbability,
      label: label,
      reason: reason,
      cutoffDifference: difference,
      category: category,
    );
  }

  /// Assign base probability based on strict cutoff difference rules
  static int _assignBaseProbability(double difference) {
    if (difference >= 5) {
      // Very strong position
      return 92; // 90-95% range
    } else if (difference >= 0 && difference < 5) {
      // Good position
      return 77; // 70-85% range
    } else if (difference >= -2 && difference < 0) {
      // Moderate position (slightly below cutoff)
      return 50; // 40-60% range
    } else if (difference >= -5 && difference < -2) {
      // Weak position (below cutoff)
      return 27; // 15-40% range
    } else if (difference >= -10 && difference < -5) {
      // Very weak position (far below cutoff)
      return 10; // 5-15% range
    } else {
      // Almost impossible (far below cutoff)
      return 2; // 0-5% range
    }
  }

  /// Assign label based on probability percentage
  static String _assignLabel(int probability) {
    if (probability >= 80) {
      return 'Excellent';
    } else if (probability >= 60) {
      return 'Good';
    } else if (probability >= 40) {
      return 'Moderate';
    } else if (probability >= 20) {
      return 'Low';
    } else {
      return 'Very Low / Dream';
    }
  }

  /// Generate detailed reason for the probability
  static String _generateReason({
    required double difference,
    required double studentCutoff,
    required double collegeCutoff,
    required int baseProbability,
    required int adjustedProbability,
    required bool isPreferredCollege,
    required bool isLocationMatch,
    required bool hostelAvailable,
  }) {
    final StringBuffer reason = StringBuffer();

    // Primary reason: Cutoff difference
    if (difference >= 5) {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${difference.toStringAsFixed(1)} marks ABOVE the college cutoff (${collegeCutoff.toStringAsFixed(1)}). This is an excellent position for admission. ');
    } else if (difference >= 0 && difference < 5) {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${difference.toStringAsFixed(1)} marks above the college cutoff (${collegeCutoff.toStringAsFixed(1)}). You have a good chance of admission. ');
    } else if (difference >= -2 && difference < 0) {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${(-difference).toStringAsFixed(1)} marks BELOW the college cutoff (${collegeCutoff.toStringAsFixed(1)}). Admission is possible but uncertain. ');
    } else if (difference >= -5 && difference < -2) {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${(-difference).toStringAsFixed(1)} marks below the college cutoff (${collegeCutoff.toStringAsFixed(1)}). Admission is unlikely. ');
    } else if (difference >= -10 && difference < -5) {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${(-difference).toStringAsFixed(1)} marks below the college cutoff (${collegeCutoff.toStringAsFixed(1)}). Admission is highly unlikely. ');
    } else {
      reason.write(
          'Your cutoff (${studentCutoff.toStringAsFixed(1)}) is ${(-difference).toStringAsFixed(1)} marks below the college cutoff (${collegeCutoff.toStringAsFixed(1)}). Admission is almost impossible. ');
    }

    // Additional factors
    final adjustmentFactors = <String>[];

    if (isPreferredCollege) {
      adjustmentFactors.add('preferred college selection (+3%)');
    }
    if (isLocationMatch) {
      adjustmentFactors.add('location match (+2%)');
    }
    if (hostelAvailable) {
      adjustmentFactors.add('hostel availability (+2%)');
    }

    if (adjustmentFactors.isNotEmpty) {
      reason.write(
          'Additional bonuses applied: ${adjustmentFactors.join(', ')}. ');
    }

    // Base to adjusted conversion
    if (baseProbability != adjustedProbability) {
      reason.write(
          'Final probability: ${adjustedProbability}% (adjusted from base ${baseProbability}%). ');
    } else {
      reason.write('Base probability: ${baseProbability}%. ');
    }

    // Reality check message
    if (adjustedProbability < 10) {
      reason.write('⚠️ VERY LOW CHANCE - Consider other options.');
    } else if (adjustedProbability < 20) {
      reason.write('Consider this a backup/dream option.');
    } else if (adjustedProbability < 40) {
      reason.write('Realistic to have this as a safety option.');
    } else if (adjustedProbability < 60) {
      reason.write('Good probability, but keep other options open.');
    } else if (adjustedProbability < 80) {
      reason.write('High probability of admission.');
    } else {
      reason.write('Excellent probability of admission.');
    }

    return reason.toString();
  }

  /// Calculate probabilities for multiple colleges (batch processing)
  static List<ProbabilityResult> calculateBatchProbabilities({
    required List<Recommendation> colleges,
    required double studentCutoff,
    required String category,
    required List<String> preferredCollegeNames,
    String? preferredLocation,
  }) {
    return colleges.map((college) {
      final isPreferred = preferredCollegeNames.any((name) =>
              name.toLowerCase().trim() ==
              college.collegeName.toLowerCase().trim()) ||
          preferredCollegeNames.any((name) =>
              college.collegeName.toLowerCase().contains(name.toLowerCase()));

      return calculateProbability(
        collegeName: college.collegeName,
        courseName: college.courseName,
        studentCutoff: studentCutoff,
        collegeCutoff: college.cutoff,
        category: category,
        isPreferredCollege: isPreferred,
        isLocationMatch: preferredLocation != null && college.district != null
            ? college.district!.toLowerCase() == preferredLocation.toLowerCase()
            : false,
        hostelAvailable: true, // Assume available unless specified
      );
    }).toList();
  }
}
