clear; clc; close all;

%% ==========================================================
%% Compressive modulus for every compression cylinder
%%
%% Uses the same classification logic as data_process_and_plot2.m
%% (highest peak force in a group = CNT_1, the rest = NEAT_1, NEAT_2...)
%% and the same AP / epoxy composition per year as
%% Fracture_GIc_KIc_Analysis.m.
%%
%% Method (toe-compensated, ASTM D695 style)
%%   1. strain = (crosshead displacement - first reading) / length
%%      stress = force / (pi*D^2/4)
%%   2. Keep the curve up to peak stress.
%%   3. Slide a window along the curve. Each window starts at a data
%%      point and extends until stress has risen by fitStressSpan of
%%      the peak. Only windows between fitLower and fitUpper of peak
%%      stress with at least minFitPoints points are considered.
%%   4. The compressive modulus is the steepest window whose
%%      R^2 >= minRSquared. Taking the steepest linear window skips
%%      the platen seating (toe) region automatically.
%%
%% Strain comes from crosshead displacement, so the result includes
%% load-frame compliance (apparent modulus).
%%
%% Cross-check: Bluehill writes its own "Modulus (Automatic Young's)"
%% to the *_N_1.csv export using placeholder geometry (20 mm diameter,
%% 50 mm gauge length). That value is rescaled to the real geometry
%%   E = E_bluehill * (D_bluehill/D)^2 * (L/L_bluehill)
%% and saved next to the fitted value.
%%
%% compression_modulus_analysis.py is a Python port of this script.
%%
%% Run this script from inside Junior_Lab_Repo
%% ==========================================================

repoFolder = pwd;
organizedFolder = fullfile(repoFolder, 'OrganizedData');
rawDataFolder = fullfile(repoFolder, 'juniorlabdata');

days = {'monday','tuesday','wednesday','thursday','friday'};
materials = ["CNT","NEAT"];
years = ["2023","2024","2025","2026"];

%% AP / epoxy weight percent for each test year
apPercentByYear = containers.Map( ...
    {'2023','2024','2025','2026'}, ...
    {   60,     40,     50,     70});

%% Fit settings
fitSettings.stressSpan = 0.20;   % each window covers 20% of peak stress
fitSettings.lower = 0.02;        % ignore the first 2% of peak stress
fitSettings.upper = 0.90;        % ignore the last 10% before peak
fitSettings.minPoints = 5;
fitSettings.minRSquared = 0.995;

%% Flag specimens whose fit differs from Bluehill by more than this
bluehillTolerance = 0.25;

outputFolder = fullfile(repoFolder, 'Compression_Modulus_Export');

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% Classify every compression specimen
classified = classifyAllCompressionSpecimens(organizedFolder, years, days);

if isempty(classified)
    error('No compression specimens were classified. Check the OrganizedData folder.');
end

bluehillIndex = indexBluehillResults(rawDataFolder, organizedFolder);

%% ==========================================================
%% Fit every specimen
%% ==========================================================

individualResults = table();

