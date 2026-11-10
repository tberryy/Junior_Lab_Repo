function results = plotCompressionModulus(opts)
%PLOTCOMPRESSIONMODULUS Compression modulus vs AP loading.
%
%   results = plotCompressionModulus()
%   results = plotCompressionModulus(Name=Value)
%
%   For every usable compression specimen in the processed workbook:
%     E = slope of a straight-line fit of stress vs strain over FitWindow
%   (same method and limits as the old calculateYoungsModulusResults).
%   A fit counts only when it has at least MinFitPoints points and
%   R^2 >= MinRSquared.
%
%   Saves
%     <repo>/Figures/Compression/Compression_Modulus_vs_AP.png
%         x = AP % (40, 50, 60, 70; year in brackets), y = modulus.
%         Dots = accepted specimens, line + bars = mean +/- 1 SD,
%         CNT and NEAT side by side at each AP loading.
%     <repo>/ProcessedData/Compression_Modulus.xlsx
%         "All Specimens"  every fit, accepted or not, with R^2 and points
%         "Summary"        mean, SD, n, min, max per AP loading and material
%
%   Options
%     ProcessedFile      workbook from prepareData (default location)
%     OutputFolder       where the PNG goes (default <repo>/Figures/Compression)
%     ResultsFile        modulus workbook (default above)
%     FitWindow          [start end] strain for the fit (default [0.002 0.010])
%     MinFitPoints       default 8
%     MinRSquared        default 0.90
%     Materials          default ["CNT","NEAT"]
%     ShowFigures        keep the figure open (default false)
%     IncludeDuplicates  also use CSVs flagged as copies (default false)
%     NumSpecimens       specimens per AP loading and material, closest to the
%                        group median (default 13; Inf = all; see private/selectSpecimens.m)
%
%   Example
%     plotCompressionModulus(FitWindow=[0.005 0.015], ShowFigures=true)

arguments
    opts.ProcessedFile     (1,1) string = ""
    opts.OutputFolder      (1,1) string = ""
    opts.ResultsFile       (1,1) string = ""
    opts.FitWindow         (1,2) double = [0.002 0.010]
    opts.MinFitPoints      (1,1) double = 8
    opts.MinRSquared       (1,1) double = 0.90
    opts.Materials         (1,:) string = ["CNT", "NEAT"]
    opts.ShowFigures       (1,1) logical = false
    opts.IncludeDuplicates (1,1) logical = false
    opts.NumSpecimens      (1,1) double {mustBePositive} = 13
end

p = pipelinePaths();
if opts.ProcessedFile == "", opts.ProcessedFile = p.ProcessedFile;                          end
if opts.OutputFolder  == "", opts.OutputFolder  = fullfile(p.Figures, 'Compression');        end
if opts.ResultsFile   == "", opts.ResultsFile   = fullfile(p.ProcessedDir, 'Compression_Modulus.xlsx'); end

[specimens, curves] = loadSpecimens(opts.ProcessedFile, "Compression", opts.IncludeDuplicates, ...
    opts.NumSpecimens);
specimens = specimens(ismember(specimens.Material, opts.Materials), :);

if height(specimens) == 0
    warning('modulus:noData', 'No usable compression specimens.');
    results = table();
    return;
end

%% ------------------------------------------------------------ fit each specimen
n = height(specimens);
E   = NaN(n, 1);
R2  = NaN(n, 1);
nPt = zeros(n, 1);

for i = 1:n
    r = specimens.CurveRows{i};
    [E(i), R2(i), nPt(i)] = fitModulus(curves.Strain(r), curves.Stress_MPa(r), opts.FitWindow);
end

accepted = isfinite(E) & E > 0 & isfinite(R2) & ...
           R2 >= opts.MinRSquared & nPt >= opts.MinFitPoints;

results = table( ...
    specimens.SpecimenID, specimens.APRatio_pct, specimens.Year, specimens.Material, ...
    specimens.Batch, specimens.Day, specimens.Group, specimens.SampleName, ...
    E, R2, nPt, ...
    repmat(opts.FitWindow(1), n, 1), repmat(opts.FitWindow(2), n, 1), ...
    accepted, specimens.FilePath, ...
    'VariableNames', {'SpecimenID', 'APRatio_pct', 'Year', 'Material', ...
                      'Batch', 'Day', 'Group', 'Sample', ...
                      'Modulus_MPa', 'RSquared', 'NumberFitPoints', ...
                      'FitStartStrain', 'FitEndStrain', 'FitAccepted', 'FilePath'});
