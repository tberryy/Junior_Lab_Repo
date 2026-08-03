clear; clc; close all;

%% ==========================================================
%% Fracture toughness (K) and critical strain energy release
%% rate (G_Ic) for compact-tension (CT) fracture specimens
%%
%% Follows the same classification / fracture-curve processing
%% logic as data_process_and_plot.m, then iterates every
%% specimen to compute K and G_Ic instead of plotting.
%%
%% Run this script from inside Junior_Lab_Repo
%% ==========================================================

repoFolder = pwd;
organizedFolder = fullfile(repoFolder, 'OrganizedData');

days = {'monday','tuesday','wednesday','thursday','friday'};
materials = {'CNT','NEAT'};
years = ["2023","2024","2025","2026"];

plotLimits.fracture = 3.5;   % displacement in mm, same crop used for plotting

outputFolder = fullfile(organizedFolder, 'Fracture_GIc_KIc_Results');

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% Classify every fracture specimen
classifiedFracture = classifyAllFractureSpecimens(organizedFolder, days);

if isempty(classifiedFracture)
    error('No fracture specimens were classified. Check the OrganizedData folder.');
end

%% ==========================================================
%% Iterate every fracture specimen and calculate K and G_Ic
%% ==========================================================

individualResults = table();

for y = 1:length(years)

    yearNumber = years(y);
    yearFolderName = yearNumber + "_organized";

    dimensionFile = fullfile( ...
        organizedFolder, ...
        yearFolderName, ...
        "SpecimenDimensions" + yearNumber + ".xlsx");

    if ~isfile(dimensionFile)
        warning('Dimension file not found: %s', dimensionFile);
        continue;
    end

    dims = readtable(dimensionFile);

    if ~ismember('Material', dims.Properties.VariableNames)
        dims.Properties.VariableNames{2} = 'Material';
    end

    for m = 1:length(materials)

        materialName = materials{m};

        rows = ...
            strcmpi(string(classifiedFracture.Year), yearFolderName) & ...
            strcmpi(string(classifiedFracture.Material), materialName);

        selected = classifiedFracture(rows,:);

        if isempty(selected)
            continue;
        end

        fprintf('\nFracture K and G_Ic: %s %s\n', yearNumber, materialName);

        for i = 1:height(selected)

            csvPath = string(selected.FilePath(i));
            groupName = string(selected.Group(i));
            sampleName = string(selected.SampleName(i));

            sectionNumber = str2double(regexprep(groupName,'\D',''));
            sampleNumber = str2double(regexprep(sampleName,'\D',''));

            [width_mm, thickness_mm, crackLength_mm, ok] = ...
                getFractureDimensions( ...
                    dims, sectionNumber, materialName, sampleNumber);

            if ~ok
                continue;
            end

            [displacement, force, peakForce, ok] = ...
                processFractureCurve(csvPath, plotLimits);

            if ~ok
                continue;
            end

            [K, alpha] = calculateStressIntensityFactor( ...
                peakForce, width_mm, thickness_mm, crackLength_mm);

            [GIc, energy_J] = calculateEnergyReleaseRate( ...
                displacement, force, width_mm, thickness_mm, crackLength_mm);

            %% a/W should fall inside 0.2-0.8 for the CT geometry
            %% factor below to be valid (ASTM E399 / D5045)
            validGeometry = ...
                isfinite(K) && isfinite(GIc) && ...
                alpha > 0.2 && alpha < 0.8;

            newRow = table( ...
                yearNumber, ...
                string(materialName), ...
                string(selected.Batch(i)), ...
                string(selected.Day(i)), ...
                groupName, ...
                sampleName, ...
                sectionNumber, ...
                sampleNumber, ...
                width_mm, ...
                thickness_mm, ...
                crackLength_mm, ...
                alpha, ...
                peakForce, ...
                energy_J, ...
                K, ...
                GIc, ...
                validGeometry, ...
                csvPath, ...
                'VariableNames',{ ...
                    'Year', ...
                    'Material', ...
                    'Batch', ...
                    'Day', ...
                    'Group', ...
                    'Sample', ...
                    'SectionNumber', ...
                    'SampleNumber', ...
                    'Width_mm', ...
                    'Thickness_mm', ...
                    'CrackLength_mm', ...
                    'a_over_W', ...
                    'PeakForce_N', ...
                    'Energy_J', ...
                    'K_MPa_sqrtm', ...
                    'GIc_kJ_per_m2', ...
                    'ValidGeometry', ...
                    'FilePath'});

            individualResults = [individualResults; newRow];

            fprintf( ...
                ['  %s | a/W = %.3f | K = %.3f MPa*m^0.5 | ' ...
                 'G_Ic = %.3f kJ/m^2\n'], ...
                sampleName, alpha, K, GIc);
        end
    end
