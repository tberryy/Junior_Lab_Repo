%% ========================================================================
%% plotYearlyFracturePoints
%%
%% One figure per test/material view, overlaying four yearly compositions:
%% 
%%   - The full experimental mean is plotted, including post-peak fall.
%%   - A shaded band shows mean +/- 1 standard deviation.
%%   - Each specimen's failure point is marked.
%%   %%   - For Tension and Fracture, the average curve is linearized through
%%     the origin and the mean failure point.
%%   - For Compression, the average curve is a polynomial best fit
%%     through the pooled pre-failure data.
%%   - The average failure point sits exactly ON that fitted curve, at the
%%     intersection of the curve and the vertical failure line.
%%
%% Error bar convention:
%%   - Along the average curve : vertical bars only (stress SD)
%%   - Along the failure line  : horizontal bars only (strain SD)
%%   - At the intersection     : both directions
%% 
%% Every year is plotted. The failure cutoff, which discards specimens that
%% have not failed by MaxFailureX, is applied ONLY to the years listed in
%% CutoffYears (2026 by default). Any figure that had the cutoff applied
%% says so in its subtitle.
%%
%% Outliers are detected on the failure points with rmoutliers and are not
%% plotted; every rejection is reported to the command window.
%%
%% Usage:
%%   plotYearlyFracturePoints(classifiedAll, organizedFolder, materials, ...
%%       'Tension', plotLimits, outputFolder);
%%
%% Display toggles (each independent, all default true):
%%   'ShowSpecimenCurves'   the solid pre-failure curve of each specimen
%%   'ShowPostFailure'      the dotted post-failure tail of each specimen
%%   'ShowFailurePoints'    the scatter marker at each specimen's failure
%%
%% Other optional name-value arguments:
%%   'CutoffYears'          years the failure cutoff applies to, default "2026"
%%                          (pass [] or "" to disable the cutoff entirely)
%%   'MaxFailureX'          cutoff value; defaults to the plot limit for the
%%                          test, so 0.015 strain for Tension
%%   'PolynomialOrder'      order of the average best fit, default 2
%%   'OutlierMethod'        'median' (default) | 'mean' | 'quartiles' | 'grubbs'
%%   'OutlierThreshold'     numeric, default 3
%%   'SmoothingSpan'        span used to smooth the SD array, default 0.15
%%   'PostFailureFactor'    how far past the plot limit the tail may run,
%%                          as a multiple of the limit, default 1.5
%%   'NumberOfErrorBars'    error bars along the average curve, default 3
%%   'NumberOfFailureBars'  error bars along the failure line, default 5
%% ========================================================================

function plotYearlyFracturePoints( ...
    classifiedAll, organizedFolder, materials, testName, ...
    plotLimits, outputFolder, varargin)

    %% ----------------------------------------------------------------
    %% Options
    %% ----------------------------------------------------------------
    parser = inputParser;

    addParameter(parser,'PolynomialOrder',2);
    addParameter(parser,'OutlierMethod','median');
    addParameter(parser,'OutlierThreshold',3);
    addParameter(parser,'SmoothingSpan',0.15);
    addParameter(parser,'PostFailureFactor',1.5);
    addParameter(parser,'NumberOfErrorBars',3);
    addParameter(parser,'NumberOfFailureBars',3);

    addParameter(parser,'CutoffYears',"2026");
    addParameter(parser,'MaxFailureX',[]);

    %% Independent display toggles
    addParameter(parser,'ShowSpecimenCurves',false);
    addParameter(parser,'ShowPostFailure',false);
    addParameter(parser,'ShowFailurePoints',false);

    parse(parser,varargin{:});

    polynomialOrder     = parser.Results.PolynomialOrder;
    outlierMethod       = parser.Results.OutlierMethod;
    outlierThreshold    = parser.Results.OutlierThreshold;
    smoothingSpan       = parser.Results.SmoothingSpan;
    postFailureFactor   = parser.Results.PostFailureFactor;
    numberOfErrorBars   = parser.Results.NumberOfErrorBars;
    numberOfFailureBars = parser.Results.NumberOfFailureBars;

    cutoffYears = string(parser.Results.CutoffYears);
    maxFailureX = parser.Results.MaxFailureX;

    showSpecimenCurves = logical(parser.Results.ShowSpecimenCurves);
    showPostFailure    = logical(parser.Results.ShowPostFailure);
    showFailurePoints  = logical(parser.Results.ShowFailurePoints);

    yearsToPlot = ["2023","2024","2025","2026"];
    testName    = string(testName);

    %% Composition percentages
    apPercentages = [60, 40, 50, 70];
    epoxyPercentages = 100 - apPercentages;


    %% Identify which material comparison is being plotted

    materialNames = upper(string(materials));

    if numel(materialNames) == 1

        if materialNames == "NEAT"
            plotGroup = "AP_Epoxy";

        elseif materialNames == "CNT"
            plotGroup = "AP_CNT_Epoxy";

        else
            plotGroup = "Other";
        end

    else
        plotGroup = "Combined";
    end


    %% Cutoff value defaults to the plot limit for this test
    if isempty(maxFailureX)

        if strcmpi(testName,'Compression')
            maxFailureX = plotLimits.compression;
        elseif strcmpi(testName,'Fracture')
            maxFailureX = plotLimits.fracture;
        else
            maxFailureX = plotLimits.tension;
        end
    end

    numberOfGridPoints  = 400;   % resolution of the fitted curve
    minimumContributors = 2;     % specimens required to report an SD

        fig = figure( ...
            'Visible','on', ...
            'Units','normalized', ...
            'Position',[0.10 0.10 0.75 0.75]);

        ax = axes(fig);

        hold(ax,'on');
        grid(ax,'on');
        box(ax,'on');

        legendHandles = gobjects(0);
        legendLabels  = strings(0);

        anythingPlotted = false;
        tailWasPlotted  = false;
        subtitlePieces  = strings(0);

    for y = 1:length(yearsToPlot)

        yearNumber     = yearsToPlot(y);
        yearFolderName = yearNumber + "_organized";
        