results = sortrows(results, {'APRatio_pct', 'Material', 'SpecimenID'});

%% ------------------------------------------------------------ summary per AP and material
ok = results(results.FitAccepted, :);
groups = unique(results(:, {'APRatio_pct', 'Year', 'Material'}));
groups = sortrows(groups, {'APRatio_pct', 'Material'});

nG = height(groups);
meanE = NaN(nG, 1); sdE = NaN(nG, 1); nE = zeros(nG, 1);
minE  = NaN(nG, 1); maxE = NaN(nG, 1);

for g = 1:nG
    v = ok.Modulus_MPa(ok.Year == groups.Year(g) & ok.Material == groups.Material(g));
    nE(g) = numel(v);
    if nE(g) >= 1
        meanE(g) = mean(v);
        minE(g)  = min(v);
        maxE(g)  = max(v);
    end
    if nE(g) >= 2
        sdE(g) = std(v);            % sample SD (N-1)
    end
end

summary = [groups, table(meanE, sdE, nE, minE, maxE, ...
    'VariableNames', {'MeanModulus_MPa', 'SD_MPa', 'NumberAccepted', ...
                      'MinModulus_MPa', 'MaxModulus_MPa'})];

fprintf('\nCompression modulus (accepted fits)\n');
fprintf('  AP %%   Year  Material   mean (MPa)   SD (MPa)   n\n');
for g = 1:nG
    fprintf('  %4g   %4d  %-8s  %10.1f  %9.1f  %3d\n', groups.APRatio_pct(g), ...
        groups.Year(g), groups.Material(g), meanE(g), sdE(g), nE(g));
end
fprintf('  %d of %d fits rejected (R^2 < %.2f or < %d points in the window)\n\n', ...
    sum(~results.FitAccepted), n, opts.MinRSquared, opts.MinFitPoints);

%% ------------------------------------------------------------ write workbook
resultsDir = fileparts(opts.ResultsFile);
if ~isfolder(resultsDir), mkdir(resultsDir); end
if isfile(opts.ResultsFile)
    delete(opts.ResultsFile);
    if isfile(opts.ResultsFile)
        error('modulus:locked', 'Close %s in Excel and run again.', opts.ResultsFile);
    end
end
writetable(results, opts.ResultsFile, 'Sheet', 'All Specimens');
writetable(summary, opts.ResultsFile, 'Sheet', 'Summary');

%% ------------------------------------------------------------ figure
fo = struct('Materials', opts.Materials, ...
            'YLabel', 'Compression modulus (MPa)', ...
            'Title', sprintf('Compression Modulus vs AP Loading  (fit %.3g-%.3g strain)', ...
                             opts.FitWindow(1), opts.FitWindow(2)), ...
            'ValueLabel', "E (MPa)", ...
            'OutFile', fullfile(opts.OutputFolder, 'Compression_Modulus_vs_AP.png'), ...
            'ShowFigures', opts.ShowFigures);
outFile = plotMetricVsAP(ok, 'Modulus_MPa', summary, 'MeanModulus_MPa', 'SD_MPa', fo);
fprintf('Saved %s\nSaved %s\n', outFile, opts.ResultsFile);
end

%% ========================================================================
function [E, R2, nPoints] = fitModulus(strain, stress, window)
% Least-squares line stress = E*strain + b over the strain window.
E = NaN; R2 = NaN;
strain = strain(:); stress = stress(:);
in = isfinite(strain) & isfinite(stress) & strain >= window(1) & strain <= window(2);
x = strain(in); y = stress(in);
nPoints = numel(x);
if nPoints < 2
    return;
end
c = polyfit(x, y, 1);
E = c(1);
ssRes = sum((y - polyval(c, x)).^2);
ssTot = sum((y - mean(y)).^2);
if ssTot > 0
    R2 = 1 - ssRes / ssTot;
end
end
