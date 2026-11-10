function figureFiles = plotSpecimenBands(testName, opts)
%PLOTSPECIMENBANDS Many-specimen curve figures: median, percentile bands and a peak strip.
%
%   plotSpecimenBands("Fracture")
%   plotSpecimenBands("Tension", APRatios=70, ShowFigures=true)
%   for t = ["Tension" "Compression" "Fracture"], plotSpecimenBands(t); end
%
%   One figure per AP loading and material, saved to
%     <repo>/Figures_Claude/<Test>/<Test>_AP<ratio>_<year>_<CNT|NEAT>.png
%   The original figures in <repo>/Figures are not touched.
%
%   Layout
%     Left   every specimen as a thin grey curve (context, not the message)
%            median curve, 25-75th percentile band (IQR), 5-95th percentile band
%            median peak point with IQR whiskers in x and y
%     Right  (tension and fracture) a strip on the same y axis: box plot of the
%            peak values (box = IQR, line = median, whiskers = 1.5 IQR) over
%            every specimen's peak as a jittered dot; hollow dots are outliers
%     x axis is tight to the data; y starts at 0.
%
%   Why median and percentiles instead of mean +/- 1 SD: with ~100 specimens
%   a few odd tests pull the mean and inflate the SD; percentiles show the
%   real spread and are not symmetric by force. 124 overlapping peak dots on
%   the curves also hid the distribution; the strip shows it directly.
%
%   The bands use the same specimens as the mean curve in plotAveragedCurves:
%   the ones that reach XEnd, the x value that at least MinFraction of the
%   specimens reach (so every point of the median is the same specimens).
%
%   Options
%     ProcessedFile      workbook (default <repo>/ProcessedData/JuniorLab_ProcessedData.xlsx)
%     OutputFolder       default <repo>/Figures_Claude/<Test>
%     XLimit             crop in strain or mm (default 0.2 tension, 0.15
%                        compression, 3.5 mm fracture, as in plotTension etc.)
%     MinFraction        share of specimens the bands must keep (default 0.75)
%     APRatios, Years    filters; [] = all (default)
%     Materials          default ["CNT","NEAT"]
%     ShowFigures        keep figures open for data tips (default false)
%     ExportPDF          also save a vector PDF next to each PNG (default false)
%     IncludeDuplicates  also use CSVs flagged as copies (default false)
%     NumSpecimens       specimens per AP loading and material, closest to the
%                        group median (default 13; Inf = all; see private/selectSpecimens.m)

arguments
    testName               (1,1) string {mustBeMember(testName, ["Tension", "Compression", "Fracture"])}
    opts.ProcessedFile     (1,1) string = ""
    opts.OutputFolder      (1,1) string = ""
    opts.XLimit            double = []
    opts.MinFraction       (1,1) double {mustBePositive} = 0.75
    opts.APRatios          double = []
    opts.Years             double = []
    opts.Materials         (1,:) string = ["CNT", "NEAT"]
    opts.ShowFigures       (1,1) logical = false
    opts.ExportPDF         (1,1) logical = false
    opts.IncludeDuplicates (1,1) logical = false
    opts.NumSpecimens      (1,1) double {mustBePositive} = 13
end

if opts.MinFraction > 1
    error('plot:minFraction', 'MinFraction must be in (0, 1], got %g.', opts.MinFraction);
end

p = pipelinePaths();
if opts.ProcessedFile == "", opts.ProcessedFile = p.ProcessedFile; end
if opts.OutputFolder  == "", opts.OutputFolder  = fullfile(p.Root, 'Figures_Claude', testName); end
spec = testSpec(testName);
if isempty(opts.XLimit), opts.XLimit = spec.DefaultXLimit; end

[specimens, curves] = loadSpecimens(opts.ProcessedFile, testName, opts.IncludeDuplicates, ...
    opts.NumSpecimens);
specimens = specimens(ismember(specimens.Material, opts.Materials), :);
if ~isempty(opts.Years),    specimens = specimens(ismember(specimens.Year, opts.Years), :);           end
if ~isempty(opts.APRatios), specimens = specimens(ismember(specimens.APRatio_pct, opts.APRatios), :); end

