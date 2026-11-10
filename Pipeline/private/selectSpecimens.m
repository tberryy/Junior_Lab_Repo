function [kept, dropped] = selectSpecimens(specimens, testName, numPerGroup, removeOutliers)
%SELECTSPECIMENS Keep the most consistent specimens of each AP loading and material.
%   [kept, dropped] = selectSpecimens(specimens, testName, numPerGroup, removeOutliers)
%
%   Within each Year (= AP loading) and Material:
%     1) if removeOutliers, drop specimens whose peak value or position of
%        the peak is more than 3 scaled MADs from the group median
%        (isoutlier's default)
%     2) keep the numPerGroup specimens closest to the group median, where
%        distance = sqrt(zPeak^2 + zPosition^2) and z is the robust z-score
%        (value - median) / (1.4826 * MAD). Groups with fewer specimens keep
%        them all. numPerGroup = Inf keeps every specimen.
%
%   Peak value and position: peak stress and strain at peak for tension and
%   compression, peak force and displacement at peak for fracture.
%
%   dropped lists every specimen left out, with a Reason column.

switch lower(string(testName))
    case {"tension", "compression"}
        peakY = "PeakStress_MPa";
        peakX = "StrainAtPeak";
    case "fracture"
        peakY = "PeakForce_N";
        peakX = "DisplacementAtPeak_mm";
    otherwise
        error('select:test', 'Unsupported test "%s".', testName);
end

reason = strings(height(specimens), 1);
groups = findgroups(specimens.Year, specimens.Material);

for g = unique(groups)'
    rows = find(groups == g);
    y = specimens.(peakY)(rows);
    x = specimens.(peakX)(rows);

    if removeOutliers && numel(rows) >= 4
        outY = isoutlier(y);
        outX = isoutlier(x);
        reason(rows(outY | outX)) = "outlier";
        keep = ~(outY | outX);
        rows = rows(keep);
        y = y(keep);
        x = x(keep);
    end

    if numel(rows) <= numPerGroup
        continue;
    end

    distance = hypot(robustZ(y), robustZ(x));
    [~, order] = sort(distance);
    farther = rows(order(numPerGroup+1:end));
    reason(farther) = sprintf('not among the %d closest', numPerGroup);
end

kept = specimens(reason == "", :);
dropped = specimens(reason ~= "", :);
dropped.Reason = reason(reason ~= "");
end

function z = robustZ(v)
% Robust z-score; NaN counts as far away so it is chosen last
scale = 1.4826 * median(abs(v - median(v, 'omitnan')), 'omitnan');
if ~(scale > 0)
    scale = std(v, 'omitnan');
end
if ~(scale > 0)
    scale = 1;
end
z = (v - median(v, 'omitnan')) / scale;
z(~isfinite(z)) = Inf;
end
