function figureFiles = plotAveragedCurves(testName, opts)
%PLOTAVERAGEDCURVES Shared engine for plotTension, plotCompression and plotFracture.
%
%   For every AP loading and material
%     <Test>_AP<ratio>_<year>_<CNT|NEAT>.png
%         faint specimen curves, mean curve and shaded +/-1 SD band
%         (tension and fracture add every specimen's peak point and the mean
%         peak +/-1 SD in both directions)
%   For every material
%     <Test>_<CNT|NEAT>_AP_Comparison.png
%         mean +/-1 SD of every AP loading on one plot (light = low AP,
%         dark = high AP)
%     <Test>_<CNT|NEAT>_AllAP_Specimens.png
%         every AP loading on one plot WITH its specimen curves (and, for
%         tension and fracture, every peak point and the mean peak +/-1 SD),
%         each AP in its own shade
%   And ProcessedData/<Test>_Averages.xlsx
%     Summary  per AP and material: specimens, end of the mean curve, peak
%              value and where it happens (mean, SD)
%     Curves   the averaged curves (x, mean, SD)
%     Removed  specimens left out by selectSpecimens.m: outliers, and those
%              beyond the opts.NumSpecimens closest to the median of their
%              AP loading and material
%     Flagged  remaining specimens worth a look; only removed if listed
%              in excludedSpecimens.m
%
%   Tension and compression plot stress vs strain; fracture plots force vs
%   displacement. How the mean is built is described in averageCurves.m.
%   opts.XLimit is the crop (strain, or mm for fracture).

if ~(opts.MinFraction > 0 && opts.MinFraction <= 1)
    error('plot:minFraction', 'MinFraction must be in (0, 1], got %g.', opts.MinFraction);
end

spec = testSpec(testName);
[specimens, curves, dropped] = loadSpecimens(opts.ProcessedFile, testName, opts.IncludeDuplicates, ...
                                             opts.NumSpecimens, opts.RemoveOutliers);

specimens = specimens(ismember(specimens.Material, opts.Materials), :);
if ~isempty(opts.Years)
    specimens = specimens(ismember(specimens.Year, opts.Years), :);
end
if ~isempty(opts.APRatios)
    specimens = specimens(ismember(specimens.APRatio_pct, opts.APRatios), :);
end

figureFiles = strings(0, 1);
if height(specimens) == 0
    warning('plot:noData', 'No usable %s specimens for the requested materials, years and AP ratios.', testName);
    return;
end
if ~isfolder(opts.OutputFolder)
    mkdir(opts.OutputFolder);
end

% One group per year (= one AP loading), ordered by AP
years  = unique(specimens.Year);
groups = sortrows([apRatio(years), years]);              % [AP, Year]; unknown AP (NaN) last

% Shades follow the AP value (40% is always the lightest), not its rank
apMap = apRatio();

results = struct([]);
flaggedParts = {};

for material = opts.Materials

    style = materialStyle(material, size(apMap, 1));
    first = numel(results) + 1;

    for gi = 1:size(groups, 1)

        ap   = groups(gi, 1);
        year = groups(gi, 2);
        sel  = specimens(specimens.Year == year & specimens.Material == material, :);
        if height(sel) == 0
            continue;
        end

        xs = cell(height(sel), 1);
        ys = cell(height(sel), 1);
        for i = 1:height(sel)
            r = sel.CurveRows{i};
            xs{i} = curves.(spec.XVar)(r);
            ys{i} = curves.(spec.YVar)(r);
        end

        res = struct();
        res.Year      = year;
        res.AP        = ap;
        res.Material  = material;
        res.Sel       = sel;
        res.X         = xs;
        res.Y         = ys;
        res.Avg       = averageCurves(xs, ys, opts.XLimit, opts.MinFraction, 500);
        res.PeakYMean = mean(sel.(spec.PeakY), 'omitnan');
        res.PeakYSD   = sdOrZero(sel.(spec.PeakY));
        res.PeakXMean = mean(sel.(spec.PeakX), 'omitnan');
        res.PeakXSD   = sdOrZero(sel.(spec.PeakX));
        k = find(apMap(:, 2) == ap, 1);
        if isempty(k)
            res.Shade = [0.54 0.53 0.51];                % AP not in apRatio.m
        else
            res.Shade = style.Ramp(k, :);
        end

        if isempty(results)
            results = res;
        else
            results(end+1) = res; %#ok<AGROW>
        end

        flaggedParts{end+1, 1} = flagSpecimens(sel, spec); %#ok<AGROW>

        figureFiles(end+1, 1) = detailFigure(res, testName, opts, style, spec); %#ok<AGROW>
    end

    if numel(results) >= first
        figureFiles(end+1, 1) = comparisonFigure(results(first:end), testName, material, ...
                                                 opts, spec); %#ok<AGROW>
        figureFiles(end+1, 1) = allAPFigure(results(first:end), testName, material, ...
                                            opts, spec); %#ok<AGROW>
    end
