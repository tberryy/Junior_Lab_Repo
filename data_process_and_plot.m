clear; clc; close all;
set(0,'DefaultFigureVisible','on');

%% ==========================================================
%% Run this script from inside Junior_Lab_Repo
%% ==========================================================

repoFolder = pwd;
organizedFolder = fullfile(repoFolder, 'OrganizedData');

days = {'monday','tuesday','wednesday','thursday','friday'};
tests = {'Compression','Tension','Fracture'};
materials = {'CNT','NEAT'};

%% ==========================================================
%% Plot limits
%% ==========================================================

plotLimits.compression = 0.35;   % strain
plotLimits.tension     = 0.015;  % strain
plotLimits.fracture    = 3.5;    % displacement in mm

%% Classify all specimens
classifiedAll = classifyAllSpecimens(organizedFolder, days);

if isempty(classifiedAll)
    error('No specimens were classified. Check the OrganizedData folder.');
end
%% ==========================================================
%% Create six yearly-average comparison graphs
%% ==========================================================

averagePlotFolder = fullfile(organizedFolder, ...
    'Yearly_Average_Comparison_Plots');

if ~isfolder(averagePlotFolder)
    mkdir(averagePlotFolder);
end

plotYearlyAverageCurves( ...
    classifiedAll, ...
    organizedFolder, ...
    materials, ...
    tests, ...
    plotLimits, ...
    averagePlotFolder);
%% ==========================================================
%% Create separate mean ± standard deviation graphs
%% ==========================================================

standardDeviationPlotFolder = fullfile( ...
    organizedFolder, ...
    'Year_Test_Standard_Deviation_Plots');

if ~isfolder(standardDeviationPlotFolder)
    mkdir(standardDeviationPlotFolder);
end

plotYearTestStandardDeviationCurves( ...
    classifiedAll, ...
    organizedFolder, ...
    materials, ...
    tests, ...
    plotLimits, ...
    standardDeviationPlotFolder);

%{
%% Plot each organized year
years = unique(classifiedAll.Year);

for y = 1:length(years)

    yearName = string(years(y));
    yearFolder = fullfile(organizedFolder, yearName);

    yearNumber = erase(yearName, "_organized");

    dimensionFile = fullfile( ...
        yearFolder, ...
        "SpecimenDimensions" + yearNumber + ".xlsx");

    if ~isfile(dimensionFile)
        warning('Dimension file not found: %s', dimensionFile);
        continue;
    end

    dims = readtable(dimensionFile);

    %% Rename material column if needed
    if ~ismember('Material', dims.Properties.VariableNames)
        dims.Properties.VariableNames{2} = 'Material';
    end

    plotFolder = fullfile(yearFolder, 'Combined_Day_Plots');

    if ~isfolder(plotFolder)
        mkdir(plotFolder);
    end

    yearRows = strcmpi(string(classifiedAll.Year), yearName);
    yearClassified = classifiedAll(yearRows,:);

    for t = 1:length(tests)

        for m = 1:length(materials)

            plotCombinedDays( ...
                yearClassified, ...
                dims, ...
                tests{t}, ...
                materials{m}, ...
                days, ...
                plotFolder, ...
                plotLimits);

        end
    end
end

fprintf('\nFinished creating plots.\n');
%}

%% ========================================================================
%% Classify all organized folders
%% ========================================================================

function classifiedAll = classifyAllSpecimens(organizedFolder, days)

    organizedYears = dir(fullfile(organizedFolder, '*_organized'));
    organizedYears = organizedYears([organizedYears.isdir]);

    classifiedAll = table();

    for y = 1:length(organizedYears)

        yearName = organizedYears(y).name;
        yearFolder = fullfile(organizedFolder, yearName);

        fprintf('\nClassifying %s...\n', yearName);

        yearResults = table();

        %% Find all batch folders
batchFolders = dir(fullfile(yearFolder, 'batch*'));
batchFolders = batchFolders([batchFolders.isdir]);

for b = 1:length(batchFolders)

    batchName = batchFolders(b).name;
    batchFolder = fullfile(yearFolder, batchName);

    fprintf('  Processing %s...\n', batchName);

    %% Loop through Monday-Friday inside this batch
    for d = 1:length(days)

        dayName = days{d};
        dayFolder = fullfile(batchFolder, dayName);

        if ~isfolder(dayFolder)
            warning('Day folder not found: %s', dayFolder);
            continue;
        end

        groupFolders = dir(dayFolder);
        groupFolders = groupFolders([groupFolders.isdir]);
        groupFolders = groupFolders( ...
            ~ismember({groupFolders.name},{'.','..'}));

        for g = 1:length(groupFolders)

            groupName = groupFolders(g).name;
            groupPath = fullfile(dayFolder, groupName);

            %% Find all CSV files recursively
            allCSVFiles = dir(fullfile(groupPath, '**', '*.csv'));

            if isempty(allCSVFiles)
                continue;
            end

            fileNamesUpper = upper(string({allCSVFiles.name}));

            compressionFiles = allCSVFiles( ...
                contains(fileNamesUpper, "COMPRESSION"));

            tensionFiles = allCSVFiles( ...
                contains(fileNamesUpper, "TENSION") & ...
                ~contains(fileNamesUpper, "FRACTURE"));

            fractureFiles = allCSVFiles( ...
                contains(fileNamesUpper, "FRACTURE"));

            if ~isempty(compressionFiles)

                temp = classifyFileListByMaxForce( ...
                    compressionFiles, ...
                    1, ...
                    yearName, ...
                    batchName, ...
                    dayName, ...
                    groupName, ...
                    "Compression");

                yearResults = [yearResults; temp];
            end

            if ~isempty(tensionFiles)

                temp = classifyFileListByMaxForce( ...
                    tensionFiles, ...
                    1, ...
                    yearName, ...
                    batchName, ...
                    dayName, ...
                    groupName, ...
                    "Tension");

                yearResults = [yearResults; temp];
            end

            if ~isempty(fractureFiles)

                temp = classifyFileListByMaxForce( ...
                    fractureFiles, ...
                    4, ...
                    yearName, ...
                    batchName, ...
                    dayName, ...
                    groupName, ...
                    "Fracture");

                yearResults = [yearResults; temp];
            end

        end     
            end
        end

        classifiedAll = [classifiedAll; yearResults];

        %% Saving the classification file is optional
        outputFile = fullfile( ...
            yearFolder, ...
            'Classified_Max_Force_Results.xlsx');

        try
            writetable(yearResults, outputFile);

            fprintf('Saved classification file:\n%s\n', ...
                outputFile);

        catch ME
            warning( ...
                'Could not save classification file. Plotting will continue.\n%s', ...
                ME.message);
        end

    end
