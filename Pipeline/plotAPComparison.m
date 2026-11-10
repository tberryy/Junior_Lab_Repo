function figureFiles = plotAPComparison(opts)
%PLOTAPCOMPARISON Mean curve +/- 1 SD of every AP loading, ending at the mean fracture point.
%
%   plotAPComparison()                one figure per test and material
%   plotAPComparison(Name=Value)      see options below
%
%   Each figure shows every AP loading (year) of one test and material:
%     - mean curve and shaded +/- 1 SD band
%     - mean fracture point (peak) with +/- 1 SD bars in both directions
%     - dashed vertical line from the mean fracture point to the x-axis
%   No title; the legend lists only the AP %.
%
%   The mean curve ends exactly at the mean fracture point. Every specimen
%   is cut at its own peak and resampled at the same fractions u of its
%   strain (or displacement) at peak, u = 0..1. At each u
%       x = u * mean(strain at peak)
%       y = mean of the specimens' stresses (forces), band = their SD
%   so at u = 1 the curve reaches (mean strain at peak, mean peak stress)
%   and the band equals the vertical SD bar. Every specimen counts along the
%   whole curve. Compression curves stop at the peak.
%
%   Saves, in OutputFolder:
%     <Test>/PNG/<Test>_<CNT|NEAT>_AP_Comparison.png
%     <Test>/PDF/<Test>_<CNT|NEAT>_AP_Comparison.pdf   (vector)
%
%   Options
%     ProcessedFile      workbook to read (default <repo>/ProcessedData/JuniorLab_ProcessedData.xlsx)
%     OutputFolder       default <repo>/Figures/AP_Comparison
%     Tests              default ["Tension", "Compression", "Fracture"]
%     Materials          default ["CNT", "NEAT"]
%     NumSpecimens       specimens per AP loading and material, closest to the
%                        group median (default Inf = all; see private/selectSpecimens.m)
%     RemoveOutliers     leave out isoutlier outliers on the peak and its
%                        position (default true)
%     YLimit             [ymin ymax]; [] = automatic (default)
%     ShowFigures        keep figures open (default false)
%     IncludeDuplicates  also use CSVs flagged as copies (default false)
%
%   Example
%     plotAPComparison(Tests="Tension", NumSpecimens=13)

arguments
    opts.ProcessedFile     (1,1) string = ""
    opts.OutputFolder      (1,1) string = ""
    opts.Tests             (1,:) string = ["Tension", "Compression", "Fracture"]
    opts.Materials         (1,:) string = ["CNT", "NEAT"]
    opts.NumSpecimens      (1,1) double {mustBePositive} = Inf
    opts.RemoveOutliers    (1,1) logical = true
    opts.YLimit            double = []
    opts.ShowFigures       (1,1) logical = false
    opts.IncludeDuplicates (1,1) logical = false
end

p = pipelinePaths();
if opts.ProcessedFile == "", opts.ProcessedFile = p.ProcessedFile;                        end
if opts.OutputFolder  == "", opts.OutputFolder  = fullfile(p.Figures, 'AP_Comparison');   end

numPoints = 200;
apMap = apRatio();
figureFiles = strings(0, 1);