compositionLabel = ...
    string(apPercentages(y)) + "% AP " + ...
    string(epoxyPercentages(y)) + "% Epoxy";


        %% Does the failure cutoff apply to this year?
        applyCutoff = ~isempty(cutoffYears) && ...
            any(strcmp(yearNumber, cutoffYears));

        fprintf('\n==== %s %s ====\n', yearNumber, testName);

        if applyCutoff
            fprintf('Failure cutoff active: specimens must fail before %.5g\n', ...
                maxFailureX);
        end

        %% ------------------------------------------------------------
        %% Dimension file (not required for the Fracture test)
        %% ------------------------------------------------------------
        dims = table();

        if ~strcmpi(testName,'Fracture')

            dimensionFile = fullfile( ...
                organizedFolder, ...
                yearFolderName, ...
                "SpecimenDimensions" + yearNumber + ".xlsx");

            if ~isfile(dimensionFile)
                warning('Dimension file not found: %s', dimensionFile);
                continue;
            end

            dims = readtable(dimensionFile);

            if ~ismember('Material',dims.Properties.VariableNames)
                dims.Properties.VariableNames{2} = 'Material';
            end
        end

        for m = 1:length(materials)

            materialName = string(materials{m});

            % Distinguish composition by color and CNT by line style.
            compositionColors = [0.00 0.45 0.74; 0.85 0.33 0.10; ...
                                 0.47 0.67 0.19; 0.49 0.18 0.56];
            thisColor = compositionColors(y,:);
            if strcmpi(materialName,'CNT')
                meanLineStyle = '--';
                materialLabel = "AP/CNT/Epoxy";
            else
                meanLineStyle = '-';
                materialLabel = "AP/Epoxy";
            end
            seriesLabel = compositionLabel + " - " + materialLabel;

            rows = ...
                strcmpi(string(classifiedAll.Year), yearFolderName) & ...
                strcmpi(string(classifiedAll.Test), testName) & ...
                strcmpi(string(classifiedAll.Material), materialName);

            selected = classifiedAll(rows,:);

            if isempty(selected)
                warning('No files for %s %s %s.', ...
                    yearNumber, materialName, testName);
                continue;
            end

            %% ========================================================
            %% STEP 1 — read the FULL response of every specimen
            %% ========================================================

            fullX     = {};
            fullY     = {};
            failIndex = [];
            failureX  = [];
            failureY  = [];
            pathList  = strings(0);

            numberSkipped = 0;

            for i = 1:height(selected)

                csvPath = string(selected.FilePath(i));

                if ~isfile(csvPath)
                    warning('CSV not found: %s', csvPath);
                    continue;
                end

                sectionNumber = str2double( ...
                    regexprep(string(selected.Group(i)),'\D',''));

                sampleNumber = str2double( ...
                    regexprep(string(selected.SampleName(i)),'\D',''));

                [xCurve, yCurve, peakIndex, ok] = readFullCurve( ...
                    csvPath, dims, sectionNumber, sampleNumber, ...
                    testName, materialName, plotLimits, postFailureFactor);

                if ~ok
                    continue;
                end

                %% Discard specimens that never failed within the window
                if applyCutoff && xCurve(peakIndex) >= maxFailureX

                    fprintf(['    skipped (no failure before %.5g, ' ...
                             'peak at %.5g): %s\n'], ...
                        maxFailureX, xCurve(peakIndex), csvPath);

                    numberSkipped = numberSkipped + 1;
                    continue;
                end

                fullX{end+1,1}     = xCurve;              %#ok<AGROW>
                fullY{end+1,1}     = yCurve;              %#ok<AGROW>
                failIndex(end+1,1) = peakIndex;           %#ok<AGROW>
                failureX(end+1,1)  = xCurve(peakIndex);   %#ok<AGROW>
                failureY(end+1,1)  = yCurve(peakIndex);   %#ok<AGROW>
                pathList(end+1,1)  = csvPath;             %#ok<AGROW>
            end

            if numberSkipped > 0
                fprintf('  %s: %d specimen(s) cut for not failing before %.5g\n', ...
                    materialName, numberSkipped, maxFailureX);
            end

            if isempty(failureX)
                warning('No usable specimens for %s %s %s.', ...
                    yearNumber, materialName, testName);
                continue;
            end

            %% ========================================================
            %% STEP 2 — outlier rejection on the failure points
            %% rmoutliers(A, method, dim, Name, Value)
            %% ========================================================

            if numel(failureX) >= 3
                if strcmpi(outlierMethod,'grubbs')
                    [~, outlierMask] = rmoutliers( ...
                        [failureX, failureY], outlierMethod, 1);
                else
                    [~, outlierMask] = rmoutliers( ...
                        [failureX, failureY], outlierMethod, 1, ...
                        'ThresholdFactor', outlierThreshold);
                end
                isOutlier = any(outlierMask, 2);
            else
                isOutlier = false(numel(failureX),1);
            end

            isKept = ~isOutlier;

            if any(isOutlier)

                fprintf('  %s: %d of %d specimens rejected as outliers\n', ...
                    materialName, sum(isOutlier), numel(isOutlier));

                for k = find(isOutlier)'
                    fprintf('    (x = %.4g, y = %.4g)  %s\n', ...
                        failureX(k), failureY(k), pathList(k));
                end
            end

            if ~any(isKept)
                warning('Every specimen rejected for %s %s %s.', ...
                    yearNumber, materialName, testName);
                continue;
            end

            keptFullX     = fullX(isKept);
            keptFullY     = fullY(isKept);
            keptFailIndex = failIndex(isKept);
            keptFailureX  = failureX(isKept);
            keptFailureY  = failureY(isKept);
            keptPaths     = pathList(isKept);

            numberKept = numel(keptFailureX);

            %% ========================================================
            %% STEP 3 — failure statistics
            %% ========================================================

            meanFailureX = mean(keptFailureX);
            meanFailureY = mean(keptFailureY);

            if numberKept >= 2
                stdFailureX = std(keptFailureX,0);
                stdFailureY = std(keptFailureY,0);
            else
                stdFailureX = 0;
                stdFailureY = 0;
            end

            %% ========================================================
            %% STEP 4 — full experimental mean, including post-peak fall
            %% ========================================================
            % Interpolate the retained FULL specimen responses at common x.
            % A specimen contributes only within its measured x-range.
            curveEnds = NaN(numberKept,1);
            cleanedX = cell(numberKept,1);
            cleanedY = cell(numberKept,1);
            for c = 1:numberKept
                [cleanedX{c}, cleanedY{c}] = makeMonotonic( ...
                    keptFullX{c}, keptFullY{c});
                if numel(cleanedX{c}) >= 2
                    curveEnds(c) = max(cleanedX{c});
                end
            end

            if ~any(isfinite(curveEnds))
                warning('No valid full curves for %s %s %s.', ...
                    yearNumber, materialName, testName);
                continue;
            end

            fitX = linspace(0, max(curveEnds), numberOfGridPoints)';
            stackedY = NaN(numberOfGridPoints, numberKept);

            for c = 1:numberKept
                if numel(cleanedX{c}) < 2
                    continue;
                end
                stackedY(:,c) = interp1( ...
                    cleanedX{c}, cleanedY{c}, fitX, 'linear', NaN);
            end

            fitCount = sum(isfinite(stackedY),2);
            fitY = mean(stackedY, 2, 'omitnan');
            fitYSpread = std(stackedY, 0, 2, 'omitnan');

            % Require at least two contributing specimens for both mean
            % and standard deviation, avoiding misleading one-sample tails.
            fitY(fitCount < minimumContributors) = NaN;
            fitYSpread(fitCount < minimumContributors) = NaN;
            fitYSpread = smoothSpread(fitYSpread, smoothingSpan);

            %% ========================================================
            %% STEP 5 — mean curve and shaded +/- 1 SD (no error bars)
            %% ========================================================
            valid = isfinite(fitX) & isfinite(fitY) & ...
                    isfinite(fitYSpread);
            if any(valid)
                % Preserve gaps where the contributor count is insufficient.
                % The fill is restricted to each contiguous valid run.
                edges = diff([false; valid; false]);
                runStarts = find(edges == 1);
                runEnds = find(edges == -1) - 1;

                for r = 1:numel(runStarts)
                    idx = runStarts(r):runEnds(r);
                    if numel(idx) < 2
                        continue;
                    end
                    shadeX = fitX(idx);
                    shadeY = fitY(idx);
                    shadeSD = fitYSpread(idx);
                    upperBound = shadeY + shadeSD;
                    lowerBound = max(shadeY - shadeSD, 0);

                    fill(ax, [shadeX; flipud(shadeX)], ...
                        [upperBound; flipud(lowerBound)], thisColor, ...
                        'FaceAlpha',0.15, 'EdgeColor','none', ...
                        'HandleVisibility','off');
                end

                fitHandle = plot(ax, fitX, fitY, ...
                    'Color',thisColor, 'LineWidth',3.0, ...
                    'LineStyle',meanLineStyle);
                legendHandles(end+1) = fitHandle;
                legendLabels(end+1) = seriesLabel + ...
                    string(sprintf(' full mean (n = %d)', numberKept));
                anythingPlotted = true;
            end

            fprintf(['  %s: n = %d, mean peak x = %.4g (SD %.4g), ' ...
                     'mean peak y = %.4g (SD %.4g)\n'], ...
                materialName, numberKept, meanFailureX, stdFailureX, ...
                meanFailureY, stdFailureY);
        end
    end  % all four compositions processed

        %% ------------------------------------------------------------
        %% Finish the figure
        %% ------------------------------------------------------------

        if ~anythingPlotted
            warning('Nothing plotted for %s %s.', testName, plotGroup);
            close(fig);
            return;
        end

        if tailWasPlotted
            tailDummy = plot(ax,NaN,NaN, ...
                'Color',[0.45 0.45 0.45], ...
                'LineStyle',':','LineWidth',1.4);

            tailDummy.HandleVisibility = 'off';
        end

        set(ax,'FontSize',18,'FontWeight','bold');

        if strcmpi(testName,'Fracture')
            xlabel(ax,'Displacement (mm)','FontWeight','bold','FontSize',20);
            ylabel(ax,'Force (N)','FontWeight','bold','FontSize',20);
        else
            xlabel(ax,'Strain','FontWeight','bold','FontSize',20);
            ylabel(ax,'Stress (MPa)','FontWeight','bold','FontSize',20);
        end

        title(ax, ...
        testName + " - " + replace(plotGroup,"_","/") + " - All Compositions", ...
        'Interpreter','none');

        subtitleText = "Full experimental mean with shaded +/- 1 SD";

        subtitle(ax, subtitleText, 'Interpreter','none');

        legend(ax, legendHandles, cellstr(legendLabels), ...
            'Location','bestoutside','Interpreter','none','FontSize',10);

        axis(ax,'tight');

        dcm = datacursormode(fig);
        set(dcm,'Enable','on','UpdateFcn',@showCSV);

        saveName = ...
    "All_Compositions_" + testName + ...
    "_" + plotGroup + "_Failure_Analysis.png";
        if ~isfolder(outputFolder), mkdir(outputFolder); end
        savePath = fullfile(outputFolder, saveName);

        exportgraphics(fig, savePath, 'Resolution',300);

        fprintf('Saved: %s\n', savePath);