figureFiles = strings(0, 1);
if height(specimens) == 0
    warning('plot:noData', 'No usable %s specimens for the requested filters.', testName);
    return;
end
if ~isfolder(opts.OutputFolder)
    mkdir(opts.OutputFolder);
end

years  = unique(specimens.Year);
groups = sortrows([apRatio(years), years]);       % [AP, Year]

for material = opts.Materials
    style = materialStyle(material);
    for gi = 1:size(groups, 1)
        sel = specimens(specimens.Year == groups(gi, 2) & specimens.Material == material, :);
        if height(sel) == 0
            continue;
        end
        xs = cell(height(sel), 1);
        ys = cell(height(sel), 1);
        for i = 1:height(sel)
            r = sel.CurveRows{i};
            x = curves.(spec.XVar)(r);
            y = curves.(spec.YVar)(r);
            k = isfinite(x) & isfinite(y) & x <= opts.XLimit;
            xs{i} = x(k);
            ys{i} = y(k);
        end
        figureFiles(end+1, 1) = bandFigure(sel, xs, ys, groups(gi, 1), groups(gi, 2), ...
                                           material, testName, spec, style, opts); %#ok<AGROW>
    end
end
end

%% ========================================================================
%% Figure
%% ========================================================================

function outFile = bandFigure(sel, xs, ys, ap, year, material, testName, spec, style, opts)

ink   = [0.13 0.13 0.12];      % titles, labels
mute  = [0.42 0.42 0.40];      % axes, secondary text
gridC = [0.90 0.90 0.88];
grey  = [0.62 0.62 0.59];      % specimen curves (drawn with alpha)

bands = percentileBands(xs, ys, opts.XLimit, opts.MinFraction);

if opts.ShowFigures, vis = 'on'; else, vis = 'off'; end
fig = figure('Visible', vis, 'Color', 'w', 'Units', 'pixels', 'Position', [80 80 1200 760]);

if spec.ShowPeaks
    ax = axes(fig, 'Position', [0.075 0.11 0.715 0.72]);
    sx = axes(fig, 'Position', [0.815 0.11 0.13 0.72]);
else
    ax = axes(fig, 'Position', [0.075 0.11 0.89 0.72]);
    sx = [];
end
hold(ax, 'on');
styleAxes(ax, mute, gridC);

% 1) Specimens: thin, grey, translucent. One handle kept for the legend.
hSpec = gobjects(0);
xMax = 0;
yMax = 0;
for i = 1:numel(xs)
    if numel(xs{i}) < 2, continue; end
    h = plot(ax, xs{i}, ys{i}, 'LineWidth', 0.6, 'Color', [grey 0.45]);
    specimenTips(h, sel.Label(i), sel.FilePath(i), spec);
    hSpec = h;
    xMax = max(xMax, max(xs{i}));
    yMax = max(yMax, max(ys{i}));
end

% 2) Bands and median
hOuter = gobjects(0); hIQR = gobjects(0); hMed = gobjects(0);
if bands.N >= 2
    hOuter = bandPatch(ax, bands.X, bands.P5,  bands.P95, style.Base, 0.15);
    hIQR   = bandPatch(ax, bands.X, bands.P25, bands.P75, style.Base, 0.35);
end
if bands.N >= 1
    hMed = plot(ax, bands.X, bands.P50, 'Color', style.Dark, 'LineWidth', 2.4);
    hMed.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
    hMed.DataTipTemplate.DataTipRows(2).Label = "Median " + spec.YWord + " (" + spec.YUnit + ")";
    hMed.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("25th pct", bands.P25);
    hMed.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("75th pct", bands.P75);
end

