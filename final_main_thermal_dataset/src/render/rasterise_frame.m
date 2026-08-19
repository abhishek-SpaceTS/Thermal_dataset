function [thermal_image, component_mask, thermal_info] = rasterise_frame( ...
config,...
t_step,...
chief_pos_eci,...
chief_quat,...
deputy_pos_eci,...
deputy_quat,...
sun_vec_eci,...
target,...
earth_state)

if nargin < 9
    earth_state = [];
end

if nargin < 8 || isempty(target)
    target = build_cad(config);
end

proj = project_to_camera( ...
    target,...
    chief_pos_eci,...
    chief_quat,...
    deputy_pos_eci,...
    deputy_quat,...
    config);

img_w = ...
    config.thermal.resolution(1);

img_h = ...
    config.thermal.resolution(2);

if exist('render_star_background', 'file') ~= 2
    addpath(fullfile(fileparts(mfilename('fullpath')), 'Renderer'));
end

[star_ra, star_dec, star_roll] = ...
    star_camera_from_eci(proj.R_eci_to_thermal);

star_camera.ra_deg          = star_ra;
star_camera.dec_deg         = star_dec;
star_camera.roll_deg        = star_roll;
star_camera.image_width     = img_w;
star_camera.image_height    = img_h;
star_camera.fov_deg         = config.thermal.fov_deg;
star_camera.focal_length_px = ...
    config.thermal.focal_length / config.thermal.pixel_pitch;

if isfield(config.thermal, 'star_config')
    star_cfg = config.thermal.star_config;
else
    star_cfg = struct();
end

stars_on = true;
if isfield(config,'run') && isfield(config.run,'stars') && ...
        isfield(config.run.stars,'enabled')
    stars_on = logical(config.run.stars.enabled);
end

if isfield(config.thermal, 'star_temp_range')
    star_range = config.thermal.star_temp_range;
elseif isfield(config, 'run') && isfield(config.run, 'sensor') && ...
        isfield(config.run.sensor, 'T_min') && isfield(config.run.sensor, 'T_max')
    % Fall back to the ACTIVE save window rather than a literal. The sky floor
    % is star_range(1) and must equal T_min, or blank sky stops mapping to
    % DN 0 and the background renders grey. This used to be a hard-coded
    % [200 400], which silently disagreed with the window once T_min moved.
    star_range = [config.run.sensor.T_min, config.run.sensor.T_max];
else
    error('rasterise_frame:noStarRange', ...
        ['Cannot determine the star temperature range: neither ' ...
         'config.thermal.star_temp_range nor config.run.sensor.T_min/T_max ' ...
         'is available. Refusing to guess a temperature window.']);
end

thermal_image = star_range(1) * ones(img_h, img_w);
if stars_on
    thermal_image = render_star_background(thermal_image, star_camera, star_cfg, star_range);
end

sun_unit = sun_vec_eci(:);
sun_unit = sun_unit / norm(sun_unit);

earth_info = struct('renderer','geoglobe', 'enabled',false, 'visible',false, ...
                    'coverage',0, 'n_pixels',0, 'mu_frame',NaN, ...
                    'T_min_K',NaN, 'T_max_K',NaN);

