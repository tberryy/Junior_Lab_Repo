function c = toStressStrain(displacement, force, dim, testName)
%TOSTRESSSTRAIN Turn one displacement-force record into a stress-strain curve.
%
%   Steps:
%     1. drop NaN/Inf points
%     2. zero the displacement at the first sample
%     3. stress = F / A  (N/mm^2 = MPa),  strain = delta / L
%     4. drop negative-strain points
%     5. where the curve ends
%          Tension      at the peak stress (the fracture point)
%          Compression  at the end of the record (test stop), so the
%                       post-yield response is kept for averaging, as in
%                       the original averaging code
%
%   The plot strain window is NOT applied here. It is a plotting option, so
%   changing it does not require re-running prepareData.
%
%   Returns a struct with Displacement_mm, Force_N, Strain, Stress_MPa
%   (column vectors), PeakStress_MPa, StrainAtPeak and Status.
%   PeakStress_MPa is the maximum stress of the whole record for both tests.

c = struct('Displacement_mm', zeros(0,1), 'Force_N', zeros(0,1), ...
           'Strain', zeros(0,1), 'Stress_MPa', zeros(0,1), ...
           'PeakStress_MPa', NaN, 'StrainAtPeak', NaN, 'Status', "ok");

displacement = displacement(:);
force = force(:);

valid = isfinite(displacement) & isfinite(force);
displacement = displacement(valid);
force = force(valid);

if isempty(force)
    c.Status = "no numeric data";
    return;
end

if ~(isfinite(dim.Area_mm2) && isfinite(dim.Length_mm))
    c.Status = "no dimensions";
    return;
end

displacement = displacement - displacement(1);

stress = force ./ dim.Area_mm2;
strain = displacement ./ dim.Length_mm;

keep = strain >= 0;
displacement = displacement(keep);
force  = force(keep);
strain = strain(keep);
stress = stress(keep);

if isempty(stress)
    c.Status = "empty after processing";
    return;
end

[peak, iPeak] = max(stress);

if strcmpi(testName, 'Tension')
    last = iPeak;                 % fracture
else
    last = numel(stress);         % whole compression record
end

c.Displacement_mm = displacement(1:last);
c.Force_N         = force(1:last);
c.Strain          = strain(1:last);
c.Stress_MPa      = stress(1:last);
c.PeakStress_MPa  = peak;
c.StrainAtPeak    = strain(iPeak);
end
