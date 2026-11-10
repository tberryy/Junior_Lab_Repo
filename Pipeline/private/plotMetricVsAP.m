function outFile = plotMetricVsAP(points, valueVar, summary, meanVar, sdVar, fo)
%PLOTMETRICVSAP One material property against AP loading.
%   Dots = accepted specimens (spread slightly so they don't overlap),
%   line with bars = mean +/- 1 SD; CNT and NEAT side by side at each AP
%   loading; x ticks show the AP % with the sample year in brackets.
%   Shared by plotCompressionModulus and plotFractureToughness.
%
%   points   accepted specimens: APRatio_pct, Material, FilePath, <valueVar>
%   summary  one row per AP loading and material:
%            APRatio_pct, Year, Material, <meanVar>, <sdVar>
%   fo       struct: Materials, YLabel, Title, ValueLabel, OutFile, ShowFigures

outDir = fileparts(fo.OutFile);
if ~isfolder(outDir)
    mkdir(outDir);
end
if fo.ShowFigures
    vis = 'on';
else
    vis = 'off';
end

fig = figure('Visible', vis, 'Color', 'w', 'Units', 'pixels', 'Position', [100 100 1000 650]);
ax = axes(fig);
hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

% Same colours as the stress-strain figures: CNT blue (#2a78d6), NEAT orange (#eb6834)
matColors = containers.Map({'CNT', 'NEAT'}, {[42 120 214] / 255, [235 104 52] / 255});
nMat = numel(fo.Materials);
offsets = linspace(-1.2, 1.2, nMat);    % x shift in AP-% units so materials sit side by side
if nMat == 1
    offsets = 0;
end

handles = gobjects(0);
labels  = strings(0);

for m = 1:nMat
    mat = fo.Materials(m);
    if isKey(matColors, char(mat))
        color = matColors(char(mat));
    else
        color = [0.32 0.32 0.31];
    end

    % accepted specimens, spread slightly so they don't overlap
    pts = points(points.Material == mat & isfinite(points.APRatio_pct) & ...
                 isfinite(points.(valueVar)), :);
    if height(pts) > 0
        jitter = zeros(height(pts), 1);
        for a = unique(pts.APRatio_pct)'
            k = find(pts.APRatio_pct == a);
            if numel(k) > 1
                jitter(k) = linspace(-0.6, 0.6, numel(k));
            end
        end
        hs = scatter(ax, pts.APRatio_pct + offsets(m) + jitter, pts.(valueVar), 36, ...
                     color, 'filled', 'MarkerFaceAlpha', 0.35);
        hs.DataTipTemplate.Interpreter = 'none';
        hs.DataTipTemplate.DataTipRows(1).Label = "AP %";
        hs.DataTipTemplate.DataTipRows(2).Label = fo.ValueLabel;
        hs.DataTipTemplate.DataTipRows(end+1) = dataTipTextRow("File", cellstr(pts.FilePath));
    end

    % mean +/- 1 SD
    s = summary(summary.Material == mat & isfinite(summary.(meanVar)) & ...
                isfinite(summary.APRatio_pct), :);
    if height(s) > 0
        s = sortrows(s, 'APRatio_pct');
        sd = s.(sdVar);
        sd(~isfinite(sd)) = 0;              % single specimen: no bar
        he = errorbar(ax, s.APRatio_pct + offsets(m), s.(meanVar), sd, 'o-', ...
                      'Color', color, 'LineWidth', 2.2, 'MarkerSize', 8, ...
                      'MarkerFaceColor', color, 'CapSize', 12);
        handles(end+1) = he;                                         %#ok<AGROW>
        labels(end+1)  = mat + " mean " + char(177) + " 1 SD";      %#ok<AGROW>
    end
end

% x axis: AP %, with the year underneath for traceability
map = apRatio();
map = map(ismember(map(:, 1), summary.Year), :);
if ~isempty(map)
    xticks(ax, map(:, 2));
    xticklabels(ax, compose("%g%% (%d)", map(:, 2), map(:, 1)));
    xlim(ax, [min(map(:, 2)) - 5, max(map(:, 2)) + 5]);
end
ylim(ax, [0 Inf]);

xlabel(ax, 'AP loading (%)  (sample year)', 'FontWeight', 'bold', 'FontSize', 16);
ylabel(ax, fo.YLabel, 'FontWeight', 'bold', 'FontSize', 16);
title(ax, fo.Title, 'FontSize', 18);
ax.FontSize = 13;
if ~isempty(handles)
    legend(ax, handles, cellstr(labels), 'Location', 'best', 'FontSize', 12);
end

outFile = string(fo.OutFile);
exportFigure(fig, outFile);
if ~fo.ShowFigures
    close(fig);
end
end
