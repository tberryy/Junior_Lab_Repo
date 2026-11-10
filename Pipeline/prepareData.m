function processedFile = prepareData(opts)
%PREPAREDATA Build the processed-data workbook that the plotting functions read.
%
%   processedFile = prepareData()
%   processedFile = prepareData(Name=Value)
%
%   Walks OrganizedData/<year>_organized/<batch>/<day>/<group>/ and, for every
%   tension, compression and fracture (compact-tension) CSV:
%     - labels it CNT or NEAT: from the filename when the group's names are
%       unambiguous (cnt / epoxy), otherwise highest max force in the group
%       folder = CNT (the old classifyFileListByMaxForce rule)
%     - flags CSVs that are copies of one already seen (DuplicateOf column);
%       the organizer has copied the same test into several folders
%     - looks up its dimensions in SpecimenDimensions<year>.xlsx, using the
%       sheet that matches the batch folder (batch1 / batch2)
%     - converts it to a stress-strain curve (tension up to fracture,
%       compression up to the end of the test), or for fracture to a
%       toe-compensated force-displacement curve up to peak load
%       (private/toForceDisplacement.m)
%     - keeps compact-tension (fracture) files out of tension, including
%       those with "Tension" in their name
%
%   Output workbook (default <repo>/ProcessedData/JuniorLab_ProcessedData.xlsx)
%     Specimens    one row per CSV: year and AP loading (private/apRatio.m),
%                  where it came from, classification,
%                  dimensions, peak stress, and a Status column
%                  ("ok" rows are the ones that get plotted)
%     Tension      SpecimenID, Displacement_mm, Force_N, Strain, Stress_MPa
%     Compression  same columns
%     Fracture     SpecimenID, Displacement_mm, Force_N
%     Settings     options used and when the file was made
%
%   Options
%     OrganizedFolder  folder holding the <year>_organized folders
%                      (default <repo>/OrganizedData)
%     OutputFile       workbook to write (default above)
%     Tests            tests to process (default ["Tension","Compression","Fracture"])
%     Days             day folders to read, in plotting order
%     CNTPerGroup      tension / compression: how many of the highest-force
%                      files in each group folder are CNT (default 1)
%     FractureCNTPerGroup   same for fracture (default 4: 4 CNT + 4 NEAT)
%     MaxPeakDisplacement   fracture specimens peaking beyond this many mm
%                      are marked as bad tests (default 4, the original rule)
%
%   Example
%     prepareData();                              % everything, defaults
%     prepareData(Tests="Compression");           % compression only

arguments
    opts.OrganizedFolder (1,1) string = ""
    opts.OutputFile      (1,1) string = ""
    opts.Tests           (1,:) string = ["Tension", "Compression", "Fracture"]
    opts.Days            (1,:) string = ["monday","tuesday","wednesday","thursday","friday"]
    opts.CNTPerGroup     (1,1) double {mustBeInteger, mustBeNonnegative} = 1
    opts.FractureCNTPerGroup (1,1) double {mustBeInteger, mustBeNonnegative} = 4
    opts.MaxPeakDisplacement (1,1) double {mustBePositive} = 4
end

p = pipelinePaths();
if opts.OrganizedFolder == "", opts.OrganizedFolder = p.Organized;     end
if opts.OutputFile      == "", opts.OutputFile      = p.ProcessedFile; end

if ~isfolder(opts.OrganizedFolder)
    error('prepareData:noFolder', 'Organized data folder not found: %s', ...
        opts.OrganizedFolder);
end

% "tension" / "TENSION" -> "Tension"
tests = upper(extractBefore(opts.Tests, 2)) + lower(extractAfter(opts.Tests, 1));

records = struct([]);
curves  = struct();
for t = tests
    curves.(t) = {};
end
specimenID = 0;
seen = containers.Map('KeyType', 'char', 'ValueType', 'double');   % raw-data fingerprint -> first SpecimenID

%% ---------------------------------------------------------------- years
yearDirs = listFolders(opts.OrganizedFolder, '*_organized');