if ~isempty(earth_state) && isfield(earth_state, 'enabled') && earth_state.enabled
    % fit_mode decides whether the GeoGlobe image is cropped to the camera
    % field or stretched whole into the frame. "crop" keeps Earth in the same
    % camera as the spacecraft; "fill" passes an empty fov_deg, which makes
    % earth_geoglobe_render skip the crop and resize its full ~60.3 deg view.
    % See cfg.earth.fit_mode for what that costs.
    fit_mode = 'crop';
    if isfield(config,'run') && isfield(config.run,'earth') && ...
            isfield(config.run.earth,'fit_mode') && ~isempty(config.run.earth.fit_mode)
        fit_mode = lower(char(config.run.earth.fit_mode));
    end
    switch fit_mode
        case 'crop', scene_fov = config.thermal.fov_deg;
        case 'fill', scene_fov = [];
        otherwise
            error('rasterise_frame:badFitMode', ...
                  'cfg.earth.fit_mode must be "crop" or "fill", got "%s".', fit_mode);
    end

    % Forced pitch/heading, if configured. The globe camera is still solved
    % from the real state to get lat/lon/altitude, then the requested angles
    % replace the derived ones -- so the sub-satellite point is genuine while
    % the framing is fixed. Earth then ignores the spacecraft attitude, which
    % is why this is documented as scenery-only.
    f_pitch = local_earth_cfg(config, 'forced_pitch_deg');
    f_head  = local_earth_cfg(config, 'forced_heading_deg');

    if isempty(f_pitch) && isempty(f_head)
        scene = struct( ...
            'deputy_pos_eci',   earth_state.geocentric_pos_eci, ...
            'R_eci_to_thermal', proj.R_eci_to_thermal, ...
            'epoch_utc',        earth_state.epoch_utc, ...
            'fov_deg',          scene_fov, ...
            'alt_m',            earth_state.altitude_m, ...
            'out_size',         [img_h img_w]);
    else
        cam = earth_geoglobe_camera(earth_state.geocentric_pos_eci, ...
                                    proj.R_eci_to_thermal, earth_state.epoch_utc);
        pit = cam.pitch_deg;   if ~isempty(f_pitch); pit = f_pitch; end
        hdg = cam.heading_deg; if ~isempty(f_head);  hdg = f_head;  end
        scene = struct( ...
            'lat_deg',     cam.lat_deg, ...
            'lon_deg',     cam.lon_deg, ...
            'alt_m',       cam.alt_m, ...
            'heading_deg', hdg, ...
            'pitch_deg',   pit, ...
            'roll_deg',    cam.roll_deg, ...
            'fov_deg',     scene_fov, ...
            'out_size',    [img_h img_w]);
    end

    [earth_rgb, gg_info] = earth_geoglobe_render(scene);

    n_sub = earth_state.geocentric_pos_eci(:);
    n_sub = n_sub / norm(n_sub);
    s_therm = sun_unit;
    if isfield(earth_state, 'lst_lag_hours') && earth_state.lst_lag_hours ~= 0
        psi = deg2rad(15.0 * earth_state.lst_lag_hours);
        cz = cos(psi); sz = sin(psi);
        s_therm = [cz*sun_unit(1) - sz*sun_unit(2); ...
                   sz*sun_unit(1) + cz*sun_unit(2); sun_unit(3)];
    end
    mu_frame = max(0, dot(n_sub, s_therm));

    cls_ctx = struct('mu', mu_frame);
    if isfield(config,'run') && isfield(config.run,'earth')
        Ecfg = config.run.earth;
        for fn = {'min_blob_px','temps','diurnal_amplitude_K','texture_amplitude_K'}
            if isfield(Ecfg, fn{1}) && ~isempty(Ecfg.(fn{1}))
                cls_ctx.(fn{1}) = Ecfg.(fn{1});
            end
        end
    end

    [earth_temp, earth_mask, cls_info] = earth_rgb_to_thermal(earth_rgb, cls_ctx);

    earth_alpha = [];
    earth_info = gg_info;
    earth_info.enabled   = true;
    earth_info.visible   = any(earth_mask(:));
    earth_info.coverage  = cls_info.earth_coverage;
    earth_info.n_pixels  = nnz(earth_mask);
    earth_info.mu_frame  = mu_frame;
    earth_info.T_min_K   = cls_info.T_min_K;
    earth_info.T_max_K   = cls_info.T_max_K;
    earth_info.renderer  = 'geoglobe';
    earth_info.fit_mode  = fit_mode;

    if earth_info.visible && ~isempty(earth_mask) && any(earth_mask(:))
        soft = earth_geoglobe_edge_sigma(config, earth_info);
        if soft > 0
            a  = imgaussfilt(double(earth_mask), soft);
            Ts = imgaussfilt(earth_temp .* double(earth_mask), soft) ./ max(a, 1e-6);
            w  = min(1, a);
            thermal_image = (1 - w) .* thermal_image + w .* Ts;
        else
            thermal_image(earth_mask) = earth_temp(earth_mask);
        end
        earth_info.edge_sigma_px = soft;
    end
end

depth_buffer = ...
    inf(img_h,img_w);
component_mask = zeros(img_h, img_w, 'uint8');

sigma = 5.670374419e-8;

Re = 6371e3;

if ~isempty(earth_state) && isfield(earth_state, 'enabled') && earth_state.enabled ...
        && isfield(earth_state, 'geocentric_pos_eci')
    if isfield(earth_state, 'radius_m') && ~isempty(earth_state.radius_m)
        Re = earth_state.radius_m;
    end
    r_sat = earth_state.geocentric_pos_eci(:);
else
    r_sat = deputy_pos_eci(:);
end

proj_sun = -dot(r_sat,sun_unit);

in_eclipse = false;

if proj_sun > 0

    d_shadow = norm( ...
        r_sat + proj_sun*sun_unit );

    if d_shadow < Re

        in_eclipse = true;

    end

end

if in_eclipse

    disp('Satellite in Earth Eclipse')

else

    disp('Satellite Sunlit')

end

% Surface temperature settings from config.m (cfg.thermal). Absent
% means compute_temperatures uses its own physical defaults.
if isfield(config,'run') && isfield(config.run,'thermal')
    tcfg = config.run.thermal;
else
    tcfg = struct();
end