end

%% ========================================================================
%% Classify files in one test folder
%% ========================================================================

function results = classifyFileListByMaxForce( ...
    csvFiles, numCNT, yearName, batchName, ...
    dayName, groupName, testName)

    numFiles = length(csvFiles);

    if numFiles == 0
        results = table();
        return;
    end

    fileNames = strings(numFiles,1);
    filePaths = strings(numFiles,1);
    maxForce = NaN(numFiles,1);

    for i = 1:numFiles

        filePath = fullfile(csvFiles(i).folder, csvFiles(i).name);

        data = readCSVNumeric(filePath);

        if size(data,2) < 3
            warning('File has fewer than 3 columns: %s', filePath);
            continue;
        end

        force = data(:,3);
        force = force(~isnan(force));

        fileNames(i) = string(csvFiles(i).name);
        filePaths(i) = string(filePath);

        if ~isempty(force)
            maxForce(i) = max(force);
        end

    end

    results = table( ...
        fileNames, ...
        filePaths, ...
        maxForce, ...
        'VariableNames', ...
        {'OriginalFileName','FilePath','MaxForce'});

    results = sortrows(results,'MaxForce','descend');

    material = strings(numFiles,1);
    sampleName = strings(numFiles,1);

    cntCounter = 1;
    neatCounter = 1;

    numCNT = min(numCNT,numFiles);

    for i = 1:numFiles

        if i <= numCNT
            material(i) = "CNT";
            sampleName(i) = "CNT_" + string(cntCounter);
            cntCounter = cntCounter + 1;
        else
            material(i) = "NEAT";
            sampleName(i) = "NEAT_" + string(neatCounter);
            neatCounter = neatCounter + 1;
        end

    end

    results.Year = repmat(string(yearName),numFiles,1);
    results.Batch = repmat(string(batchName),numFiles,1);
    results.Day = repmat(string(dayName),numFiles,1);
    results.Group = repmat(string(groupName),numFiles,1);
    results.Test = repmat(string(testName),numFiles,1);
    results.Material = material;
    results.SampleName = sampleName;

    results = results(:,{ ...
        'Year', ...
        'Batch', ...
        'Day', ...
        'Group', ...
        'Test', ...
        'SampleName', ...
        'Material', ...
        'OriginalFileName', ...
        'FilePath', ...
        'MaxForce'});
end

%% ========================================================================
%% Plot all Monday-Friday curves for one test and one material
%% ========================================================================

function plotCombinedDays( ...
    classified, ...
    dims, ...
    testName, ...
    materialName, ...
    days, ...
    plotFolder, ...
    plotLimits)

    fig = figure( ...
        'Visible','on', ...
        'Units','normalized', ...
        'Position',[0.02 0.05 0.96 0.88]);

    ax = axes(fig);

    hold(ax,'on');
    grid(ax,'on');
    box(ax,'on');

    %% Explicit legend storage
    plotHandles = gobjects(0);
    legendLabels = strings(0);

    %% Count possible curves
    numCurves = sum( ...
        strcmpi(strtrim(string(classified.Test)), ...
                 strtrim(string(testName))) & ...
        strcmpi(strtrim(string(classified.Material)), ...
                 strtrim(string(materialName))));

    colors = turbo(max(numCurves,1));

    %% Day line styles
    lineStyles = {'-','--',':','-.','-'};

    colorIndex = 1;
    plotCount = 0;

    for d = 1:length(days)

        dayName = days{d};
        lineStyle = lineStyles{d};

        rows = ...
            strcmpi(strtrim(string(classified.Test)), ...
                    strtrim(string(testName))) & ...
            strcmpi(strtrim(string(classified.Material)), ...
                    strtrim(string(materialName))) & ...
            strcmpi(strtrim(string(classified.Day)), ...
                    strtrim(string(dayName)));

        selected = classified(rows,:);

        fprintf('%s %s %s: %d files found\n', ...
            testName, ...
            materialName, ...
            upper(dayName), ...
            height(selected));

        for i = 1:height(selected)

            csvPath = string(selected.FilePath(i));

            if ~isfile(csvPath)
                warning('CSV not found: %s', csvPath);
                continue;
            end

            groupName = string(selected.Group(i));

            sectionNumber = str2double( ...
                regexprep(groupName,'\D',''));

            sampleName = string(selected.SampleName(i));

            sampleNumber = str2double( ...
                regexprep(sampleName,'\D',''));

            data = readCSVNumeric(csvPath);

            if size(data,2) < 3
                warning( ...
                    'CSV does not have at least three columns: %s', ...
                    csvPath);
                continue;
            end

            displacement = data(:,2);
            force = data(:,3);

            valid = ...
                ~isnan(displacement) & ...
                ~isnan(force) & ...
                ~isinf(displacement) & ...
                ~isinf(force);

            displacement = displacement(valid);
            force = force(valid);

            if isempty(displacement) || isempty(force)
                warning('No valid numeric data in: %s', csvPath);
                continue;
            end

            %% ============================================================
            %% Fracture processing
            %% ============================================================

            if strcmpi(testName,'Fracture')

                peakForceOriginal = max(force);

                if isempty(peakForceOriginal) || ...
                        isnan(peakForceOriginal) || ...
                        peakForceOriginal <= 0

                    warning( ...
                        'Invalid fracture force data: %s', ...
                        csvPath);
                    continue;
                end

                %% Detect loading start at 5% of original peak
                startThreshold = 0.05 * peakForceOriginal;

                startIndex = find( ...
                    force >= startThreshold, ...
                    1, ...
                    'first');

                if isempty(startIndex)
                    warning( ...
                        'Could not detect fracture loading start: %s', ...
                        csvPath);
                    continue;
                end

                displacement = displacement(startIndex:end);
                force = force(startIndex:end);