% 3) Median peak with IQR whiskers (x and y)
hPk = gobjects(0);
if spec.ShowPeaks
    px = sel.(spec.PeakX);
    py = sel.(spec.PeakY);
    ok = isfinite(px) & isfinite(py) & px <= opts.XLimit;
    px = px(ok);
    py = py(ok);
    if ~isempty(py)
        qx = pct(px(:), [25 50 75]);
        qy = pct(py(:), [25 50 75]);
        hPk = errorbar(ax, qx(2), qy(2), qy(2) - qy(1), qy(3) - qy(2), ...
                       qx(2) - qx(1), qx(3) - qx(2), 'D', 'Color', style.Dark, ...
                       'MarkerFaceColor', style.Dark, 'MarkerEdgeColor', 'w', ...
                       'MarkerSize', 8, 'LineWidth', 1.4, 'CapSize', 8);
        yMax = max(yMax, max(py));
    end
end

% Limits: x tight to the data, y from 0 with a little headroom, shared by the strip
yTop = niceTop(1.04 * yMax);
xlim(ax, [0 max(xMax, eps)]);
ylim(ax, [0 yTop]);

xlabel(ax, spec.XLabel, 'FontSize', 14, 'Color', ink);
ylabel(ax, spec.YLabel, 'FontSize', 14, 'Color', ink);

apText = sprintf('%g%% AP', ap);
if isnan(ap), apText = 'AP ?'; end
title(ax, sprintf('%s %s  %s  %s (%d)', material, lower(testName), char(183), apText, year), ...
      'FontSize', 17, 'FontWeight', 'bold', 'Color', ink);
sub = sprintf('%d specimens %s median and bands from the %d that reach %s', ...
              numel(xs), char(183), bands.N, xText(bands.XEnd, spec));
subtitle(ax, sub, 'FontSize', 11.5, 'Color', mute);
ax.TitleHorizontalAlignment = 'left';

% Legend (lower right is empty for these curve shapes)
hs = gobjects(0); ls = strings(0);
if ~isempty(hSpec),  hs(end+1) = hSpec;  ls(end+1) = sprintf('Specimens (%d)', numel(xs)); end
if ~isempty(hOuter), hs(end+1) = hOuter; ls(end+1) = "5" + char(8211) + "95th percentile"; end
if ~isempty(hIQR),   hs(end+1) = hIQR;   ls(end+1) = "25" + char(8211) + "75th percentile (IQR)"; end
if ~isempty(hMed),   hs(end+1) = hMed;   ls(end+1) = "Median"; end
if ~isempty(hPk),    hs(end+1) = hPk;    ls(end+1) = "Median " + lower(spec.PeakName) + " " + char(177) + " IQR"; end
if ~isempty(hs)
    lg = legend(ax, hs, cellstr(ls), 'Location', 'southeast', 'Box', 'off', ...
                'FontSize', 11, 'Interpreter', 'none');
    lg.TextColor = ink;
end

% 4) Peak strip
if spec.ShowPeaks
    peakStrip(sx, py, style, spec, yTop, ink, mute, gridC);
    linkaxes([ax sx], 'y');
end

outFile = string(fullfile(opts.OutputFolder, ...
    sprintf('%s_AP%g_%d_%s.png', testName, ap, year, material)));
saveFigure(fig, outFile, opts);
fprintf('Saved %s  (%d specimens, bands from %d)\n', outFile, numel(xs), bands.N);
end

function peakStrip(sx, py, style, spec, yTop, ink, mute, gridC)
% Box plot (IQR, median, 1.5 IQR whiskers) over jittered peak values
hold(sx, 'on');
styleAxes(sx, mute, gridC);
sx.XAxis.Visible = 'off';
sx.YTickLabel = {};
sx.YAxis.Color = 'none';            % keep the grid, hide the spine
xlim(sx, [-0.6 0.6]);
ylim(sx, [0 yTop]);
title(sx, spec.PeakName, 'FontSize', 12, 'FontWeight', 'normal', 'Color', ink);
if isempty(py)
    return;
end

q = pct(py(:), [25 50 75]);
iqrW = q(3) - q(1);
inFence = py >= q(1) - 1.5 * iqrW & py <= q(3) + 1.5 * iqrW;
wLo = min(py(inFence));
wHi = max(py(inFence));

