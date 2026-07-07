clear; clc; close all;

%% Main folder
mainFolder = pwd;
dimensionFile = fullfile(mainFolder,'Specimen_Dimensions.xlsx');

%% Read dimension sheets
dimsCNT = readtable(dimensionFile,'Sheet','CNT');
dimsNEAT = readtable(dimensionFile,'Sheet','NEAT');

%% Output folder
outputFolder = fullfile(mainFolder,'All_Days_Stress_Strain_Graphs');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% Day folders
dayFolders = {'ALL_MONDAY','ALL_TUESDAY','ALL_WEDNESDAY','ALL_THURSDAY','ALL_FRIDAY'};
dataFolders = {'data_runs_Monday','data_runs_Tuesday','data_runs_Wednesday','data_runs_Thursday','data_runs_Friday'};
dayLabels = {'Monday','Tuesday','Wednesday','Thursday','Friday'};

%% Collect CSV files
files = [];

for d = 1:length(dayFolders)

    folderPath = fullfile(mainFolder,dayFolders{d},dataFolders{d});

    fprintf('Searching: %s\n',folderPath);

    temp = dir(fullfile(folderPath,'*.csv'));
    fprintf('  Found %d CSV files\n',length(temp))

    for k = 1:length(temp)
        temp(k).dayLabel = dayLabels{d};
    end

    files = [files; temp];

end

fprintf('\nTotal CSV files found: %d\n\n',length(files));

%% Materials and tests
materials = {'CNT','NEAT'};
tests = {'TENSION','COMPRESSION','FRACTURE'};

%% Generate 6 graphs
for m = 1:length(materials)

    materialWanted = string(materials{m});

    for t = 1:length(tests)

        testWanted = string(tests{t});

        fig = figure;
        hold on; grid on;

        xlabel('Strain');
        ylabel('Stress (MPa)');
        title(sprintf('%s %s Stress vs Strain - All Days', ...
            materialWanted,testWanted));

        plotCount = 0;

        for i = 1:length(files)

            fileName = files(i).name;
            filePath = fullfile(files(i).folder,fileName);
            dayLabel = files(i).dayLabel;

            [~,baseName,~] = fileparts(fileName);

            tokens = regexp(baseName, ...
                '^(Tension|Compression|Fracture)_?(\d{5})_(CNT|NEAT)_(\d+)$', ...
                'tokens','once','ignorecase');

            if isempty(tokens)
                continue
            end

            test = upper(string(tokens{1}));
            section = string(tokens{2});
            material = upper(string(tokens{3}));
            sample = string(tokens{4});

            if test ~= testWanted || material ~= materialWanted
                continue
            end

            %% Lookup dimensions
            [area,L0,isValid] = lookupDimensions( ...
                dimsCNT,dimsNEAT,section,material,test,sample);

            if ~isValid
                warning('Missing dimensions for %s',fileName);
                continue
            end

            %% Read CSV
            % CSV has:
            % blank row
            % header row
            % units row
            % numeric data starts after 3 lines
            data = readmatrix(filePath,'NumHeaderLines',3);

            displacement = data(:,2);   % mm
            force = data(:,3);          % N

            valid = ~isnan(displacement) & ~isnan(force);
            displacement = displacement(valid);
            force = force(valid);

            if isempty(displacement)
                continue
            end

            %% Stress and strain
            strain = displacement ./ L0;
            stress = force ./ area;

            %% Plot
            plot(strain,stress,'LineWidth',1.1, ...
                'DisplayName',sprintf('%s S%s-%s',dayLabel,section,sample));

            plotCount = plotCount + 1;

        end

        fprintf('%s %s curves plotted: %d\n', ...
            materialWanted,testWanted,plotCount);

        if plotCount > 0
            legend('Location','bestoutside');

            saveBase = sprintf('%s_%s_All_Days_Stress_Strain', ...
                materialWanted,testWanted);

            saveas(fig,fullfile(outputFolder,[char(saveBase) '.png']));
            savefig(fig,fullfile(outputFolder,[char(saveBase) '.fig']));
        else
            close(fig);
        end

    end
end

disp('Finished creating 6 stress-strain graphs.');

%% ============================================================
%% Functions
%% ============================================================

function [area,L0,isValid] = lookupDimensions(dimsCNT,dimsNEAT,section,material,test,sample)

    area = NaN;
    L0 = NaN;
    isValid = false;

    if material == "CNT"
        dims = dimsCNT;
    elseif material == "NEAT"
        dims = dimsNEAT;
    else
        return
    end

    row = dims( ...
        string(dims.Section) == section & ...
        upper(string(dims.Test)) == test & ...
        string(dims.Sample) == sample,:);

    if isempty(row)
        return
    end

    if test == "COMPRESSION"

    diameter = getValue(row,"Diameter");
    L0 = getValue(row,"GaugeLength");

    if isnan(L0)
        L0 = getValue(row,"Length");
    end

    if isnan(diameter) || isnan(L0)
        return
    end

    area = pi*(diameter/2)^2;

elseif test == "FRACTURE"

    width = getValue(row,"Width");
    thickness = getValue(row,"Thickness");
    notchLength = getValue(row,"NotchLength");
    preCrackLength = getValue(row,"PreCrackLength");

    if isnan(width) || isnan(thickness) || isnan(notchLength) || isnan(preCrackLength)
        return
    end

    area = width * thickness;
    L0 = notchLength;

else

    width = getValue(row,"Width");
    thickness = getValue(row,"Thickness");

    L0 = getValue(row,"GaugeLength");

    if isnan(L0)
        L0 = getValue(row,"Length");
    end

    if isnan(width) || isnan(thickness) || isnan(L0)
        return
    end

    area = width * thickness;

end

    isValid = true;

end

function value = getValue(row,baseName)

    value = NaN;

    names = string(row.Properties.VariableNames);
    cleanNames = lower(regexprep(names,'[^a-zA-Z0-9]',''));
    cleanBase = lower(regexprep(baseName,'[^a-zA-Z0-9]',''));

    idx = contains(cleanNames,cleanBase);

    if any(idx)
        temp = row{1,find(idx,1)};

        if isnumeric(temp)
            value = temp;
        else
            value = str2double(string(temp));
        end
    end

end