%% Smooth force before calculating slope
smoothWindow = 25;

forceSmooth = movmean(force, smoothWindow);

%% Calculate loading slope in N/mm
dFdx = gradient(forceSmooth, displacement);

%% Adjustable settings
slopeThreshold = 50;    % N/mm
requiredPoints = 15;    % consecutive points above threshold

%% Require a sustained positive slope
isLoading = dFdx >= slopeThreshold;

sustainedLoading = movsum(isLoading, requiredPoints) >= requiredPoints;

startIndex = find(sustainedLoading, 1, 'first');

if isempty(startIndex)
    warning('Could not detect loading start. Using first data point.');
    startIndex = 1;
end

%% Start slightly before detected loading
paddingPoints = 3;
startIndex = max(1, startIndex - paddingPoints);

%% Remove initial flat section
displacement = displacement(startIndex:end);
force = force(startIndex:end);

%% Shift curve to origin
displacement = displacement - displacement(1);
force = force - force(1);

%% Remove small negative values caused by noise
displacement(displacement < 0) = 0;
force(force < 0) = 0;

                %% Find shifted peak
                [peakForceShifted, peakIndex] = max(force);

                %% Crop after force falls below 20% of peak
                endThreshold = 0.20 * peakForceShifted;

                dropRelative = find( ...
                    force(peakIndex:end) <= endThreshold, ...
                    1, ...
                    'first');

                if ~isempty(dropRelative)

                    endIndex = peakIndex + dropRelative - 1;

                    displacement = displacement(1:endIndex);
                    force = force(1:endIndex);

                end

                %% Reject only extreme peak-displacement outliers
                displacementAtPeak = displacement(peakIndex);

                maxAllowedPeakDisplacement = 4.0;

                if displacementAtPeak > maxAllowedPeakDisplacement

                    warning( ...
                        ['Skipping fracture outlier: %s\n' ...
                         'Peak displacement = %.3f mm'], ...
                        csvPath, ...
                        displacementAtPeak);

                    continue;
                end

                %% Apply fracture plotting limit
                keep = ...
                    displacement >= 0 & ...
                    displacement <= plotLimits.fracture;

                displacement = displacement(keep);
                force = force(keep);

                if isempty(displacement) || isempty(force)
                    warning( ...
                        'Fracture data empty after cropping: %s', ...
                        csvPath);
                    continue;
                end
                %% Keep data only up to the maximum force
                [~, peakIndex] = max(force);

                displacement = displacement(1:peakIndex);
                force = force(1:peakIndex);

                %% Plot fracture
              h = plot(displacement, force, ...
              'Color', colors(colorIndex,:), ...
              'LineStyle', lineStyle, ...
              'LineWidth', 1.8);

              h.UserData = csvPath;

            %% ============================================================
            %% Compression and tension processing
            %% ============================================================

            else

                displacement = ...
                    displacement - displacement(1);

                if strcmpi(testName,'Tension')

                    [displacement, force] = ...
                        cropAfterFailure(displacement,force);

                end

                [area, lengthValue, ok] = getDimensions( ...
                    dims, ...
                    sectionNumber, ...
                    testName, ...
                    materialName, ...
                    sampleNumber);

                if ~ok
                    warning( ...
                        'Skipping file because dimensions are invalid: %s', ...
                        csvPath);
                    continue;
                end

                stress = force ./ area;
                strain = displacement ./ lengthValue;

                validSS = ...
                    ~isnan(strain) & ...
                    ~isnan(stress) & ...
                    ~isinf(strain) & ...
                    ~isinf(stress);

                strain = strain(validSS);
                stress = stress(validSS);

                if isempty(strain) || isempty(stress)
                    warning( ...
                        'Stress-strain data empty: %s', ...
                        csvPath);
                    continue;
                end

                if strcmpi(testName,'Compression')

                    keep = ...
                        strain >= 0 & ...
                        strain <= plotLimits.compression;

                else

                    keep = ...
                        strain >= 0 & ...
                        strain <= plotLimits.tension;

                end

                strain = strain(keep);
                stress = stress(keep);

                if isempty(strain) || isempty(stress)
                    warning( ...
                        'Stress-strain data empty after cropping: %s', ...
                        csvPath);
                    continue;
                end
                %% Keep data only up to the maximum stress
                [~, peakIndex] = max(stress);

                strain = strain(1:peakIndex);
                stress = stress(1:peakIndex);

                %% Plot stress-strain
                h = plot(strain, stress, ...
                'Color', colors(colorIndex,:), ...
                'LineStyle', lineStyle, ...
                'LineWidth', 1.8);

                h.UserData = csvPath;

            end

            %% ============================================================
            %% Store every successful curve in the legend
            %% ============================================================

            batchName = string(selected.Batch(i));

            labelText = ...
                upper(batchName) + " " + ...
                upper(string(dayName)) + ...
                " Sec " + string(sectionNumber) + ...
                " " + sampleName;

            plotHandles(end+1) = h;
            legendLabels(end+1) = labelText;

            colorIndex = colorIndex + 1;
            plotCount = plotCount + 1;

            fprintf( ...
                'Plotted: %s | legend entry: %s\n', ...
                csvPath, ...
                labelText);

        end
    end

    %% Axis labels
    if strcmpi(testName,'Compression') || ...
            strcmpi(testName,'Tension')

        xlabel(ax,'Strain');
        ylabel(ax,'Stress (MPa)');

    else

        xlabel(ax,'Displacement (mm)');
        ylabel(ax,'Force (N)');

    end

    title( ...
        ax, ...
        string(testName) + ...
        " - " + string(materialName) + ...
        " - Monday through Friday");

    if plotCount > 0

        axis(ax,'tight');

        %% Use the explicit handles and labels
        lgd = legend( ...
            ax, ...
            plotHandles, ...
            cellstr(legendLabels), ...
            'Location','eastoutside');

        lgd.NumColumns = 3;
        lgd.FontSize = 6;
        lgd.Interpreter = 'none';
        dcm = datacursormode(gcf);
        set(dcm,'Enable','on','UpdateFcn',@showCSV);
        fprintf( ...
            '%s %s legend contains %d entries.\n', ...
            testName, ...
            materialName, ...
            numel(legendLabels));

        %% Verify Friday legend count
        fridayCount = sum(startsWith(legendLabels,"FRIDAY"));

        fprintf( ...
            '%s %s Friday legend entries: %d\n', ...
            testName, ...
            materialName, ...
            fridayCount);

    else

        warning( ...
            'No data plotted for %s %s', ...
            testName, ...
            materialName);

    end

    drawnow;

    saveName = ...
        string(testName) + "_" + ...
        string(materialName) + ...
        "_All_Days.png";

    figPath = fullfile(plotFolder,saveName);

    exportgraphics( ...
        fig, ...
        figPath, ...
        'Resolution',300);

    fprintf('Saved plot: %s\n',figPath);

