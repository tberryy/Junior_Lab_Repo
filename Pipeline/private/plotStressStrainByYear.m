function figureFiles = plotStressStrainByYear(testName, processedFile, opts)
%PLOTSTRESSSTRAINBYYEAR Shared engine for plotTension and plotCompression.
%   One figure per AP loading (one year's samples) per material, every
%   usable specimen of that test, ordered by AP % (see apRatio.m).
%   Colour = lab day, line style = batch. Hover a curve (data tip) to see
%   which specimen it is.
%
%   Reads only the processed workbook written by prepareData.

[specimens, curves] = loadSpecimens(processedFile, testName, opts.IncludeDuplicates);

if ~isempty(opts.Years)
    specimens = specimens(ismember(specimens.Year, opts.Years), :);
end
if ~isempty(opts.APRatios)
    specimens = specimens(ismember(specimens.APRatio_pct, opts.APRatios), :);
end

if height(specimens) == 0
    warning('plot:noData', 'No usable %s specimens for the requested years / AP ratios.', testName);
    figureFiles = strings(0, 1);
    return;
end

if ~isfolder(opts.OutputFolder)
    mkdir(opts.OutputFolder);
end

% One figure per year, ordered by AP loading (unknown AP last)
groups = unique(specimens(:, {'Year', 'APRatio_pct'}), 'stable');
groups = sortrows(groups, {'APRatio_pct', 'Year'});   % NaN sorts last

dayOrder  = ["monday", "tuesday", "wednesday", "thursday", "friday"];
dayColors = [0.000 0.447 0.741;     % Monday     blue
             0.850 0.325 0.098;     % Tuesday    orange
             0.466 0.674 0.188;     % Wednesday  green
             0.494 0.184 0.556;     % Thursday   purple
             0.635 0.078 0.184];    % Friday     dark red
batchStyles = ["-", "--", ":", "-."];

figureFiles = strings(0, 1);

for gi = 1:height(groups)
    year = groups.Year(gi);
    ap   = groups.APRatio_pct(gi);
    if isnan(ap)
        apText = "AP ?";          apFile = "APunknown";
    else
        apText = sprintf('%g%% AP', ap); apFile = sprintf('AP%g', ap);
    end

    for material = opts.Materials

        sel = specimens(specimens.Year == year & specimens.Material == material, :);
        if height(sel) == 0
            fprintf('No %s %s specimens for %s (%d), skipping.\n', material, testName, apText, year);
            continue;
        end

        if opts.ShowFigures, vis = 'on'; else, vis = 'off'; end
        fig = figure('Visible', vis, ...
                     'Color', 'w', 'Units', 'pixels', 'Position', [100 100 1100 700]);
        ax = axes(fig);
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

        batches = unique(sel.Batch)';
        nPlotted = 0;

        for i = 1:height(sel)

            r = sel.CurveRows{i};
            if isempty(r)
                continue;
            end
            x = curves.Strain(r);
            y = curves.Stress_MPa(r);

            dayIdx = find(dayOrder == lower(sel.Day(i)), 1);
            if isempty(dayIdx), color = [0.4 0.4 0.4]; else, color = dayColors(dayIdx, :); end

            bIdx = find(batches == sel.Batch(i), 1);
            style = batchStyles(min(bIdx, numel(batchStyles)));

            h = plot(ax, x, y, 'Color', color, 'LineStyle', char(style), 'LineWidth', 1.4);

            % Data tip shows which specimen this is
            h.DataTipTemplate.DataTipRows(1).Label = "Strain";
            h.DataTipTemplate.DataTipRows(2).Label = "Stress (MPa)";
            h.DataTipTemplate.DataTipRows(end+1) = ...
                dataTipTextRow("Specimen", repmat(cellstr(sel.Label(i)), numel(x), 1));
            h.DataTipTemplate.DataTipRows(end+1) = ...
                dataTipTextRow("File", repmat(cellstr(sel.FilePath(i)), numel(x), 1));

            nPlotted = nPlotted + 1;
        end

        % Legend: one entry per day present, one per batch
        [legendHandles, legendLabels] = buildLegend(ax, sel, dayOrder, dayColors, ...
                                                    batches, batchStyles);
        legend(ax, legendHandles, cellstr(legendLabels), 'Location', 'eastoutside', ...
               'Interpreter', 'none', 'FontSize', 11);

        xlim(ax, 'tight');              % fit x to the plotted data
        if isempty(opts.YLimit)
            ylim(ax, [0 Inf]);
        else
            ylim(ax, opts.YLimit);
        end

        xlabel(ax, 'Strain (mm/mm)', 'FontWeight', 'bold', 'FontSize', 16);
        ylabel(ax, 'Stress (MPa)',   'FontWeight', 'bold', 'FontSize', 16);
        title(ax, sprintf('%s %s - %s  (%d samples, n = %d)', ...
              material, testName, apText, year, nPlotted), 'FontSize', 18);
        ax.FontSize = 13;

        outFile = fullfile(opts.OutputFolder, ...
            sprintf('%s_%s_%d_%s.png', testName, apFile, year, material));
        exportFigure(fig, outFile);
        fprintf('Saved %s  (%d curves)\n', outFile, nPlotted);
        figureFiles(end+1, 1) = string(outFile); %#ok<AGROW>

        if ~opts.ShowFigures
            close(fig);
        end
    end
end
end

function [handles, labels] = buildLegend(ax, sel, dayOrder, dayColors, batches, batchStyles)
% Invisible proxy lines so the legend explains colour and style once
handles = gobjects(0);
labels  = strings(0);

presentDays = dayOrder(ismember(dayOrder, lower(sel.Day)));
for d = presentDays
    idx = find(dayOrder == d, 1);
    handles(end+1) = plot(ax, NaN, NaN, '-', 'Color', dayColors(idx, :), 'LineWidth', 2.5); %#ok<AGROW>
    labels(end+1)  = upper(extractBefore(d, 2)) + extractAfter(d, 1);                      %#ok<AGROW>
end

if numel(batches) > 1
    for b = 1:numel(batches)
        handles(end+1) = plot(ax, NaN, NaN, 'Color', 'k', 'LineWidth', 1.5, ...   %#ok<AGROW>
                              'LineStyle', char(batchStyles(min(b, numel(batchStyles)))));
        labels(end+1)  = batches(b);                                                      %#ok<AGROW>
    end
end
end
