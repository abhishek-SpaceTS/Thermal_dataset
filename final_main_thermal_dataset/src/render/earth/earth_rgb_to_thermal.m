function [T, earth_mask, info] = earth_rgb_to_thermal(rgb, ctx)
% Convert a GeoGlobe RGB Earth image into a Kelvin field.

if nargin < 2 || isempty(ctx); ctx = struct(); end

if isinteger(rgb)
    A = double(rgb) / 255;
else
    A = double(rgb);
    if max(A(:)) > 1.001; A = A / 255; end
end
r = A(:,:,1); g = A(:,:,2); b = A(:,:,3);

lum      = 0.299*r + 0.587*g + 0.114*b;
blueness = b - max(r, g);

temps = local_field(ctx, 'temps', [290, 305, 240]);
T_ocean = temps(1); T_land = temps(2); T_cloud = temps(3);

space_thr = local_field(ctx, 'space_threshold', 0.07);

CL = struct('space',0, 'ocean',1, 'land',2, 'cloud',3);

is_earth = (lum >= space_thr) | (blueness > 0.06 & lum > 0.03);

[H, W] = size(lum);
cls = zeros(H, W, 'uint8');

cloud = is_earth & (r > 0.745) & (g > 0.745) & (b > 0.745);
cls(cloud) = CL.cloud;

ocean = is_earth & cls == 0 & (b > g + 0.039) & (b > r + 0.039);
cls(ocean) = CL.ocean;

cls(is_earth & cls == 0) = CL.land;

earth_mask = cls > 0;

min_blob = local_field(ctx, 'min_blob_px', 5000);
if min_blob > 0 && any(earth_mask(:))
    kept = bwareaopen(earth_mask, min_blob);
    cls(earth_mask & ~kept) = CL.space;
    earth_mask = kept;
end

T = zeros(H, W);
T(cls == CL.ocean) = T_ocean;
T(cls == CL.land)  = T_land;
T(cls == CL.cloud) = T_cloud;

tex = local_field(ctx, 'texture_amplitude_K', [2, 8, 3]);
tex_ids = [CL.ocean, CL.land, CL.cloud];
for k = 1:numel(tex_ids)
    if tex(k) <= 0; continue; end
    mk = (cls == tex_ids(k));
    if nnz(mk) < 2; continue; end
    L    = lum(mk);
    sd_c = std(L);
    if sd_c < 1e-6; continue; end
    d = max(-1, min(1, (L - mean(L)) / (2 * sd_c)));
    T(mk) = T(mk) + tex(k) * d;
end

% Day/night rise, PER CLASS. Thermal inertia differs enormously between
% surfaces: ocean swings 0.5-3 K over a day, vegetated land 10-20 K, desert
% 30-50 K, and a cloud top essentially not at all because its temperature is
% set by altitude rather than by local time. One shared amplitude would give
% the ocean a land-sized swing, so this takes [ocean land cloud].
%
% A scalar is still accepted and applied to every class, which keeps older
% configs working.
amp = local_field(ctx, 'diurnal_amplitude_K', [0 0 0]);
if isscalar(amp); amp = repmat(amp, 1, 3); end
amp = amp(:).';

if any(amp > 0)
    mu   = local_field(ctx, 'mu', 1);
    ramp = max(0, min(1, mu)).^0.25;         % radiative-equilibrium exponent
    if isscalar(ramp); ramp = ramp * ones(H, W); end
    for k = 1:numel(tex_ids)
        if amp(k) <= 0; continue; end
        mk = (cls == tex_ids(k));
        if ~any(mk(:)); continue; end
        T(mk) = T(mk) + amp(k) * ramp(mk);
    end
end

info.class_map      = cls;
info.class_ids      = CL;
info.class_fraction = struct( ...
    'ocean', nnz(cls == CL.ocean) / numel(cls), ...
    'land',  nnz(cls == CL.land)  / numel(cls), ...
    'cloud', nnz(cls == CL.cloud) / numel(cls));
info.earth_coverage = nnz(earth_mask) / numel(earth_mask);
if any(earth_mask(:))
    info.T_min_K = min(T(earth_mask));
    info.T_max_K = max(T(earth_mask));
else
    info.T_min_K = NaN; info.T_max_K = NaN;
end
info.classes             = struct('ocean',T_ocean, 'land',T_land, 'cloud',T_cloud);
info.diurnal_amplitude_K = amp;
info.texture_amplitude_K = tex;
info.method              = ['simple 4-class engineering model ' ...
                            '(space/ocean/land/cloud) + within-class brightness texture'];

end

function v = local_field(s, f, dflt)
% Read a field, falling back to a default when absent or empty.
if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end