for y = 1:numel(yearDirs)

    yearName  = yearDirs(y);
    yearLabel = erase(yearName, "_organized");
    yearValue = str2double(yearLabel);
    yearPath  = fullfile(opts.OrganizedFolder, yearName);
    dimsFile  = fullfile(yearPath, "SpecimenDimensions" + yearLabel + ".xlsx");

    fprintf('\n%s\n', yearName);

    %% ------------------------------------------------------------ batches
    batchDirs = listFolders(yearPath, 'batch*');

    for b = 1:numel(batchDirs)

        batchName = batchDirs(b);
        batchPath = fullfile(yearPath, batchName);
        dims = readDimensionSheet(dimsFile, batchName);

        %% -------------------------------------------------------- days
        for dayName = opts.Days

            dayPath = fullfile(batchPath, dayName);
            if ~isfolder(dayPath)
                continue;
            end

            groupDirs = listFolders(dayPath, '*');

            %% ---------------------------------------------------- groups
            for g = 1:numel(groupDirs)

                groupName = groupDirs(g);
                groupPath = fullfile(dayPath, groupName);
                sectionNumber = str2double(regexprep(groupName, '\D', ''));

                for testName = tests

                    files = findTestFiles(groupPath, testName);
                    nFiles = numel(files);
                    if nFiles == 0
                        continue;
                    end

                    % Read every file in the group, then rank by max force
                    raw = cell(nFiles, 1);
                    maxForce = NaN(nFiles, 1);
                    for k = 1:nFiles
                        data = readCSVNumeric(fullfile(files(k).folder, files(k).name));
                        if size(data, 2) >= 3 && any(isfinite(data(:, 3)))
                            raw{k} = data(:, 2:3);           % [Displacement, Force]
                            maxForce(k) = max(data(:, 3), [], 'omitnan');
                        else
                            raw{k} = zeros(0, 2);
                        end
                    end

                    isFracture = testName == "Fracture";
                    if isFracture
                        nCNT = opts.FractureCNTPerGroup;
                    else
                        nCNT = opts.CNTPerGroup;
                    end
                    [~, order] = sort(maxForce, 'descend', 'MissingPlacement', 'last');
                    [materials, materialSource] = classifyGroup( ...
                        string({files.name})', order, nCNT);
                    count = struct('CNT', 0, 'NEAT', 0);

                    for r = 1:nFiles

                        k = order(r);
                        material = materials(k);
                        count.(material) = count.(material) + 1;
                        sampleNumber = count.(material);
                        sampleName = material + "_" + sampleNumber;

                        dim = lookupDimensions(dims, sectionNumber, testName, ...
                                               material, sampleNumber);
                        if isFracture
                            c = toForceDisplacement(raw{k}(:, 1), raw{k}(:, 2), ...
                                                    opts.MaxPeakDisplacement);
                        else
                            c = toStressStrain(raw{k}(:, 1), raw{k}(:, 2), dim, testName);
                        end

                        specimenID = specimenID + 1;
                        filePath = string(fullfile(files(k).folder, files(k).name));

                        % Same raw record already seen in another folder?
                        fp = fingerprint(raw{k});
                        duplicateOf = NaN;
                        if fp ~= ""
                            if isKey(seen, char(fp))
                                duplicateOf = seen(char(fp));
                            else
                                seen(char(fp)) = specimenID;
                            end
                        end

                        rec = struct();
                        rec.SpecimenID      = specimenID;
                        rec.Year            = yearValue;
                        rec.APRatio_pct     = apRatio(yearValue);
                        rec.Batch           = batchName;
                        rec.Day             = dayName;
                        rec.Group           = groupName;
                        rec.Section         = sectionNumber;
                        rec.Test            = testName;
                        rec.Material        = material;
                        rec.SampleName      = sampleName;
                        rec.SampleNumber    = sampleNumber;
                        rec.MaterialSource  = materialSource;
                        rec.FilesInGroup    = nFiles;
                        rec.MaxForceRank    = r;
                        rec.DuplicateOf     = duplicateOf;
                        rec.Label           = string(sprintf('%s %s %s Sec %g %s', ...
                                                yearLabel, batchName, dayName, ...
                                                sectionNumber, sampleName));
                        rec.FilePath        = relativePath(filePath, p.Root);
                        rec.MaxForce_N      = maxForce(k);
                        rec.Width_mm        = dim.Width_mm;
                        rec.Thickness_mm    = dim.Thickness_mm;
                        rec.Diameter_mm     = dim.Diameter_mm;
                        rec.Length_mm       = dim.Length_mm;
                        rec.NotchLength_mm  = dim.NotchLength_mm;
                        rec.PreCrackLength_mm = dim.PreCrackLength_mm;
                        rec.CrackLength_mm  = dim.CrackLength_mm;
                        rec.Area_mm2        = dim.Area_mm2;
                        rec.DimensionSource = dim.Source;
                        rec.DimensionCheck  = dim.Check;
                        rec.PeakStress_MPa  = fieldOr(c, 'PeakStress_MPa');
                        rec.StrainAtPeak    = fieldOr(c, 'StrainAtPeak');
                        rec.PeakForce_N     = fieldOr(c, 'PeakForce_N');
                        rec.DisplacementAtPeak_mm = fieldOr(c, 'DisplacementAtPeak_mm');
                        rec.Energy_J        = fieldOr(c, 'Energy_J');
                        rec.ToeShift_mm     = fieldOr(c, 'ToeShift_mm');
                        rec.NumPoints       = numel(c.Displacement_mm);
                        rec.Status          = c.Status;

                        if isempty(records)
                            records = rec;
                        else
                            records(end+1) = rec; %#ok<AGROW>
                        end

                        if c.Status == "ok"
                            curves.(testName){end+1} = curveTable(specimenID, c, isFracture);
                        else
                            warning('prepareData:skipped', '%s (%s): %s', ...
                                rec.Label, testName, c.Status);
                        end
                    end
                end
            end
        end
        fprintf('  %s done (%d specimens so far)\n', batchName, specimenID);
    end
end

if isempty(records)
    error('prepareData:nothingFound', ...
        'No test CSVs found under %s', opts.OrganizedFolder);
end

specimens = struct2table(records(:));

%% ------------------------------------------------------------ write
processedFile = opts.OutputFile;
outDir = fileparts(processedFile);
if ~isfolder(outDir)
    mkdir(outDir);
end

if isfile(processedFile)
    delete(processedFile);
    if isfile(processedFile)
        error('prepareData:locked', ...
            'Could not overwrite %s. Close it in Excel and run again.', processedFile);
    end
end

fprintf('\nWriting %s ...\n', processedFile);
writetable(specimens, processedFile, 'Sheet', 'Specimens');

for testName = tests
    if isempty(curves.(testName))
        empty = struct('Displacement_mm', zeros(0, 1), 'Force_N', zeros(0, 1), ...
                       'Strain', zeros(0, 1), 'Stress_MPa', zeros(0, 1));
        sheet = curveTable(zeros(0, 1), empty, testName == "Fracture");
    else
        sheet = vertcat(curves.(testName){:});
    end
    writetable(sheet, processedFile, 'Sheet', char(testName));
end

settings = table( ...
    ["Created"; "OrganizedFolder"; "Tests"; "Days"; "CNTPerGroup"; "FractureCNTPerGroup"; ...
     "MaxPeakDisplacement_mm"; "MaterialRule"; "APRatioByYear"; "CurveEnd"], ...
    [string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')); ...
     opts.OrganizedFolder; strjoin(tests, ", "); strjoin(opts.Days, ", "); ...
     string(opts.CNTPerGroup); string(opts.FractureCNTPerGroup); ...
     string(opts.MaxPeakDisplacement); ...
     "Filename (CNT / NEAT / EPOXY) when every file in the group names one and both materials appear; otherwise the CNTPerGroup highest max-force files are CNT"; ...
     strjoin(compose("%d = %g%% AP", apRatio())', ", "); ...
     "Tension: up to peak stress (fracture). Compression: whole record to test stop. " + ...
     "Fracture: toe-compensated (10-40% of peak load line extrapolated to zero load), up to peak load; measured forces"], ...
    'VariableNames', {'Setting', 'Value'});
writetable(settings, processedFile, 'Sheet', 'Settings');

printSummary(specimens);
fprintf('Done: %s\n', processedFile);
end

%% ========================================================================
%% Local helpers
%% ========================================================================

function names = listFolders(parent, pattern)
% Sorted names of sub-folders of parent matching pattern (no . or ..)
d = dir(fullfile(parent, pattern));
d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
names = sort(string({d.name}));
end

function files = findTestFiles(groupPath, testName)
% CSVs for one test anywhere under a group folder.
% Compact-tension (fracture) records are never tension or compression:
% they are named Fracture_* or *Compact Tension*, or sit in a "fracture"
% folder. In 2025, 32 of them have "Tension" in the name (e.g.
% "Epoxy 4 Compact Tension_3_2.csv"), which the old filter counted as
% tension coupons.
allFiles = dir(fullfile(groupPath, '**', '*.csv'));
if isempty(allFiles)
    files = allFiles;
    return;
end
names   = upper(string({allFiles.name}));
folders = upper(string({allFiles.folder}));
below   = extractAfter(folders, strlength(string(groupPath)));   % sub-folders under the group
isFracture = contains(names, ["FRACTURE", "COMPACT"]) | ...
             contains(below, string(filesep) + "FRACTURE");
switch upper(testName)
    case "TENSION"
        pick = contains(names, "TENSION") & ~isFracture;
    case "COMPRESSION"
        pick = contains(names, "COMPRESSION") & ~isFracture;
    case "FRACTURE"
        pick = isFracture;
    otherwise
        error('prepareData:test', 'Unsupported test "%s".', testName);
end
files = allFiles(pick);
end

function [materials, source] = classifyGroup(fileNames, order, nCNT)
% CNT / NEAT for every file in one group folder.
% 1) Filename, when it is unambiguous: every file says CNT or NEAT/EPOXY
%    and both materials appear (e.g. compression_cnt_2_2 / compression_epoxy_1_2).
% 2) Otherwise the old rule: the nCNT highest max-force files are CNT.
n = numel(fileNames);
upperNames = upper(fileNames);
hints = strings(n, 1);
hints(contains(upperNames, "CNT")) = "CNT";
hints(contains(upperNames, ["NEAT", "EPOXY"]) & hints == "") = "NEAT";