for testName = opts.Tests

    spec = testSpec(testName);
    [specimens, curves] = loadSpecimens(opts.ProcessedFile, testName, opts.IncludeDuplicates, ...
                                        opts.NumSpecimens, opts.RemoveOutliers);

    pngFolder = fullfile(opts.OutputFolder, testName, 'PNG');
    pdfFolder = fullfile(opts.OutputFolder, testName, 'PDF');
    if ~isfolder(pngFolder), mkdir(pngFolder); end
    if ~isfolder(pdfFolder), mkdir(pdfFolder); end

    for material = opts.Materials

        sel = specimens(specimens.Material == material, :);
        if height(sel) == 0
            warning('plot:noData', 'No usable %s %s specimens.', material, testName);
            continue;
        end

        ramp = materialRamp(material, size(apMap, 1));
        groups = sortrows([apRatio(unique(sel.Year)), unique(sel.Year)]);   % [AP, Year]

        % Compute every AP loading first so bands can be drawn under all curves
        res = struct('AP', {}, 'Shade', {}, 'X', {}, 'Mean', {}, 'SD', {}, ...
                     'PeakX', {}, 'PeakY', {}, 'PeakXSD', {}, 'PeakYSD', {});
        for gi = 1:size(groups, 1)
            g = sel(sel.Year == groups(gi, 2), :);
            [x, m, s] = averageToPeak(g, curves, spec, numPoints);
            k = find(apMap(:, 2) == groups(gi, 1), 1);
            if isempty(k)
                shade = [0.54 0.53 0.51];                   % AP not in apRatio.m
            else
                shade = ramp(k, :);
            end
            res(end+1) = struct('AP', groups(gi, 1), 'Shade', shade, 'X', x, 'Mean', m, 'SD', s, ...
                                'PeakX', mean(g.(spec.PeakX), 'omitnan'), ...
                                'PeakY', mean(g.(spec.PeakY), 'omitnan'), ...
                                'PeakXSD', sdOrZero(g.(spec.PeakX)), ...
                                'PeakYSD', sdOrZero(g.(spec.PeakY))); %#ok<AGROW>
        end

        [fig, ax] = styledFigure(opts.ShowFigures);

        % 1) SD bands
        for r = 1:numel(res)
            lo = max(res(r).Mean - res(r).SD, 0);
            hi = res(r).Mean + res(r).SD;
            ok = isfinite(lo) & isfinite(hi);
            fill(ax, [res(r).X(ok); flipud(res(r).X(ok))], [lo(ok); flipud(hi(ok))], res(r).Shade, ...
                 'FaceAlpha', 0.18, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end

        % 2) Dashed line from each mean fracture point down to the x-axis
        for r = 1:numel(res)
            plot(ax, [res(r).PeakX res(r).PeakX], [0 res(r).PeakY], '--', ...
                 'Color', res(r).Shade, 'LineWidth', 1.3, 'HandleVisibility', 'off');
        end

        % 3) Mean curves, ending on the mean fracture point
        handles = gobjects(0);
        labels  = strings(0);
        for r = 1:numel(res)
            handles(end+1) = plot(ax, res(r).X, res(r).Mean, 'Color', res(r).Shade, ...
                                  'LineWidth', 2.4); %#ok<AGROW>
            labels(end+1) = sprintf('%g%% AP', res(r).AP); %#ok<AGROW>
        end

        % 4) Mean fracture point +/- 1 SD in both directions
        for r = 1:numel(res)
            errorbar(ax, res(r).PeakX, res(r).PeakY, res(r).PeakYSD, res(r).PeakYSD, ...
                     res(r).PeakXSD, res(r).PeakXSD, 'D', 'Color', res(r).Shade, ...
                     'MarkerFaceColor', res(r).Shade, 'MarkerEdgeColor', 'w', ...
                     'MarkerSize', 8, 'LineWidth', 1.6, 'CapSize', 10, 'HandleVisibility', 'off');
        end
        ink = [0.32 0.32 0.31];
        handles(end+1) = plot(ax, NaN, NaN, 'D', 'Color', ink, 'MarkerFaceColor', ink, ...
                              'MarkerEdgeColor', 'w', 'MarkerSize', 7);
        labels(end+1)  = "Mean " + spec.PeakName + " " + char(177) + " 1 SD";

        xlim(ax, [0 Inf]);
        if isempty(opts.YLimit)
            ylim(ax, [0 Inf]);
        else
            ylim(ax, opts.YLimit);
        end
        xlabel(ax, spec.XLabel, 'FontWeight', 'bold', 'FontSize', 16, 'Color', [0.04 0.04 0.04]);
        ylabel(ax, spec.YLabel, 'FontWeight', 'bold', 'FontSize', 16, 'Color', [0.04 0.04 0.04]);
        legend(ax, handles, cellstr(labels), 'Location', 'eastoutside', ...
               'Interpreter', 'none', 'FontSize', 13);

        name = sprintf('%s_%s_AP_Comparison', testName, material);
        pngFile = string(fullfile(pngFolder, name + ".png"));
        pdfFile = string(fullfile(pdfFolder, name + ".pdf"));
        pngFile = exportFigure(fig, pngFile);
        pdfFile = exportFigure(fig, pdfFile);
        if ~opts.ShowFigures
            close(fig);
        end
        figureFiles(end+1:end+2, 1) = [pngFile; pdfFile];
        fprintf('Saved %s (+ PDF)\n', pngFile);
    end
