import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:guidex/models/college_option.dart';
import 'package:guidex/models/recommendation.dart';
import 'package:guidex/models/recommendation_result.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:8080';

  static const String _cloudRunBaseUrl = String.fromEnvironment(
    'CLOUD_API_BASE_URL',
    defaultValue: 'https://pathwise-backend-z43lsllm3q-el.a.run.app',
  );

  static const String _realDeviceHost =
      String.fromEnvironment('LOCAL_API_HOST', defaultValue: '192.168.1.100');

  static const String _apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const Duration _localProbeTimeout = Duration(seconds: 4);

  static String? _preferredBaseUrl;
  static List<String>? _cachedDistricts;
  static List<String>? _cachedCourses;

  static final RegExp _nonAlnumPattern = RegExp(r'[^a-z0-9]+');
  static final RegExp _spacePattern = RegExp(r'\s+');

  String _normalizeBaseUrl(String rawBaseUrl) {
    return rawBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  List<String> _baseCandidates() {
    final candidates = <String>[];

    final override = _normalizeBaseUrl(_apiBaseUrlOverride);
    if (override.isNotEmpty) {
      candidates.add(override);
      return candidates;
    }

    if (kIsWeb) {
      candidates.add(_cloudRunBaseUrl);
      candidates.add('http://localhost:8080');
      return candidates;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      candidates.add(_cloudRunBaseUrl);
      candidates.add(_androidEmulatorBaseUrl);
      candidates.add('http://$_realDeviceHost:8080');
      return candidates;
    }

    candidates.add(_cloudRunBaseUrl);
    candidates.add('http://$_realDeviceHost:8080');
    candidates.add('http://localhost:8080');
    return candidates;
  }

  List<String> _orderedBaseCandidates() {
    final candidates = _baseCandidates();
    final preferred = _preferredBaseUrl;

    if (preferred == null || preferred.trim().isEmpty) {
      return candidates;
    }

    final ordered = <String>[preferred, ...candidates];
    final seen = <String>{};

    return ordered
        .map(_normalizeBaseUrl)
        .where((base) => seen.add(base))
        .toList();
  }

  Duration _timeoutForBase(String base, {String path = ''}) {
    final normalizedBase = _normalizeBaseUrl(base);
    final normalizedCloud = _normalizeBaseUrl(_cloudRunBaseUrl);

    final isMetadataPath = path == '/api/courses' ||
        path == '/api/districts' ||
        path == '/api/available-courses' ||
        path == '/api/college-options';

    if (isMetadataPath) {
      if (normalizedBase == normalizedCloud) {
        return const Duration(seconds: 4);
      }
      return const Duration(seconds: 3);
    }

    if (normalizedBase == normalizedCloud) {
      return _requestTimeout;
    }
    return _localProbeTimeout;
  }

  Uri _buildUri(
    String base,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return Uri.parse('$base$path').replace(queryParameters: queryParameters);
  }

  String _normalizeCourseForApi(String course) {
    final raw = course.trim();
    if (raw.isEmpty) {
      return raw;
    }

    final normalized =
        raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

    const aliases = <String, String>{
      'cs': 'Computer Science Engineering',
      'cse': 'Computer Science Engineering',
      'computer science and engineering': 'Computer Science Engineering',
      'computer science engineering': 'Computer Science Engineering',
      'ec': 'Electronics and Communication Engineering',
      'ee': 'Electrical and Electronics Engineering',
      'ei': 'Electronics and Instrumentation Engineering',
      'it': 'Information Technology',
      'ece': 'Electronics and Communication Engineering',
      'eee': 'Electrical and Electronics Engineering',
      'ad': 'Artificial Intelligence and Data Science',
      'am': 'Artificial Intelligence and Machine Learning',
      'mech': 'Mechanical Engineering',
      'me': 'Mechanical Engineering',
      'ce': 'Civil Engineering',
      'civil': 'Civil Engineering',
      'bt': 'Biotechnology',
      'bme': 'Biomedical Engineering',
    };

    return aliases[normalized] ?? raw;
  }

  Future<RecommendationResult> getRecommendationResult({
    required String category,
    required double cutoff,
    required String preferredCourse,
    String? district,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final body = <String, dynamic>{
      'student_cutoff': cutoff,
      'category': category.trim().toUpperCase(),
      'preferred_course': _normalizeCourseForApi(preferredCourse),
      'preferred_colleges': preferredCollegeIds.take(5).toList(),
    };

    final normalizedDistrict = district?.trim();
    if (normalizedDistrict != null &&
        normalizedDistrict.isNotEmpty &&
        normalizedDistrict.toLowerCase() != 'any') {
      body['district'] = normalizedDistrict;
    }

    Object? lastError;
    for (final base in _orderedBaseCandidates()) {
      final uri = _buildUri(base, '/api/recommend');
      debugPrint('Recommendation request URL: $uri');

      try {
        final timeout = _timeoutForBase(base, path: '/api/recommend');
        final response = await http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(timeout);

        debugPrint('Recommendation response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          final parsed = _parseRecommendationResponse(
            decoded,
            preferredCollegeIds: preferredCollegeIds,
            preferredCollegeNames: preferredCollegeNames,
          );
          final result = _enforceRecommendationRules(
            parsed,
            preferredCourse: preferredCourse,
            preferredCollegeIds: preferredCollegeIds,
            preferredCollegeNames: preferredCollegeNames,
          );

          _preferredBaseUrl = _normalizeBaseUrl(base);
          return result;
        }

        if (response.statusCode == 404 ||
            response.statusCode == 405 ||
            response.statusCode == 415) {
          final legacy = await _tryLegacyRecommendation(
            base: base,
            category: category,
            cutoff: cutoff,
            preferredCourse: preferredCourse,
            district: normalizedDistrict,
            preferredCollegeIds: preferredCollegeIds,
            preferredCollegeNames: preferredCollegeNames,
          );

          if (legacy != null) {
            _preferredBaseUrl = _normalizeBaseUrl(base);
            return _enforceRecommendationRules(
              legacy,
              preferredCourse: preferredCourse,
              preferredCollegeIds: preferredCollegeIds,
              preferredCollegeNames: preferredCollegeNames,
            );
          }
        }

        lastError = Exception(
          'Recommendation API failed with status ${response.statusCode}',
        );
      } on TimeoutException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is TimeoutException) {
      throw TimeoutException(
          'Recommendation request timed out', _requestTimeout);
    }

    throw Exception('Failed to fetch recommendations');
  }

  Future<List<Recommendation>> getRecommendations({
    required String category,
    required double cutoff,
    required String interest,
    String? district,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final grouped = await getRecommendationResult(
      category: category,
      cutoff: cutoff,
      preferredCourse: interest,
      district: district,
      preferredCollegeIds: preferredCollegeIds,
      preferredCollegeNames: preferredCollegeNames,
    );

    return grouped.all;
  }

  Future<List<CollegeOption>> getCollegeOptions({
    required String preferredCourse,
    String? district,
    String? category,
    double? cutoff,
  }) async {
    if (preferredCourse.trim().isEmpty) {
      return const [];
    }

    final queryParams = <String, String>{
      'preferred_course': _normalizeCourseForApi(preferredCourse),
    };

    final normalizedDistrict = district?.trim();
    if (normalizedDistrict != null &&
        normalizedDistrict.isNotEmpty &&
        normalizedDistrict.toLowerCase() != 'any') {
      queryParams['district'] = normalizedDistrict;
    }

    Object? lastError;

    for (final base in _orderedBaseCandidates()) {
      final uri =
          _buildUri(base, '/api/college-options', queryParameters: queryParams);
      debugPrint('College options request URL: $uri');

      try {
        final timeout = _timeoutForBase(base, path: '/api/college-options');
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode == 404 || response.statusCode == 405) {
          final legacyOptions = await _tryLegacyCollegeOptions(
            base: base,
            category: category,
            cutoff: cutoff,
            preferredCourse: preferredCourse,
            district: normalizedDistrict,
          );

          if (legacyOptions != null) {
            _preferredBaseUrl = _normalizeBaseUrl(base);
            return legacyOptions;
          }
        }

        if (response.statusCode != 200) {
          lastError = Exception(
            'College options API failed with status ${response.statusCode}',
          );
          continue;
        }

        final decoded = json.decode(response.body);
        if (decoded is! List) {
          continue;
        }

        final options = decoded
            .whereType<Map>()
            .map((entry) => CollegeOption.fromJson(
                  Map<String, dynamic>.from(entry),
                ))
            .where((item) =>
                item.collegeId.trim().isNotEmpty &&
                item.collegeName.trim().isNotEmpty)
            .toList();

        _preferredBaseUrl = _normalizeBaseUrl(base);
        return options;
      } on TimeoutException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }

    debugPrint('Failed to fetch college options. Last error: $lastError');
    return const [];
  }

  Future<List<String>> getDistricts() async {
    final cached = _cachedDistricts;
    if (cached != null && cached.isNotEmpty) {
      return List<String>.from(cached);
    }

    final fetched = await _getStringList('/api/districts');
    if (fetched.isNotEmpty) {
      _cachedDistricts = List<String>.from(fetched);
    }
    return fetched;
  }

  Future<List<String>> getCourses() async {
    final cached = _cachedCourses;
    if (cached != null && cached.isNotEmpty) {
      return List<String>.from(cached);
    }

    final fetched = await _getStringList('/api/courses');
    if (fetched.isNotEmpty) {
      _cachedCourses = List<String>.from(fetched);
    }
    return fetched;
  }

  Future<List<String>> getAvailableCourses({
    required String category,
    required double cutoff,
  }) async {
    final queryParams = <String, String>{
      'category': category.trim().toUpperCase(),
      'cutoff': cutoff.toString(),
    };

    Object? lastError;
    for (final base in _orderedBaseCandidates()) {
      final uri = _buildUri(base, '/api/available-courses',
          queryParameters: queryParams);

      try {
        final timeout = _timeoutForBase(base, path: '/api/available-courses');
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode != 200) {
          lastError = Exception(
              'Available courses API failed with status ${response.statusCode}');
          continue;
        }

        final decoded = json.decode(response.body);
        if (decoded is List) {
          _preferredBaseUrl = _normalizeBaseUrl(base);
          return decoded
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toList();
        }
      } on TimeoutException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }

    debugPrint('Failed available courses request. Last error: $lastError');
    return [];
  }

  Future<List<String>> _getStringList(String path) async {
    Object? lastError;
    for (final base in _orderedBaseCandidates()) {
      final uri = _buildUri(base, path);

      try {
        final timeout = _timeoutForBase(base, path: path);
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode != 200) {
          lastError =
              Exception('List API failed with status ${response.statusCode}');
          continue;
        }

        final decoded = json.decode(response.body);
        if (decoded is List) {
          _preferredBaseUrl = _normalizeBaseUrl(base);
          return decoded
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toList();
        }
      } on TimeoutException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }

    debugPrint('Failed list request for $path. Last error: $lastError');
    return [];
  }

  RecommendationResult _parseGroupedRecommendations(dynamic decoded) {
    if (decoded is! Map) {
      return const RecommendationResult.empty();
    }

    final map = Map<String, dynamic>.from(decoded);

    List<Recommendation> parseList(dynamic rawList, String forcedCategory) {
      if (rawList is! List) {
        return const [];
      }

      return rawList.whereType<Map>().map((entry) {
        final jsonEntry = Map<String, dynamic>.from(entry);
        jsonEntry['category'] = forcedCategory;
        jsonEntry['recommendation_type'] = forcedCategory;
        return Recommendation.fromJson(jsonEntry);
      }).toList();
    }

    final preferred = parseList(
      map['preferred_colleges'] ?? map['preferredColleges'] ?? const [],
      'preferred',
    );

    final safe = parseList(
      map['safe_colleges'] ?? map['safeColleges'] ?? const [],
      'safe',
    );

    return RecommendationResult(
      preferredColleges: preferred,
      safeColleges: safe,
    );
  }

  RecommendationResult _enforceRecommendationRules(
    RecommendationResult source, {
    required String preferredCourse,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) {
    final requestedBranchCode = _resolveBranchCode(preferredCourse);
    if (requestedBranchCode == null || requestedBranchCode.isEmpty) {
      return source;
    }

    final deduped = <String, Recommendation>{};
    for (final item in source.all) {
      final itemBranch = _resolveBranchCode(item.courseName);
      if (itemBranch == null || itemBranch != requestedBranchCode) {
        continue;
      }

      final key =
          '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      final existing = deduped[key];
      if (existing == null || item.probability > existing.probability) {
        deduped[key] = item;
      }
    }

    final all = deduped.values.toList();

    final preferredTokens = {
      ...preferredCollegeIds.map(_normalizeToken),
      ...preferredCollegeNames.map(_normalizeToken),
    }.where((value) => value.isNotEmpty).toSet();

    int compareByPriority(Recommendation a, Recommendation b) {
      final byProbability = b.probability.compareTo(a.probability);
      if (byProbability != 0) {
        return byProbability;
      }
      final byCutoff = b.cutoff.compareTo(a.cutoff);
      if (byCutoff != 0) {
        return byCutoff;
      }
      return a.collegeName.toLowerCase().compareTo(b.collegeName.toLowerCase());
    }

    bool isSelectedPreferred(Recommendation item) {
      final collegeToken = _normalizeToken(item.collegeName);
      if (collegeToken.isEmpty) {
        return false;
      }

      for (final token in preferredTokens) {
        if (token.isEmpty) {
          continue;
        }

        if (collegeToken == token ||
            collegeToken.contains(token) ||
            token.contains(collegeToken)) {
          return true;
        }
      }

      return false;
    }

    final mandatoryPreferredKeys = <String>{
      ...source.preferredColleges
          .where((item) =>
              _resolveBranchCode(item.courseName) == requestedBranchCode)
          .map((item) =>
              '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}'),
      ...all.where(isSelectedPreferred).map((item) =>
          '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}'),
    };

    final preferred = all.where((item) {
      final key =
          '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      return mandatoryPreferredKeys.contains(key) || item.probability >= 70;
    }).toList()
      ..sort(compareByPriority);

    final safe = all.where((item) {
      final key =
          '${_normalizeToken(item.collegeName)}|${_normalizeToken(item.courseName)}';
      if (mandatoryPreferredKeys.contains(key)) {
        return false;
      }
      return item.probability >= 40 && item.probability <= 69;
    }).toList()
      ..sort(compareByPriority);

    return RecommendationResult(
      preferredColleges: preferred,
      safeColleges: safe.take(15).toList(),
    );
  }

  String? _resolveBranchCode(String rawCourse) {
    final trimmed = rawCourse.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final upper = trimmed.toUpperCase();
    if (!upper.contains(' ')) {
      return upper;
    }

    final normalized = _normalizeCourseToken(trimmed);

    switch (normalized) {
      case 'computer science':
      case 'computer science engineering':
      case 'computer science and engineering':
        return 'CS';
      case 'artificial intelligence and data science':
      case 'ai and data science':
      case 'ai ds':
      case 'ai&ds':
        return 'AD';
      case 'artificial intelligence and machine learning':
      case 'ai and machine learning':
      case 'ai ml':
        return 'AM';
      case 'electronics and communication engineering':
        return 'EC';
      case 'electrical and electronics engineering':
        return 'EE';
      case 'electronics and instrumentation engineering':
        return 'EI';
      case 'information technology':
        return 'IT';
      case 'civil engineering':
        return 'CE';
      case 'mechanical engineering':
        return 'ME';
      case 'biomedical engineering':
        return 'BME';
      default:
        return null;
    }
  }

  String _normalizeCourseToken(String value) {
    final lowered = value.toLowerCase();
    final alnum = lowered.replaceAll(_nonAlnumPattern, ' ');
    return alnum.replaceAll(_spacePattern, ' ').trim();
  }

  RecommendationResult _parseRecommendationResponse(
    dynamic decoded, {
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) {
    if (decoded is Map) {
      return _parseGroupedRecommendations(decoded);
    }

    return _parseLegacyRecommendations(
      decoded,
      preferredCollegeIds: preferredCollegeIds,
      preferredCollegeNames: preferredCollegeNames,
    );
  }

  RecommendationResult _parseLegacyRecommendations(
    dynamic decoded, {
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) {
    if (decoded is! List) {
      return const RecommendationResult.empty();
    }

    final preferredTokens = {
      ...preferredCollegeIds.map(_normalizeToken),
      ...preferredCollegeNames.map(_normalizeToken),
    }.where((value) => value.isNotEmpty).toSet();

    final preferred = <Recommendation>[];
    final safe = <Recommendation>[];

    for (final entry in decoded.whereType<Map>()) {
      final recommendation =
          Recommendation.fromJson(Map<String, dynamic>.from(entry));
      final collegeToken = _normalizeToken(recommendation.collegeName);

      final isPreferred = preferredTokens.any((token) {
        if (token.isEmpty) {
          return false;
        }

        if (collegeToken == token) {
          return true;
        }

        return collegeToken.contains(token) || token.contains(collegeToken);
      });

      final tagged = _withCategory(
        recommendation,
        isPreferred ? 'preferred' : 'safe',
      );

      if (isPreferred) {
        preferred.add(tagged);
      } else {
        safe.add(tagged);
      }
    }

    return RecommendationResult(
      preferredColleges: preferred,
      safeColleges: safe,
    );
  }

  Recommendation _withCategory(Recommendation item, String category) {
    return Recommendation(
      collegeName: item.collegeName,
      courseName: item.courseName,
      cutoff: item.cutoff,
      probability: item.probability,
      category: category,
      district: item.district,
      collegeType: item.collegeType,
      collegeRank: item.collegeRank,
    );
  }

  String _normalizeToken(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<RecommendationResult?> _tryLegacyRecommendation({
    required String base,
    required String category,
    required double cutoff,
    required String preferredCourse,
    String? district,
    List<String> preferredCollegeIds = const [],
    List<String> preferredCollegeNames = const [],
  }) async {
    final queryParams = <String, String>{
      'category': category.trim().toUpperCase(),
      'cutoff': cutoff.toString(),
      'interest': _normalizeCourseForApi(preferredCourse),
    };

    final uri = _buildUri(base, '/api/recommend', queryParameters: queryParams);

    final response = await http
        .get(uri)
        .timeout(_timeoutForBase(base, path: '/api/recommend'));

    if (response.statusCode != 200) {
      return null;
    }

    final decoded = json.decode(response.body);
    final parsed = _parseLegacyRecommendations(
      decoded,
      preferredCollegeIds: preferredCollegeIds,
      preferredCollegeNames: preferredCollegeNames,
    );

    final normalizedDistrict = district?.trim();
    if (normalizedDistrict == null ||
        normalizedDistrict.isEmpty ||
        normalizedDistrict.toLowerCase() == 'any') {
      return parsed;
    }

    final filteredSafe = parsed.safeColleges
        .where((item) => _matchesDistrict(item, normalizedDistrict))
        .toList();

    return RecommendationResult(
      preferredColleges: parsed.preferredColleges,
      safeColleges: filteredSafe,
    );
  }

  bool _matchesDistrict(Recommendation item, String district) {
    final districtToken = _normalizeToken(district);
    if (districtToken.isEmpty) {
      return true;
    }

    final recommendationDistrict = _normalizeToken(item.district ?? '');
    if (recommendationDistrict.isNotEmpty) {
      return recommendationDistrict == districtToken;
    }

    final collegeToken = _normalizeToken(item.collegeName);
    return collegeToken.contains(districtToken);
  }

  Future<List<CollegeOption>?> _tryLegacyCollegeOptions({
    required String base,
    required String preferredCourse,
    String? category,
    double? cutoff,
    String? district,
  }) async {
    final effectiveCategory = category?.trim().toUpperCase();
    if (effectiveCategory == null || effectiveCategory.isEmpty) {
      return null;
    }

    if (cutoff == null || cutoff <= 0) {
      return null;
    }

    final queryParams = <String, String>{
      'category': effectiveCategory,
      'cutoff': cutoff.toString(),
      'interest': _normalizeCourseForApi(preferredCourse),
    };

    if (district != null &&
        district.isNotEmpty &&
        district.toLowerCase() != 'any') {
      queryParams['district'] = district;
    }

    final uri = _buildUri(base, '/api/recommend', queryParameters: queryParams);
    final response = await http
        .get(uri)
        .timeout(_timeoutForBase(base, path: '/api/recommend'));

    if (response.statusCode != 200) {
      return null;
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      return null;
    }

    final byId = <String, CollegeOption>{};
    for (final entry in decoded.whereType<Map>()) {
      final rec = Recommendation.fromJson(Map<String, dynamic>.from(entry));
      final id = rec.collegeName.trim();
      if (id.isEmpty) {
        continue;
      }

      byId.putIfAbsent(
        id,
        () => CollegeOption(
          collegeId: id,
          collegeName: rec.collegeName,
          district: rec.district,
        ),
      );
    }

    final options = byId.values.toList()
      ..sort(
        (a, b) =>
            a.collegeName.toLowerCase().compareTo(b.collegeName.toLowerCase()),
      );

    return options;
  }
}