end

%% ========================================================================
%% Read one specimen's COMPLETE response and locate its failure point
%%
%% Unlike processCurveForYearlyAverage this does not truncate at the peak,
%% so post-failure data is preserved. peakIndex marks the failure point.
%% ========================================================================

function [xCurve, yCurve, peakIndex, ok] = readFullCurve( ...
    csvPath, dims, sectionNumber, sampleNumber, ...
    testName, materialName, plotLimits, postFailureFactor)

    xCurve    = [];
    yCurve    = [];
    peakIndex = [];
    ok        = false;

    data = readCSVNumeric(csvPath);

    if size(data,2) < 3
        warning('CSV has fewer than three columns: %s', csvPath);
        return;
    end

    displacement = data(:,2);
    force        = data(:,3);

    valid = isfinite(displacement) & isfinite(force);

    displacement = displacement(valid);
    force        = force(valid);

    if numel(displacement) < 3
        return;
    end

    %% --------------------------------------------------------------
    %% Fracture test: force against displacement, no dimensions needed
    %% --------------------------------------------------------------
    if strcmpi(testName,'Fracture')

        peakForce = max(force);

        if ~isfinite(peakForce) || peakForce <= 0
            return;
        end

        startIndex = find(force >= 0.05 * peakForce, 1, 'first');

        if isempty(startIndex)
            return;
        end

        displacement = displacement(startIndex:end);
        force        = force(startIndex:end);

        displacement = displacement - displacement(1);
        force        = force - force(1);

        displacement(displacement < 0) = 0;
        force(force < 0) = 0;

        limitValue = plotLimits.fracture * postFailureFactor;

        keep = displacement >= 0 & displacement <= limitValue;

        displacement = displacement(keep);
        force        = force(keep);

        if numel(displacement) < 3
            return;
        end

        [~, peakIndex] = max(force);

        xCurve = displacement;
        yCurve = force;
        ok     = true;
        return;
    end

    %% --------------------------------------------------------------
    %% Compression and tension: convert to stress and strain
    %% --------------------------------------------------------------
    displacement = displacement - displacement(1);

    [area, lengthValue, dimensionsOK] = getDimensions( ...
        dims, sectionNumber, testName, materialName, sampleNumber);

    if ~dimensionsOK
        return;
    end

    stress = force ./ area;
    strain = displacement ./ lengthValue;

    valid = isfinite(strain) & isfinite(stress);

    strain = strain(valid);
    stress = stress(valid);

    if numel(strain) < 3
        return;
    end

    stress = stress - stress(1);

    strain(strain < 0) = 0;
    stress(stress < 0) = 0;

    if strcmpi(testName,'Compression')
        limitValue = plotLimits.compression * postFailureFactor;
    else
        limitValue = plotLimits.tension * postFailureFactor;
    end

    keep = strain >= 0 & strain <= limitValue;

    strain = strain(keep);
    stress = stress(keep);

    if numel(strain) < 3
        return;
    end

    [~, peakIndex] = max(stress);

    if peakIndex < 2
        return;
    end

    xCurve = strain;
    yCurve = stress;
    ok     = true;