end

if isempty(results)
    warning('plot:noData', 'Nothing to plot for %s.', testName);
    return;
end

flagged = vertcat(flaggedParts{:});
removed = dropped(ismember(dropped.Material, opts.Materials), ...
                  {'Year', 'Material', 'SpecimenID', 'Label', 'FilePath', ...
                   char(spec.PeakY), char(spec.PeakX), 'Reason'});
writeAverages(results, flagged, removed, opts.SummaryFile, spec);
printRemoved(removed, testName);
printFlags(flagged, testName);
end

%% ========================================================================
%% What each test plots
%% ========================================================================

function spec = testSpec(testName)
switch lower(string(testName))
    case {"tension", "compression"}
        spec.XVar   = "Strain";
        spec.YVar   = "Stress_MPa";
        spec.XLabel = 'Strain (mm/mm)';
        spec.YLabel = 'Stress (MPa)';
        spec.XTip   = "Strain";
        spec.YTip   = "Stress (MPa)";
        spec.XWord  = "strain";
        spec.YWord  = "stress";
        spec.XUnit  = "";               % "0.15 strain"
        spec.YUnit  = "MPa";
        spec.PeakX  = "StrainAtPeak";
        spec.PeakY  = "PeakStress_MPa";
        spec.ShowPeaks = strcmpi(testName, "Tension");
        spec.PeakName  = "Fracture";
    case "fracture"
        spec.XVar   = "Displacement_mm";
        spec.YVar   = "Force_N";
        spec.XLabel = 'Displacement (mm)';
        spec.YLabel = 'Force (N)';
        spec.XTip   = "Displacement (mm)";
        spec.YTip   = "Force (N)";
        spec.XWord  = "displacement";
        spec.YWord  = "force";
        spec.XUnit  = "mm";
        spec.YUnit  = "N";
        spec.PeakX  = "DisplacementAtPeak_mm";
        spec.PeakY  = "PeakForce_N";
        spec.ShowPeaks = true;
        spec.PeakName  = "Peak load";
    otherwise
        error('plot:test', 'Unsupported test "%s".', testName);
end
end

function txt = xText(value, spec)
% "0.15 strain" or "1.2 mm"
if spec.XUnit == ""
    txt = string(sprintf('%.3g %s', value, spec.XWord));
else
    txt = string(sprintf('%.3g %s', value, spec.XUnit));
end
end

%% ========================================================================
%% Figures
%% ========================================================================

function outFile = detailFigure(res, testName, opts, style, spec)
% One AP loading, one material: specimens, mean, SD band (+ peak points)

[fig, ax] = styledFigure(opts.ShowFigures);
avg = res.Avg;
sel = res.Sel;
[~, apFile] = apLabels(res.AP);

handles = gobjects(0);
labels  = strings(0);

% Specimen curves: solid = in the mean, dotted = ended before the mean's end
if opts.ShowSpecimens
    hIn  = gobjects(0);
    hOut = gobjects(0);
    for i = 1:height(sel)
        x = res.X{i};
        y = res.Y{i};
        k = x <= opts.XLimit;
        if avg.Included(i)
            ls = '-';
        else
            ls = ':';
        end
        h = plot(ax, x(k), y(k), 'Color', style.Light, 'LineWidth', 0.8, 'LineStyle', ls);
        specimenTips(h, sel.Label(i), sel.FilePath(i), spec);
        if avg.Included(i)
            hIn = h;
        else
            hOut = h;
        end
    end
    if ~isempty(hIn)
        handles(end+1) = hIn;
        labels(end+1)  = "Specimens in the mean";
    end
    if ~isempty(hOut)
        handles(end+1) = hOut;
        labels(end+1)  = "Shorter tests, not averaged";
    end
end