end

if isempty(individualResults)
    error('No fracture K / G_Ic results were calculated.');
end

%% Save every specimen's results
individualFile = fullfile( ...
    outputFolder, 'Fracture_GIc_KIc_All_Specimens.xlsx');

writetable(individualResults, individualFile, 'Sheet','All Specimens');

acceptedResults = individualResults(individualResults.ValidGeometry,:);

writetable(acceptedResults, individualFile, 'Sheet','Valid Geometry');

%% ==========================================================
%% Yearly mean and sample standard deviation
%% ==========================================================

yearlySummary = table();

for y = 1:length(years)

    for m = 1:length(materials)

        rows = ...
            strcmpi(acceptedResults.Year, years(y)) & ...
            strcmpi(acceptedResults.Material, materials(m));

        Kvalues = acceptedResults.K_MPa_sqrtm(rows);
        Kvalues = Kvalues(isfinite(Kvalues));

        GIcValues = acceptedResults.GIc_kJ_per_m2(rows);
        GIcValues = GIcValues(isfinite(GIcValues));

        if isempty(Kvalues) && isempty(GIcValues)
            continue;
        end

        meanK = mean(Kvalues,'omitnan');
        meanGIc = mean(GIcValues,'omitnan');

        if length(Kvalues) >= 2
            stdK = std(Kvalues,0,'omitnan');
        else
            stdK = NaN;
        end

        if length(GIcValues) >= 2
            stdGIc = std(GIcValues,0,'omitnan');
        else
            stdGIc = NaN;
        end

        newSummaryRow = table( ...
            years(y), ...
            string(materials(m)), ...
            meanK, ...
            stdK, ...
            length(Kvalues), ...
            meanGIc, ...
            stdGIc, ...
            length(GIcValues), ...
            'VariableNames',{ ...
                'Year', ...
                'Material', ...
                'MeanK_MPa_sqrtm', ...
                'StdK_MPa_sqrtm', ...
                'NumberOfK_Specimens', ...
                'MeanGIc_kJ_per_m2', ...
                'StdGIc_kJ_per_m2', ...
                'NumberOfGIc_Specimens'});

        yearlySummary = [yearlySummary; newSummaryRow];
    end
end

summaryFile = fullfile( ...
    outputFolder, 'Fracture_GIc_KIc_Yearly_Summary.xlsx');

writetable(yearlySummary, summaryFile, 'Sheet','Yearly Summary');

fprintf('\nFinished. Results saved to:\n%s\n%s\n', ...
    individualFile, summaryFile);

%% ========================================================================
%% Classify all fracture specimens (mirrors classifyAllSpecimens in
%% data_process_and_plot.m, restricted to the Fracture test)
%% ========================================================================

function classifiedAll = classifyAllFractureSpecimens(organizedFolder, days)

    organizedYears = dir(fullfile(organizedFolder, '*_organized'));
    organizedYears = organizedYears([organizedYears.isdir]);

    classifiedAll = table();

    for y = 1:length(organizedYears)

        yearName = organizedYears(y).name;
        yearFolder = fullfile(organizedFolder, yearName);

        fprintf('\nClassifying fracture specimens in %s...\n', yearName);

        yearResults = table();

        batchFolders = dir(fullfile(yearFolder, 'batch*'));
        batchFolders = batchFolders([batchFolders.isdir]);

        for b = 1:length(batchFolders)

            batchName = batchFolders(b).name;
            batchFolder = fullfile(yearFolder, batchName);

            for d = 1:length(days)

                dayName = days{d};
                dayFolder = fullfile(batchFolder, dayName);

                if ~isfolder(dayFolder)
                    continue;
                end

                groupFolders = dir(dayFolder);
                groupFolders = groupFolders([groupFolders.isdir]);
                groupFolders = groupFolders( ...
                    ~ismember({groupFolders.name},{'.','..'}));

                for g = 1:length(groupFolders)

                    groupName = groupFolders(g).name;
                    groupPath = fullfile(dayFolder, groupName);

                    allCSVFiles = dir(fullfile(groupPath, '**', '*.csv'));

                    if isempty(allCSVFiles)
                        continue;
                    end

                    fileNamesUpper = upper(string({allCSVFiles.name}));

                    fractureFiles = allCSVFiles( ...
                        contains(fileNamesUpper, "FRACTURE"));

                    if isempty(fractureFiles)
                        continue;
                    end

                    temp = classifyFractureFileList( ...
                        fractureFiles, ...
                        4, ...
                        yearName, ...
                        batchName, ...
                        dayName, ...
                        groupName);

                    yearResults = [yearResults; temp];
                end
            end
        end

        classifiedAll = [classifiedAll; yearResults];
    end
