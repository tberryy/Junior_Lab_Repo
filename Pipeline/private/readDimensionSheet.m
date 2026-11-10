function dims = readDimensionSheet(dimsFile, batchName)
%READDIMENSIONSHEET Read the SpecimenDimensions<year>.xlsx sheet for one batch.
%   The workbook has one sheet per batch (batch1, batch2). The old script read
%   only the first sheet, so batch2 specimens were matched against batch1
%   measurements. This reads the sheet whose name matches the batch folder.
%
%   Returns an empty table when the file is missing. Text columns are
%   normalised to upper-case strings and numeric columns to double.

dims = table();

if ~isfile(dimsFile)
    warning('prepareData:noDimensionFile', ...
        'Dimension file not found: %s', dimsFile);
    return;
end

sheets = sheetnames(dimsFile);
match  = sheets(strcmpi(sheets, batchName));

if isempty(match)
    sheet = sheets(1);
    warning('prepareData:noBatchSheet', ...
        'No sheet "%s" in %s. Using sheet "%s".', batchName, dimsFile, sheet);
else
    sheet = match(1);
end

dims = readtable(dimsFile, 'Sheet', sheet, 'VariableNamingRule', 'preserve');

% Column 2 holds cnt/neat but has no header in the workbooks
names = dims.Properties.VariableNames;
if ~ismember('Material', names)
    dims.Properties.VariableNames{2} = 'Material';
end

dims.Material = upper(strtrim(string(dims.Material)));
dims.Test     = upper(strtrim(string(dims.Test)));
dims.Section  = toNumber(dims.Section);
dims.Sample   = toNumber(dims.Sample);

numericCols = ["Width_mm","Thickness_mm","GaugeLength_mm", ...
               "Diameter_mm","Length_mm","NotchLength_mm","PreCrackLength_mm"];

for c = numericCols
    if ismember(c, dims.Properties.VariableNames)
        dims.(c) = toNumber(dims.(c));
    else
        dims.(c) = NaN(height(dims), 1);
    end
end
end

function v = toNumber(x)
if isnumeric(x)
    v = double(x);
else
    v = str2double(string(x));
end
end