% Deterministic jitter (golden-ratio sequence), so reruns look identical
n = numel(py);
[~, order] = sort(py);
jit = zeros(n, 1);
jit(order) = (mod((1:n)' * 0.618034, 1) - 0.5) * 0.56;

scatter(sx, jit(inFence), py(inFence), 16, style.Base, 'filled', ...
        'MarkerFaceAlpha', 0.55, 'MarkerEdgeColor', 'none');
scatter(sx, jit(~inFence), py(~inFence), 22, style.Base, 'LineWidth', 1);

rectangle(sx, 'Position', [-0.35 q(1) 0.7 max(iqrW, eps)], 'EdgeColor', style.Dark, 'LineWidth', 1.3);
plot(sx, [-0.35 0.35], [q(2) q(2)], 'Color', style.Dark, 'LineWidth', 2.4);
plot(sx, [0 0], [q(3) wHi], 'Color', style.Dark, 'LineWidth', 1.1);
plot(sx, [0 0], [wLo q(1)], 'Color', style.Dark, 'LineWidth', 1.1);
plot(sx, [-0.12 0.12], [wHi wHi], 'Color', style.Dark, 'LineWidth', 1.1);
plot(sx, [-0.12 0.12], [wLo wLo], 'Color', style.Dark, 'LineWidth', 1.1);

text(sx, 0.5, -0.02, sprintf('median %s %s\nIQR %s%s%s', fmt(q(2)), spec.YUnit, ...
     fmt(q(1)), char(8211), fmt(q(3))), 'Units', 'normalized', ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
     'FontSize', 10.5, 'Color', mute);
end

%% ========================================================================
%% Statistics
%% ========================================================================

function b = percentileBands(xs, ys, xLimit, minFraction)
% Percentiles on a common grid, using the specimens that reach XEnd
% (same rule as averageCurves, so the median never jumps when a test ends)
avg = averageCurves(xs, ys, xLimit, minFraction, 500);
b.XEnd = avg.XEnd;
b.N    = avg.N;
b.X    = zeros(0, 1);
[b.P5, b.P25, b.P50, b.P75, b.P95] = deal(zeros(0, 1));
if avg.N == 0
    return;
end
x = linspace(0, avg.XEnd, 500)';
idx = find(avg.Included);
Y = NaN(numel(x), numel(idx));
for c = 1:numel(idx)
    e = xs{idx(c)}(:);
    s = ys{idx(c)}(:);
    [e, firstIdx] = unique(e);          % sorted, distinct x for interp1
    s = s(firstIdx);
    if numel(e) >= 2
        Y(:, c) = interp1(e, s, x, 'linear', NaN);
    end
end
P = pct(Y', [5 25 50 75 95]);           % rows of Y' are specimens
b.X   = x;
b.P5  = P(:, 1); b.P25 = P(:, 2); b.P50 = P(:, 3); b.P75 = P(:, 4); b.P95 = P(:, 5);
end

function q = pct(A, p)
% Percentiles down each column of A, NaN ignored, linear interpolation
% between order statistics (no Statistics Toolbox needed).
% Returns size(A,2) x numel(p); pass a column (v(:)) for one variable.
q = NaN(size(A, 2), numel(p));
for j = 1:size(A, 2)
    v = sort(A(isfinite(A(:, j)), j));
    n = numel(v);
    if n == 0, continue; end
    if n == 1, q(j, :) = v; continue; end
    h = (n - 1) * p(:)' / 100 + 1;
    lo = floor(h);
    hi = min(lo + 1, n);
    q(j, :) = v(lo)' + (h - lo) .* (v(hi)' - v(lo)');
end
end

%% ========================================================================
%% Helpers
%% ========================================================================

function spec = testSpec(testName)
switch testName
    case {"Tension", "Compression"}
        spec.XVar = "Strain";            spec.YVar = "Stress_MPa";
        spec.XLabel = 'Strain (mm/mm)';  spec.YLabel = 'Stress (MPa)';
        spec.XTip = "Strain";            spec.YTip = "Stress (MPa)";
        spec.XWord = "strain";           spec.YWord = "stress";
        spec.XUnit = "";                 spec.YUnit = "MPa";
        spec.PeakX = "StrainAtPeak";     spec.PeakY = "PeakStress_MPa";
        spec.ShowPeaks = testName == "Tension";
        spec.PeakName  = "Fracture stress";
        if testName == "Tension", spec.DefaultXLimit = 0.2; else, spec.DefaultXLimit = 0.15; end
    case "Fracture"
        spec.XVar = "Displacement_mm";   spec.YVar = "Force_N";
        spec.XLabel = 'Displacement (mm)'; spec.YLabel = 'Force (N)';
        spec.XTip = "Displacement (mm)"; spec.YTip = "Force (N)";
        spec.XWord = "displacement";     spec.YWord = "force";
        spec.XUnit = "mm";               spec.YUnit = "N";
        spec.PeakX = "DisplacementAtPeak_mm"; spec.PeakY = "PeakForce_N";
        spec.ShowPeaks = true;
        spec.PeakName  = "Peak load";
        spec.DefaultXLimit = 3.5;
end
end

function styleAxes(ax, mute, gridC)
ax.FontSize   = 12;
ax.Box        = 'off';
ax.TickDir    = 'out';
ax.TickLength = [0.006 0.006];
ax.XColor     = mute;
ax.YColor     = mute;
ax.LineWidth  = 0.8;
ax.XGrid      = 'off';
ax.YGrid      = 'on';
ax.GridColor  = gridC;
ax.GridAlpha  = 1;
ax.Layer      = 'bottom';
ax.SortMethod = 'childorder';
end

function h = bandPatch(ax, x, lo, hi, color, alpha)
ok = isfinite(lo) & isfinite(hi);
h = gobjects(0);
if nnz(ok) < 2, return; end
x = x(ok); lo = max(lo(ok), 0); hi = hi(ok);
h = fill(ax, [x; flipud(x)], [lo; flipud(hi)], color, ...
         'FaceAlpha', alpha, 'EdgeColor', 'none', 'PickableParts', 'none');
end

function specimenTips(h, label, filePath, spec)
n = numel(h.XData);
h.DataTipTemplate.Interpreter = 'none';
h.DataTipTemplate.DataTipRows(1).Label = spec.XTip;
h.DataTipTemplate.DataTipRows(2).Label = spec.YTip;
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("Specimen", repmat(cellstr(label), n, 1));
h.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("File", repmat(cellstr(filePath), n, 1));
end

function st = materialStyle(material)
% Same hues as plotAveragedCurves: CNT blue, NEAT orange
switch upper(string(material))
    case "CNT",  st.Base = hex2rgb("#2a78d6"); st.Dark = hex2rgb("#0d366b");
    case "NEAT", st.Base = hex2rgb("#eb6834"); st.Dark = hex2rgb("#7a2a01");
    otherwise,   st.Base = hex2rgb("#52514e"); st.Dark = hex2rgb("#0b0b0b");
end
end

function rgb = hex2rgb(hex)
h = char(hex);
rgb = sscanf(h(2:end), '%2x')' / 255;
end

function t = niceTop(v)
% Round up to a 1/2/2.5/5 x 10^k step so the top tick is a round number
if ~(v > 0), t = 1; return; end
k = 10^floor(log10(v));
steps = [1 1.2 1.5 2 2.5 3 3.5 4 5 6 7 8 10];
t = k * steps(find(steps * k >= v, 1));
end

function s = fmt(v)
s = sprintf('%.3g', v);
end

function txt = xText(value, spec)
if spec.XUnit == ""
    txt = sprintf('%.3g %s', value, spec.XWord);
else
    txt = sprintf('%.3g %s', value, spec.XUnit);
end
end

function saveFigure(fig, outFile, opts)
% Retries, then a timestamped name if the PNG is open in another program
files = outFile;
if opts.ExportPDF
    files(end+1) = replace(outFile, ".png", ".pdf");
end
for f = files
    exportFigure(fig, f);
end
if ~opts.ShowFigures
    close(fig);
end
end
