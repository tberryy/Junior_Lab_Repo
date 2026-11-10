function ap = apRatio(year)
%APRATIO AP loading (%) used for each Junior Lab year.
%   ap  = apRatio(year)   AP % for each year (NaN if the year is not listed)
%   map = apRatio()       the whole table as [year, AP%] rows
%
%   This is the only place the year -> AP relationship is defined.
%   Add a row here when a new year's samples are made.

map = [ 2024  40
        2025  50
        2023  60
        2026  70 ];

if nargin == 0
    ap = sortrows(map, 2);
    return;
end

ap = NaN(size(year));
for i = 1:numel(year)
    k = find(map(:, 1) == year(i), 1);
    if ~isempty(k)
        ap(i) = map(k, 2);
    end
end
end
