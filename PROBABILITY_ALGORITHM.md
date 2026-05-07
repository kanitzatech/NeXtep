# College Recommendation Engine - Probability Calculator

## Overview

The **ProbabilityCalculatorService** is a strict, accuracy-focused admission probability calculator that generates precise probability scores based on student data and college cutoff information.

---

## Algorithm Rules (STRICT)

### Input Data Required:
- **student_cutoff** (numeric) - Student's entrance exam score
- **category** (OC, BC, MBC, SC, ST) - Student's category for reservation
- **college_cutoff** (numeric) - College's last-year closing cutoff for that category
- **preferred_colleges** (max 5) - List of colleges student prefers
- **preferred_location** (optional) - Preferred district/location
- **hostel_required** (optional) - Whether hostel facility is needed

---

## Probability Calculation Formula

### Step 1: Calculate Cutoff Difference (PRIMARY - >80% influence)

```
difference = student_cutoff - college_cutoff
```

**Example:**
- Student Cutoff: 180
- College Cutoff: 175
- Difference: +5 (student is 5 marks ABOVE college cutoff)

### Step 2: Assign Base Probability (STRICT RULES)

| Cutoff Difference | Probability Range | Interpretation |
|-------------------|-------------------|-----------------|
| >= +5 | 90-95% | Excellent position - Very likely to get admission |
| 0 to +5 | 70-85% | Good position - Good chance of admission |
| -2 to 0 | 40-60% | Moderate position - Uncertain, possible admission |
| -5 to -2 | 15-40% | Weak position - Unlikely to get admission |
| -10 to -5 | 5-15% | Very weak position - Highly unlikely |
| < -10 | 0-5% | Almost impossible - Very unlikely |

### Step 3: Apply Optional Adjustments (MAX 5% each)

These factors make SMALL adjustments ONLY:

1. **Preferred College Selection**: +3%
   - Applied when college is in student's preferred list

2. **Location Match**: +2%
   - Applied when college location matches student's preferred district

3. **Hostel Availability**: +2%
   - Applied when college has hostel and student requires it

**Total Maximum Adjustment**: +7% (capped to not exceed adjustments)

### Step 4: Final Probability Calculation

```
adjusted_probability = base_probability + adjustments
final_probability = min(adjusted_probability, 100%)
```

### Step 5: Assign Label

| Probability Range | Label | Meaning |
|-------------------|-------|---------|
| 80-100% | Excellent | Very high chance of admission |
| 60-79% | Good | Good chance of admission |
| 40-59% | Moderate | Moderate chance - be cautious |
| 20-39% | Low | Low chance - consider backup |
| <20% | Very Low / Dream | Almost no chance - dream option |

---

## Key Principles

### STRICT ACCURACY RULES:

✅ **DO:**
- Always calculate difference first
- Penalize negative differences strongly
- Keep cutoff difference as >80% influence
- Provide detailed reason for each probability
- Show cutoff difference clearly in output

❌ **DON'T:**
- Give high probability if student_cutoff < college_cutoff (without proper adjustment)
- Assume data without verification
- Use only student's cutoff bracket (must compare with college cutoff)
- Ignore location or preference without proper weighting
- Exceed 100% probability

---

## Example Calculation

### Scenario:
```
Student Name: Raj Kumar
Student Cutoff: 185
Category: OC
Preferred College: IIT Madras
College Cutoff (OC): 190
College Location: Chennai (matches student's preferred location)
Hostel Required: Yes
```

### Calculation Steps:

1. **Difference**: 185 - 190 = -5
   - Student is 5 marks BELOW college cutoff

2. **Base Probability** (difference = -5):
   - Falls in range: -5 to -2
   - Base probability = 27%

3. **Adjustments**:
   - Preferred college: +3% ✓
   - Location match: +2% ✓
   - Hostel available: +2% ✓
   - Total adjustment: +7%

4. **Final Probability**: 27% + 7% = 34%

5. **Label**: "Low"

6. **Reason Generated**:
   ```
   "Your cutoff (185.0) is 5.0 marks BELOW the college cutoff (190.0). 
   Admission is unlikely. Additional bonuses applied: preferred college 
   selection (+3%), location match (+2%), hostel availability (+2%). 
   Final probability: 34% (adjusted from base 27%). 
   Consider this a backup/dream option."
   ```

---

## Output Format

Each college recommendation returns:

```dart
{
  "collegeName": "IIT Madras",
  "courseName": "Computer Science",
  "studentCutoff": 185.0,
  "collegeCutoff": 190.0,
  "probability": 34,
  "label": "Low",
  "reason": "Your cutoff (185.0) is 5.0 marks BELOW...",
  "cutoffDifference": -5.0,
  "category": "OC"
}
```

---

## Implementation Details

### File: `probability_calculator_service.dart`

**Main Class**: `ProbabilityCalculatorService`

