package com.pathwise.backend.service;

import com.pathwise.backend.dto.CollegeOptionResponse;
import com.pathwise.backend.dto.RecommendationResponse;
import com.pathwise.backend.dto.TargetCollegeResponse;
import com.pathwise.backend.repository.CutoffHistoryRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class RecommendationService {

    private final CutoffHistoryRepository cutoffHistoryRepository;

    public RecommendationService(CutoffHistoryRepository cutoffHistoryRepository) {
        this.cutoffHistoryRepository = cutoffHistoryRepository;
    }

    private static class StrictScore {
        double probability;
        String label;
        String reason;
    }

    private StrictScore calculateStrictScore(Double studentCutoff, Double collegeCutoff, boolean locationMatch, boolean hostelAvailable) {
        double diff = studentCutoff - collegeCutoff;
        double baseProb = 0.0;
        String reason = "";

        if (diff >= 5) {
            baseProb = 90.0 + Math.min(5.0, (diff - 5) * 0.5);
            reason = String.format("Your cutoff is %.2f marks higher than the closing cutoff, making admission highly likely.", diff);
        } else if (diff >= 0) {
            baseProb = 70.0 + (diff * 3.0); 
            reason = String.format("Your cutoff is %.2f marks higher than the closing cutoff, giving you a strong chance.", diff);
        } else if (diff >= -2) {
            baseProb = 40.0 + ((diff + 2) * 10.0);
            reason = String.format("Your cutoff is %.2f marks lower than the closing cutoff. Admission is possible but competitive.", Math.abs(diff));
        } else if (diff >= -5) {
            baseProb = 15.0 + ((diff + 5) * 8.33);
            reason = String.format("Your cutoff is %.2f marks lower than the closing cutoff. Admission chances are low.", Math.abs(diff));
        } else if (diff >= -10) {
            baseProb = 5.0 + ((diff + 10) * 2.0);
            reason = String.format("Your cutoff is %.2f marks significantly lower than the closing cutoff.", Math.abs(diff));
        } else {
            baseProb = Math.max(0.0, 5.0 + ((diff + 10) * 0.5));
            reason = String.format("Your cutoff is %.2f marks below the closing cutoff, making admission almost impossible.", Math.abs(diff));
        }
        
        // Adjustment (+/- 5% max)
        double adjustment = 0;
        if (locationMatch) {
            adjustment += 5;
        } else if (hostelAvailable) {
            // Location mismatch but hostel is available
            adjustment += 2;
            reason += " (Hostel facility available for outstation students)";
        } else {
            // Location mismatch and NO hostel
            adjustment -= 3;
            reason += " (Note: Outside preferred location with no hostel facility)";
        }
        
        double finalProb = Math.min(95.0, Math.max(0.0, baseProb + adjustment));
        
        // STRICT RULE: NEVER give high probability if student_cutoff < college_cutoff
        if (diff < 0 && finalProb > 60) finalProb = 55.0; 
        if (diff < -5 && finalProb > 30) finalProb = 25.0;
        
        String label;
        if (finalProb >= 80) label = "Excellent";
        else if (finalProb >= 60) label = "Good";
        else if (finalProb >= 40) label = "Moderate";
        else if (finalProb >= 20) label = "Low";
        else label = "Very Low / Dream";
        
        StrictScore score = new StrictScore();
        score.probability = Math.round(finalProb * 100.0) / 100.0;
        score.label = label;
        score.reason = reason;
        return score;
    }


    // ========================================================================
    // MAIN ENDPOINT: Returns both Preferred Analysis + Target Colleges
    // ========================================================================
    @Transactional(readOnly = true)
    public TargetCollegeResponse getTargetColleges(
            Double studentCutoff,
            String community,
            String preferredCity,
            String preferredCourse,
            String hostelRequired,
            List<String> preferredColleges) {

        String comm = community.toLowerCase(Locale.ROOT);
        List<Object[]> rows = cutoffHistoryRepository.findTargetColleges(comm);

        // ⭐ SECTION 1: Preferred Colleges Analysis (probability formula)
        List<TargetCollegeResponse.PreferredCollegeAnalysis> preferredAnalysis = new ArrayList<>();
        Set<String> seenPreferred = new HashSet<>();

        // 🎯 SECTION 2: Target Colleges (weighted scoring)
        Map<String, TargetCollegeResponse.TargetCollege> targetMap = new LinkedHashMap<>();

        // Resolve course aliases for matching
        String prefCourseLower = preferredCourse != null ? preferredCourse.toLowerCase() : "";

        for (Object[] row : rows) {
            String collegeName = String.valueOf(row[0]);
            String branchName = String.valueOf(row[1]);
            Double collegeCutoff = convertToDouble(row[2]);
            String city = String.valueOf(row[3]);
            String district = String.valueOf(row[4]);
            String branchCode = String.valueOf(row[5]);

            if (collegeCutoff == null || collegeCutoff <= 0) continue;

            String branchLower = branchName.toLowerCase();

            // --- Check if this college is in the user's preferred list ---
            boolean isPreferred = false;
            if (preferredColleges != null) {
                for (String pref : preferredColleges) {
                    if (collegeName.toLowerCase().contains(pref.toLowerCase())
                            || pref.toLowerCase().contains(collegeName.toLowerCase())) {
                        isPreferred = true;
                        break;
                    }
                }
            }

            // ⭐ Preferred: ONLY include rows matching the user's chosen course
            if (isPreferred && matchesCourse(prefCourseLower, branchLower)) {
                String dedupeKey = collegeName.toLowerCase();
                if (seenPreferred.add(dedupeKey)) {
                    boolean locationMatch = false;
                    if (preferredCity != null && !preferredCity.isEmpty() && !preferredCity.equalsIgnoreCase("any")) {
                        if (district != null && district.toLowerCase().contains(preferredCity.toLowerCase())) locationMatch = true;
                        if (city != null && city.toLowerCase().contains(preferredCity.toLowerCase())) locationMatch = true;
                    } else {
                        locationMatch = true;
                    }

                    boolean hostelMatch = "yes".equalsIgnoreCase(hostelRequired);

                    StrictScore strictScore = calculateStrictScore(studentCutoff, collegeCutoff, locationMatch, hostelMatch);

                    preferredAnalysis.add(TargetCollegeResponse.PreferredCollegeAnalysis.builder()
                            .college_name(collegeName)
                            .course(branchName)
                            .your_cutoff(studentCutoff)
                            .college_cutoff(collegeCutoff)
                            .probability(strictScore.probability)
                            .chance_label(strictScore.label)
                            .reason(strictScore.reason)
                            .build());
                }
            }

            // 🎯 Target: only include rows matching preferred course, deduplicate by college
            if (matchesCourse(prefCourseLower, branchLower)) {
                double score = calculateWeightedScore(
                        studentCutoff, collegeCutoff,
                        preferredCity, city, district,
                        preferredCourse, branchCode, branchName,
                        hostelRequired,
                        collegeName, preferredColleges
                );

                String key = collegeName.toLowerCase();
                TargetCollegeResponse.TargetCollege existing = targetMap.get(key);
                double roundedScore = Math.round(score * 100.0) / 100.0;

                if (existing == null || roundedScore > existing.getScore()) {
                    targetMap.put(key, TargetCollegeResponse.TargetCollege.builder()
                            .college_name(collegeName)
                            .course(branchName)
                            .score(roundedScore)
                            .chance_label(getWeightedChanceLabel(score))
                            .build());
                }
            }
        }

        // Sort preferred by probability DESC
        preferredAnalysis.sort(Comparator.comparing(
                TargetCollegeResponse.PreferredCollegeAnalysis::getProbability).reversed());

        // Sort target by score DESC and take top 10
        List<TargetCollegeResponse.TargetCollege> top10 = targetMap.values().stream()
                .sorted(Comparator.comparing(TargetCollegeResponse.TargetCollege::getScore).reversed())
                .limit(10)
                .collect(Collectors.toList());

        return TargetCollegeResponse.builder()
                .preferred_colleges_analysis(preferredAnalysis)
                .target_colleges(top10)
                .build();
    }

    // ========================================================================
    // FINAL REPORT ENDPOINT: Generates top 5 Safe (Preferred) + 15 Target
    // ========================================================================
    @Transactional(readOnly = true)
    public com.pathwise.backend.dto.FinalReportResponse generateFinalReport(com.pathwise.backend.dto.FinalReportRequest request) {
        String comm = request.getCategory() != null ? request.getCategory().toLowerCase(Locale.ROOT) : "oc";
        List<Object[]> rows = cutoffHistoryRepository.findTargetColleges(comm);

        String studentName = request.getStudentName() != null ? request.getStudentName() : "Student";
        Double studentCutoff = request.getStudentCutoff() != null ? request.getStudentCutoff() : 0.0;
        String preferredCourse = request.getPreferredCourse() != null ? request.getPreferredCourse() : "";
        String preferredDistrict = request.getDistrict() != null ? request.getDistrict() : "Any";
        Boolean hostelRequired = request.getHostelRequired() != null && request.getHostelRequired();
        List<String> preferredCollegeNames = request.getPreferredCollegeNames() != null ? request.getPreferredCollegeNames() : new ArrayList<>();

        List<com.pathwise.backend.dto.FinalReportResponse.SafeCollegeResponse> safeColleges = new ArrayList<>();
        Map<String, com.pathwise.backend.dto.FinalReportResponse.TargetCollegeResponse> targetMap = new LinkedHashMap<>();

        String prefCourseLower = preferredCourse.toLowerCase().trim();
        
        // Track which original preferred names were found
        Set<String> foundOriginalPrefs = new HashSet<>();

        System.out.println("Generating Final Report for student: " + studentName);
        System.out.println("Preferred Colleges Input: " + preferredCollegeNames);
        System.out.println("Rows count from DB: " + rows.size());

        for (Object[] row : rows) {
            String collegeName = String.valueOf(row[0]);
            String branchName = String.valueOf(row[1]);
            Double collegeCutoff = convertToDouble(row[2]);
            String city = String.valueOf(row[3]);
            String district = String.valueOf(row[4]);
            String branchCode = String.valueOf(row[5]);
            boolean actualHostel = false;
            if (row.length > 6 && row[6] != null) {
                Object hostelObj = row[6];
                if (hostelObj instanceof Boolean) actualHostel = (Boolean) hostelObj;
                else if (hostelObj instanceof Number) actualHostel = ((Number) hostelObj).intValue() == 1;
            }

            if (collegeCutoff == null || collegeCutoff <= 0) continue;

            String collegeNameLower = collegeName.toLowerCase().replaceAll("[^a-z0-9]", " ").replaceAll("\\s+", " ").trim();
            String branchLower = branchName.toLowerCase().trim();

            // ⭐ STEP 1: FILTER DATA - Match course based on interest_area
            // We only apply this filter for TARGET recommendations.
            // For PREFERRED choices, we want to know if the college exists AT ALL to give a better reason.
            boolean courseMatches = matchesCourse(prefCourseLower, branchLower);

            // Check if this college is one of the preferred choices
            boolean isPreferred = false;
            String matchedOriginalPref = null;
            for (String pref : preferredCollegeNames) {
                String normPref = pref.toLowerCase().replaceAll("[^a-z0-9]", " ").replaceAll("\\s+", " ").trim();
                if (collegeNameLower.contains(normPref) || normPref.contains(collegeNameLower)) {
                    isPreferred = true;
                    matchedOriginalPref = pref;
                    break;
                }
            }

            boolean locationMatch = false;
            if (!preferredDistrict.isEmpty() && !preferredDistrict.equalsIgnoreCase("any")) {
                if (district != null && district.toLowerCase().contains(preferredDistrict.toLowerCase())) locationMatch = true;
                if (city != null && city.toLowerCase().contains(preferredDistrict.toLowerCase())) locationMatch = true;
            } else {
                locationMatch = true;
            }

            if (isPreferred) {
                System.out.println("Found Preferred College Match: " + collegeName + " (Course Match: " + courseMatches + ")");
                if (courseMatches) {
                    foundOriginalPrefs.add(matchedOriginalPref);
                    StrictScore strictScore = calculateStrictScore(studentCutoff, collegeCutoff, locationMatch, actualHostel);
                    
                    boolean alreadyAdded = false;
                    for (int i = 0; i < safeColleges.size(); i++) {
                        if (safeColleges.get(i).getCollegeName().equalsIgnoreCase(collegeName)) {
                            alreadyAdded = true;
                            if (strictScore.probability > safeColleges.get(i).getProbability()) {
                                safeColleges.set(i, com.pathwise.backend.dto.FinalReportResponse.SafeCollegeResponse.builder()
                                        .collegeName(collegeName)
                                        .course(branchName)
                                        .collegeCutoff(collegeCutoff)
                                        .probability(strictScore.probability)
                                        .chanceLabel(strictScore.label)
                                        .reason(strictScore.reason)
                                        .isAvailable(true)
                                        .build());
                            }
                            break;
                        }
                    }
                    
                    if (!alreadyAdded) {
                        safeColleges.add(com.pathwise.backend.dto.FinalReportResponse.SafeCollegeResponse.builder()
                                .collegeName(collegeName)
                                .course(branchName)
                                .collegeCutoff(collegeCutoff)
                                .probability(strictScore.probability)
                                .chanceLabel(strictScore.label)
                                .reason(strictScore.reason)
                                .isAvailable(true)
                                .build());
                    }
                }
            } else if (courseMatches) {
                double score = calculateWeightedScore(studentCutoff, collegeCutoff, preferredDistrict, city, district, preferredCourse, branchCode, branchName, hostelRequired ? "yes" : "no", collegeName, preferredCollegeNames);
                
                String key = collegeNameLower;
                if (!targetMap.containsKey(key) || score > targetMap.get(key).getScorePercentage()) {
                    targetMap.put(key, com.pathwise.backend.dto.FinalReportResponse.TargetCollegeResponse.builder()
                            .collegeName(collegeName)
                            .course(branchName)
                            .cutoff(collegeCutoff)
                            .scorePercentage(Math.round(score * 10.0) / 10.0)
                            .chanceLabel(getWeightedChanceLabel(score))
                            .locationScore(locationMatch ? 1.0 : 0.5)
                            .build());
                }
            }
        }

        // Handle preferred colleges NOT found in DB for this course/category
        System.out.println("Found " + foundOriginalPrefs.size() + " original prefs in matches.");
        for (String pref : preferredCollegeNames) {
            if (!foundOriginalPrefs.contains(pref)) {
                System.out.println("Adding 'Not Available' for: " + pref);
                safeColleges.add(com.pathwise.backend.dto.FinalReportResponse.SafeCollegeResponse.builder()
                        .collegeName(pref)
                        .course(preferredCourse)
                        .isAvailable(false)
                        .chanceLabel("Not Available")
                        .reason("This college does not have a registered cutoff for " + preferredCourse + " in the " + comm.toUpperCase() + " category.")
                        .probability(0.0)
                        .build());
            }
        }

        // Sort: Found colleges first (by probability DESC), then Not Found colleges
        safeColleges.sort((a, b) -> {
            boolean aAvail = a.getIsAvailable() != null && a.getIsAvailable();
            boolean bAvail = b.getIsAvailable() != null && b.getIsAvailable();
            if (aAvail && !bAvail) return -1;
            if (!aAvail && bAvail) return 1;
            
            Double aProb = a.getProbability() != null ? a.getProbability() : 0.0;
            Double bProb = b.getProbability() != null ? b.getProbability() : 0.0;
            return bProb.compareTo(aProb);
        });

        List<com.pathwise.backend.dto.FinalReportResponse.SafeCollegeResponse> finalSafeColleges = safeColleges.stream().limit(10).collect(Collectors.toList());

        // Sort targetColleges by finalScore descending and limit to 15
        List<com.pathwise.backend.dto.FinalReportResponse.TargetCollegeResponse> sortedTargets = targetMap.values().stream()
                .sorted(Comparator.comparing(com.pathwise.backend.dto.FinalReportResponse.TargetCollegeResponse::getScorePercentage).reversed())
                .limit(15)
                .collect(Collectors.toList());

        return com.pathwise.backend.dto.FinalReportResponse.builder()
                .studentName(request.getStudentName() != null ? request.getStudentName() : "Student")
                .studentCutoff(studentCutoff)
                .studentCategory(request.getCategory() != null ? request.getCategory().toUpperCase() : "")
                .preferredCourse(preferredCourse)
                .preferredLocation(preferredDistrict)
                .hostelRequired(hostelRequired)
                .safeColleges(finalSafeColleges)
                .targetColleges(sortedTargets)
                .build();
    }

    // ========================================================================
    // ⭐ PREFERRED COLLEGES: Simple Probability Formula
    // probability = (student_cutoff / college_cutoff) × 100
    // Then tiered into realistic ranges
    // ========================================================================
    private double calculateProbability(Double studentCutoff, Double collegeCutoff) {
        double ratio = studentCutoff / collegeCutoff;

        if (ratio >= 1.0) {
            // Student cutoff >= college cutoff → 90-95%
            // The higher the ratio, the closer to 95%
            return Math.min(95.0, 90.0 + (ratio - 1.0) * 50.0);
        } else if (ratio >= 0.9) {
            // 0.9 to 1.0 → 75-90%
            double t = (ratio - 0.9) / 0.1; // 0 to 1 within range
            return 75.0 + t * 15.0;
        } else if (ratio >= 0.8) {
            // 0.8 to 0.9 → 60-75%
            double t = (ratio - 0.8) / 0.1;
            return 60.0 + t * 15.0;
        } else if (ratio >= 0.7) {
            // 0.7 to 0.8 → 40-60%
            double t = (ratio - 0.7) / 0.1;
            return 40.0 + t * 20.0;
        } else {
            // Below 0.7 → 10-40%
            double t = Math.max(0, ratio / 0.7);
            return 10.0 + t * 30.0;
        }
    }

    private String getProbabilityLabel(double probability) {
        if (probability >= 80) return "Strong";
        if (probability >= 60) return "Moderate";
        if (probability >= 40) return "Competitive";
        return "Dream";
    }

    // ========================================================================
    // 🎯 TARGET COLLEGES: Weighted Scoring Model
    // Score = 0.4×Cutoff + 0.2×Location + 0.15×Course + 0.1×Hostel
    //       + 0.1×Category + 0.05×Preference
    // ========================================================================
    private double calculateWeightedScore(
            Double studentCutoff, Double collegeCutoff,
            String preferredCity, String city, String district,
            String preferredCourse, String branchCode, String branchName,
            String hostelRequired,
            String collegeName, List<String> preferredColleges) {

        // 1. Cutoff Match Score (40%)
        double cutoffScore;
        double ratio = studentCutoff / collegeCutoff;
        if (ratio >= 1.0) {
            // Student meets or exceeds cutoff
            cutoffScore = Math.min(100, 80 + (ratio - 1.0) * 200);
        } else if (ratio >= 0.95) {
            cutoffScore = 70 + ((ratio - 0.95) / 0.05) * 10;
        } else if (ratio >= 0.9) {
            cutoffScore = 55 + ((ratio - 0.9) / 0.05) * 15;
        } else if (ratio >= 0.8) {
            cutoffScore = 30 + ((ratio - 0.8) / 0.1) * 25;
        } else {
            cutoffScore = Math.max(0, ratio * 37.5);
        }

        // 2. Location Match Score (20%)
        double locationScore = 30; // default: no match
        if (preferredCity != null && !preferredCity.isEmpty()) {
            String prefLower = preferredCity.toLowerCase();
            if (city != null && city.toLowerCase().contains(prefLower)) {
                locationScore = 100; // exact city match
            } else if (district != null && district.toLowerCase().contains(prefLower)) {
                locationScore = 70; // district match
            }
        } else {
            locationScore = 50; // no preference given
        }

        // 3. Course Interest Match (15%)
        double courseScore = 0;
        if (preferredCourse != null && !preferredCourse.isEmpty()) {
            String prefCourseLower = preferredCourse.toLowerCase();
            String branchLower = branchName != null ? branchName.toLowerCase() : "";
            String codeLower = branchCode != null ? branchCode.toLowerCase() : "";

            if (branchLower.contains(prefCourseLower) || codeLower.contains(prefCourseLower)
                    || prefCourseLower.contains(branchLower) || prefCourseLower.contains(codeLower)) {
                courseScore = 100; // course matches
            }
            // Partial match for common abbreviations
            else if (matchesCourseAlias(prefCourseLower, branchLower)) {
                courseScore = 80;
            }
        } else {
            courseScore = 50; // no preference
        }

        // 4. Hostel Facility Score (10%)
        double hostelScore = 50; // default neutral
        if ("yes".equalsIgnoreCase(hostelRequired)) {
            hostelScore = 70; // assume available unless we know otherwise
        }

        // 5. Category Advantage (10%)
        double categoryScore;
        if (ratio >= 1.0) {
            categoryScore = 100; // student cutoff exceeds college
        } else if (ratio >= 0.95) {
            categoryScore = 75;
        } else if (ratio >= 0.9) {
            categoryScore = 50;
        } else {
            categoryScore = 25;
        }

        // 6. Preference Boost (5%)
        double preferenceScore = 0;
        if (preferredColleges != null) {
            for (String pref : preferredColleges) {
                if (collegeName.toLowerCase().contains(pref.toLowerCase())
                        || pref.toLowerCase().contains(collegeName.toLowerCase())) {
                    preferenceScore = 100;
                    break;
                }
            }
        }

        return (0.40 * cutoffScore) +
               (0.20 * locationScore) +
               (0.15 * courseScore) +
               (0.10 * hostelScore) +
               (0.10 * categoryScore) +
               (0.05 * preferenceScore);
    }

    /**
     * Check if a branch name matches the user's preferred course.
     * Uses direct substring match + alias expansion.
     */
    private boolean matchesCourse(String prefCourseLower, String branchLower) {
        if (prefCourseLower == null || prefCourseLower.trim().isEmpty()) return true; // no filter
        
        // Normalize: remove common suffix/prefix words and special characters
        String nPref = prefCourseLower.toLowerCase()
                .replaceAll("\\b(and|&|engineering|technology|engg|tech|branch|department)\\b", "")
                .replaceAll("[^a-z0-9]", " ")
                .replaceAll("\\s+", " ")
                .trim();
        String nActual = branchLower.toLowerCase()
                .replaceAll("\\b(and|&|engineering|technology|engg|tech|branch|department)\\b", "")
                .replaceAll("[^a-z0-9]", " ")
                .replaceAll("\\s+", " ")
                .trim();
        
        if (nPref.isEmpty() || nActual.isEmpty()) return false;
        
        // Check if normalized strings contain each other
        if (nActual.contains(nPref) || nPref.contains(nActual)) return true;

        // Check aliases if direct match fails
        return matchesCourseAlias(prefCourseLower.toLowerCase().trim(), branchLower.toLowerCase().trim());
    }

    /**
     * Match common course abbreviations like CS → Computer Science
     */
    private boolean matchesCourseAlias(String preferred, String actual) {
        Map<String, List<String>> aliases = Map.ofEntries(
                Map.entry("cs", List.of("computer science", "computer", "cse", "it")),
                Map.entry("cse", List.of("computer science", "computer", "cs", "it")),
                Map.entry("ece", List.of("electronics and communication", "electronics", "ec")),
                Map.entry("eee", List.of("electrical and electronics", "electrical", "ee")),
                Map.entry("mech", List.of("mechanical engineering", "mechanical", "me")),
                Map.entry("civil", List.of("civil engineering", "ce")),
                Map.entry("it", List.of("information technology", "cs", "cse")),
                Map.entry("ai", List.of("artificial intelligence", "ai and", "machine learning")),
                Map.entry("aids", List.of("artificial intelligence and data science", "ai", "data science")),
                Map.entry("ads", List.of("artificial intelligence and data science", "ai", "data science")),
                Map.entry("cyber", List.of("cyber security", "cybersecurity", "security")),
                Map.entry("bio", List.of("biotechnology", "biomedical", "bio technology", "bio medical"))
        );

        List<String> expandedAliases = aliases.getOrDefault(preferred, List.of());
        for (String alias : expandedAliases) {
            if (actual.contains(alias)) return true;
        }
        // Also check reverse
        for (Map.Entry<String, List<String>> entry : aliases.entrySet()) {
            if (entry.getValue().stream().anyMatch(a -> a.contains(preferred))) {
                if (actual.contains(entry.getKey())) return true;
            }
        }
        return false;
    }

    private String getWeightedChanceLabel(double score) {
        if (score >= 70) return "Strong Chance";
        if (score >= 50) return "Moderate";
        return "Dream";
    }

    // ========================================================================
    // Legacy /api/recommend endpoint
    // ========================================================================
    @Transactional(readOnly = true)
    public Map<String, List<RecommendationResponse>> getRecommendations(Double userCutoff, String userCommunity) {
        String community = userCommunity.toLowerCase(Locale.ROOT);
        List<Object[]> rows = cutoffHistoryRepository.findTargetColleges(community);

        List<RecommendationResponse> safeColleges = new ArrayList<>();
        List<RecommendationResponse> preferredColleges = new ArrayList<>();

        for (Object[] row : rows) {
            String collegeName = String.valueOf(row[0]);
            String branchName = String.valueOf(row[1]);
            Double cutoff = convertToDouble(row[2]);

            if (cutoff == null) continue;

            RecommendationResponse response = RecommendationResponse.builder()
                    .collegeName(collegeName)
                    .courseName(branchName)
                    .cutoff(cutoff)
                    .category(community.toUpperCase(Locale.ROOT))
                    .build();

            if (cutoff <= userCutoff) {
                safeColleges.add(response);
            } else if (cutoff > userCutoff && cutoff <= userCutoff + 5) {
                preferredColleges.add(response);
            }
        }

        Map<String, List<RecommendationResponse>> result = new LinkedHashMap<>();
        result.put("safe_colleges", safeColleges);
        result.put("preferred_colleges", preferredColleges);

        return result;
    }

    @Transactional(readOnly = true)
    public List<String> getAllCourses() {
        return cutoffHistoryRepository.findDistinctBranches();
    }

    public long getCollegeCount() {
        return cutoffHistoryRepository.count();
    }

    @Transactional(readOnly = true)
    public List<CollegeOptionResponse> getCollegeOptions(String courseName) {
        List<CollegeOptionResponse> options = new ArrayList<>();

        if (courseName == null || courseName.trim().isEmpty()) {
            List<Object[]> allColleges = cutoffHistoryRepository.findAllColleges();
            for (Object[] row : allColleges) {
                Long collegeId = convertToLong(row[0]);
                String collegeName = String.valueOf(row[1]);
                String district = String.valueOf(row[2]);

                options.add(CollegeOptionResponse.builder()
                        .collegeId(collegeId != null ? collegeId.toString() : "")
                        .collegeName(collegeName)
                        .district(district != null ? district : "")
                        .build());
            }
        } else {
            List<Object[]> colleges = cutoffHistoryRepository.findCollegesByCourseName(courseName.trim());
            for (Object[] row : colleges) {
                Long collegeId = convertToLong(row[0]);
                String collegeName = String.valueOf(row[1]);
                String district = String.valueOf(row[2]);

                options.add(CollegeOptionResponse.builder()
                        .collegeId(collegeId != null ? collegeId.toString() : "")
                        .collegeName(collegeName)
                        .district(district != null ? district : "")
                        .build());
            }
        }

        return options;
    }

    private Long convertToLong(Object obj) {
        if (obj == null) return null;
        if (obj instanceof Number) return ((Number) obj).longValue();
        try {
            return Long.parseLong(obj.toString());
        } catch (Exception e) {
            return null;
        }
    }

    private Double convertToDouble(Object obj) {
        if (obj == null) return null;
        if (obj instanceof Number) return ((Number) obj).doubleValue();
        try {
            return Double.parseDouble(obj.toString());
        } catch (Exception e) {
            return null;
        }
    }
}
