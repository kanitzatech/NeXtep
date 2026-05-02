import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/services/pdf_report_generator.dart';
import 'package:http/http.dart' as http;

class FinalReportPage extends StatefulWidget {
  final String studentName;
  final String category;
  final double studentCutoff;
  final String preferredCourse;
  final String? district;
  final bool hostelRequired;
  final List<String> preferredCollegeIds;
  final List<String> preferredCollegeNames;
  final List<Recommendation>? allRecommendations;
  final List<Recommendation>? safeColleges;

  const FinalReportPage({
    super.key,
    required this.studentName,
    required this.category,
    required this.studentCutoff,
    required this.preferredCourse,
    this.district,
    required this.hostelRequired,
    required this.preferredCollegeIds,
    required this.preferredCollegeNames,
    this.allRecommendations,
    this.safeColleges,
  });

  @override
  State<FinalReportPage> createState() => _FinalReportPageState();
}

class _FinalReportPageState extends State<FinalReportPage> {
  bool _isLoadingTargets = true;
  bool _isDownloading = false;
  List<_TargetCollege> _targetColleges = [];
  List<_PreferredAnalysis> _preferredAnalysis = [];

  @override
  void initState() {
    super.initState();
    _fetchTargetColleges();
  }

  Future<void> _fetchTargetColleges() async {
    setState(() => _isLoadingTargets = true);

    try {
      final queryParams = <String, List<String>>{
        'cutoff': [widget.studentCutoff.toString()],
        'community': [widget.category.toLowerCase()],
        'preferred_course': [widget.preferredCourse],
        'hostel_required': [widget.hostelRequired ? 'yes' : 'no'],
      };
      if (widget.district != null && widget.district!.isNotEmpty) {
        queryParams['preferred_city'] = [widget.district!];
      }
      if (widget.preferredCollegeNames.isNotEmpty) {
        queryParams['preferred_colleges'] = widget.preferredCollegeNames;
      }

      final uri = Uri.https(
        'pathwise-backend-t3mkeqs5ga-el.a.run.app',
        '/api/target-colleges',
        queryParams.map((k, v) => MapEntry(k, v.length == 1 ? v.first : v)),
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Parse preferred colleges analysis
        final prefList = data['preferred_colleges_analysis'] as List? ?? [];
        _preferredAnalysis = prefList.map((item) {
          return _PreferredAnalysis(
            collegeName: item['college_name'] ?? '',
            course: item['course'] ?? '',
            yourCutoff: (item['your_cutoff'] as num?)?.toDouble() ?? 0,
            collegeCutoff: (item['college_cutoff'] as num?)?.toDouble() ?? 0,
            probability: (item['probability'] as num?)?.toDouble() ?? 0,
            chanceLabel: item['chance_label'] ?? '',
          );
        }).toList();

        // Parse target colleges
        final targetList = data['target_colleges'] as List? ?? [];
        _targetColleges = targetList.map((item) {
          return _TargetCollege(
            collegeName: item['college_name'] ?? '',
            course: item['course'] ?? '',
            score: (item['score'] as num?)?.toDouble() ?? 0,
            chanceLabel: item['chance_label'] ?? '',
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error fetching target colleges: $e');
    }

    if (mounted) {
      setState(() => _isLoadingTargets = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStudentHeader(),
                    const SizedBox(height: 20),
                    _buildPreferredCollegesSection(),
                    const SizedBox(height: 20),
                    _buildTargetCollegesSection(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildBottomBar(),
    );
  }

  // ─── App Bar ───────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Final Report',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _fetchTargetColleges,
          ),
        ],
      ),
    );
  }

  // ─── Student Profile Header ────────────────────────────────
  Widget _buildStudentHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Profile',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.studentName,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _profileChip(Icons.trending_up, 'Cutoff',
                  widget.studentCutoff.toStringAsFixed(1)),
              const SizedBox(width: 12),
              _profileChip(
                  Icons.school, 'Category', widget.category.toUpperCase()),
              const SizedBox(width: 12),
              _profileChip(Icons.code, 'Course',
                  _shortCourse(widget.preferredCourse)),
            ],
          ),
          if (widget.district != null && widget.district!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.location_on,
                      size: 14, color: Colors.white.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Text(
                    'District: ${widget.district}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ─── ⭐ Preferred Colleges Analysis ────────────────────────
  Widget _buildPreferredCollegesSection() {
    // ONLY show user-selected preferred colleges from the API
    final displayItems = _preferredAnalysis.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '⭐ Preferred Colleges Analysis',
          Colors.amber.shade700,
          'Probability based on your cutoff vs college cutoff',
        ),
        const SizedBox(height: 12),
        if (_isLoadingTargets)
          const Center(child: CircularProgressIndicator())
        else if (displayItems.isEmpty)
          _emptyState(widget.preferredCollegeNames.isEmpty
              ? 'No preferred colleges selected'
              : 'No matching preferred colleges found')
        else
          ...displayItems.asMap().entries.map((entry) {
            return _buildPreferredCard(entry.value, entry.key + 1);
          }),
      ],
    );
  }

  Widget _buildPreferredCard(_PreferredAnalysis college, int rank) {
    final prob = college.probability;
    final color = prob >= 80
        ? const Color(0xFF22C55E)
        : prob >= 60
            ? const Color(0xFFF59E0B)
            : prob >= 40
                ? const Color(0xFFF97316)
                : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rank badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('#$rank',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(college.collegeName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(college.course,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                // Chance label with probability
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '🎯 ${prob.toStringAsFixed(1)}% (${college.chanceLabel})',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
                const SizedBox(height: 8),
                // Cutoff comparison
                Row(
                  children: [
                    Text(
                      '📊 Your: ${college.yourCutoff.toStringAsFixed(1)}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '📉 College: ${college.collegeCutoff.toStringAsFixed(1)}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 🎯 Target Colleges Section ───────────────────────────
  Widget _buildTargetCollegesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '🎯 Target Colleges (${_targetColleges.length})',
          const Color(0xFF2563EB),
          'Weighted score: Cutoff 40% • Location 20% • Course 15% • Hostel 10% • Category 10% • Pref 5%',
        ),
        const SizedBox(height: 12),
        if (_isLoadingTargets)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_targetColleges.isEmpty)
          _emptyState('No target colleges found for your criteria')
        else
          // Table-style display
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                          flex: 4,
                          child: Text('College / Course',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4F46E5)))),
                      Expanded(
                          flex: 2,
                          child: Text('Score %',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4F46E5)),
                              textAlign: TextAlign.center)),
                      Expanded(
                          flex: 2,
                          child: Text('Chance',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4F46E5)),
                              textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                // Table rows
                ..._targetColleges.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final tc = entry.value;
                  final isLast = idx == _targetColleges.length - 1;
                  return _buildTargetRow(tc, idx + 1, isLast);
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTargetRow(_TargetCollege tc, int rank, bool isLast) {
    final chanceColor = tc.chanceLabel == 'Strong Chance'
        ? const Color(0xFF22C55E)
        : tc.chanceLabel == 'Moderate'
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tc.collegeName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(tc.course,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text('${tc.score.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                // Mini progress bar
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (tc.score / 100).clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        color: chanceColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chanceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tc.chanceLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: chanceColor),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Action Bar ─────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isDownloading ? null : _downloadReport,
          icon: _isDownloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download_rounded, size: 20),
          label: Text(
            _isDownloading ? 'Generating PDF...' : 'Download Report',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 4,
            shadowColor: const Color(0xFF4F46E5).withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadReport() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      // Convert preferred analysis to Recommendation objects (real data)
      final preferredRecs = _preferredAnalysis.map((p) {
        return Recommendation(
          collegeName: p.collegeName,
          courseName: p.course,
          cutoff: p.collegeCutoff,
          probability: p.probability.round().clamp(0, 100),
          category: 'preferred',
        );
      }).toList();

      // Convert target colleges to Recommendation objects (real data)
      final targetRecs = _targetColleges.map((t) {
        return Recommendation(
          collegeName: t.collegeName,
          courseName: t.course,
          cutoff: 0,
          probability: t.score.round().clamp(0, 100),
          category: 'safe',
        );
      }).toList();

      await PdfReportGenerator.generateAndDownloadPdf(
        AnalysisPdfReportData(
          fileName: '${_buildFileName()}.pdf',
          name: widget.studentName,
          category: widget.category,
          cutoff: widget.studentCutoff,
          selectedCourse: widget.preferredCourse,
          summary:
              'Analysis for cutoff ${widget.studentCutoff.toStringAsFixed(1)} in ${widget.category.toUpperCase()} category. ${preferredRecs.length} preferred colleges analyzed, ${targetRecs.length} target colleges scored by weighted model.',
          preferredColleges: preferredRecs,
          safeColleges: targetRecs,
          selectedPreferredCollegeNames: widget.preferredCollegeNames,
          logoAssetPath: 'assets/image/category.png',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ PDF report generated successfully!'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }


  // ─── Helpers ───────────────────────────────────────────────
  Widget _sectionHeader(String title, Color color, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827))),
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      ),
    );
  }

  String _shortCourse(String course) {
    const map = {
      'Computer Science Engineering': 'CSE',
      'Information Technology': 'IT',
      'Electronics and Communication Engineering': 'ECE',
      'Electrical and Electronics Engineering': 'EEE',
      'Mechanical Engineering': 'ME',
      'Civil Engineering': 'CE',
      'Artificial Intelligence and Data Science': 'AI&DS',
    };
    return map[course] ?? (course.length > 5 ? course.substring(0, 5) : course);
  }

  String _buildFileName() {
    final now = DateTime.now();
    final safe = widget.studentName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return '${safe}_final_report_$date';
  }
}

// ─── Data Classes ──────────────────────────────────────────
class _PreferredAnalysis {
  final String collegeName;
  final String course;
  final double yourCutoff;
  final double collegeCutoff;
  final double probability;
  final String chanceLabel;

  _PreferredAnalysis({
    required this.collegeName,
    required this.course,
    required this.yourCutoff,
    required this.collegeCutoff,
    required this.probability,
    required this.chanceLabel,
  });
}

class _TargetCollege {
  final String collegeName;
  final String course;
  final double score;
  final String chanceLabel;

  _TargetCollege({
    required this.collegeName,
    required this.course,
    required this.score,
    required this.chanceLabel,
  });
}