hBand = drawBand(ax, avg, style.Base, 0.22);
hMean = drawMean(ax, avg, style.Base, spec);
if ~isempty(hBand)
    handles(end+1) = hBand;
    labels(end+1)  = char(177) + " 1 SD";
end
if ~isempty(hMean)
    handles(end+1) = hMean;
    labels(end+1)  = "Mean";
end

if spec.ShowPeaks
    px = sel.(spec.PeakX);
    py = sel.(spec.PeakY);
    hPts = scatter(ax, px, py, 36, style.Base, 'filled', ...
                   'MarkerEdgeColor', 'w', 'LineWidth', 0.75);
    hPts.DataTipTemplate.Interpreter = 'none';
    hPts.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
    hPts.DataTipTemplate.DataTipRows(2).Label = spec.YTip;
    hPts.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("Specimen", cellstr(sel.Label));
    handles(end+1) = hPts;
    labels(end+1)  = spec.PeakName + " points";

    hPk = errorbar(ax, res.PeakXMean, res.PeakYMean, res.PeakYSD, res.PeakYSD, ...
                   res.PeakXSD, res.PeakXSD, 'D', 'Color', style.Dark, ...
                   'MarkerFaceColor', style.Dark, 'MarkerEdgeColor', 'w', ...
                   'MarkerSize', 8, 'LineWidth', 1.8, 'CapSize', 10);
    handles(end+1) = hPk;
    labels(end+1)  = "Mean " + lower(spec.PeakName) + " " + char(177) + " 1 SD";
end

finishAxes(ax, opts, spec);
legend(ax, handles, cellstr(labels), 'Location', 'eastoutside', ...
       'Interpreter', 'none', 'FontSize', 11);

outFile = string(fullfile(opts.OutputFolder, ...
    sprintf('%s_%s_%d_%s.png', testName, apFile, res.Year, res.Material)));
saveFigure(fig, outFile, opts.ShowFigures);
fprintf('Saved %s  (mean of %d of %d, to %s)\n', outFile, avg.N, avg.NTotal, xText(avg.XEnd, spec));
end

function outFile = comparisonFigure(resList, testName, material, opts, spec)
% Every AP loading of one material on one plot

[fig, ax] = styledFigure(opts.ShowFigures);
handles = gobjects(0);
labels  = strings(0);
ends    = zeros(0, 3);          % [x, y, AP] for direct labels
yTop    = 0;

for r = 1:numel(resList)
    res = resList(r);
    avg = res.Avg;
    [apText, ~] = apLabels(res.AP);

    drawBand(ax, avg, res.Shade, 0.18);
    hMean = drawMean(ax, avg, res.Shade, spec);
    if isempty(hMean)
        continue;
    end
    handles(end+1) = hMean; %#ok<AGROW>
    labels(end+1)  = apText; %#ok<AGROW>

    ends(end+1, :) = [avg.XEnd, avg.Mean(end), res.AP]; %#ok<AGROW>
    sd = avg.SD;
    sd(~isfinite(sd)) = 0;
    yTop = max([yTop; avg.Mean + sd]);              % max ignores NaN

    if spec.ShowPeaks
        errorbar(ax, res.PeakXMean, res.PeakYMean, res.PeakYSD, res.PeakYSD, ...
                 res.PeakXSD, res.PeakXSD, 'D', 'Color', res.Shade, ...
                 'MarkerFaceColor', res.Shade, 'MarkerEdgeColor', 'w', ...
                 'MarkerSize', 7, 'LineWidth', 1.6, 'CapSize', 8);
        yTop = max([yTop, res.PeakYMean + res.PeakYSD]);
    end
end