if all(hints ~= "") && any(hints == "CNT") && any(hints == "NEAT")
    materials = hints;
    source = "filename";
else
    materials = repmat("NEAT", n, 1);
    materials(order(1:min(nCNT, n))) = "CNT";
    source = "max force rank";
end
end

function fp = fingerprint(dispForce)
% Cheap content signature of a raw record, used to spot the same CSV
% copied into several group/batch folders.
if isempty(dispForce)
    fp = "";
    return;
end
ok = all(isfinite(dispForce), 2);
d = dispForce(ok, 1);
F = dispForce(ok, 2);
fp = string(sprintf('%d|%.8g|%.8g|%.8g', numel(F), sum(F), max(F), sum(d)));
end

function T = curveTable(specimenID, c, isFracture)
% Rows of one specimen for the test's curve sheet
n = numel(c.Displacement_mm);
id = repmat(specimenID, n, 1);
if isFracture
    T = table(id, c.Displacement_mm, c.Force_N, ...
        'VariableNames', {'SpecimenID', 'Displacement_mm', 'Force_N'});
else
    T = table(id, c.Displacement_mm, c.Force_N, c.Strain, c.Stress_MPa, ...
        'VariableNames', {'SpecimenID', 'Displacement_mm', 'Force_N', 'Strain', 'Stress_MPa'});
