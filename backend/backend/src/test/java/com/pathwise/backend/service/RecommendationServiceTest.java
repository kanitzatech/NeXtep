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

        rows.add(row("2001", "CS", "Top Preferred", 175.0, 184.0));
        rows.add(row("2002", "CS", "Strong Preferred", 170.0, 184.0));

        for (int i = 0; i < 20; i++) {
            double min = 169.5 + (i * 0.25);
            rows.add(row("S" + i, "CS", "Safe College " + i, min, 200.0));
        }

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

    private CutoffHistory row(String code, String branch, String collegeName, double bcMin, double bcMax) {
        return CutoffHistory.builder()
                .collegeCode(code)
                .branch(branch)
                .collegeName(collegeName)
                .bcMin(bcMin)
                .bcMax(bcMax)
                .build();
    }
}