for y = 1:length(years)

    yearNumber = years(y);
    apPercent = apPercentByYear(char(yearNumber));

    dimensionSheets = loadCompressionDimensions(organizedFolder, yearNumber);

    selected = classified(classified.Year == yearNumber,:);

    fprintf('\nCompression modulus: %g%% AP (%s), %d specimens\n', ...
        apPercent, yearNumber, height(selected));

    for i = 1:height(selected)

        [diameter_mm, length_mm, dimensionSource] = ...
            getCompressionDimensions( ...
                dimensionSheets, ...
                selected.Batch(i), ...
                selected.SectionNumber(i), ...
                selected.Material(i), ...
                selected.SampleNumber(i));

        data = readCurve(selected.FilePath(i));

        area_mm2 = pi * diameter_mm^2 / 4;
        strain = (data(:,2) - data(1,2)) ./ length_mm;
        stress = data(:,3) ./ area_mm2;

        fit = fitCompressiveModulus(strain, stress, fitSettings);

        %% Bluehill cross-check
        bluehillModulus = NaN;
        bluehillName = extractBefore(selected.OriginalFileName(i), ...
            strlength(selected.OriginalFileName(i)) - 4) + "1.csv";

        if isKey(bluehillIndex, char(bluehillName))
            [eBH, dBH, lBH, okBH] = ...
                readBluehillResults(bluehillIndex(char(bluehillName)));
            if okBH
                bluehillModulus = eBH * (dBH/diameter_mm)^2 * (length_mm/lBH);
            end
        end

        ratio = fit.Modulus_MPa / bluehillModulus;
        differsFromBluehill = isfinite(ratio) && abs(ratio - 1) > bluehillTolerance;

        fitAccepted = isfinite(fit.Modulus_MPa) && fit.Modulus_MPa > 0 && ...
            fit.RSquared >= fitSettings.minRSquared;

        newRow = table( ...
            apPercent, 100 - apPercent, yearNumber, ...
            selected.Material(i), selected.Batch(i), selected.Day(i), ...
            selected.Group(i), selected.SampleName(i), ...
            selected.SectionNumber(i), selected.SampleNumber(i), ...
            diameter_mm, length_mm, dimensionSource, ...
            max(data(:,3)), max(stress), ...
            fit.Modulus_MPa, fit.Intercept_MPa, fit.RSquared, ...
            fit.NumberFitPoints, fit.FitStartStrain, fit.FitEndStrain, ...
            bluehillModulus, ratio, differsFromBluehill, fitAccepted, ...
            selected.OriginalFileName(i), selected.FilePath(i), ...
            'VariableNames',{ ...
                'AP_Percent','Epoxy_Percent','Year', ...
                'Material','Batch','Day', ...
                'Group','SampleName', ...
                'SectionNumber','SampleNumber', ...
                'Diameter_mm','Length_mm','DimensionSource', ...
                'PeakForce_N','PeakStress_MPa', ...
                'Modulus_MPa','Intercept_MPa','RSquared', ...
                'NumberFitPoints','FitStartStrain','FitEndStrain', ...
                'Bluehill_Modulus_Rescaled_MPa','Ratio_Fit_to_Bluehill', ...
                'DiffersFromBluehill','FitAccepted', ...
                'OriginalFileName','FilePath'});

        individualResults = [individualResults; newRow];

        fprintf('  %-18s %-7s E = %7.0f MPa | R^2 = %.4f | Bluehill = %7.0f\n', ...
            selected.Group(i), selected.SampleName(i), ...
            fit.Modulus_MPa, fit.RSquared, bluehillModulus);
    end
end

individualResults = sortrows(individualResults, ...
    {'AP_Percent','Material','Batch','Day','Group','SampleNumber'});

acceptedResults = individualResults(individualResults.FitAccepted,:);

individualFile = fullfile(outputFolder, 'Compression_Modulus_All_Specimens.xlsx');

writetable(individualResults, individualFile, 'Sheet','All Specimens');
writetable(acceptedResults, individualFile, 'Sheet','Accepted Fits');

%% ==========================================================
%% Mean and sample standard deviation per composition
%% ==========================================================

summary = table();

for y = 1:length(years)
    for m = 1:length(materials)

        rows = acceptedResults.Year == years(y) & ...
            acceptedResults.Material == materials(m);

        values = acceptedResults.Modulus_MPa(rows);

        if isempty(values)
            continue;
        end

        n = numel(values);

        if n >= 2
            sd = std(values);
        else
            sd = NaN;
        end

        apPercent = apPercentByYear(char(years(y)));

        summary = [summary; table( ...
            apPercent, 100 - apPercent, years(y), materials(m), ...
            mean(values), sd, sd/sqrt(n), median(values), ...
            min(values), max(values), n, ...
            'VariableNames',{ ...
                'AP_Percent','Epoxy_Percent','Year','Material', ...
                'MeanModulus_MPa','StdModulus_MPa','StdErrModulus_MPa', ...
                'MedianModulus_MPa','MinModulus_MPa','MaxModulus_MPa', ...
                'NumberOfSpecimens'})];
    end
end

summary = sortrows(summary, {'AP_Percent','Material'});

summaryFile = fullfile(outputFolder, 'Compression_Modulus_Summary.xlsx');
writetable(summary, summaryFile, 'Sheet','Composition Summary');

disp(summary);

plotModulusVsAP(acceptedResults, summary, materials, ...
    fullfile(outputFolder, 'Compression_Modulus_vs_AP_Content'));

fprintf('\nAccepted %d of %d specimens. %d differ from Bluehill by more than %.0f%%.\n', ...
    height(acceptedResults), height(individualResults), ...
    sum(individualResults.DiffersFromBluehill), 100*bluehillTolerance);