end

%% ========================================================================
%% Read CSV data as a numeric array
%% ========================================================================

function data = readCSVNumeric(filePath)
    fprintf('Reading: %s\n', filePath);

    opts = detectImportOptions(filePath);

    %% Skip header and units rows
    opts.DataLines = [3 Inf];

    T = readtable(filePath,opts);

    data = NaN(height(T),width(T));

    for c = 1:width(T)

        col = T{:,c};

        if isnumeric(col)
            data(:,c) = col;
        else
            data(:,c) = str2double(string(col));
        end

    end
end

%% ========================================================================
%% Look up specimen dimensions
%% ========================================================================

function [area,lengthValue,ok] = getDimensions( ...
    dims,sectionNumber,testName,materialName,sampleNumber)

    ok = true;

    %% Convert table columns safely
    sectionValues = str2double(string(dims.Section));
    sampleValues  = str2double(string(dims.Sample));

    materialValues = strtrim(string(dims.Material));
    testValues     = strtrim(string(dims.Test));

    %% Find matching row
    matchingRows = ...
        sectionValues == sectionNumber & ...
        strcmpi(materialValues,string(materialName)) & ...
        strcmpi(testValues,string(testName)) & ...
        sampleValues == sampleNumber;

    row = dims(matchingRows,:);

    if isempty(row)

        warning( ...
            'Missing dimensions: Section %g, %s, %s, Sample %g', ...
            sectionNumber, ...
            materialName, ...
            testName, ...
            sampleNumber);

        area = NaN;
        lengthValue = NaN;
        ok = false;
        return;
    end

    %% Compression specimen
    if strcmpi(testName,'Compression')

        diameter = str2double(string(row.Diameter_mm(1)));
        lengthValue = str2double(string(row.Length_mm(1)));

        area = pi * (diameter / 2)^2;

    %% Tension specimen
    elseif strcmpi(testName,'Tension')

        width = str2double(string(row.Width_mm(1)));
        thickness = str2double(string(row.Thickness_mm(1)));
        lengthValue = str2double(string(row.GaugeLength_mm(1)));

        area = width * thickness;

    else

        area = NaN;
        lengthValue = NaN;
        ok = false;
        return;

    end

    %% Validate dimensions
    if isnan(area) || ...
            isnan(lengthValue) || ...
            area <= 0 || ...
            lengthValue <= 0

        warning( ...
            'Invalid dimensions: Section %g, %s, %s, Sample %g', ...
            sectionNumber, ...
            materialName, ...
            testName, ...
            sampleNumber);

        ok = false;
    end