if spec.ShowPeaks && ~isempty(handles)
    ink = [0.32 0.32 0.31];
    handles(end+1) = plot(ax, NaN, NaN, 'D', 'Color', ink, 'MarkerFaceColor', ink, ...
                          'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    labels(end+1)  = "Mean " + lower(spec.PeakName) + " " + char(177) + " 1 SD";
end

% Direct labels at the right-hand end of long mean curves, spread so they
% never sit on top of each other
if ~isempty(ends)
    long = ends(:, 1) >= 0.6 * opts.XLimit & isfinite(ends(:, 2));
    lab  = sortrows(ends(long, :), 2);
    gap  = 0.045 * max(yTop, 1);
    yPrev = -Inf;
    for i = 1:size(lab, 1)
        y = max(lab(i, 2), yPrev + gap);
        yPrev = y;
        text(ax, lab(i, 1) - 0.01 * opts.XLimit, y, sprintf('%g%%', lab(i, 3)), ...
             'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
             'FontSize', 11, 'Color', [0.32 0.32 0.31]);
    end
end

finishAxes(ax, opts, spec);
if ~isempty(handles)
    legend(ax, handles, cellstr(labels), 'Location', 'eastoutside', ...
           'Interpreter', 'none', 'FontSize', 11);
end

outFile = string(fullfile(opts.OutputFolder, ...
    sprintf('%s_%s_AP_Comparison.png', testName, material)));
saveFigure(fig, outFile, opts.ShowFigures);
fprintf('Saved %s\n', outFile);
end

function outFile = allAPFigure(resList, testName, material, opts, spec)
% Every AP loading of one material on one plot, with every specimen behind
% its mean +/- 1 SD (same shades as the comparison figure)

[fig, ax] = styledFigure(opts.ShowFigures);
handles = gobjects(0);
labels  = strings(0);

% 1) Specimen curves first so the means sit on top
if opts.ShowSpecimens
    for r = 1:numel(resList)
        res = resList(r);
        for i = 1:numel(res.X)
            x = res.X{i};
            y = res.Y{i};
            k = x <= opts.XLimit;
            if nnz(k) < 2
                continue;
            end
            h = plot(ax, x(k), y(k), 'Color', [res.Shade 0.22], 'LineWidth', 0.6);
            specimenTips(h, res.Sel.Label(i), res.Sel.FilePath(i), spec);
        end
    end
end

% 2) SD bands, then mean curves
for r = 1:numel(resList)
    drawBand(ax, resList(r).Avg, resList(r).Shade, 0.18);
end
for r = 1:numel(resList)
    res = resList(r);
    [apText, ~] = apLabels(res.AP);
    hMean = drawMean(ax, res.Avg, res.Shade, spec);
    if isempty(hMean)
        continue;
    end
    hMean.LineWidth = 2.6;
    handles(end+1) = hMean; %#ok<AGROW>
    labels(end+1)  = apText; %#ok<AGROW>
end

