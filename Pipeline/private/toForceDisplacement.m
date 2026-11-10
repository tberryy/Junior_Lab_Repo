function c = toForceDisplacement(displacement, force, maxPeakDisplacement)
%TOFORCEDISPLACEMENT Condition one compact-tension (fracture) record.
%
%   Steps
%     1. drop NaN/Inf points, zero the displacement at the first sample
%     2. peak load = the maximum measured force (the load cell is zeroed
%        before each test; first samples read 0 +/- 0.5 N)
%     3. toe compensation: fit a line to the loading curve between 10 % and
%        40 % of peak load; where it reaches zero force is the true start of
%        loading. Displacement is shifted to that point (removes pin and
%        fixture slack), and the slack below 10 % of peak is replaced by the
%        straight line from (0, 0). Forces are kept as measured.
%     4. keep the curve up to peak load
%     5. Status "peak displacement over X mm" when peak load sits beyond
%        maxPeakDisplacement (the original rule used 4 mm: a slipped pin or a
%        bad test); those specimens are left out of plots and K / G.
%
%   Why not the original method: it found the start of loading, then
%   subtracted the force at that point (about 6 % of peak) from every
%   sample. That made every K_Ic about 6 % low and every fracture energy
%   (so G_Ic) about 12 % low.
%
%   Returns Displacement_mm, Force_N (column vectors, up to peak),
%   PeakForce_N, DisplacementAtPeak_mm, Energy_J (area under the curve up
%   to peak), ToeShift_mm and Status.

c = struct('Displacement_mm', zeros(0, 1), 'Force_N', zeros(0, 1), ...
           'PeakForce_N', NaN, 'DisplacementAtPeak_mm', NaN, 'Energy_J', NaN, ...
           'ToeShift_mm', NaN, 'Status', "ok");

d = displacement(:);
F = force(:);
ok = isfinite(d) & isfinite(F);
d = d(ok);
F = F(ok);

if numel(F) < 3
    c.Status = "no numeric data";
    return;
end

d = d - d(1);
[peak, iPeak] = max(F);
if ~(peak > 0)
    c.Status = "no positive load";
    return;
end

% Toe compensation from the 10-40 % of peak loading segment
loading = (1:numel(F))' <= iPeak & F >= 0.10 * peak & F <= 0.40 * peak;
d0 = 0;
if nnz(loading) >= 3
    p = polyfit(d(loading), F(loading), 1);
    if p(1) > 0
        d0 = -p(2) / p(1);
    end
end
if ~(d0 > 0 && d0 < d(iPeak))
    d0 = 0;                     % no toe, or a fit that makes no sense
end

% Below 10 % of peak the record is slack / seating, so it is replaced by
% the straight loading line from the new origin (ASTM-style toe
% compensation): the curve is (0,0) followed by the data from 10 % of peak.
i10 = find(F(1:iPeak) >= 0.10 * peak, 1, 'first');
x = d(i10:iPeak) - d0;
y = F(i10:iPeak);
keep = x > 0;
x = [0; x(keep)];
y = [0; y(keep)];

c.Displacement_mm       = x;
c.Force_N               = y;
c.PeakForce_N           = peak;
c.DisplacementAtPeak_mm = x(end);
c.Energy_J              = trapz(x, y) / 1000;      % N*mm -> J
c.ToeShift_mm           = d0;

if c.DisplacementAtPeak_mm > maxPeakDisplacement
    c.Status = string(sprintf('peak displacement over %g mm', maxPeakDisplacement));
end
end