end

%% ========================================================================
%% Crop tension data after failure
%% ========================================================================

function [displacement, force] = cropAfterFailure( ...
    displacement, force)

    [peakForce, peakIndex] = max(force);

    if isempty(peakForce) || ...
            isnan(peakForce) || ...
            peakForce <= 0
        return;
    end

    %% Crop when force falls below 90% of the peak
    cutoffForce = 0.90 * peakForce;

    dropIndex = find( ...
        force(peakIndex:end) < cutoffForce, ...
        1, ...
        'first');

    if ~isempty(dropIndex)

        lastIndex = peakIndex + dropIndex - 1;

        displacement = displacement(1:lastIndex);
        force = force(1:lastIndex);

    end
end 
%% ========================================================================
%% Plot average curves for 2023, 2024, 2025, and 2026
%% ========================================================================

function plotYearlyAverageCurves( ...
    classifiedAll, organizedFolder, materials, tests, ...
    plotLimits, outputFolder)

    yearsToPlot = ["2023","2024","2025","2026"];

    % Number of interpolation points used for every average curve
    numberOfAveragePoints = 500;

    for t = 1:length(tests)

        testName = string(tests{t});

        for m = 1:length(materials)

            materialName = string(materials{m});

            fig = figure( ...
                'Visible','on', ...
                'Units','normalized', ...
                'Position',[0.10 0.10 0.75 0.75]);

            ax = axes(fig);

            hold(ax,'on');
            grid(ax,'on');
            box(ax,'on');

            plottedYears = strings(0);
            plotHandles = gobjects(0);

            for y = 1:length(yearsToPlot)

                yearNumber = yearsToPlot(y);
                yearFolderName = yearNumber + "_organized";

                %% Select this year, material, and test
                rows = ...
                    strcmpi(string(classifiedAll.Year), ...
                            yearFolderName) & ...
                    strcmpi(string(classifiedAll.Test), ...
                            testName) & ...
                    strcmpi(string(classifiedAll.Material), ...
                            materialName);

                selected = classifiedAll(rows,:);

                fprintf( ...
                    '\nAverage processing: %s %s %s — %d files\n', ...
                    yearNumber, ...
                    materialName, ...
                    testName, ...
                    height(selected));

                if isempty(selected)
                    warning( ...
                        'No files found for %s %s %s.', ...
                        yearNumber, materialName, testName);
                    continue;
                end

                %% Read the dimension file for this year
                dims = table();

                if ~strcmpi(testName,'Fracture')

                    dimensionFile = fullfile( ...
                        organizedFolder, ...
                        yearFolderName, ...
                        "SpecimenDimensions" + yearNumber + ".xlsx");

                    if ~isfile(dimensionFile)
                        warning( ...
                            'Dimension file not found: %s', ...
                            dimensionFile);
                        continue;
                    end

                    dims = readtable(dimensionFile);

                    if ~ismember( ...
                            'Material', ...
                            dims.Properties.VariableNames)

                        dims.Properties.VariableNames{2} = ...
                            'Material';
                    end
                end

                %% Store every successfully processed curve
                xCurves = cell(0);
                yCurves = cell(0);

                for i = 1:height(selected)

                    csvPath = string(selected.FilePath(i));

                    if ~isfile(csvPath)
                        warning('CSV not found: %s', csvPath);
                        continue;
                    end

                    groupName = string(selected.Group(i));

                    sectionNumber = str2double( ...
                        regexprep(groupName,'\D',''));

                    sampleName = string(selected.SampleName(i));

                    sampleNumber = str2double( ...
                        regexprep(sampleName,'\D',''));

                    [xCurve, yCurve, ok] = ...
                        processCurveForYearlyAverage( ...
                            csvPath, ...
                            dims, ...
                            sectionNumber, ...
                            sampleNumber, ...
                            testName, ...
                            materialName, ...
                            plotLimits);

                    if ~ok
                        continue;
                    end

                    xCurves{end+1,1} = xCurve;
                    yCurves{end+1,1} = yCurve;
                end

                if isempty(xCurves)
                    warning( ...
                        'No valid curves for %s %s %s.', ...
                        yearNumber, materialName, testName);
                    continue;
                end

                %% Find range shared by all curves
                curveStarts = cellfun(@(x) min(x), xCurves);
                curveEnds = cellfun(@(x) max(x), xCurves);

                commonStart = max(curveStarts);
                commonEnd = min(curveEnds);

                if commonEnd <= commonStart
                    warning( ...
                        ['The curves do not have a common x range for ' ...
                         '%s %s %s.'], ...
                        yearNumber, materialName, testName);
                    continue;
                end

                %% Common x-axis for interpolation
                commonX = linspace( ...
                    commonStart, ...
                    commonEnd, ...
                    numberOfAveragePoints)';

                interpolatedY = NaN( ...
                    numberOfAveragePoints, ...
                    length(xCurves));

                %% Interpolate every specimen onto commonX
                for c = 1:length(xCurves)

                    xCurrent = xCurves{c};
                    yCurrent = yCurves{c};

                    [xCurrent, uniqueIndices] = ...
                        unique(xCurrent,'stable');

                    yCurrent = yCurrent(uniqueIndices);

                    if length(xCurrent) < 2
                        continue;
                    end

                    interpolatedY(:,c) = interp1( ...
                        xCurrent, ...
                        yCurrent, ...
                        commonX, ...
                        'linear', ...
                        NaN);
                end

                %% Remove failed interpolation columns
                validColumns = ...
                    sum(isfinite(interpolatedY),1) >= 2;

                interpolatedY = ...
                    interpolatedY(:,validColumns);

                if isempty(interpolatedY)
                    warning( ...
                        'Interpolation failed for %s %s %s.', ...
                        yearNumber, materialName, testName);
                    continue;
                end

                %% Point-by-point average
                averageY = mean( ...
                    interpolatedY, ...
                    2, ...
                    'omitnan');

                %% Plot this year's average
                h = plot( ...
                    ax, ...
                    commonX, ...
                    averageY, ...
                    'LineWidth',2.5);

                plotHandles(end+1) = h;

                plottedYears(end+1) = ...
                    yearNumber + ...
                    " average (n = " + ...
                    string(size(interpolatedY,2)) + ")";

                fprintf( ...
                    'Plotted %s average using %d curves.\n', ...
                    yearNumber, ...
                    size(interpolatedY,2));
            end

            %% Labels
            if strcmpi(testName,'Fracture')

                xlabel(ax,'Displacement (mm)');
                ylabel(ax,'Force (N)');

            else

                xlabel(ax,'Strain');
                ylabel(ax,'Stress (MPa)');

            end

            title( ...
                ax, ...
                materialName + " " + testName + ...
                " — Yearly Average Curves");

            if ~isempty(plotHandles)

                legend( ...
                    ax, ...
                    plotHandles, ...
                    cellstr(plottedYears), ...
                    'Location','best', ...
                    'Interpreter','none');

                axis(ax,'tight');

            else

                warning( ...
                    'No yearly averages were plotted for %s %s.', ...
                    materialName, testName);
            end

            %% Save graph
            saveName = ...
                materialName + "_" + testName + ...
                "_Yearly_Averages.png";

            savePath = fullfile(outputFolder,saveName);

            exportgraphics( ...
                fig, ...
                savePath, ...
                'Resolution',300);

            fprintf('Saved average plot: %s\n',savePath);
        end
    end