fprintf('\nFinished. Results saved to:\n%s\n', outputFolder);

%% ========================================================================
%% Classify all compression files
%% ========================================================================

function classified = classifyAllCompressionSpecimens(organizedFolder, years, days)

    classified = table();

    for y = 1:length(years)

        yearFolder = fullfile(organizedFolder, years(y) + "_organized");
        batchFolders = dir(fullfile(yearFolder, 'batch*'));
        batchFolders = batchFolders([batchFolders.isdir]);

        for b = 1:length(batchFolders)

            batchName = string(batchFolders(b).name);

            for d = 1:length(days)

                dayFolder = fullfile(yearFolder, batchName, days{d});

                if ~isfolder(dayFolder)
                    continue;
                end

                groupFolders = dir(dayFolder);
                groupFolders = groupFolders([groupFolders.isdir] & ...
                    ~ismember({groupFolders.name},{'.','..'}));

                for g = 1:length(groupFolders)

                    groupName = string(groupFolders(g).name);
                    csvFiles = dir(fullfile(dayFolder, groupName, '**', '*.csv'));

                    filePaths = strings(0,1);
                    fileNames = strings(0,1);
                    peakForces = zeros(0,1);

                    for k = 1:length(csvFiles)

                        name = string(csvFiles(k).name);
                        path = string(fullfile(csvFiles(k).folder, name));

                        %% Keep curve exports, skip Bluehill results tables
                        if ~contains(upper(name), "COMPRESSION") || ~isCurveFile(path)
                            continue;
                        end

                        data = readCurve(path);

                        filePaths(end+1,1) = path;
                        fileNames(end+1,1) = name;
                        peakForces(end+1,1) = max([data(:,3); -Inf]);
                    end

                    if isempty(filePaths)
                        continue;
                    end

                    [~, order] = sort(peakForces, 'descend');

                    for r = 1:length(order)

                        if r == 1
                            material = "CNT";
                            sampleNumber = 1;
                        else
                            material = "NEAT";
                            sampleNumber = r - 1;
                        end

                        k = order(r);

                        classified = [classified; table( ...
                            years(y), batchName, string(days{d}), groupName, ...
                            material, material + "_" + sampleNumber, sampleNumber, ...
                            str2double(regexprep(groupName,'\D','')), ...
                            fileNames(k), filePaths(k), peakForces(k), ...
                            'VariableNames',{ ...
                                'Year','Batch','Day','Group', ...
                                'Material','SampleName','SampleNumber', ...
                                'SectionNumber', ...
                                'OriginalFileName','FilePath','MaxForce_N'})];
                    end
                end
            end
        end
    end
end

%% ========================================================================
%% True when a CSV holds Time / Displacement / Force data
%% ========================================================================

function tf = isCurveFile(filePath)

    fid = fopen(filePath, 'r');
    head = fread(fid, 300, '*char')';
    fclose(fid);

    tf = ~isempty(regexp(head, '(^|\n)\s*Time', 'once'));
end

%% ========================================================================
%% Read [time, displacement, force] from a curve export
%% ========================================================================

function data = readCurve(filePath)

    text = fileread(filePath);
    lines = splitlines(string(text));

    headerLine = find(startsWith(strtrim(lines), "Time"), 1, 'first');

    data = zeros(0,3);

    if isempty(headerLine)
        return;
    end

    %% Skip the header and units rows
    lines = erase(lines(headerLine+2:end), '"');
    values = NaN(numel(lines), 3);

    for k = 1:numel(lines)
        parts = split(lines(k), ',');
        if numel(parts) >= 3
            values(k,:) = str2double(parts(1:3))';
        end
    end

    data = values(all(isfinite(values), 2), :);
end

%% ========================================================================
%% Map Bluehill results-table file name -> path
%% ========================================================================

function index = indexBluehillResults(rawDataFolder, organizedFolder)

    index = containers.Map();
    candidates = [ ...
        dir(fullfile(rawDataFolder, '**', '*.csv')); ...
        dir(fullfile(organizedFolder, '*_organized', '**', '*.csv'))];

    for k = 1:length(candidates)
        name = candidates(k).name;
        if contains(upper(name), 'COMPRESSION') && endsWith(name, '_1.csv') && ...
                ~isKey(index, name)
            index(name) = fullfile(candidates(k).folder, name);
        end
    end
end

