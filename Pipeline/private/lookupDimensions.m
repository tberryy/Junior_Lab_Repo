function dim = lookupDimensions(dims, sectionNumber, testName, materialName, sampleNumber)
%LOOKUPDIMENSIONS Specimen dimensions for one specimen.
%
%   Tension:      Area = Width_mm * Thickness_mm,   Length = GaugeLength_mm
%   Compression:  Area = pi/4 * Diameter_mm^2,      Length = Length_mm
%   Fracture (compact tension, ASTM D5045 / E399 notation):
%                 W = Width_mm, B = Thickness_mm,
%                 a = NotchLength_mm + PreCrackLength_mm   (CrackLength_mm)
%                 Area = ligament area B * (W - a)
%
%   Matching row: same Section, Test, Material and Sample in the batch sheet.
%   If the row is missing or a cell is blank, the median of that test's rows
%   in the same sheet is used and Source says so. (The old hard-coded
%   defaults were fracture-specimen values: 9.48 x 0.71 mm, 14.25 mm gauge,
%   which are ~10x off for the tension coupons.)
%
%   Check flags a specimen whose area or length (crack length for fracture)
%   is more than 25 % away from the sheet median, which usually means a typo
%   in the workbook.

dim = struct('Width_mm', NaN, 'Thickness_mm', NaN, 'Diameter_mm', NaN, ...
             'Length_mm', NaN, 'NotchLength_mm', NaN, 'PreCrackLength_mm', NaN, ...
             'CrackLength_mm', NaN, 'Area_mm2', NaN, ...
             'Source', "missing", 'Check', "");

if isempty(dims) || height(dims) == 0
    return;
end

testKey = upper(string(testName));

switch testKey
    case "TENSION"
        cols = ["Width_mm", "Thickness_mm", "GaugeLength_mm"];
    case "COMPRESSION"
        cols = ["Diameter_mm", "Length_mm"];
    case "FRACTURE"
        cols = ["Width_mm", "Thickness_mm", "NotchLength_mm", "PreCrackLength_mm"];
    otherwise
        error('lookupDimensions:test', 'Unsupported test "%s".', testName);
end

pool = dims(dims.Test == testKey, :);

row = pool( ...
    pool.Section  == sectionNumber & ...
    pool.Material == upper(string(materialName)) & ...
    pool.Sample   == sampleNumber, :);

vals = NaN(1, numel(cols));
usedMedian = false;

for k = 1:numel(cols)
    % a pre-crack of 0 mm is a real value; every other dimension must be > 0
    if cols(k) == "PreCrackLength_mm"
        isValid = @(v) isfinite(v) & v >= 0;
    else
        isValid = @(v) isfinite(v) & v > 0;
    end
    v = NaN;
    if height(row) >= 1
        v = row.(cols(k))(1);
    end
    if ~isValid(v)
        poolVals = pool.(cols(k));
        poolVals = poolVals(isValid(poolVals));
        if ~isempty(poolVals)
            v = median(poolVals);
        end
        usedMedian = true;
    end
    vals(k) = v;
end

if any(~isfinite(vals))
    return;                                   % Source stays "missing"
end

if height(row) == 0
    dim.Source = "sheet median (no row)";
elseif usedMedian
    dim.Source = "sheet median (blank cell)";
else
    dim.Source = "measured";
end

% Area, length and the same quantities for every row in the sheet
switch testKey
    case "TENSION"
        dim.Width_mm     = vals(1);
        dim.Thickness_mm = vals(2);
        dim.Length_mm    = vals(3);
        dim.Area_mm2     = vals(1) * vals(2);
        lengthValue = dim.Length_mm;
        poolArea   = pool.Width_mm .* pool.Thickness_mm;
        poolLength = pool.GaugeLength_mm;
    case "COMPRESSION"
        dim.Diameter_mm  = vals(1);
        dim.Length_mm    = vals(2);
        dim.Area_mm2     = pi / 4 * vals(1)^2;
        lengthValue = dim.Length_mm;
        poolArea   = pi / 4 * pool.Diameter_mm.^2;
        poolLength = pool.Length_mm;
    case "FRACTURE"
        dim.Width_mm          = vals(1);
        dim.Thickness_mm      = vals(2);
        dim.NotchLength_mm    = vals(3);
        dim.PreCrackLength_mm = vals(4);
        dim.CrackLength_mm    = vals(3) + vals(4);
        dim.Area_mm2          = vals(2) * (vals(1) - dim.CrackLength_mm);
        lengthValue = dim.CrackLength_mm;
        poolCrack  = pool.NotchLength_mm + pool.PreCrackLength_mm;
        poolArea   = pool.Thickness_mm .* (pool.Width_mm - poolCrack);
        poolLength = poolCrack;
end

% Sanity check against the sheet median
notes = strings(0);
medArea   = median(poolArea(isfinite(poolArea) & poolArea > 0));
medLength = median(poolLength(isfinite(poolLength) & poolLength > 0));

if isfinite(medArea) && abs(dim.Area_mm2 / medArea - 1) > 0.25
    notes(end+1) = sprintf('area %+.0f%% vs median', 100 * (dim.Area_mm2 / medArea - 1));
end
if isfinite(medLength) && abs(lengthValue / medLength - 1) > 0.25
    notes(end+1) = sprintf('length %+.0f%% vs median', 100 * (lengthValue / medLength - 1));
end
if ~isempty(notes)
    dim.Check = strjoin(notes, "; ");
end
end