end

%% ========================================================================
%% Sort, deduplicate, and strip non-finite pairs so interp1 will accept them
%% ========================================================================

function [xClean, yClean] = makeMonotonic(xRaw, yRaw)

    xClean = xRaw(:);
    yClean = yRaw(:);

    good = isfinite(xClean) & isfinite(yClean);

    xClean = xClean(good);
    yClean = yClean(good);

    [xClean, sortIndex] = sort(xClean);
    yClean = yClean(sortIndex);

    [xClean, uniqueIndex] = unique(xClean,'stable');
    yClean = yClean(uniqueIndex);
end

%% ========================================================================
%% Light smoothing of a standard-deviation array so the error bars do not
%% jitter against a smooth fitted curve
%% ========================================================================

function ySmooth = smoothSpread(yValues, span)

    ySmooth = yValues(:);

    numberOfPoints = numel(ySmooth);

    if numberOfPoints < 5
        return;
    end

    isMissing = ~isfinite(ySmooth);

    if all(isMissing)
        return;
    end

    yFilled = ySmooth;

    if any(isMissing)
        yFilled(isMissing) = interp1( ...
            find(~isMissing), ySmooth(~isMissing), find(isMissing), ...
            'linear','extrap');
    end

    windowLength = max(5, round(span * numberOfPoints));

    if mod(windowLength,2) == 0
        windowLength = windowLength + 1;
    end

    windowLength = min(windowLength, numberOfPoints);

    ySmooth = smoothdata(yFilled,'movmean',windowLength);

    ySmooth(isMissing) = NaN;
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
%% Look up specimen dimensions, falling back to measured averages
%% ========================================================================

