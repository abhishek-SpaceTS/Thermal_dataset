function out = planck_band(mode, x, lam_range)
%PLANCK_BAND  In-band Planck radiance and its inverse.
%
%   L = planck_band('L', T, [lam1 lam2])   temperature K -> band radiance
%   T = planck_band('T', L, [lam1 lam2])   band radiance -> temperature K
%
%   The two are exact inverses of each other, which is the only property that
%   matters: the renderer converts a kinetic temperature to radiance, mixes it
%   with the environment, and converts back.
%
%       L(T) = INT_lam1^lam2  (1/lam^5) / (exp(c2/(lam*T)) - 1)  dlam
%
%   WHY NOT THE BAND CENTRE
%   -----------------------
%   Evaluating Planck at a single wavelength is exact only for a monochromatic
%   detector. A real LWIR sensor integrates 8-14 um, and Planck is strongly
%   non-linear across that span -- at 300 K the spectral radiance varies by
%   about 40 % between 8 and 14 um. For a perfect emitter the two agree by
%   construction (apparent equals kinetic either way), so the difference shows
%   up exactly where emissivity is low and a hot surface is mixed with a cold
%   environment: the band integral weights the two differently than a single
%   wavelength does. That is MLI, which is the material this dataset most needs
%   to get right.
%
%   The constant prefactor 2*h*c^2 is dropped. It cancels: the same convention
%   is used in both directions, and only the ratio ever reaches the output.
%
%   IMPLEMENTATION
%   The forward integral has no elementary closed form and the inverse has none
%   at all, so both run off a lookup table built once per band and cached. The
%   table is interpolated in LOG radiance, because L spans about twelve orders
%   of magnitude between 50 K and 600 K and linear interpolation there would be
%   worthless at the cold end.
%
%   Accuracy is checked in tests/run_all_tests.m by round-tripping: T -> L -> T
%   must return the input to well under the 4.12 mK quantisation of the save
%   window.

if nargin < 3 || isempty(lam_range) || numel(lam_range) ~= 2
    error('planck_band:badRange', ...
        'A two-element wavelength range in metres is required, e.g. [8e-6 14e-6].');
end

[T_grid, logL_grid] = local_lut(lam_range);

switch upper(char(mode))
    case 'L'
        T = max(x, T_grid(1));
        out = exp(interp1(T_grid, logL_grid, min(T, T_grid(end)), 'linear', 'extrap'));
        out(x <= T_grid(1)) = 0;     % nothing radiates in band at a few K
    case 'T'
        L = max(x, realmin);
        out = interp1(logL_grid, T_grid, log(L), 'linear', 'extrap');
        out = min(max(out, T_grid(1)), T_grid(end));
    otherwise
        error('planck_band:badMode', 'mode must be ''L'' or ''T'', got "%s".', mode);
end
out = reshape(out, size(x));

end


% -----------------------------------------------------------------------------
function [T_grid, logL_grid] = local_lut(lam_range)
% Cached per band. Rebuilt only when the band changes, which happens once.
persistent c_range c_T c_logL
if ~isempty(c_range) && isequal(c_range, lam_range)
    T_grid = c_T; logL_grid = c_logL; return;
end

c2 = 1.4387768775e-2;                  % second radiation constant, m*K

% 30 K is below anything the save window can express; 600 K is above the
% hottest class (RTG, 362 K) with margin. 0.2 K spacing keeps interpolation
% error far below the 4.12 mK per DN of the encoding.
T_grid = (30:0.2:600).';

n_lam = 401;                           % Simpson over the band
lam = linspace(lam_range(1), lam_range(2), n_lam);
w = ones(1, n_lam); w(2:2:end-1) = 4; w(3:2:end-2) = 2;
w = w * (lam(2)-lam(1)) / 3;

L = zeros(size(T_grid));
for i = 1:numel(T_grid)
    e = exp(c2 ./ (lam * T_grid(i)));
    % exp overflows to Inf for cold T; 1/(Inf-1) is 0, which is correct.
    B = (1 ./ lam.^5) ./ (e - 1);
    B(~isfinite(B)) = 0;
    L(i) = sum(w .* B);
end

L = max(L, realmin);
logL_grid = log(L);

% The table must be strictly increasing or interp1 cannot invert it.
if any(diff(logL_grid) <= 0)
    error('planck_band:notMonotonic', ...
        'Band radiance is not monotonic in temperature; the lookup cannot be inverted.');
end

c_range = lam_range; c_T = T_grid; c_logL = logL_grid;
end