[face_temperature, ~, ~] = compute_temperatures( ...
    target, ...
    chief_quat, ...
    sun_vec_eci, ...
    in_eclipse, ...
    tcfg);

% ---- Kinetic -> apparent temperature ---------------------------------
% face_temperature is the KINETIC temperature the thermal model produced.
% A camera measures radiance and inverts it assuming a perfect emitter, so
% what lands in the image is the APPARENT temperature: low-emissivity
% surfaces reflect their surroundings instead of showing their own heat.
% This is the sensor conversion, applied where a sensor applies it -- the
% physical model above is untouched.
if isfield(target, 'face_emissivity') && ~isempty(target.face_emissivity)
    lam = local_get_num(config.thermal, 'wavelength_center', []);
    if isempty(lam)
        error('rasterise_frame:noWavelength', ...
            ['config.thermal.wavelength_center is required to convert kinetic ' ...
             'to apparent temperature. It is set by apply_band.']);
    end
    % What each face reflects. An explicit cfg.sensor.surroundings_K still
    % wins and is applied to every face, for reproducing older datasets.
    % Otherwise the per-face Earth-IR model runs: see environment_temperature.
    if isfield(config,'run') && isfield(config.run,'sensor') && ...
            isfield(config.run.sensor,'surroundings_K') && ...
            ~isempty(config.run.sensor.surroundings_K)
        T_surr = config.run.sensor.surroundings_K;
        env_info = struct('model','scalar_override','earth_ir_K',NaN, ...
                          'altitude_m',NaN,'rho_deg',NaN, ...
                          'F_min',NaN,'F_max',NaN,'F_mean',NaN);
    else
        % Orbit geometry, needed whether or not the Earth BACKGROUND renders.
        % Those are separate settings and must stay separate: turning the
        % background off must not silently change the radiometry.
        %   1. earth_state carries it when the scenario supplied one
        %   2. otherwise a deputy position that is actually geocentric
        %      (validate_against_hil passes real ECI vectors) serves
        %   3. otherwise there is no orbit -- fall back to the cold limit
        r_env = [];
        if ~isempty(earth_state) && isfield(earth_state,'geocentric_pos_eci') ...
                && ~isempty(earth_state.geocentric_pos_eci)
            r_env = earth_state.geocentric_pos_eci(:);
        elseif norm(deputy_pos_eci) > Re
            r_env = deputy_pos_eci(:);
        end

        if isempty(r_env)
            nadir_eci = []; alt_m = [];
        else
            nadir_eci = -r_env / norm(r_env);
            alt_m     = norm(r_env) - Re;
        end

        % Face normals in ECI, rotated the same way compute_temperatures
        % rotates them for the Sun angle, so both use one convention.
        R_body_to_eci = quat2rotm(chief_quat);
        n_eci = (R_body_to_eci * target.face_normals.').';

        ecfg = struct('environment', struct(), 'thermal', config.thermal);
        if isfield(config,'run')
            ecfg.run = config.run;          % carries sensor.planck_mode
            if isfield(config.run,'environment')
                ecfg.environment = config.run.environment;
            end
        end
        [T_surr, env_info] = environment_temperature(n_eci, nadir_eci, alt_m, ecfg);
    end

    % Band-integrated unless cfg.sensor.planck_mode says "centre".
    lam_range = [];
    if ~strcmpi(local_planck_mode(config), 'centre') && ...
            isfield(config.thermal,'wavelength_range') && ~isempty(config.thermal.wavelength_range)
        lam_range = config.thermal.wavelength_range;
    end
    face_apparent = apparent_temperature(face_temperature, ...
        target.face_emissivity(:), T_surr, lam, lam_range);
else
    face_apparent = face_temperature;
end

num_faces = size(target.faces,1);

face_depth = zeros(num_faces,1);

for k = 1:num_faces

verts = target.faces(k,:);

face_depth(k) = ...
mean(proj.vertices_thermal(verts,3));

end

[~,draw_order] = sort(face_depth,'descend');

R_body_to_eci_chief = quat2rotm(chief_quat);

for n = 1:num_faces

face_idx = draw_order(n);

verts = target.faces(face_idx,:);

uv = proj.pixel_uv(verts,:);

if any(isnan(uv(:)))
    continue
end

normal_body = ...
    target.face_normals(face_idx,:)';

normal_eci = ...
    R_body_to_eci_chief * normal_body;

normal_cam = ...
proj.R_eci_to_thermal * normal_eci;

if normal_cam(3) >= 0
    continue
end

T = face_apparent(face_idx);          % what the camera reports, not kinetic
material = target.face_material(face_idx);

x_min = max(1, floor(min(uv(:,1))));
x_max = min(img_w, ceil(max(uv(:,1))));
y_min = max(1, floor(min(uv(:,2))));
y_max = min(img_h, ceil(max(uv(:,2))));

if x_max < x_min || y_max < y_min
    continue
end

bb_w = x_max - x_min + 1;
bb_h = y_max - y_min + 1;

mask_local = poly2mask( ...
        uv(:,1) - x_min + 1, ...
        uv(:,2) - y_min + 1, ...
        bb_h, ...
        bb_w);

face_z = mean( ...
    proj.vertices_thermal(verts,3));

db_region = depth_buffer(y_min:y_max, x_min:x_max);
update_local = mask_local & (face_z < db_region);

if any(update_local(:))
    ti_region = thermal_image(y_min:y_max, x_min:x_max);
    ti_region(update_local) = T;
    thermal_image(y_min:y_max, x_min:x_max) = ti_region;

    cm_region = component_mask(y_min:y_max, x_min:x_max);
    cm_region(update_local) = material;
    component_mask(y_min:y_max, x_min:x_max) = cm_region;

    db_region(update_local) = face_z;
    depth_buffer(y_min:y_max, x_min:x_max) = db_region;
end

end

% Optical blur. cfg.camera.psf_sigma_px is the hardware value; a run may
% override it through cfg.sensor.psf_sigma_px. Both resolve to 1.5 px today,
% which is what this used to hard-code.
psf_sigma = local_get_num(config.thermal, 'psf_sigma', 1.5);
if isfield(config,'run') && isfield(config.run,'sensor') && ...
        isfield(config.run.sensor,'psf_sigma_px') && ...
        ~isempty(config.run.sensor.psf_sigma_px)
    psf_sigma = config.run.sensor.psf_sigma_px;
end
if psf_sigma > 0
    thermal_image = imgaussfilt(thermal_image, psf_sigma);
end

fprintf('Max Temperature : %.2f K\n', ...
    max(face_temperature));

fprintf('Min Temperature : %.2f K\n', ...
    min(face_temperature));

% Per-class mean face temperature, generated from the live taxonomy. These
% used to be six hard-coded fields (Bus_mean_K ... ReactionWheel_mean_K) that
% covered only class ids 1-6, so every class added since was silently absent.
% Informational only -- nothing downstream reads them and the rendering above
% is unaffected. A class with no faces on this target reports 0, matching the
% previous NaN-to-zero behaviour.
cls_info = class_definitions();
for ci = 1:numel(cls_info)
    if cls_info(ci).id == 0; continue; end          % Background carries no faces
    sel = (target.face_material == cls_info(ci).id);
    fname = [regexprep(cls_info(ci).name, '[^A-Za-z0-9]', '') '_mean_K'];
    if any(sel)
        thermal_info.(fname) = mean(face_temperature(sel));
    else
        thermal_info.(fname) = 0;
    end
end

fn = fieldnames(thermal_info);
for k=1:numel(fn)
    if isnumeric(thermal_info.(fn{k})) && isscalar(thermal_info.(fn{k})) && ...
            isnan(thermal_info.(fn{k}))
        thermal_info.(fn{k}) = 0;
    end
end

thermal_info.earth = earth_info;

% Environment model actually used for the reflected term, recorded so a frame
% is self-describing: whether Earth IR was applied, at what altitude, and the
% spread of view factors across the faces.
thermal_info.environment = env_info;

% Illumination state and the realised face-temperature spread for THIS frame.
% Both are already computed above; without surfacing them the sequence
% metadata cannot say which frames were eclipsed or what actually rendered.
thermal_info.in_eclipse   = logical(in_eclipse);
thermal_info.face_T_min_K  = min(face_temperature);
thermal_info.face_T_max_K  = max(face_temperature);
thermal_info.face_T_mean_K = mean(face_temperature);

% Apparent temperatures are what the image actually holds; the kinetic values
% above are the model's own output. Both are reported so the emissivity effect
% is visible in the metadata rather than only in the pixels.
thermal_info.face_Tapp_min_K  = min(face_apparent);
thermal_info.face_Tapp_max_K  = max(face_apparent);
thermal_info.face_Tapp_mean_K = mean(face_apparent);

end


function v = local_get_num(s, f, dflt)
% Read a numeric field, falling back to dflt when absent or empty.
if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end


function v = local_earth_cfg(config, field)
% Read config.run.earth.<field>, [] when absent or empty.
v = [];
if isfield(config,'run') && isfield(config.run,'earth') && ...
        isfield(config.run.earth, field) && ~isempty(config.run.earth.(field))
    v = config.run.earth.(field);
end

end


function m = local_planck_mode(config)
m = 'band';
if isfield(config,'run') && isfield(config.run,'sensor') && ...
        isfield(config.run.sensor,'planck_mode') && ~isempty(config.run.sensor.planck_mode)
    m = char(config.run.sensor.planck_mode);
end
end