end
end

function v = fieldOr(s, name)
% s.(name), or NaN when that result type does not have the field
if isfield(s, name)
    v = s.(name);
else
    v = NaN;
end
end

function rel = relativePath(fullPath, root)
% Path relative to the repo root, so the workbook works on any computer
prefix = string(root) + filesep;
rel = string(fullPath);
if startsWith(rel, prefix, 'IgnoreCase', ispc)
    rel = extractAfter(rel, strlength(prefix));
end
end

function printSummary(specimens)
fprintf('\nSummary (specimens plotted / found)\n');
keys = unique(specimens(:, {'Year', 'Test', 'Material'}));
for i = 1:height(keys)
    rows = specimens.Year == keys.Year(i) & ...
           specimens.Test == keys.Test(i) & ...
           specimens.Material == keys.Material(i);
    nOk = sum(rows & specimens.Status == "ok");
    fprintf('  %d  %-12s %-5s %3d / %3d\n', keys.Year(i), keys.Test(i), ...
        keys.Material(i), nOk, sum(rows));
end

nMedian = sum(startsWith(specimens.DimensionSource, "sheet median"));
nCheck  = sum(specimens.DimensionCheck ~= "");
nSingle = sum(specimens.FilesInGroup == 1 & specimens.MaterialSource ~= "filename");
nDup    = sum(isfinite(specimens.DuplicateOf));
fprintf('\n  %d used sheet-median dimensions (see DimensionSource)\n', nMedian);
fprintf('  %d have dimensions >25%% off the sheet median (see DimensionCheck)\n', nCheck);
fprintf('  %d came from a group with a single file, so CNT/NEAT is a guess (FilesInGroup = 1)\n', nSingle);
fprintf('  %d are byte-for-byte copies of an earlier specimen (DuplicateOf); plots skip them by default\n\n', nDup);
end
