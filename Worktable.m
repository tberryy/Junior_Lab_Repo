clear; clc;

%% Main folder
mainFolder = 'JUNIOR LAB SPRING 2026';

files = dir(fullfile(mainFolder,'**','*.csv'));

if isempty(files)
    error('No CSV files found.');
end

CNT = {};
NEAT = {};

for i = 1:length(files)

    [~,name,~] = fileparts(files(i).name);
    parts = split(name,'_');

    if numel(parts) < 4
        continue
    end

    test = upper(string(parts(1)));
    section = string(parts(2));
    material = upper(string(parts(3)));
    sample = string(parts(4));

    row = {section,...
        test,...
        sample,...
        NaN,...   % Width
        NaN,...   % Thickness
        NaN,...   % Diameter
        NaN,...   % Gauge Length
        NaN,...   % Notch Length
        NaN};     % Pre-crack Length

    if material == "CNT"
        CNT(end+1,:) = row;
    elseif material == "NEAT"
        NEAT(end+1,:) = row;
    end

end

%% Convert to tables

varNames = {'Section','Test','Sample',...
    'Width_mm','Thickness_mm','Diameter_mm',...
    'GaugeLength_mm','NotchLength_mm','PreCrackLength_mm'};

CNT = cell2table(CNT,'VariableNames',varNames);
NEAT = cell2table(NEAT,'VariableNames',varNames);

CNT = sortrows(CNT,{'Section','Test','Sample'});
NEAT = sortrows(NEAT,{'Section','Test','Sample'});

%% Remove duplicate rows
[~,idx] = unique(CNT(:,{'Section','Test','Sample'}),'rows');
CNT = CNT(idx,:);

[~,idx] = unique(NEAT(:,{'Section','Test','Sample'}),'rows');
NEAT = NEAT(idx,:);

%% Write Excel workbook
filename = 'Specimen_Dimensions.xlsx';

writetable(CNT,filename,'Sheet','CNT');
writetable(NEAT,filename,'Sheet','NEAT');

disp('Workbook created successfully!');