end
end

%% ========================================================================
%% Mean curve that ends at the mean fracture point
%% ========================================================================

function [x, m, s] = averageToPeak(g, curves, spec, numPoints)
% Resample each specimen at fractions u of its own position of the peak,
% then average across specimens at each u (see the header)
u = linspace(0, 1, numPoints)';
Y = NaN(numPoints, height(g));
for i = 1:height(g)
    r  = g.CurveRows{i};
    xi = curves.(spec.XVar)(r);
    yi = curves.(spec.YVar)(r);
    [~, peak] = max(yi);
    xi = xi(1:peak);
    yi = yi(1:peak);
    [xi, first] = unique(xi);                     % interp1 needs distinct x
    yi = yi(first);
    if numel(xi) < 2 || ~(xi(end) > 0)
        continue;
    end
    Y(:, i) = interp1(xi, yi, u * xi(end), 'linear', 'extrap');
end
x = u * mean(g.(spec.PeakX), 'omitnan');
m = mean(Y, 2, 'omitnan');
s = std(Y, 0, 2, 'omitnan');
s(~isfinite(s)) = 0;
end

%% ========================================================================
%% Helpers (same look as plotAveragedCurves)
%% ========================================================================

function spec = testSpec(testName)
switch lower(string(testName))
    case {"tension", "compression"}
        spec.XVar   = "Strain";
        spec.YVar   = "Stress_MPa";
        spec.XLabel = 'Strain (mm/mm)';
        spec.YLabel = 'Stress (MPa)';
        spec.PeakX  = "StrainAtPeak";
        spec.PeakY  = "PeakStress_MPa";
        if strcmpi(testName, "Tension")
            spec.PeakName = "fracture";
        else
            spec.PeakName = "peak";
        end
    case "fracture"
        spec.XVar   = "Displacement_mm";
        spec.YVar   = "Force_N";
        spec.XLabel = 'Displacement (mm)';
        spec.YLabel = 'Force (N)';
        spec.PeakX  = "DisplacementAtPeak_mm";
        spec.PeakY  = "PeakForce_N";
        spec.PeakName = "fracture";
    otherwise
        error('plot:test', 'Unsupported test "%s".', testName);
end
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
ax.GridColor  = [0.80 0.80 0.78];
ax.GridAlpha  = 0.6;
ax.XColor     = [0.32 0.32 0.31];
ax.YColor     = [0.32 0.32 0.31];
end

function R = materialRamp(material, nShades)
% CNT = blue family, NEAT = orange family, light = low AP -> dark = high AP
switch upper(string(material))
    case "CNT"
        ramp = ["#86b6ef", "#3987e5", "#1c5cab", "#0d366b"];
    case "NEAT"
        ramp = ["#fe9068", "#e15102", "#9e3601", "#611e01"];
    otherwise
        ramp = ["#c3c2b7", "#898781", "#52514e", "#0b0b0b"];
end
R = zeros(numel(ramp), 3);
for i = 1:numel(ramp)
    h = char(ramp(i));
    R(i, :) = sscanf(h(2:end), '%2x')' / 255;
end
if nShades ~= size(R, 1) && nShades >= 2
    R = interp1(linspace(0, 1, size(R, 1)), R, linspace(0, 1, nShades));
end
end

function s = sdOrZero(v)
v = v(isfinite(v));
if numel(v) >= 2
    s = std(v);
else
    s = 0;
end
end
