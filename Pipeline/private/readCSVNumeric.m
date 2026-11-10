function data = readCSVNumeric(filePath)
%READCSVNUMERIC Read an instrument CSV export as a numeric matrix.
%   Expected layout (Instron/Bluehill export):
%       Time,Displacement,Force      <- header
%       (s),(mm),(N)                 <- units
%       "0.0000","0.0000","-0.0061"  <- quoted numbers
%   Columns that come in as text are converted with str2double.

opts = detectImportOptions(filePath);
opts.DataLines = [3 Inf];          % skip header and units rows

T = readtable(filePath, opts);

data = NaN(height(T), width(T));
for c = 1:width(T)
    col = T{:, c};
    if isnumeric(col)
        data(:, c) = col;
    else
        data(:, c) = str2double(string(col));
    end
end
end
