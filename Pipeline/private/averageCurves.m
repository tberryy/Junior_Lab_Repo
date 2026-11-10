function avg = averageCurves(strains, stresses, cropStrain, minFraction, nPoints)
%AVERAGECURVES Mean and standard deviation of stress-strain curves.
%
%   avg = averageCurves(strains, stresses, cropStrain, minFraction, nPoints)
%     strains, stresses  cell arrays, one column vector per specimen
%     cropStrain         right edge of the plot window (e.g. 0.15)
%     minFraction        share of specimens the mean must keep (0-1]
%     nPoints            points on the common strain grid (default 500)
%
%   Method (same idea as the original yearly-average code, without its jumps)
%     1. The mean curve runs from 0 to XEnd, the largest strain that at
%        least ceil(minFraction * n) specimens reach (capped at cropStrain).
%     2. Only the specimens that reach XEnd are averaged, so every point of
%        the curve is the mean of the SAME specimens. In the original
%        compression average a short test dropping out made the mean jump.
%     3. Each of those curves is linearly interpolated onto a common grid
%        of nPoints strains; mean and sample SD (N-1) are taken point by
%        point. SD is NaN when fewer than 2 specimens are averaged.
%   minFraction = 1 reproduces the original tension average (range shared
%   by every specimen).
%
%   avg fields
%     Strain, Mean, SD   column vectors on the common grid (MPa for stress)
%     XEnd               end strain of the mean curve
%     N                  specimens averaged
%     NTotal             specimens with usable data
%     Included           logical, one per input curve: true if averaged

if nargin < 5 || isempty(nPoints)
    nPoints = 500;
end

n = numel(strains);
ends = NaN(n, 1);
for j = 1:n
    e = strains{j}(:);
    s = stresses{j}(:);
    ok = isfinite(e) & isfinite(s);
    if nnz(ok) >= 2
        ends(j) = max(e(ok));
    end
end

usable = isfinite(ends) & ends > 0;
nUsable = nnz(usable);

avg = struct('Strain', zeros(0, 1), 'Mean', zeros(0, 1), 'SD', zeros(0, 1), ...
             'XEnd', NaN, 'N', 0, 'NTotal', nUsable, 'Included', false(n, 1));
if nUsable == 0
    return;
end

% End of the mean curve: strain reached by at least `need` specimens
need = max(min(2, nUsable), ceil(minFraction * nUsable));
sortedEnds = sort(ends(usable), 'descend');
xEnd = min(sortedEnds(need), cropStrain);

included = usable & ends >= xEnd;
idx = find(included);

x = linspace(0, xEnd, nPoints)';
Y = NaN(nPoints, numel(idx));

for c = 1:numel(idx)
    e = strains{idx(c)}(:);
    s = stresses{idx(c)}(:);
    ok = isfinite(e) & isfinite(s);
    e = e(ok);
    s = s(ok);
    [e, order] = sort(e);
    s = s(order);
    [e, firstIdx] = unique(e);          % interp1 needs distinct strains
    s = s(firstIdx);
    if numel(e) >= 2
        Y(:, c) = interp1(e, s, x, 'linear', NaN);
    end
end

count = sum(isfinite(Y), 2);
meanY = mean(Y, 2, 'omitnan');
sdY   = std(Y, 0, 2, 'omitnan');
sdY(count < 2) = NaN;

avg.Strain   = x;
avg.Mean     = meanY;
avg.SD       = sdY;
avg.XEnd     = xEnd;
avg.N        = numel(idx);
avg.Included = included;
end
