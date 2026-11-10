function figureFiles = plotTension(opts)
%PLOTTENSION Averaged tension stress-strain figures (mean +/- 1 SD).
%
%   plotTension()                     uses the default processed workbook
%   plotTension(Name=Value)           see options below
%
%   Reads only the workbook made by prepareData (Specimens + Tension sheets)
%   and saves, in <repo>/Figures/Tension:
%     Tension_AP<ratio>_<year>_<CNT|NEAT>.png   one per AP loading and material:
%         faint specimen curves, mean, shaded +/-1 SD band, every fracture
%         point and the mean fracture point +/-1 SD
%     Tension_<CNT|NEAT>_AP_Comparison.png      all AP loadings on one plot
%   plus ProcessedData/Tension_Averages.xlsx (summary, averaged curves and
%   flagged specimens). Year -> AP % is set in private/apRatio.m; bad
%   tests are left out by listing them in private/excludedSpecimens.m.
%
%   Each mean curve averages the same specimens from 0 to the strain that
%   at least MinFraction of them reach (here: are still intact at), so it
%   never jumps when a coupon breaks. See private/averageCurves.m.
%
%   Options
%     ProcessedFile      workbook to read (default <repo>/ProcessedData/JuniorLab_ProcessedData.xlsx)
%     OutputFolder       where the PNGs go (default <repo>/Figures/Tension)
%     SummaryFile        averages workbook (default <repo>/ProcessedData/Tension_Averages.xlsx)
%     StrainLimit        crop / x-axis upper limit (default 0.2)
%     MinFraction        share of specimens the mean must keep (default 0.75;
%                        1 = range shared by every specimen, as in the old code)
%     YLimit             [ymin ymax] in MPa; [] = automatic (default)
%     APRatios           e.g. [40 70]; [] = every AP loading in the workbook
%     Years              e.g. [2025 2026]; [] = every year in the workbook
%     Materials          default ["CNT","NEAT"]
%     ShowSpecimens      draw the faint specimen curves (default true)
%     ShowFigures        keep figures open to hover over curves (default false)
%     IncludeDuplicates  also use CSVs flagged as copies (default false)
%     RemoveOutliers     leave out specimens whose peak or position of the
%                        peak is more than 3 scaled MADs from their group's
%                        median (isoutlier) (default true)
%     NumSpecimens       specimens kept per AP loading and material: the
%                        ones closest to the group median (default 13;
%                        Inf = all). Left-out specimens are in the Removed
%                        sheet. See private/selectSpecimens.m
%
%   Example
%     plotTension(APRatios=[40 70], ShowFigures=true)

arguments
    opts.ProcessedFile     (1,1) string = ""
    opts.OutputFolder      (1,1) string = ""
    opts.SummaryFile       (1,1) string = ""
    opts.StrainLimit       (1,1) double {mustBePositive} = 0.2
    opts.MinFraction       (1,1) double = 0.75
    opts.YLimit            double = []
    opts.APRatios          double = []
    opts.Years             double = []
    opts.Materials         (1,:) string = ["CNT", "NEAT"]
    opts.ShowSpecimens     (1,1) logical = true
    opts.ShowFigures       (1,1) logical = false
    opts.IncludeDuplicates (1,1) logical = false
    opts.RemoveOutliers    (1,1) logical = true
    opts.NumSpecimens      (1,1) double {mustBePositive} = 13
end

p = pipelinePaths();
if opts.ProcessedFile == "", opts.ProcessedFile = p.ProcessedFile;                                  end
if opts.OutputFolder  == "", opts.OutputFolder  = fullfile(p.Figures, 'Tension');                    end
if opts.SummaryFile   == "", opts.SummaryFile   = fullfile(p.ProcessedDir, 'Tension_Averages.xlsx'); end

opts.XLimit = opts.StrainLimit;
figureFiles = plotAveragedCurves("Tension", opts);
end