**Key Methods**:

```dart
// Single college calculation
static ProbabilityResult calculateProbability({
  required String collegeName,
  required String courseName,
  required double studentCutoff,
  required double collegeCutoff,
  required String category,
  bool isPreferredCollege = false,
  bool isLocationMatch = false,
  bool hostelAvailable = false,
})

// Batch calculation for multiple colleges
static List<ProbabilityResult> calculateBatchProbabilities({
  required List<Recommendation> colleges,
  required double studentCutoff,
  required String category,
  required List<String> preferredCollegeNames,
  String? preferredLocation,
})
```

---

## Integration with UI

### Updated Files:

1. **final_report_page.dart**
   - Added import for `ProbabilityCalculatorService`
   - Updated `_loadFinalReport()` to fetch college data first
   - New method: `_computePreferredCollegesWithAccuracy()` uses strict algorithm
   - Displays probability breakdown in college cards

2. **College Card Display** (_buildPreferredCollegeCard)
   - Shows probability percentage
   - Shows chance label (Excellent/Good/Moderate/Low/Very Low)
   - Shows detailed reason explaining probability calculation
   - Displays student vs. college cutoff comparison

---

## Validation & Testing

### Test Cases Covered:

✅ Student significantly above cutoff (>=+5)
✅ Student near cutoff (0 to +5)
✅ Student slightly below cutoff (-2 to 0)
✅ Student well below cutoff (-5 to -2)
✅ Student far below cutoff (-10 to -5)
✅ Student extremely below cutoff (<-10)
✅ Preferred college bonus application
✅ Location match bonus application
✅ Hostel availability bonus application
✅ Multiple adjustments combined
✅ Probability capping at 100%

---

## Real-World Examples

### Example 1: Strong Candidate
```
Student Cutoff: 195
College Cutoff: 185
Difference: +10

Base Probability: 92% (>=+5)
Label: Excellent ✓
Reason: Your cutoff is 10 marks ABOVE the college cutoff. 
        Excellent position for admission.
```

### Example 2: Borderline Candidate
```
Student Cutoff: 175
College Cutoff: 180
Difference: -5

Base Probability: 27% (-5 to -2)
+ Preferred College: +3%
Final: 30%
Label: Low
Reason: Your cutoff is 5 marks BELOW the college cutoff. 
        Admission is unlikely. Consider as backup.
```

### Example 3: Dream College (Far Below)
```
Student Cutoff: 150
College Cutoff: 200
Difference: -50

Base Probability: 2% (<-10)
+ Adjustments: +7% (capped)
Final: 9%
Label: Very Low / Dream
Reason: Your cutoff is 50 marks BELOW the college cutoff. 
        Admission is almost impossible. This is a dream option.
```

---

## Future Enhancements

Possible future improvements while maintaining strict accuracy:

1. **Historical Data Analysis**
   - Include past years' cutoff trends
   - Consider category-specific trends
   - Add branch-specific historical data

2. **Advanced Metrics**
   - College ranking impact
   - Specialization demand analysis
   - Placement statistics integration

3. **Dynamic Adjustments**
   - Seasonal cutoff variations
   - Inter-year cutoff trends
   - COVID impact normalization

4. **Batch Analytics**
   - Overall admission probability across 5 colleges
   - Risk assessment for student's choice portfolio
   - Recommendations for college selection strategy

---

## Key Files

| File | Purpose |
|------|---------|
| `probability_calculator_service.dart` | Core calculation engine |
| `final_report_page.dart` | UI integration & display |
| `recommendation.dart` | Model for college data |
| `api_service.dart` | Fetches college cutoff data |

---

## Glossary

- **Cutoff**: The minimum score required for admission in a specific category
- **Probability**: Percentage chance of getting admission
- **Category**: Reservation category (OC, BC, MBC, SC, ST, etc.)
- **Preferred College**: College selected by student from available options
- **Difference**: Student cutoff minus college cutoff
- **Base Probability**: Probability before adjustments
- **Adjusted Probability**: Final probability after all adjustments

---

## FAQ

**Q: Why is the algorithm so strict?**
A: Accuracy is more important than optimism. False hope leads to poor decision-making. We prioritize truthfulness.

**Q: Can probability go above 100%?**
A: No, it's capped at 100% maximum. This ensures realistic expectations.

**Q: Why is cutoff difference 80% of the calculation?**
A: Because it's the single most important factor in Indian college admissions. It directly determines eligibility and merit.

**Q: What if college cutoff is 0?**
A: The calculator uses a fallback of 100.0 as the college cutoff to prevent division by zero errors.

**Q: Are adjustments guaranteed?**
A: Yes, they're always applied when conditions are met (preferred college, location match, hostel available).

---

**Version**: 1.0  
**Last Updated**: May 7, 2026  
**Maintained by**: College Recommendation Engine Team