% 3) Peak points and mean peak +/- 1 SD for each AP
if spec.ShowPeaks
    for r = 1:numel(resList)
        res = resList(r);
        hPts = scatter(ax, res.Sel.(spec.PeakX), res.Sel.(spec.PeakY), 16, res.Shade, 'filled', ...
                       'MarkerEdgeColor', 'w', 'LineWidth', 0.4, 'MarkerFaceAlpha', 0.8);
        hPts.DataTipTemplate.Interpreter = 'none';
        hPts.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
        hPts.DataTipTemplate.DataTipRows(2).Label = spec.YTip;
        hPts.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("Specimen", cellstr(res.Sel.Label));
    end
    for r = 1:numel(resList)
        res = resList(r);
        errorbar(ax, res.PeakXMean, res.PeakYMean, res.PeakYSD, res.PeakYSD, ...
                 res.PeakXSD, res.PeakXSD, 'D', 'Color', res.Shade, ...
                 'MarkerFaceColor', res.Shade, 'MarkerEdgeColor', 'w', ...
                 'MarkerSize', 8, 'LineWidth', 1.8, 'CapSize', 10);
    end
    ink = [0.32 0.32 0.31];
    handles(end+1) = plot(ax, NaN, NaN, 'o', 'Color', ink, 'MarkerFaceColor', ink, ...
                          'MarkerEdgeColor', 'w', 'MarkerSize', 5);
    labels(end+1)  = spec.PeakName + " points";
    handles(end+1) = plot(ax, NaN, NaN, 'D', 'Color', ink, 'MarkerFaceColor', ink, ...
                          'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    labels(end+1)  = "Mean " + lower(spec.PeakName) + " " + char(177) + " 1 SD";
end

finishAxes(ax, opts, spec);
if ~isempty(handles)
    legend(ax, handles, cellstr(labels), 'Location', 'eastoutside', ...
           'Interpreter', 'none', 'FontSize', 11);
end

outFile = string(fullfile(opts.OutputFolder, ...
    sprintf('%s_%s_AllAP_Specimens.png', testName, material)));
saveFigure(fig, outFile, opts.ShowFigures);
fprintf('Saved %s\n', outFile);
end

%% ========================================================================
%% Drawing helpers
%% ========================================================================

function h = drawBand(ax, avg, color, alpha)
% Shaded mean +/- 1 SD (never below zero); empty if no SD
h = gobjects(0);
ok = isfinite(avg.SD) & isfinite(avg.Mean);
if nnz(ok) < 2
    return;
end
x  = avg.Strain(ok);
lo = max(avg.Mean(ok) - avg.SD(ok), 0);
hi = avg.Mean(ok) + avg.SD(ok);
h = fill(ax, [x; flipud(x)], [lo; flipud(hi)], color, ...
         'FaceAlpha', alpha, 'EdgeColor', 'none', 'PickableParts', 'none');
end

function h = drawMean(ax, avg, color, spec)
% Mean curve with data tips showing SD and n
h = gobjects(0);
if isempty(avg.Strain)
    return;
end
h = plot(ax, avg.Strain, avg.Mean, 'Color', color, 'LineWidth', 2.4);
h.DataTipTemplate.Interpreter = 'none';
h.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
h.DataTipTemplate.DataTipRows(2).Label = "Mean " + spec.YWord + " (" + spec.YUnit + ")";
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("SD (" + spec.YUnit + ")", avg.SD);
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("Specimens", repmat(avg.N, numel(avg.Strain), 1));
end

function specimenTips(h, label, filePath, spec)
n = numel(h.XData);
h.DataTipTemplate.Interpreter = 'none';
h.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
h.DataTipTemplate.DataTipRows(2).Label = spec.YTip;
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("Specimen", repmat(cellstr(label), n, 1));
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("File", repmat(cellstr(filePath), n, 1));
end

function [fig, ax] = styledFigure(show)
if show
    vis = 'on';
else
    vis = 'off';
end
fig = figure('Visible', vis, 'Color', 'w', 'Units', 'pixels', 'Position', [100 100 1150 700]);
ax = axes(fig);
hold(ax, 'on');
grid(ax, 'on');
box(ax, 'on');
ax.SortMethod = 'childorder';           % draw order = creation order
ax.FontSize   = 13;
ax.GridColor  = [0.80 0.80 0.78];       % recessive grid
ax.GridAlpha  = 0.6;
ax.XColor     = [0.32 0.32 0.31];
ax.YColor     = [0.32 0.32 0.31];
end

function finishAxes(ax, opts, spec)
xlim(ax, 'tight');                      % fit x to the plotted data (XLimit still crops the mean)
if isempty(opts.YLimit)
    ylim(ax, [0 Inf]);
else
    ylim(ax, opts.YLimit);
end
xlabel(ax, spec.XLabel, 'FontWeight', 'bold', 'FontSize', 16, 'Color', [0.04 0.04 0.04]);
ylabel(ax, spec.YLabel, 'FontWeight', 'bold', 'FontSize', 16, 'Color', [0.04 0.04 0.04]);
end

function saveFigure(fig, outFile, show)
exportFigure(fig, outFile);
if ~show
    close(fig);
end
end

function [apText, apFile] = apLabels(ap)
if isnan(ap)
    apText = "AP ?";
    apFile = "APunknown";
else
    apText = string(sprintf('%g%% AP', ap));
    apFile = string(sprintf('AP%g', ap));
end
end

function st = materialStyle(material, nShades)
% CNT = blue family, NEAT = orange family in every figure (incl. modulus).
% Ramps are one hue, light -> dark, validated as ordinal ramps.
switch upper(string(material))
    case "CNT"
        base = "#2a78d6";  ramp = ["#86b6ef", "#3987e5", "#1c5cab", "#0d366b"];
    case "NEAT"
        base = "#eb6834";  ramp = ["#fe9068", "#e15102", "#9e3601", "#611e01"];
    otherwise
        base = "#52514e";  ramp = ["#c3c2b7", "#898781", "#52514e", "#0b0b0b"];
end
R = zeros(numel(ramp), 3);
for i = 1:numel(ramp)
    R(i, :) = hex2rgb(ramp(i));
end
if nShades ~= size(R, 1) && nShades >= 2
    R = interp1(linspace(0, 1, size(R, 1)), R, linspace(0, 1, nShades));
end
st.Base  = hex2rgb(base);
st.Light = 1 - 0.35 * (1 - st.Base);     % faint specimen curves
st.Dark  = R(end, :);
st.Ramp  = R;
end

function rgb = hex2rgb(hex)
h = char(hex);
rgb = sscanf(h(2:end), '%2x')' / 255;
end

function s = sdOrZero(v)
v = v(isfinite(v));
if numel(v) >= 2
    s = std(v);
else
    s = 0;
end
end

%% ========================================================================
%% Outliers, flags and workbook
%% ========================================================================

function printRemoved(removed, testName)
if isempty(removed) || height(removed) == 0
    return;
end
fprintf('\n%s: left out %d specimens (see the Removed sheet)\n', testName, height(removed));
for i = 1:height(removed)
    fprintf('  %g%% AP %-4s %s - %s\n', apRatio(removed.Year(i)), removed.Material(i), ...
        removed.Label(i), removed.Reason(i));
end
end

function rows = flagSpecimens(sel, spec)
% Specimens worth a look: peak under half the group median, or peak
% position over 3x the group median. Nothing is removed here.
cols = {'Year', 'APRatio_pct', 'Material', 'SpecimenID', 'Label', 'FilePath', ...
        char(spec.PeakY), char(spec.PeakX)};
rows = sel([], cols);
rows.Reason = strings(0, 1);
if height(sel) < 3
    return;
end
peakY = sel.(spec.PeakY);
peakX = sel.(spec.PeakX);
medY = median(peakY, 'omitnan');
medX = median(peakX, 'omitnan');
low = peakY < 0.5 * medY;
far = peakX > 3 * medX;
reason = strings(height(sel), 1);
reason(low) = sprintf('peak under half the group median (%.3g %s)', medY, spec.YUnit);
reason(far & ~low) = sprintf('%s at peak over 3x the group median (%s)', spec.XWord, xText(medX, spec));
reason(far & low) = reason(far & low) + ...
    sprintf('; %s at peak over 3x the group median (%s)', spec.XWord, xText(medX, spec));
pick = reason ~= "";
rows = sel(pick, cols);
rows.Reason = reason(pick);
end

function printFlags(flagged, testName)
if isempty(flagged) || height(flagged) == 0
    return;
end
fprintf('\n%s: %d specimens worth a look (nothing removed; add bad ones to excludedSpecimens.m)\n', ...
    testName, height(flagged));
for i = 1:height(flagged)
    fprintf('  %g%% AP %-4s %s - %s\n      %s\n', flagged.APRatio_pct(i), flagged.Material(i), ...
        flagged.Label(i), flagged.Reason(i), flagged.FilePath(i));
end
fprintf('\n');
end

function writeAverages(results, flagged, removed, file, spec)
% Summary, averaged curves and flags in one workbook
n = numel(results);
avgs = [results.Avg];
summary = table([results.AP]', [results.Year]', [results.Material]', ...
                [avgs.NTotal]', [avgs.N]', [avgs.XEnd]', ...
                [results.PeakYMean]', [results.PeakYSD]', ...
                [results.PeakXMean]', [results.PeakXSD]', ...
    'VariableNames', {'APRatio_pct', 'Year', 'Material', ...
                      'NumSpecimens', 'NumInMean', char("MeanCurveEnd_" + spec.XVar), ...
                      char(spec.PeakY + "_Mean"), char(spec.PeakY + "_SD"), ...
                      char(spec.PeakX + "_Mean"), char(spec.PeakX + "_SD")});

parts = cell(n, 1);
for r = 1:n
    a = results(r).Avg;
    m = numel(a.Strain);
    parts{r} = table(repmat(results(r).AP, m, 1), repmat(results(r).Year, m, 1), ...
                     repmat(results(r).Material, m, 1), a.Strain, a.Mean, a.SD, ...
                     repmat(a.N, m, 1), ...
                     'VariableNames', {'APRatio_pct', 'Year', 'Material', char(spec.XVar), ...
                                       char("Mean_" + spec.YVar), char("SD_" + spec.YVar), ...
                                       'NumInMean'});
end
curveTable = vertcat(parts{:});

folder = fileparts(file);
if ~isfolder(folder)
    mkdir(folder);
end
if isfile(file)
    delete(file);
    if isfile(file)
        error('plot:locked', 'Close %s in Excel and run again.', file);
    end
end
writetable(summary, file, 'Sheet', 'Summary');
writetable(curveTable, file, 'Sheet', 'Curves');
if ~isempty(flagged)
    writetable(flagged, file, 'Sheet', 'Flagged');
end
if ~isempty(removed) && height(removed) > 0
    writetable(removed, file, 'Sheet', 'Removed');
end
fprintf('Saved %s\n', file);
end
