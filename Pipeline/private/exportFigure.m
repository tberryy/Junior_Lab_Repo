function savedFile = exportFigure(fig, outFile)
%EXPORTFIGURE Save a figure as PNG (300 dpi) or vector PDF, by extension.
%   savedFile = exportFigure(fig, outFile)
%
%   If the file cannot be written (usually because it is open in an image
%   viewer or being synced by OneDrive), retries three times, then saves it
%   under a timestamped name next to it and warns, so the run carries on.

outFile = string(outFile);
if endsWith(outFile, ".pdf", 'IgnoreCase', true)
    args = {'ContentType', 'vector'};
else
    args = {'Resolution', 300};
end

for attempt = 1:3
    try
        exportgraphics(fig, outFile, args{:});
        savedFile = outFile;
        return;
    catch err
        lastErr = err;
        pause(0.5);
    end
end

[folder, name, ext] = fileparts(outFile);
savedFile = string(fullfile(folder, name + "_" + string(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) + ext));
warning('plot:fileLocked', ['Could not write %s (%s).\n' ...
        'Close it if it is open in another program. Saved to %s instead.'], ...
        outFile, lastErr.message, savedFile);
exportgraphics(fig, savedFile, args{:});
end