end
%% ========================================================================
%% Plot separate mean ± standard deviation graph for every year,
%% material, and test
%% ========================================================================

function plotYearTestStandardDeviationCurves( ...
    classifiedAll, organizedFolder, materials, tests, ...
    plotLimits, outputFolder)

    yearsToPlot = ["2023","2024","2025","2026"];

    numberOfAveragePoints = 500;

    for y = 1:length(yearsToPlot)

        yearNumber = yearsToPlot(y);
        yearFolderName = yearNumber + "_organized";

        for t = 1:length(tests)

            testName = string(tests{t});

            for m = 1:length(materials)

                materialName = string(materials{m});

                fprintf( ...
                    '\nMean and standard deviation: %s %s %s\n', ...
                    yearNumber, materialName, testName);

                %% Select files for one year, material, and test
                rows = ...
                    strcmpi( ...
                        strtrim(string(classifiedAll.Year)), ...
                        yearFolderName) & ...
                    strcmpi( ...
                        strtrim(string(classifiedAll.Test)), ...
                        testName) & ...
                    strcmpi( ...
                        strtrim(string(classifiedAll.Material)), ...
                        materialName);

                selected = classifiedAll(rows,:);

                if isempty(selected)

                    warning( ...
                        'No files found for %s %s %s.', ...
                        yearNumber, materialName, testName);

                    continue;
                end

                %% Read dimension file for compression and tension
                dims = table();

                if ~strcmpi(testName,'Fracture')

                    dimensionFile = fullfile( ...
                        organizedFolder, ...
                        yearFolderName, ...
                        "SpecimenDimensions" + ...
                        yearNumber + ".xlsx");

                    if ~isfile(dimensionFile)

                        warning( ...
                            'Dimension file not found: %s', ...
                            dimensionFile);

                        continue;
                    end

                    dims = readtable(dimensionFile);

                    if ~ismember( ...
                            'Material', ...
                            dims.Properties.VariableNames)

                        dims.Properties.VariableNames{2} = ...
                            'Material';
                    end
                end

                %% Process and store individual specimen curves
                xCurves = {};
                yCurves = {};

                for i = 1:height(selected)

                    csvPath = string(selected.FilePath(i));

                    if ~isfile(csvPath)

                        warning( ...
                            'CSV not found: %s', ...
                            csvPath);

                        continue;
                    end

                    groupName = string(selected.Group(i));

                    sectionNumber = str2double( ...
                        regexprep(groupName,'\D',''));

                    sampleName = string(selected.SampleName(i));

                    sampleNumber = str2double( ...
                        regexprep(sampleName,'\D',''));

                    [xCurve, yCurve, ok] = ...
                        processCurveForYearlyAverage( ...
                            csvPath, ...
                            dims, ...
                            sectionNumber, ...
                            sampleNumber, ...
                            testName, ...
                            materialName, ...
                            plotLimits);

                    if ~ok || ...
                            length(xCurve) < 2 || ...
                            length(yCurve) < 2
                        continue;
                    end

                    xCurves{end+1,1} = xCurve(:);
                    yCurves{end+1,1} = yCurve(:);
                end

                numberOfCurves = length(xCurves);

                if numberOfCurves == 0

                    warning( ...
                        'No valid curves for %s %s %s.', ...
                        yearNumber, materialName, testName);

                    continue;
                end

                %% Determine interpolation domain
                curveStarts = cellfun( ...
                    @(x) min(x), xCurves);

                curveEnds = cellfun( ...
                    @(x) max(x), xCurves);

                if strcmpi(testName,'Compression')

                    % Keep the full compression response.
                    commonStart = 0;

                    commonEnd = min( ...
                        max(curveEnds), ...
                        plotLimits.compression);

                else

                    % Tension and fracture use a range shared by
                    % all valid specimens.
                    commonStart = max(curveStarts);
                    commonEnd = min(curveEnds);
                end

                if ~isfinite(commonStart) || ...
                        ~isfinite(commonEnd) || ...
                        commonEnd <= commonStart

                    warning( ...
                        ['Invalid interpolation range for ' ...
                         '%s %s %s.'], ...
                        yearNumber, materialName, testName);

                    continue;
                end

                commonX = linspace( ...
                    commonStart, ...
                    commonEnd, ...
                    numberOfAveragePoints)';

                interpolatedY = NaN( ...
                    numberOfAveragePoints, ...
                    numberOfCurves);

                %% Interpolate specimens onto the common x-axis
                for c = 1:numberOfCurves

                    xCurrent = xCurves{c};
                    yCurrent = yCurves{c};

                    validCurrent = ...
                        isfinite(xCurrent) & ...
                        isfinite(yCurrent);

                    xCurrent = xCurrent(validCurrent);
                    yCurrent = yCurrent(validCurrent);

                    [xCurrent, sortIndex] = sort(xCurrent);
                    yCurrent = yCurrent(sortIndex);

                    [xCurrent, uniqueIndex] = ...
                        unique(xCurrent,'stable');

                    yCurrent = yCurrent(uniqueIndex);

                    if length(xCurrent) < 2
                        continue;
                    end

                    interpolatedY(:,c) = interp1( ...
                        xCurrent, ...
                        yCurrent, ...
                        commonX, ...
                        'linear', ...
                        NaN);
                end

                %% Remove curves whose interpolation completely failed
                validColumns = ...
                    sum(isfinite(interpolatedY),1) >= 2;

                interpolatedY = ...
                    interpolatedY(:,validColumns);

                numberIncluded = size(interpolatedY,2);

                if numberIncluded == 0

                    warning( ...
                        ['Interpolation failed for every curve: ' ...
                         '%s %s %s.'], ...
                        yearNumber, materialName, testName);

                    continue;
                end

                %% Number of curves contributing at each x-location
                contributingCount = ...
                    sum(isfinite(interpolatedY),2);

                %% Point-by-point average and standard deviation
                averageY = mean( ...
                    interpolatedY, ...
                    2, ...
                    'omitnan');

                standardDeviationY = std( ...
                    interpolatedY, ...
                    0, ...
                    2, ...
                    'omitnan');

                %% Standard deviation is undefined with only one curve
                standardDeviationY( ...
                    contributingCount < 2) = NaN;

                %% Remove points with no valid average
                validAverage = ...
                    isfinite(commonX) & ...
                    isfinite(averageY);

                commonX = commonX(validAverage);
                averageY = averageY(validAverage);
                standardDeviationY = ...
                    standardDeviationY(validAverage);

                contributingCount = ...
                    contributingCount(validAverage);

                if isempty(commonX)
                    continue;
                end

                %% Cut final fracture average at its maximum
                if strcmpi(testName,'Fracture')

                    [~, averagePeakIndex] = max(averageY);

                    commonX = commonX(1:averagePeakIndex);
                    averageY = averageY(1:averagePeakIndex);

                    standardDeviationY = ...
                        standardDeviationY(1:averagePeakIndex);

                    contributingCount = ...
                        contributingCount(1:averagePeakIndex);
                end

                %% Upper and lower standard-deviation boundaries
                lowerBound = ...
                    averageY - standardDeviationY;

                upperBound = ...
                    averageY + standardDeviationY;

                % Force and stress should not be below zero
                lowerBound(lowerBound < 0) = 0;

                %% Only shade points where standard deviation exists
                shadeValid = ...
                    isfinite(commonX) & ...
                    isfinite(lowerBound) & ...
                    isfinite(upperBound);

                xShade = commonX(shadeValid);
                lowerShade = lowerBound(shadeValid);
                upperShade = upperBound(shadeValid);

                %% Create figure
                fig = figure( ...
                    'Visible','on', ...
                    'Units','normalized', ...
                    'Position',[0.12 0.10 0.72 0.76]);

                ax = axes(fig);

                hold(ax,'on');
                grid(ax,'on');
                box(ax,'on');

                %% Draw shaded standard-deviation region
                if length(xShade) >= 2

                    shadeHandle = fill( ...
                        ax, ...
                        [xShade; flipud(xShade)], ...
                        [lowerShade; flipud(upperShade)], ...
                        [0.5 0.5 0.5], ...
                        'FaceAlpha',0.25, ...
                        'EdgeColor','none', ...
                        'DisplayName','Mean \pm 1 standard deviation');

                else

                    shadeHandle = gobjects(0);
                end

                %% Draw average curve over the shaded region
                meanHandle = plot( ...
                    ax, ...
                    commonX, ...
                    averageY, ...
                    'LineWidth',2.5, ...
                    'DisplayName', ...
                    sprintf( ...
                        'Average curve (n = %d)', ...
                        numberIncluded));

                %% Labels
                if strcmpi(testName,'Fracture')

                    xlabel(ax,'Displacement (mm)');
                    ylabel(ax,'Force (N)');

                else

                    xlabel(ax,'Strain');
                    ylabel(ax,'Stress (MPa)');
                end

                title( ...
                    ax, ...
                    yearNumber + " " + ...
                    materialName + " " + ...
                    testName + ...
                    " — Mean \pm Standard Deviation");

                if isempty(shadeHandle)

                    legend( ...
                        ax, ...
                        meanHandle, ...
                        'Location','best', ...
                        'Interpreter','tex');

                else

                    legend( ...
                        ax, ...
                        [meanHandle, shadeHandle], ...
                        'Location','best', ...
                        'Interpreter','tex');
                end

                axis(ax,'tight');

                %% Add minimum contributor information
                positiveCounts = ...
                    contributingCount(contributingCount > 0);

                if ~isempty(positiveCounts)

                    minimumContributors = min(positiveCounts);

                    subtitle( ...
                        ax, ...
                        sprintf( ...
                            ['Curves included: %d; minimum curves ' ...
                             'contributing at any plotted point: %d'], ...
                            numberIncluded, ...
                            minimumContributors));
                end

                %% Save graph
                saveName = ...
                    yearNumber + "_" + ...
                    materialName + "_" + ...
                    testName + ...
                    "_Mean_StdDev.png";

                savePath = fullfile( ...
                    outputFolder, ...
                    saveName);

                exportgraphics( ...
                    fig, ...
                    savePath, ...
                    'Resolution',300);

                fprintf( ...
                    ['Saved mean and standard-deviation plot ' ...
                     'using %d curves:\n%s\n'], ...
                    numberIncluded, ...
                    savePath);
            end
        end
    end