end

%% ========================================================================
%% Classify fracture files in one group folder by max force
%% (mirrors classifyFileListByMaxForce in data_process_and_plot.m)
%% ========================================================================

function results = classifyFractureFileList( ...
    csvFiles, numCNT, yearName, batchName, dayName, groupName)

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
        fileNames, filePaths, maxForce, ...
        'VariableNames',{'OriginalFileName','FilePath','MaxForce'});

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
    results.Test = repmat("Fracture",numFiles,1);
    results.Material = material;
    results.SampleName = sampleName;

    results = results(:,{ ...
        'Year','Batch','Day','Group','Test','SampleName', ...
        'Material','OriginalFileName','FilePath','MaxForce'});
end

%% ========================================================================
%% Read a numeric CSV, skipping header/units rows
%% (mirrors readCSVNumeric in data_process_and_plot.m)
%% ========================================================================

function data = readCSVNumeric(filePath)

    opts = detectImportOptions(filePath);
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
%% Look up CT specimen dimensions for one fracture specimen
%% W = Width_mm, B = Thickness_mm, a = NotchLength_mm + PreCrackLength_mm
%% ========================================================================

function [width_mm, thickness_mm, crackLength_mm, ok] = ...
    getFractureDimensions(dims, sectionNumber, materialName, sampleNumber)

    ok = true;

    sectionValues = str2double(string(dims.Section));
    sampleValues  = str2double(string(dims.Sample));

    materialValues = strtrim(string(dims.Material));
    testValues     = strtrim(string(dims.Test));

    matchingRows = ...
        sectionValues == sectionNumber & ...
        strcmpi(materialValues,string(materialName)) & ...
        strcmpi(testValues,"Fracture") & ...
        sampleValues == sampleNumber;

    row = dims(matchingRows,:);

    if isempty(row)

        warning( ...
            'Missing fracture dimensions: Section %g, %s, Sample %g', ...
            sectionNumber, materialName, sampleNumber);

        width_mm = NaN;
        thickness_mm = NaN;
        crackLength_mm = NaN;
        ok = false;
        return;
    end

    width_mm = str2double(string(row.Width_mm(1)));
    thickness_mm = str2double(string(row.Thickness_mm(1)));

    notchLength_mm = str2double(string(row.NotchLength_mm(1)));
    preCrackLength_mm = str2double(string(row.PreCrackLength_mm(1)));

    crackLength_mm = notchLength_mm + preCrackLength_mm;

    if isnan(width_mm) || isnan(thickness_mm) || isnan(crackLength_mm) || ...
            width_mm <= 0 || thickness_mm <= 0 || crackLength_mm <= 0

        warning( ...
            'Invalid fracture dimensions: Section %g, %s, Sample %g', ...
            sectionNumber, materialName, sampleNumber);

        ok = false;
    end
end

%% ========================================================================
%% Load and crop one fracture force-displacement curve
%% (mirrors the fracture-processing block in data_process_and_plot.m)
%% Returns the curve up to peak force, plus the peak force itself.
%% ========================================================================

