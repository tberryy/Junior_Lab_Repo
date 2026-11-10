function list = excludedSpecimens()
%EXCLUDEDSPECIMENS Specimens left out of every average, plot and modulus fit.
%
%   One row per specimen: its FilePath exactly as it appears in the
%   Specimens sheet of ProcessedData/JuniorLab_ProcessedData.xlsx, and a
%   short reason. Nothing is left out unless it is listed here.
%
%   plotTension / plotCompression / plotFracture print "check these"
%   candidates (peak under half the group median, or strain / displacement
%   at peak over 3x the group median) and list them in the Flagged sheet of
%   ProcessedData/<Test>_Averages.xlsx. Look at the curve, then add it here
%   if the test was bad (slipped in the grips, aborted, wrong specimen...).
%
%   Example (remove the % to use it):
%   list = [
%       "OrganizedData\2026_organized\batch2\monday\monday_10457\tension\TENSION_20260420_155824_2.csv", "slipped in grips"
%       "OrganizedData\2025_organized\batch2\wednesday\wednesday_80464\compression\COMPRESSION_20251119_182203_1_2.csv", "test aborted early"
%   ];

list = [
    % "FilePath", "reason"
    "OrganizedData\2026_organized\batch2\friday\friday_10444\tension\TENSION_20260424_83721_1.csv", "slipped in grips (flat at 0.9 MPa to 0.005 strain)"
    "OrganizedData\2026_organized\batch2\friday\friday_10444\tension\TENSION_20260424_83721_2.csv", "slipped in grips (flat at 0.9 MPa to 0.005 strain)"
];

list = string(list);
if isempty(list)
    list = strings(0, 2);
end
end