end
%% ========================================================================
%% Process one specimen for the yearly average
%% ========================================================================

function [xCurve, yCurve, ok] = ...
    processCurveForYearlyAverage( ...
        csvPath, dims, sectionNumber, sampleNumber, ...
        testName, materialName, plotLimits)

    xCurve = [];
    yCurve = [];
    ok = false;

    data = readCSVNumeric(csvPath);

    if size(data,2) < 3
        warning( ...
            'CSV has fewer than three columns: %s', ...
            csvPath);
        return;
    end

    displacement = data(:,2);
    force = data(:,3);

    valid = ...
        isfinite(displacement) & ...
        isfinite(force);

    displacement = displacement(valid);
    force = force(valid);

    if length(displacement) < 3
        return;
    end

    %% Remove duplicate displacement values
    [displacement, uniqueIndices] = ...
        unique(displacement,'stable');

    force = force(uniqueIndices);

    %% ====================================================================
    %% Fracture
    %% ====================================================================

    if strcmpi(testName,'Fracture')

        peakForceOriginal = max(force);

        if ~isfinite(peakForceOriginal) || ...
                peakForceOriginal <= 0
            return;
        end

        %% Find beginning of loading
        startThreshold = 0.05 * peakForceOriginal;

        startIndex = find( ...
            force >= startThreshold, ...
            1, ...
            'first');

        if isempty(startIndex)
            return;
        end

        displacement = displacement(startIndex:end);
        force = force(startIndex:end);

        %% Shift to origin
        displacement = displacement - displacement(1);
        force = force - force(1);

        displacement(displacement < 0) = 0;
        force(force < 0) = 0;