%% ========================================================================
%% Read Bluehill's modulus and placeholder geometry from a results table
%% ========================================================================

function [modulus, diameter, gaugeLength, ok] = readBluehillResults(filePath)

    modulus = NaN;
    diameter = NaN;
    gaugeLength = NaN;
    ok = false;

    lines = splitlines(string(fileread(filePath)));
    headerLine = find(contains(lines, "Modulus (Automatic Young's)"), 1, 'first');

    if isempty(headerLine) || headerLine + 2 > numel(lines)
        return;
    end

    header = strtrim(split(lines(headerLine), ','));
    values = str2double(erase(split(lines(headerLine + 2), ','), '"'));

    modulusColumn = find(header == "Modulus (Automatic Young's)", 1);
    diameterColumn = find(header == "Diameter", 1);
    gaugeColumn = find(header == "Compressive strain (Displacement) gauge length", 1);

    if isempty(modulusColumn) || isempty(diameterColumn) || isempty(gaugeColumn) || ...
            max([modulusColumn, diameterColumn, gaugeColumn]) > numel(values)
        return;
    end

    modulus = values(modulusColumn);
    diameter = values(diameterColumn);
    gaugeLength = values(gaugeColumn);
    ok = all(isfinite([modulus, diameter, gaugeLength]));
end

%% ========================================================================
%% Read the compression rows of every sheet in a year's dimension file
%% ========================================================================

function sheets = loadCompressionDimensions(organizedFolder, yearNumber)

    sheets = struct();

    dimensionFile = fullfile(organizedFolder, yearNumber + "_organized", ...
        "SpecimenDimensions" + yearNumber + ".xlsx");

    if ~isfile(dimensionFile)
        warning('Dimension file not found: %s', dimensionFile);
        return;
    end

    sheetNames = sheetnames(dimensionFile);

    for s = 1:numel(sheetNames)

        dims = readtable(dimensionFile, 'Sheet', sheetNames(s));

        if ~ismember('Material', dims.Properties.VariableNames)
            dims.Properties.VariableNames{2} = 'Material';
        end

        dims.Material = upper(strtrim(string(dims.Material)));
        dims.Test = upper(strtrim(string(dims.Test)));

        %% Some sections are stored as text with a leading zero (e.g. '033016')
        numericColumns = {'Section','Sample','Diameter_mm','Length_mm'};
        for c = 1:numel(numericColumns)
            column = dims.(numericColumns{c});
            if ~isnumeric(column)
                dims.(numericColumns{c}) = str2double(string(column));
            end
        end

        sheets.(char(matlab.lang.makeValidName(sheetNames(s)))) = ...
            dims(dims.Test == "COMPRESSION",:);
    end
end

%% ========================================================================
%% Diameter and length for one compression specimen
%%
%% Uses the sheet matching the batch, then the same section/material with
%% any sample number, then the median of that year's measurements (the
%% median ignores typos such as a length typed into the diameter column)
%% ========================================================================

function [diameter_mm, length_mm, source] = getCompressionDimensions( ...
    sheets, batchName, sectionNumber, materialName, sampleNumber)

    diameter_mm = NaN;
    length_mm = NaN;
    source = "missing";

    sheetList = fieldnames(sheets);

    if isempty(sheetList)
        return;
    end

    batchField = char(matlab.lang.makeValidName(batchName));

    if isfield(sheets, batchField)
        dims = sheets.(batchField);
    else
        dims = sheets.(sheetList{1});
    end

    validRows = dims.Diameter_mm > 0 & dims.Length_mm > 0;

    sameSpecimen = validRows & ...
        dims.Section == sectionNumber & ...
        dims.Material == materialName;

    exactRow = find(sameSpecimen & dims.Sample == sampleNumber, 1, 'first');
    sectionRow = find(sameSpecimen, 1, 'first');

    if ~isempty(exactRow)
        diameter_mm = dims.Diameter_mm(exactRow);
        length_mm = dims.Length_mm(exactRow);
        source = "measured";
        return;
    end

    if ~isempty(sectionRow)
        diameter_mm = dims.Diameter_mm(sectionRow);
        length_mm = dims.Length_mm(sectionRow);
        source = "same section";
        return;
    end

    allDiameters = [];
    allLengths = [];

    for s = 1:numel(sheetList)
        t = sheets.(sheetList{s});
        keep = t.Diameter_mm > 0 & t.Length_mm > 0;
        allDiameters = [allDiameters; t.Diameter_mm(keep)];
        allLengths = [allLengths; t.Length_mm(keep)];
    end

    if isempty(allDiameters)
        return;
    end

    diameter_mm = median(allDiameters);
    length_mm = median(allLengths);
    source = "year median";

    warning('No dimensions for section %g %s sample %g; using year median.', ...
        sectionNumber, materialName, sampleNumber);
