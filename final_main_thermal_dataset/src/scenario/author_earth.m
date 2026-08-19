function e = author_earth(config, boresight_eci)
% Author the Earth background state for ONE sequence.

if nargin < 2 || isempty(boresight_eci)
    error('author_earth:noBoresight', ...
          ['A camera boresight is required to place the Earth. Pass ' ...
           'quat2rotm(scenario.deputy_quaternion).'' * [0;0;1].']);
end
b = boresight_eci(:) / norm(boresight_eci);

e.enabled = true;
if isfield(config,'run') && isfield(config.run,'earth') && ...
        isfield(config.run.earth,'enabled')
    e.enabled = logical(config.run.earth.enabled);
end

e.radius_m   = 6371e3;
% Use chaser altitude from config, default to 600 km if not set
if isfield(config, 'orbit') && isfield(config.orbit, 'altitude_chaser_m')
    e.altitude_m = config.orbit.altitude_chaser_m;
else
    e.altitude_m = 600e3;  % default 600 km
end

f_px    = config.thermal.focal_length / config.thermal.pixel_pitch;
theta_c = atand(hypot(config.thermal.resolution(1), ...
                      config.thermal.resolution(2)) / (2 * f_px));
rho     = asind(e.radius_m / (e.radius_m + e.altitude_m));

margin   = 0.30;
p_target = [0.30 0.40 0.30];
if isfield(config,'run') && isfield(config.run,'earth') && ...
        isfield(config.run.earth,'scene_class_mix') && ...
        ~isempty(config.run.earth.scene_class_mix)
    p_target = config.run.earth.scene_class_mix(:)';
    if numel(p_target) ~= 3 || any(p_target < 0) || sum(p_target) <= 0
        error('author_earth:badSceneMix', ...
              ['cfg.earth.scene_class_mix must be 3 non-negative weights ' ...
               '[none limb full] with a positive sum; got %s.'], mat2str(p_target));
    end
    p_target = p_target / sum(p_target);
end
u = rand();
if u < p_target(1)
    e.class = 'none'; lo = rho + theta_c + margin; hi = 180;
elseif u < p_target(1) + p_target(2)
    e.class = 'limb'; lo = rho - theta_c + margin; hi = rho + theta_c - margin;
else
    e.class = 'full'; lo = 0;                      hi = rho - theta_c - margin;
end

cl = cosd(lo); ch = cosd(hi);
e.theta_deg = acosd(cl - rand() * (cl - ch));
e.phi_deg   = 360 * rand();

e.orbit_normal_psi_deg = 360 * rand();
e.motion_enabled       = true;

mu_earth             = 3.986004418e14;
e.orbital_rate_rad_s = sqrt(mu_earth / (e.radius_m + e.altitude_m)^3);

e.angular_radius_deg  = rho;
e.half_fov_corner_deg = theta_c;
e.theta_interval_deg  = [lo hi];

e.lst_lag_hours = 2.0;
if isfield(config,'run') && isfield(config.run,'earth') && ...
        isfield(config.run.earth,'lst_lag_hours')
    e.lst_lag_hours = config.run.earth.lst_lag_hours;
end

[p1, p2] = perpendicular_basis(b);
th = deg2rad(e.theta_deg); ph = deg2rad(e.phi_deg);
nadir_eci = b*cos(th) + (p1*cos(ph) + p2*sin(ph))*sin(th);
nadir_eci = nadir_eci / norm(nadir_eci);
e.geocentric_pos_eci = (e.radius_m + e.altitude_m) * (-nadir_eci);

e.epoch_utc = datetime(2025,1,1,0,0,0) + seconds(365.25*86400*rand());

end
