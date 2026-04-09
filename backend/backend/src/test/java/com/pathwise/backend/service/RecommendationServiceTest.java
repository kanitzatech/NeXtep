package com.pathwise.backend.service;

import com.pathwise.backend.dto.RecommendationResponse;
import com.pathwise.backend.model.CutoffHistory;
import com.pathwise.backend.repository.CollegeRepository;
import com.pathwise.backend.repository.CutoffHistoryRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RecommendationServiceTest {

    @Mock
    private CutoffHistoryRepository cutoffHistoryRepository;

    @Mock
    private CollegeRepository collegeRepository;

    private RecommendationService recommendationService;

    @BeforeEach
    void setUp() {
        recommendationService = new RecommendationService(
                cutoffHistoryRepository,
                collegeRepository
        );

        when(collegeRepository.findAll()).thenReturn(List.of());
    }

    @Test
    void csSelectionReturnsOnlyCsBranchRows() {
        CutoffHistory csRow = row("1001", "CS", "Alpha Engineering", 182.0, 196.0);
        CutoffHistory adRow = row("1002", "AD", "Beta Engineering", 176.0, 194.0);

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("BC"), eq("CS")))
                .thenReturn(List.of(csRow, adRow));

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "BC",
                190.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> all = new ArrayList<>();
        all.addAll(result.getOrDefault("preferred_colleges", List.of()));
        all.addAll(result.getOrDefault("safe_colleges", List.of()));

        assertFalse(all.isEmpty());
        assertTrue(all.stream().allMatch(item -> "Computer Science Engineering".equals(item.getCourseName())));
        verify(cutoffHistoryRepository)
                .findByCategoryAndExactBranchWithCommunityRange(eq("BC"), eq("CS"));
    }

    @Test
    void probabilityBucketsAndSafeLimitAreDeterministic() {
        List<CutoffHistory> rows = new ArrayList<>();

        rows.add(row("2001", "CS", "Top Preferred", 160.0, 170.0));
        rows.add(row("2002", "CS", "Strong Preferred", 170.0, 178.0));

        for (int i = 0; i < 20; i++) {
            double min = 182.0 + (i * 0.15);
            rows.add(row("S" + i, "CS", "Safe College " + i, min, min + 6.0));
        }

        // Below minimum by >5 marks, should be excluded (<40 probability).
        rows.add(row("X1", "CS", "Excluded College", 186.0, 192.0));

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(anyString(), anyString()))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "BC",
                180.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred = result.getOrDefault("preferred_colleges", List.of());
        List<RecommendationResponse> safe = result.getOrDefault("safe_colleges", List.of());

        assertTrue(preferred.stream().allMatch(item -> item.getProbability() >= 70));
        assertTrue(safe.stream().allMatch(item -> item.getProbability() >= 40 && item.getProbability() <= 69));
        assertEquals(15, safe.size());

        for (int i = 1; i < preferred.size(); i++) {
            assertTrue(preferred.get(i - 1).getProbability() >= preferred.get(i).getProbability());
        }

        for (int i = 1; i < safe.size(); i++) {
            assertTrue(safe.get(i - 1).getProbability() >= safe.get(i).getProbability());
        }

        Map<String, List<RecommendationResponse>> resultSecond = recommendationService.getPreferenceDrivenRecommendations(
                "BC",
                180.0,
                "CS",
                null,
                List.of()
        );

        List<String> firstPreferredSignature = preferred.stream()
            .map(item -> item.getCollegeName() + "|" + item.getProbability())
            .toList();
        List<String> secondPreferredSignature = resultSecond.getOrDefault("preferred_colleges", List.of())
            .stream()
            .map(item -> item.getCollegeName() + "|" + item.getProbability())
            .toList();

        List<String> firstSafeSignature = safe.stream()
            .map(item -> item.getCollegeName() + "|" + item.getProbability())
            .toList();
        List<String> secondSafeSignature = resultSecond.getOrDefault("safe_colleges", List.of())
            .stream()
            .map(item -> item.getCollegeName() + "|" + item.getProbability())
            .toList();

        assertEquals(firstPreferredSignature, secondPreferredSignature);
        assertEquals(firstSafeSignature, secondSafeSignature);
    }

    @Test
    void studentAboveHistoricalMaxGetsNearGuaranteedProbability() {
        List<CutoffHistory> rows = List.of(
                rowMbc("3001", "CS", "Anna University CEG", 81.20, 99.26),
                rowMbc("3002", "CS", "Kumaraguru College", 74.10, 94.43),
                rowMbc("3003", "CS", "Government College Salem", 73.90, 91.52),
                rowMbc("3004", "CS", "Arulmigu Meenakshi College", 70.20, 81.93)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result196 = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                196.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred196 = result196.getOrDefault("preferred_colleges", List.of());
        assertEquals(4, preferred196.size());
        assertTrue(preferred196.stream().allMatch(item -> item.getProbability() == 99));
        assertTrue(result196.getOrDefault("safe_colleges", List.of()).isEmpty());

        Map<String, List<RecommendationResponse>> result117 = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                117.5,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred117 = result117.getOrDefault("preferred_colleges", List.of());
        assertEquals(4, preferred117.size());
        assertTrue(preferred117.stream().allMatch(item -> item.getProbability() == 99));
        assertTrue(result117.getOrDefault("safe_colleges", List.of()).isEmpty());
        assertEquals(99, probabilityFor(preferred117, "Anna University CEG"));
        assertEquals(99, probabilityFor(preferred117, "Arulmigu Meenakshi College"));
    }

    @Test
    void collegeWithoutCommunityMaxIsSkipped() {
        List<CutoffHistory> rows = List.of(
                row("4001", "CS", "Valid College", 85.0, 99.0),
                row("4002", "CS", "Missing Max College", 80.0, null)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("BC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "BC",
                100.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> all = new ArrayList<>();
        all.addAll(result.getOrDefault("preferred_colleges", List.of()));
        all.addAll(result.getOrDefault("safe_colleges", List.of()));

        assertEquals(1, all.size());
        assertEquals("Valid College", all.get(0).getCollegeName());
        assertEquals(90, all.get(0).getProbability());
    }

    @Test
    void reportCase1HighScorer196AllPreferredNearGuaranteed() {
        List<CutoffHistory> rows = List.of(
                rowMbc("5001", "CS", "Anna CEG", 81.0, 99.26),
                rowMbc("5002", "CS", "Kumaraguru", 74.0, 94.43),
                rowMbc("5003", "CS", "Thiagarajar", 75.0, 95.63),
                rowMbc("5004", "CS", "PSG iTech", 72.0, 91.67)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                196.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred = result.getOrDefault("preferred_colleges", List.of());
        List<RecommendationResponse> safe = result.getOrDefault("safe_colleges", List.of());

        assertEquals(4, preferred.size());
        assertTrue(safe.isEmpty());
        assertEquals(99, probabilityFor(preferred, "Anna CEG"));
        assertEquals(99, probabilityFor(preferred, "Kumaraguru"));
        assertEquals(99, probabilityFor(preferred, "Thiagarajar"));
        assertEquals(99, probabilityFor(preferred, "PSG iTech"));
        assertTrue(preferred.stream().allMatch(item -> item.getProbability() >= 90));
    }

    @Test
    void reportCase2MidScorer117_5StillPreferredForBelow100Maxes() {
        List<CutoffHistory> rows = List.of(
                rowMbc("5101", "CS", "Anna CEG", 81.0, 99.26),
                rowMbc("5102", "CS", "Arulmigu Meenakshi", 70.0, 81.93),
                rowMbc("5103", "CS", "UCE Ariyalur", 71.0, 82.00),
                rowMbc("5104", "CS", "Safe College Max80", 68.0, 80.00)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                117.5,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred = result.getOrDefault("preferred_colleges", List.of());
        List<RecommendationResponse> safe = result.getOrDefault("safe_colleges", List.of());

        assertEquals(4, preferred.size());
        assertTrue(safe.isEmpty());
        assertEquals(99, probabilityFor(preferred, "Anna CEG"));
        assertEquals(99, probabilityFor(preferred, "Arulmigu Meenakshi"));
        assertEquals(99, probabilityFor(preferred, "UCE Ariyalur"));
        assertEquals(99, probabilityFor(preferred, "Safe College Max80"));
    }

    @Test
    void reportCase3LowScorerBandingAndExclusion() {
        List<CutoffHistory> rows = List.of(
                rowMbc("5201", "CS", "Case 3A", 85.0, 90.0),
                rowMbc("5202", "CS", "Case 3B", 78.0, 82.0),
                rowMbc("5203", "CS", "Case 3C", 70.0, 75.0),
                rowMbc("5204", "CS", "Case 3D", 88.0, 95.0)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                80.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred = result.getOrDefault("preferred_colleges", List.of());
        List<RecommendationResponse> safe = result.getOrDefault("safe_colleges", List.of());
        List<RecommendationResponse> all = new ArrayList<>();
        all.addAll(preferred);
        all.addAll(safe);

        int case3AProbability = probabilityFor(all, "Case 3A");
        int case3BProbability = probabilityFor(all, "Case 3B");
        int case3CProbability = probabilityFor(all, "Case 3C");

        assertTrue(case3AProbability >= 40 && case3AProbability <= 49);
        assertEquals(80, case3BProbability);
        assertEquals(95, case3CProbability);
        assertFalse(all.stream().anyMatch(item -> "Case 3D".equals(item.getCollegeName())));
        assertTrue(preferred.stream().allMatch(item -> item.getProbability() >= 70));
        assertTrue(safe.stream().allMatch(item -> item.getProbability() >= 40 && item.getProbability() <= 69));
    }

    @Test
    void reportCase4NullCommunityMaxOrMinSkipsCollege() {
        List<CutoffHistory> rows = List.of(
                rowMbc("5301", "CS", "Valid MBC Data", 82.0, 90.0),
                rowMbc("5302", "CS", "Null Max", 80.0, null),
                rowMbc("5303", "CS", "Null Min", null, 88.0)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                95.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> all = new ArrayList<>();
        all.addAll(result.getOrDefault("preferred_colleges", List.of()));
        all.addAll(result.getOrDefault("safe_colleges", List.of()));

        assertEquals(1, all.size());
        assertEquals("Valid MBC Data", all.get(0).getCollegeName());
    }

    @Test
    void reportCase5SortsByProbabilityDescendingInBothBuckets() {
        List<CutoffHistory> rows = List.of(
                rowMbc("5401", "CS", "Preferred 99", 50.0, 65.0),
                rowMbc("5402", "CS", "Preferred 90", 60.0, 80.0),
                rowMbc("5403", "CS", "Safe 69", 80.02, 90.0),
                rowMbc("5404", "CS", "Safe 40", 85.5, 90.0)
        );

        when(cutoffHistoryRepository.findByCategoryAndExactBranchWithCommunityRange(eq("MBC"), eq("CS")))
                .thenReturn(rows);

        Map<String, List<RecommendationResponse>> result = recommendationService.getPreferenceDrivenRecommendations(
                "MBC",
                80.0,
                "CS",
                null,
                List.of()
        );

        List<RecommendationResponse> preferred = result.getOrDefault("preferred_colleges", List.of());
        List<RecommendationResponse> safe = result.getOrDefault("safe_colleges", List.of());

        assertEquals(2, preferred.size());
        assertEquals(99, preferred.get(0).getProbability());
        assertEquals("Preferred 99", preferred.get(0).getCollegeName());
        assertEquals(90, preferred.get(1).getProbability());
        assertEquals("Preferred 90", preferred.get(1).getCollegeName());

        assertEquals(2, safe.size());
        assertEquals(69, safe.get(0).getProbability());
        assertEquals("Safe 69", safe.get(0).getCollegeName());
        assertEquals(40, safe.get(1).getProbability());
        assertEquals("Safe 40", safe.get(1).getCollegeName());
    }

    private int probabilityFor(List<RecommendationResponse> rows, String collegeName) {
        return rows.stream()
                .filter(item -> collegeName.equals(item.getCollegeName()))
                .findFirst()
                .map(RecommendationResponse::getProbability)
                .orElseThrow(() -> new AssertionError("Missing college in result: " + collegeName));
    }

    private CutoffHistory row(String code, String branch, String collegeName, Double bcMin, Double bcMax) {
        return CutoffHistory.builder()
                .collegeCode(code)
                .branch(branch)
                .collegeName(collegeName)
                .bcMin(bcMin)
                .bcMax(bcMax)
                .build();
    }

    private CutoffHistory rowMbc(String code, String branch, String collegeName, Double mbcMin, Double mbcMax) {
        return CutoffHistory.builder()
                .collegeCode(code)
                .branch(branch)
                .collegeName(collegeName)
                .mbcMin(mbcMin)
                .mbcMax(mbcMax)
                .build();
    }
}