end

%% ========================================================================
%% Steepest linear window on the pre-peak stress-strain curve
%% ========================================================================

function fit = fitCompressiveModulus(strain, stress, settings)

    fit.Modulus_MPa = NaN;
    fit.Intercept_MPa = NaN;
    fit.RSquared = NaN;
    fit.NumberFitPoints = 0;
    fit.FitStartStrain = NaN;
    fit.FitEndStrain = NaN;

    if numel(stress) < settings.minPoints
        return;
    end

    [peakStress, peakIndex] = max(stress);
    strain = strain(1:peakIndex);
    stress = stress(1:peakIndex);

    if ~isfinite(peakStress) || peakStress <= 0
        return;
    end

    for i = 1:numel(stress)

        if stress(i) < settings.lower * peakStress
            continue;
        end

        %% Extend the window until stress has risen by the span
        j = find(stress(i:end) - stress(i) >= ...
            settings.stressSpan * peakStress, 1, 'first');

        if isempty(j)
            break;
        end

        j = i + j - 1;

        x = strain(i:j);
        yValues = stress(i:j);

        if numel(x) < settings.minPoints || ...
                max(yValues) > settings.upper * peakStress
            continue;
        end

        coefficients = polyfit(x, yValues, 1);
        residual = yValues - polyval(coefficients, x);
        totalSumSquares = sum((yValues - mean(yValues)).^2);

        if totalSumSquares <= 0
            continue;
        end

        rSquared = 1 - sum(residual.^2) / totalSumSquares;

        if rSquared < settings.minRSquared
            continue;
        end

        if ~isfinite(fit.Modulus_MPa) || coefficients(1) > fit.Modulus_MPa
            fit.Modulus_MPa = coefficients(1);
            fit.Intercept_MPa = coefficients(2);
            fit.RSquared = rSquared;
            fit.NumberFitPoints = numel(x);
            fit.FitStartStrain = x(1);
            fit.FitEndStrain = x(end);
        end
    end
end

%% ========================================================================
%% Mean +/- 1 SD vs. AP content with individual specimens
%% ========================================================================

function plotModulusVsAP(acceptedResults, summary, materials, savePath)

    colors = containers.Map({'CNT','NEAT'}, {[0.16 0.44 0.86], [0.85 0.51 0.17]});
    offsets = containers.Map({'CNT','NEAT'}, {-0.8, 0.8});

    fig = figure('Visible','on', 'Units','normalized', ...
        'Position',[0.18 0.12 0.6 0.65]);
    ax = axes(fig);
    hold(ax,'on'); grid(ax,'on'); box(ax,'on');

    for m = 1:length(materials)

        key = char(materials(m));
        s = summary(summary.Material == materials(m),:);
        pts = acceptedResults(acceptedResults.Material == materials(m),:);

        scatter(ax, pts.AP_Percent + offsets(key) + 0.8*(rand(height(pts),1) - 0.5), ...
            pts.Modulus_MPa, 16, colors(key), 'filled', ...
            'MarkerFaceAlpha',0.35, 'HandleVisibility','off');

        errorbar(ax, s.AP_Percent + offsets(key), s.MeanModulus_MPa, ...
            s.StdModulus_MPa, '-o', 'Color',colors(key), ...
            'MarkerFaceColor',colors(key), 'LineWidth',2, 'CapSize',8, ...
            'DisplayName', key + " mean \pm 1 SD");
    end

    apValues = unique(summary.AP_Percent);
    xticks(ax, apValues);
    xticklabels(ax, compose('%g%% AP', apValues));
    xlabel(ax, 'AP content (wt%)');
    ylabel(ax, 'Compressive modulus (MPa)');
    title(ax, 'Compressive modulus vs. AP content');
    ylim(ax, [0, Inf]);
    legend(ax, 'Location','best');

    exportgraphics(fig, savePath + ".png", 'Resolution',200);
    exportgraphics(fig, savePath + ".pdf", 'ContentType','vector');
end