%% Cut each fracture specimen at maximum force
[~, peakIndex] = max(force);

displacement = displacement(1:peakIndex);
force = force(1:peakIndex);


        %% Apply plotting limit
        keep = ...
            displacement >= 0 & ...
            displacement <= plotLimits.fracture;

        displacement = displacement(keep);
        force = force(keep);

        if length(displacement) < 2
            return;
        end

        xCurve = displacement;
        yCurve = force; 
        ok = true;
        return;
    end

    %% ====================================================================
    %% Compression and tension
    %% ====================================================================

    displacement = displacement - displacement(1);

    if strcmpi(testName,'Tension')
        [displacement, force] = ...
            cropAfterFailure(displacement,force);
    end

    [area, lengthValue, dimensionsOK] = ...
        getDimensions( ...
            dims, ...
            sectionNumber, ...
            testName, ...
            materialName, ...
            sampleNumber);

    if ~dimensionsOK
        return;
    end

    stress = force ./ area;
    strain = displacement ./ lengthValue;

    valid = isfinite(strain) & isfinite(stress);

    strain = strain(valid);
    stress = stress(valid);

    if length(strain) < 3
        return;
    end

    %% Shift stress so the curve starts at zero
    stress = stress - stress(1);

    strain(strain < 0) = 0;
    stress(stress < 0) = 0;

    %% Apply test-specific limit
    if strcmpi(testName,'Compression')

        keep = ...
            strain >= 0 & ...
            strain <= plotLimits.compression;

    else

        keep = ...
            strain >= 0 & ...
            strain <= plotLimits.tension;
    end

    strain = strain(keep);
    stress = stress(keep);

    if length(strain) < 3
        return;
    end

    %% Cut tension at its maximum, but keep the full compression curve
if strcmpi(testName,'Tension')

    [~, peakIndex] = max(stress);

    strain = strain(1:peakIndex);
    stress = stress(1:peakIndex);

end

    if length(strain) < 2
        return;
    end

    xCurve = strain;
    yCurve = stress;
    ok = true;
end
%% ------------------------------------------------------------------------
function txt = showCSV(~,event)

h = get(event,'Target');

csvPath = h.UserData;

fprintf('\n=================================================\n');
fprintf('CSV File:\n%s\n', csvPath);
fprintf('=================================================\n\n');

txt = {'CSV File' char(csvPath)};

end