function [displacement, force, peakForce, ok] = ...
    processFractureCurve(csvPath, plotLimits)

    ok = true;
    displacement = [];
    force = [];
    peakForce = NaN;

    if ~isfile(csvPath)
        warning('CSV not found: %s', csvPath);
        ok = false;
        return;
    end

    data = readCSVNumeric(csvPath);

    if size(data,2) < 3
        warning('CSV does not have at least three columns: %s', csvPath);
        ok = false;
        return;
    end

    displacement = data(:,2);
    force = data(:,3);

    valid = ...
        ~isnan(displacement) & ~isnan(force) & ...
        ~isinf(displacement) & ~isinf(force);

    displacement = displacement(valid);
    force = force(valid);

    if isempty(displacement) || isempty(force)
        warning('No valid numeric data in: %s', csvPath);
        ok = false;
        return;
    end

    peakForceOriginal = max(force);

    if isempty(peakForceOriginal) || isnan(peakForceOriginal) || ...
            peakForceOriginal <= 0
        warning('Invalid fracture force data: %s', csvPath);
        ok = false;
        return;
    end

    %% Detect loading start at 5% of original peak
    startThreshold = 0.05 * peakForceOriginal;
    startIndex = find(force >= startThreshold, 1, 'first');

    if isempty(startIndex)
        warning('Could not detect fracture loading start: %s', csvPath);
        ok = false;
        return;
    end

    displacement = displacement(startIndex:end);
    force = force(startIndex:end);

    %% Smooth force before calculating slope
    smoothWindow = 25;
    forceSmooth = movmean(force, smoothWindow);

    dFdx = gradient(forceSmooth, displacement);

    slopeThreshold = 50;    % N/mm
    requiredPoints = 15;    % consecutive points above threshold

    isLoading = dFdx >= slopeThreshold;
    sustainedLoading = movsum(isLoading, requiredPoints) >= requiredPoints;

    startIndex = find(sustainedLoading, 1, 'first');

    if isempty(startIndex)
        startIndex = 1;
    end

    paddingPoints = 3;
    startIndex = max(1, startIndex - paddingPoints);

    displacement = displacement(startIndex:end);
    force = force(startIndex:end);

    %% Shift curve to origin
    displacement = displacement - displacement(1);
    force = force - force(1);

    displacement(displacement < 0) = 0;
    force(force < 0) = 0;

    [peakForceShifted, peakIndex] = max(force);

    %% Crop after force falls below 20% of peak
    endThreshold = 0.20 * peakForceShifted;
    dropRelative = find(force(peakIndex:end) <= endThreshold, 1, 'first');

    if ~isempty(dropRelative)
        endIndex = peakIndex + dropRelative - 1;
        displacement = displacement(1:endIndex);
        force = force(1:endIndex);
    end

    %% Reject extreme peak-displacement outliers
    displacementAtPeak = displacement(peakIndex);
    maxAllowedPeakDisplacement = 4.0;

    if displacementAtPeak > maxAllowedPeakDisplacement
        warning( ...
            'Skipping fracture outlier: %s (peak displacement = %.3f mm)', ...
            csvPath, displacementAtPeak);
        ok = false;
        return;
    end

    %% Apply fracture plotting limit
    keep = displacement >= 0 & displacement <= plotLimits.fracture;
    displacement = displacement(keep);
    force = force(keep);

    if isempty(displacement) || isempty(force)
        warning('Fracture data empty after cropping: %s', csvPath);
        ok = false;
        return;
    end

    %% Keep data only up to the maximum force
    [peakForce, peakIndex] = max(force);

    displacement = displacement(1:peakIndex);
    force = force(1:peakIndex);

    %% Need at least two points to integrate the energy under the curve
    if numel(displacement) < 2
        warning( ...
            'Fracture curve has too few points before peak: %s', csvPath);
        ok = false;
        return;
    end
end

%% ========================================================================
%% Stress intensity factor K for a compact-tension (CT) specimen
%% ASTM E399 / D5045 geometry factor f(a/W)
%% ========================================================================

function [K_MPa_sqrtm, alpha] = calculateStressIntensityFactor( ...
    peakForce_N, width_mm, thickness_mm, crackLength_mm)

    alpha = crackLength_mm / width_mm;

    %% alpha >= 1 means the crack length exceeds the specimen width
    %% (impossible geometry, usually a bad dimension entry) - the CT
    %% factor below is undefined there, so return NaN instead of a
    %% silently-wrong complex number.
    if alpha >= 1
        K_MPa_sqrtm = NaN;
        return;
    end

    f = ((2 + alpha) * ...
        (0.886 + 4.64*alpha - 13.32*alpha^2 + 14.72*alpha^3 - 5.6*alpha^4)) ...
        / (1 - alpha)^1.5;

    B_m = thickness_mm / 1000;
    W_m = width_mm / 1000;

    K_Pa_sqrtm = (peakForce_N / (B_m * sqrt(W_m))) * f;

    K_MPa_sqrtm = K_Pa_sqrtm / 1e6;
end

%% ========================================================================
%% Critical strain energy release rate G_Ic for a CT specimen
%%
%% G_Ic = U / (B * (W - a)), where U is the area under the
%% force-displacement curve up to peak load and (W - a) is the
%% uncracked ligament length. This treats the ASTM D5045
%% compliance-calibration factor (phi) as 1; replace with a
%% phi value from your lab manual / ASTM D5045 Table X1 if a
%% is outside 0.45-0.55*W or higher accuracy is required.
%% ========================================================================

function [GIc_kJ_per_m2, energy_J] = calculateEnergyReleaseRate( ...
    displacement_mm, force_N, width_mm, thickness_mm, crackLength_mm)

    energy_Nmm = trapz(displacement_mm, force_N);
    energy_J = energy_Nmm / 1000;

    B_m = thickness_mm / 1000;
    W_m = width_mm / 1000;
    a_m = crackLength_mm / 1000;

    ligamentArea_m2 = B_m * (W_m - a_m);

    GIc_J_per_m2 = energy_J / ligamentArea_m2;
    GIc_kJ_per_m2 = GIc_J_per_m2 / 1000;
end
