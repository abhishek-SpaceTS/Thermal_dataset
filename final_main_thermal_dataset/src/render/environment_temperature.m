function [T_surr, info] = environment_temperature(face_normals_eci, nadir_eci, altitude_m, cfg)
%ENVIRONMENT_TEMPERATURE  What each face reflects, per face, in Kelvin.
%
%   [T_surr, info] = environment_temperature(n_eci, nadir_eci, altitude_m, cfg)
%
%   Returns the effective temperature of the environment seen by each face,
%   for use as T_surroundings in apparent_temperature. One value per face.
%
%   WHY PER FACE
%   ------------
%   A low-emissivity surface reports mostly what it REFLECTS. Modelling that
%   reflection as deep space everywhere -- the previous behaviour, and what
%   cfg.sensor.surroundings_K = [] still selects -- is the cold limit: gold
%   MLI at 215 K kinetic with eps = 0.05 reads about 146 K. In low Earth
%   orbit a blanket pointed at the ground instead reflects a ~255 K disc that
%   fills a 66 deg half-angle of its sky, and reads nearer 230 K.
%
%   So MLI is not uniformly cold, it is VIEW-DEPENDENT: the same blanket
%   swings ~80 K between facing space and facing Earth within one tumble.
%   A scalar surroundings temperature cannot express that, which is why this
%   returns a vector.
%
%   WHAT IS AND IS NOT MODELLED
%   ---------------------------
%   REFLECTION ONLY. Earth IR is NOT added as a heating term. The kinetic
%   temperatures come from src/target/thermal_database.m, whose values are
%   realistic LEO equilibrium temperatures -- a blanket sits at 215 K in
%   eclipse precisely BECAUSE Earth IR and the spacecraft interior hold it
%   there. Adding Earth IR again as an input would double-count it and drive
%   every surface too hot. The old HIL synthetic_thermal_gen_v2 could add it
%   as heating because it solved an energy balance from a cold start; this
%   generator does not.
%
%   Solar reflection (albedo) is also excluded. In the LWIR band the
%   reflected-solar contribution at Earth is a fraction of a percent of the
%   thermal signal, far below the modelling error in the surface
%   temperatures themselves.
%
%   VIEW FACTOR
%   -----------
%   F is the fraction of a face's hemisphere filled by Earth, from the
%   standard flat-element-to-sphere geometry:
%
%       sin(rho) = R_earth / (R_earth + altitude)     Earth angular radius
%       F(theta) = (1/pi) * INT_cone max(0, cos psi) dOmega
%
%   with theta the angle between the face normal and nadir. The integral is
%   evaluated numerically on a theta grid and cached per altitude, rather
%   than using a closed form: the closed form has a partial-horizon branch
%   that is easy to get subtly wrong, and at 600 km Earth subtends 66 deg so
%   most faces are IN that branch. The quadrature is self-checking --
%   F(0) must equal sin^2(rho) exactly, which the tests assert.
%
%   Nadir-facing at 600 km gives F = 0.835; zenith-facing gives 0.

R_earth = 6371e3;

env = struct('enabled', true, 'earth_ir_K', 255, 'deep_space_K', 2.7);
if nargin >= 4 && ~isempty(cfg) && isfield(cfg, 'environment')
    e = cfg.environment;
    for f = {'enabled', 'earth_ir_K', 'deep_space_K'}
        if isfield(e, f{1}) && ~isempty(e.(f{1})); env.(f{1}) = e.(f{1}); end
    end
end

n_faces = size(face_normals_eci, 1);
info = struct('model', 'deep_space', 'earth_ir_K', env.earth_ir_K, ...
              'altitude_m', NaN, 'rho_deg', NaN, ...
              'F_min', 0, 'F_max', 0, 'F_mean', 0);

% ---- cold limit --------------------------------------------------------
% Either the environment model is off, or the caller has no orbit geometry
% to give (no Earth state and an observer at the frame origin). Falling back
% to deep space reproduces the previous behaviour exactly.
if ~env.enabled || isempty(nadir_eci) || isempty(altitude_m) || ...
        ~isfinite(altitude_m) || altitude_m <= 0
    T_surr = repmat(env.deep_space_K, n_faces, 1);
    return;
