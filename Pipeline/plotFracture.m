function figureFiles = plotFracture(opts)
%PLOTFRACTURE Averaged compact-tension (fracture) force-displacement figures.
%
%   plotFracture()                    uses the default processed workbook
%   plotFracture(Name=Value)          see options below
%
%   Reads only the workbook made by prepareData (Specimens + Fracture sheets)
%   and saves, in <repo>/Figures/Fracture:
%     Fracture_AP<ratio>_<year>_<CNT|NEAT>.png   one per AP loading and material:
%         faint specimen curves, mean, shaded +/-1 SD band, every specimen's
%         peak load and the mean peak +/-1 SD
%     Fracture_<CNT|NEAT>_AP_Comparison.png      all AP loadings on one plot
%   plus ProcessedData/Fracture_Averages.xlsx (summary, averaged curves and
%   flagged specimens). K_Ic and G_Ic come from plotFractureToughness.
%
%   Curves are toe-compensated and run to peak load (see
%   private/toForceDisplacement.m). Each mean curve averages the same
%   specimens from 0 to the displacement that at least MinFraction of them
%   reach, so it never jumps when a specimen fails. See private/averageCurves.m.
%
%   Options
%     ProcessedFile      workbook to read (default <repo>/ProcessedData/JuniorLab_ProcessedData.xlsx)
%     OutputFolder       where the PNGs go (default <repo>/Figures/Fracture)
%     SummaryFile        averages workbook (default <repo>/ProcessedData/Fracture_Averages.xlsx)
%     DisplacementLimit  crop / x-axis upper limit in mm (default 3.5, as in the old code)
%     MinFraction        share of specimens the mean must keep (default 0.75)
%     YLimit             [ymin ymax] in N; [] = automatic (default)
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
%     plotFracture(DisplacementLimit=1.5, APRatios=50, ShowFigures=true)

arguments
    opts.ProcessedFile     (1,1) string = ""
    opts.OutputFolder      (1,1) string = ""
    opts.SummaryFile       (1,1) string = ""
    opts.DisplacementLimit (1,1) double {mustBePositive} = 3.5
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
if opts.ProcessedFile == "", opts.ProcessedFile = p.ProcessedFile;                                   end
if opts.OutputFolder  == "", opts.OutputFolder  = fullfile(p.Figures, 'Fracture');                    end
if opts.SummaryFile   == "", opts.SummaryFile   = fullfile(p.ProcessedDir, 'Fracture_Averages.xlsx'); end

opts.XLimit = opts.DisplacementLimit;
figureFiles = plotAveragedCurves("Fracture", opts);
end
