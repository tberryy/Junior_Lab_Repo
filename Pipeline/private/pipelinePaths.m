function p = pipelinePaths()
%PIPELINEPATHS Standard repo locations, resolved from where this file lives.
%   Works no matter what MATLAB's current folder is.
%
%   <repo>/Pipeline/private/pipelinePaths.m  ->  <repo>

here = fileparts(mfilename('fullpath'));          % <repo>/Pipeline/private
p.Root          = fileparts(fileparts(here));     % <repo>
p.Organized     = fullfile(p.Root, 'OrganizedData');
p.ProcessedDir  = fullfile(p.Root, 'ProcessedData');
p.ProcessedFile = fullfile(p.ProcessedDir, 'JuniorLab_ProcessedData.xlsx');
p.Figures       = fullfile(p.Root, 'Figures');
end