end

sin_rho = R_earth / (R_earth + altitude_m);
sin_rho = min(1, max(0, sin_rho));
rho = asin(sin_rho);

nadir_eci = nadir_eci(:) / norm(nadir_eci);
nn = face_normals_eci;
len = vecnorm(nn, 2, 2);
len(len < eps) = 1;
nn = nn ./ len;

cos_theta = max(-1, min(1, nn * nadir_eci));
F = local_view_factor(acos(cos_theta), rho);

% ---- mix the two radiance sources, then invert --------------------------
% Mixing must happen in RADIANCE, not temperature. Planck is strongly
% non-linear at 10 um, so a face seeing half Earth and half space is nowhere
% near the average of 255 K and 2.7 K -- it is about 240 K.
lam = 10e-6; lam_range = [];
if nargin >= 4 && ~isempty(cfg) && isfield(cfg, 'thermal')
    if isfield(cfg.thermal,'wavelength_center') && ~isempty(cfg.thermal.wavelength_center)
        lam = cfg.thermal.wavelength_center;
    end
    if isfield(cfg.thermal,'wavelength_range') && ~isempty(cfg.thermal.wavelength_range)
        lam_range = cfg.thermal.wavelength_range;
    end
end
% Must use the SAME Planck treatment as apparent_temperature. If this inverted
% at the band centre while the surface term integrated the band, the mixed
% radiance would be assembled from two different definitions of radiance and
% the reflected term would be quietly wrong.
if ~isempty(lam_range) && band_mode(cfg)
    L_env = F .* planck_band('L', env.earth_ir_K,   lam_range) + ...
        (1 - F) .* planck_band('L', env.deep_space_K, lam_range);
    T_surr = planck_band('T', max(L_env, realmin), lam_range);
else
    k = 1.4387768775e-2 / lam;
    L = @(T) 1 ./ (exp(k ./ T) - 1);
    L_env = F .* L(env.earth_ir_K) + (1 - F) .* L(env.deep_space_K);
    L_env = max(L_env, realmin);
    T_surr = k ./ log(1 + 1 ./ L_env);
end

info.model      = 'earth_ir_view_factor';
info.altitude_m = altitude_m;
info.rho_deg    = rad2deg(rho);
info.F_min      = min(F);
info.F_max      = max(F);
info.F_mean     = mean(F);

end


% =============================================================================
function F = local_view_factor(theta, rho)
% Fraction of a flat element's hemisphere filled by a sphere of angular
% radius rho, whose centre lies at angle theta from the element normal.
%
% Cached per rho: the lookup costs a 2-D quadrature, and rho is fixed for a
% given altitude, so it is built once and reused for every face of every
% frame at that altitude.
persistent cache_rho cache_theta cache_F
if isempty(cache_rho) || abs(cache_rho - rho) > 1e-9
    n_th = 721;
    cache_theta = linspace(0, pi, n_th);
    cache_F = zeros(1, n_th);

    % Quadrature over the Earth cone: polar angle a in [0, rho], azimuth p.
    na = 160; np = 320;
    a  = (0.5:na-0.5) / na * rho;          % midpoint rule
    p  = (0.5:np-0.5) / np * 2*pi;
    da = rho / na;
    dp = 2*pi / np;
    [A, P] = ndgrid(a, p);
    sinA = sin(A); cosA = cos(A); cosP = cos(P);

    for i = 1:n_th
        th = cache_theta(i);
        cos_psi = cos(th) * cosA + sin(th) * sinA .* cosP;
        cache_F(i) = sum(max(0, cos_psi) .* sinA, 'all') * da * dp / pi;
    end
    cache_rho = rho;
end
F = interp1(cache_theta, cache_F, theta, 'linear', 0);
F = max(0, min(1, F(:)));
end


function tf = band_mode(cfg)
% cfg.run.sensor.planck_mode, defaulting to band integration.
tf = true;
if ~isempty(cfg) && isfield(cfg,'run') && isfield(cfg.run,'sensor') && ...
        isfield(cfg.run.sensor,'planck_mode') && ~isempty(cfg.run.sensor.planck_mode)
    tf = strcmpi(char(cfg.run.sensor.planck_mode), 'band');
end
end
