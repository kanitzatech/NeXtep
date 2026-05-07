package com.pathwise.backend.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.*;
import java.util.List;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@ToString
public class FinalReportRequest {
    @JsonProperty("student_name")
    private String studentName;

    private String category;

    @JsonProperty("student_cutoff")
    private Double studentCutoff;

    @JsonProperty("preferred_course")
    private String preferredCourse;

    private String district;

    @JsonProperty("hostel_required")
    private Boolean hostelRequired;

    @JsonProperty("preferred_college_ids")
    private List<String> preferredCollegeIds;

    @JsonProperty("preferred_college_names")
    private List<String> preferredCollegeNames;
}
