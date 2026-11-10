%% Junior Lab analysis: run this file top to bottom
%
%  Folder layout
%    Pipeline/                  code (this file + the functions below)
%      prepareData.m            OrganizedData CSVs  ->  processed workbook
%      plotTension.m            processed workbook  ->  Figures/Tension
%      plotCompression.m        processed workbook  ->  Figures/Compression
%      plotCompressionModulus.m processed workbook  ->  modulus vs AP figure + xlsx
%      plotFracture.m           processed workbook  ->  Figures/Fracture (force-displacement)
%      plotFractureToughness.m  processed workbook  ->  K_Ic and G_Ic vs AP + xlsx
%                               (replaces the old Fracture_GIc_KIc_Analysis.m)
%      plotSpecimenBands.m      processed workbook  ->  Figures_Claude/<Test> (median + percentile bands + peak strip)
%      plotAPComparison.m       processed workbook  ->  Figures/AP_Comparison/<Test>/PNG and PDF
%                               (every AP on one plot, curves ending at the mean fracture point)
%      private/                 helpers used by the functions above
%
%  Settings you edit
%    private/apRatio.m            year -> AP loading (2024 40%, 2025 50%, 2023 60%, 2026 70%)
%    private/excludedSpecimens.m  bad tests to leave out of every plot and average
%
%  Outputs
%    ProcessedData/
%      JuniorLab_ProcessedData.xlsx   specimens + curves (made by prepareData)
%      Tension_Averages.xlsx          mean curves, fracture stats, flagged specimens
%      Compression_Averages.xlsx      mean curves, peak stats, flagged specimens
%      Compression_Modulus.xlsx       modulus per specimen + summary
%      Fracture_Averages.xlsx         mean curves, peak-load stats, flagged specimens
%      Fracture_Toughness.xlsx        K_Ic and G_Ic per specimen + summary
%    Figures/
%      Tension/Tension_AP<ratio>_<year>_<CNT|NEAT>.png          mean +/- 1 SD, one AP loading
%      Tension/Tension_<CNT|NEAT>_AP_Comparison.png             every AP loading on one plot
%      Compression/Compression_AP<ratio>_<year>_<CNT|NEAT>.png
%      Compression/Compression_<CNT|NEAT>_AP_Comparison.png
%      Compression/Compression_Modulus_vs_AP.png
%      Fracture/Fracture_AP<ratio>_<year>_<CNT|NEAT>.png
%      Fracture/Fracture_<CNT|NEAT>_AP_Comparison.png
%      Fracture/Fracture_KIc_vs_AP.png, Fracture/Fracture_GIc_vs_AP.png
%
%  The plotting functions read ONLY the processed workbook. Run prepareData
%  again when the raw data, SpecimenDimensions workbooks or this code change.
%  Type "help plotTension" (or prepareData / plotCompression) for options,
%  e.g. plotTension(StrainLimit=0.03) to zoom in.

clear; clc; close all;

pipelineFolder = fileparts(mfilename('fullpath'));
addpath(pipelineFolder);

rebuildProcessedData = true;    % false = reuse the existing workbook

%% 1) Data preparation
if rebuildProcessedData
    processedFile = prepareData();
else
    processedFile = fullfile(fileparts(pipelineFolder), ...
        'ProcessedData', 'JuniorLab_ProcessedData.xlsx');
end

%% 2) Tension figures
plotTension('ProcessedFile', processedFile);

%% 3) Compression figures
plotCompression('ProcessedFile', processedFile);

%% 4) Compression modulus vs AP loading
plotCompressionModulus('ProcessedFile', processedFile);

%% 5) Fracture (compact tension) force-displacement figures
plotFracture('ProcessedFile', processedFile);

%% 6) Fracture toughness K_Ic and G_Ic vs AP loading
plotFractureToughness('ProcessedFile', processedFile);

%% 7) Redesigned multi-specimen figures (median, percentile bands, peak strip)
%     -> Figures_Claude/<Test>; the figures above are left as they are
for testName = ["Tension", "Compression", "Fracture"]
    plotSpecimenBands(testName, 'ProcessedFile', processedFile);
end

%% 8) AP comparison series: every specimen, mean curve ending at the mean
%     fracture point with a dashed line to the axis -> Figures/AP_Comparison
plotAPComparison('ProcessedFile', processedFile);

fprintf('\nAll figures are in %s\n', fullfile(fileparts(pipelineFolder), 'Figures'));
fprintf('Redesigned figures are in %s\n', fullfile(fileparts(pipelineFolder), 'Figures_Claude'));