function [area, lengthValue, ok, usedDefault] = getDimensions( ...
    dims, sectionNumber, testName, materialName, sampleNumber)

    ok = true;
    usedDefault = false;

    defaultTension.Width_mm       = 9.4811;
    defaultTension.Thickness_mm   = 0.7125;
    defaultTension.GaugeLength_mm = 14.25;

    defaultCompression.Diameter_mm = 9.4811;
    defaultCompression.Length_mm   = 25.40;

    sectionValues = str2double(string(dims.Section));
    sampleValues  = str2double(string(dims.Sample));

    materialValues = strtrim(string(dims.Material));
    testValues     = strtrim(string(dims.Test));

    matchingRows = ...
        sectionValues == sectionNumber & ...
        strcmpi(materialValues,string(materialName)) & ...
        strcmpi(testValues,string(testName)) & ...
        sampleValues == sampleNumber;

    row = dims(matchingRows,:);

    rowFound = ~isempty(row);

    if ~rowFound
        warning( ...
            ['Missing dimensions: Section %g, %s, %s, Sample %g. ' ...
             'Using default averages.'], ...
            sectionNumber, materialName, testName, sampleNumber);
    end

    if strcmpi(testName,'Compression')

        if rowFound
            diameter    = safeNumber(row,'Diameter_mm');
            lengthValue = safeNumber(row,'Length_mm');
        else
            diameter    = NaN;
            lengthValue = NaN;
        end

        if ~isfinite(diameter) || diameter <= 0
            diameter    = defaultCompression.Diameter_mm;
            usedDefault = true;
        end

        if ~isfinite(lengthValue) || lengthValue <= 0
            lengthValue = defaultCompression.Length_mm;
            usedDefault = true;
        end

        area = pi * (diameter / 2)^2;

    elseif strcmpi(testName,'Tension')

        if rowFound
            width       = safeNumber(row,'Width_mm');
            thickness   = safeNumber(row,'Thickness_mm');
            lengthValue = safeNumber(row,'GaugeLength_mm');
        else
            width       = NaN;
            thickness   = NaN;
            lengthValue = NaN;
        end

        if ~isfinite(width) || width <= 0
            width       = defaultTension.Width_mm;
            usedDefault = true;
        end

        if ~isfinite(thickness) || thickness <= 0
            thickness   = defaultTension.Thickness_mm;
            usedDefault = true;
        end

        if ~isfinite(lengthValue) || lengthValue <= 0
            lengthValue = defaultTension.GaugeLength_mm;
            usedDefault = true;
        end

        area = width * thickness;

    else
        area        = NaN;
        lengthValue = NaN;
        ok          = false;
        return;
    end

    if usedDefault
        warning( ...
            ['Default dimensions applied: Section %g, %s, %s, Sample %g ' ...
             '(area = %.4f mm^2, length = %.4f mm)'], ...
            sectionNumber, materialName, testName, sampleNumber, ...
            area, lengthValue);
    end

    if ~isfinite(area) || ~isfinite(lengthValue) || ...
            area <= 0 || lengthValue <= 0

        warning( ...
            'Invalid dimensions even after defaults: Section %g, %s, %s, Sample %g', ...
            sectionNumber, materialName, testName, sampleNumber);

        ok = false;
    end
end

%% ------------------------------------------------------------------------
function value = safeNumber(row, columnName)

    if ismember(columnName, row.Properties.VariableNames)
        value = str2double(string(row.(columnName)(1)));
    else
        value = NaN;
    end
end

%% ========================================================================
%% Data cursor callback: report the source CSV
%% ========================================================================

function txt = showCSV(~,event)

    h = get(event,'Target');

    csvPath = h.UserData;

    fprintf('\n=================================================\n');
    fprintf('CSV File:\n%s\n', csvPath);
    fprintf('=================================================\n\n');

    txt = {'CSV File' char(csvPath)};
end