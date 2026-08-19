function meta = build_sequence_metadata(ctx)
%BUILD_SEQUENCE_METADATA Assemble one sequence's metadata.json content.
%
%   meta = build_sequence_metadata(ctx)
%
%   Pure assembly: takes the sequence's realised state and returns the struct
%   that gets serialised. Holds ONLY what varies per sequence -- camera
%   intrinsics, sensor band, radiometry, the Earth and star models and the
%   known limitations are written once by write_dataset_json.
%
%   ctx carries the values the sequence produced:
%     seq_name, spacecraft_name, scenario, config, RUN, target_cad
%     fr              per-frame accumulators
%     frames_per_sequence, fps, T_min, T_max, seq_thermal_seed

seq_name            = ctx.seq_name;
spacecraft_name     = ctx.spacecraft_name;
scenario            = ctx.scenario;
config              = ctx.config;
RUN                 = ctx.RUN;
target_cad          = ctx.target_cad;
fr                  = ctx.fr;
frames_per_sequence = ctx.frames_per_sequence;
fps                 = ctx.fps;
T_min               = ctx.T_min;
T_max               = ctx.T_max;
seq_thermal_seed    = ctx.seq_thermal_seed;

% dataset/dataset_info.json by write_dataset_json.
% ------------------------------------------------------------------
meta = struct();

meta.sequence.id            = seq_name;
meta.sequence.spacecraft    = spacecraft_name;
meta.sequence.scenario_type = scenario.scenario_type;
meta.sequence.num_frames    = frames_per_sequence;
meta.sequence.frame_rate_hz = fps;
meta.sequence.duration_s    = frames_per_sequence / fps;

% Seeds. Without these a sequence cannot be regenerated: trajectory,
% attitude, sun direction, blur and NETD are all random draws.
if isempty(RUN.random_seed)
    meta.sequence.random_seed = [];
    meta.sequence.seed_note   = ['cfg.random_seed was empty (shuffle); ' ...
        'this sequence is not exactly reproducible'];
else
    meta.sequence.random_seed = RUN.random_seed;
end
meta.sequence.thermal_seed = seq_thermal_seed;

meta.target.num_triangles = size(target_cad.faces, 1);
if isfield(target_cad, 'cad_units')
    meta.target.cad_units = target_cad.cad_units;
end
meta.target.class_ids_present = reshape(unique(target_cad.face_material), 1, []);

if strcmp(scenario.trajectory_type, 'cw_relative_motion')
    meta.trajectory.model            = 'Clohessy-Wiltshire';
else
    meta.trajectory.model            = 'Procedural';
end
% Save the TRUE 3D distances actually rendered, not just the bracket label.
meta.trajectory.distance_start_m = norm(scenario.positions(:,1));
meta.trajectory.distance_end_m   = norm(scenario.positions(:,end));
meta.trajectory.name = scenario.trajectory_name;
meta.trajectory.type = scenario.trajectory_type;

meta.attitude.initial_quaternion               = scenario.initial_quaternion;
meta.attitude.angular_velocity_rad_s           = scenario.angular_velocity;
meta.attitude.angular_velocity_magnitude_rad_s = scenario.angular_velocity_magnitude;
meta.attitude.rotation_axis                    = scenario.rotation_axis;
meta.attitude.motion_bin                       = scenario.attitude_name;

meta.observer.deputy_quaternion = scenario.deputy_quaternion;
[meta.observer.camera_ra_deg, meta.observer.camera_dec_deg, ...
 meta.observer.camera_roll_deg] = ...
    star_camera_from_eci(quat2rotm(scenario.deputy_quaternion));

% Illumination. `condition` is the most useful filter in the dataset:
% eclipse changes the whole temperature model, and a "mixed" sequence
% is the only place a thermal transition is visible.
n_ecl = nnz(fr.in_eclipse);
meta.illumination.sun_direction_cam = scenario.sun_vector;
meta.illumination.sun_bin           = scenario.sun_name;
% The phase drawn when the sun was sampled. The per-frame values below
% differ slightly because the target is not exactly on the boresight.
if isfield(scenario, 'sun_phase_deg')
    meta.illumination.sun_phase_nominal_deg = scenario.sun_phase_deg;
end
if n_ecl == 0
    meta.illumination.condition = 'sunlit';
elseif n_ecl == frames_per_sequence
    meta.illumination.condition = 'eclipse';
else
    meta.illumination.condition = 'mixed';
end
meta.illumination.sunlit_frames    = frames_per_sequence - n_ecl;
meta.illumination.eclipse_frames   = n_ecl;
meta.illumination.eclipse_fraction = n_ecl / frames_per_sequence;
d_ecl = diff([false, fr.in_eclipse]);
meta.illumination.eclipse_entry_frame = find(d_ecl ==  1, 1);
meta.illumination.eclipse_exit_frame  = find(d_ecl == -1, 1);

% Solar phase angle over the sequence: 0 front-lit, 90 side-lit,
% 180 backlit. Lets a sequence be filtered by lighting geometry
% without opening labels.csv.
ph = fr.phase_deg(~isnan(fr.phase_deg));
if ~isempty(ph)
    meta.illumination.solar_phase_angle_deg.min  = min(ph);
    meta.illumination.solar_phase_angle_deg.max  = max(ph);
    meta.illumination.solar_phase_angle_deg.mean = mean(ph);
end

meta.noise.netd_realised_K   = scenario.netd;
meta.noise.netd_bin          = scenario.netd_name;
meta.noise.psf_blur_sigma_px = scenario.blur;
meta.noise.blur_bin          = scenario.blur_name;

% Thermal: the per-sequence draw (the input) and what actually
% rendered (the output), split by illumination so the eclipse drop is
% visible without opening a frame.
st = config.run.thermal.realised;
present = meta.target.class_ids_present;
present = present(present >= 1 & present <= numel(st.base_K));
rs = struct('class_id', {}, 'name', {}, 'base', {}, 'sunlit', {}, 'eclipse', {});
for q = 1:numel(present)
    cid = present(q);
    rs(q).class_id = cid;
    rs(q).name     = st.name{cid};
    rs(q).base     = st.base_K(cid);
    rs(q).sunlit   = st.sunlit_K(cid);
    rs(q).eclipse  = st.eclipse_K(cid);
end
meta.thermal.model_id         = 'component_database_v1';
meta.thermal.realised_state_K = rs;
meta.thermal.rendered_K.sunlit_frames  = temperature_stats(fr, ~fr.in_eclipse);
meta.thermal.rendered_K.eclipse_frames = temperature_stats(fr,  fr.in_eclipse);

% How the reflected term was modelled. A low-emissivity surface reports mostly
% what it reflects, so a frame's apparent temperatures cannot be interpreted
% without knowing whether Earth IR was applied and at what view factor.
if isfield(fr, 'environment') && ~isempty(fr.environment)
    meta.thermal.environment = fr.environment;
else
    meta.thermal.environment = struct('model', 'deep_space');
end
have_T = ~isnan(fr.T_min);
if any(have_T)
    meta.thermal.rendered_K.below_save_floor_pct = ...
        100 * mean(fr.T_min(have_T) < T_min);
    meta.thermal.rendered_K.above_save_ceiling_pct = ...
        100 * mean(fr.T_max(have_T) > T_max);
end

e = scenario.earth;
meta.earth.enabled              = logical(RUN.earth.enabled);
meta.earth.scene_class          = e.class;

% ---- scene class: requested vs actually rendered ------------------
% author_earth picks the class GEOMETRICALLY, from the angle between
% the boresight and the geocentre:
%   none: disc entirely outside the frame  -> coverage 0
%   full: frame entirely inside the disc   -> coverage 1
%   limb: the limb crosses the frame       -> 0 < coverage < 1
% So the coverage thresholds are implied by that definition, not
% invented here. The tolerance is the project's existing speckle
% floor, cfg.earth.min_blob_px, expressed as a coverage fraction and
% applied symmetrically (a few stray space pixels inside a full disc
% are the complement of a few stray Earth pixels in empty sky).
%
% CAVEAT: with cfg.earth.fit_mode = "fill" the Earth layer is drawn at
% GeoGlobe's ~60 deg native field while the class was computed for the
% configured camera FOV. The two cameras disagree by roughly 10x, so
% marginal cases can legitimately mismatch. That is the documented
% fit_mode trade-off, not a defect in this check.
cov = fr.earth_cov(~isnan(fr.earth_cov));
cov_eps = RUN.earth.min_blob_px / prod(config.thermal.resolution);
meta.earth.scene_class_requested = e.class;
if isempty(cov)
    meta.earth.scene_class_actual = 'unknown';
    meta.earth.scene_class_match  = [];
else
    per_frame = repmat("limb", 1, numel(cov));
    per_frame(cov <= cov_eps)     = "none";
    per_frame(cov >= 1 - cov_eps) = "full";
    meta.earth.scene_class_actual = char(mode(categorical(per_frame)));
    meta.earth.scene_class_match  = ...
        strcmp(meta.earth.scene_class_actual, e.class);

    meta.earth.earth_coverage.min  = min(cov);
    meta.earth.earth_coverage.max  = max(cov);
    meta.earth.earth_coverage.mean = mean(cov);

    n = numel(cov);
    meta.earth.frames_pct.no_earth = 100 * nnz(per_frame == "none") / n;
    meta.earth.frames_pct.limb     = 100 * nnz(per_frame == "limb") / n;
    meta.earth.frames_pct.full     = 100 * nnz(per_frame == "full") / n;
    meta.earth.coverage_threshold  = cov_eps;

    if ~meta.earth.scene_class_match
        fprintf(['  [SCENE CLASS] %s: requested "%s" but measured ' ...
                 'coverage %.3f reads as "%s"\n'], seq_name, e.class, ...
                mean(cov), meta.earth.scene_class_actual);
    end
end

meta.earth.epoch_utc            = char(string(e.epoch_utc, 'yyyy-MM-dd HH:mm:ss'));
meta.earth.altitude_m           = e.altitude_m;
meta.earth.geocentric_pos_eci   = e.geocentric_pos_eci;
meta.earth.direction_theta_deg  = e.theta_deg;
meta.earth.direction_phi_deg    = e.phi_deg;
meta.earth.orbit_normal_psi_deg = e.orbit_normal_psi_deg;
meta.earth.angular_radius_deg   = e.angular_radius_deg;
meta.earth.theta_interval_deg   = e.theta_interval_deg;
meta.earth.motion_enabled       = e.motion_enabled;

% Summary, so 110 sequences can be filtered without opening a PNG or
% parsing labels.csv.
vis = fr.visible;
meta.summary.range_m.min             = min(fr.range_m);
meta.summary.range_m.max             = max(fr.range_m);
meta.summary.frames_target_visible   = nnz(vis);
meta.summary.frames_target_truncated = nnz(fr.truncated);
meta.summary.frames_bbox_failed      = nnz(fr.bbox_fail);

% ---- clipping census against the configured save window -----------
% Counted on the Kelvin field before to_gray16 clamps.
% target_core excludes a 2 px erosion of the mask, so PSF-blurred edge
% pixels are reported separately from real component temperatures: at
% long range the target is a few pixels wide and blur mixes it with
% the cold sky, which drags edge pixels below any face temperature.
cl = struct();
cl.window_K = [T_min, T_max];
cl.scene_T_min = min(fr.scene_T_min);
cl.scene_T_max = max(fr.scene_T_max);
cl.tolerance_K = (T_max - T_min) / 65535;
cl.tolerance_note = ['counts use one quantisation step of tolerance; ' ...
    'the sky floor equals T_min, so blank sky sits a float epsilon ' ...
    'below it and a bare comparison would report it as clipped'];
cl.background.pixels_below_T_min = sum(fr.px_below_tmin_bg);
cl.background.pixels_at_floor    = sum(fr.px_at_floor_bg);
cl.background.pixels_above_T_max = sum(fr.px_above_tmax_bg);
cl.background.percentage_below   = 100*sum(fr.px_below_tmin_bg)/max(sum(fr.n_bg),1);
cl.background.percentage_above   = 100*sum(fr.px_above_tmax_bg)/max(sum(fr.n_bg),1);
cl.target.pixels_below_T_min     = sum(fr.px_below_tmin_tgt);
cl.target.pixels_above_T_max     = sum(fr.px_above_tmax_tgt);
cl.target.percentage_below       = 100*sum(fr.px_below_tmin_tgt)/max(sum(fr.n_tgt),1);
cl.target.percentage_above       = 100*sum(fr.px_above_tmax_tgt)/max(sum(fr.n_tgt),1);
cl.target_core.pixels_below_T_min = sum(fr.px_below_tmin_core);
cl.target_core.percentage_below   = 100*sum(fr.px_below_tmin_core)/max(sum(fr.n_core),1);
cl.target_core.note = ['mask eroded by 2 px; excludes PSF-blurred edge ' ...
    'pixels, which mix target radiance with the cold background'];
meta.summary.clipping = cl;
if any(vis)
    meta.summary.target_pixels.min  = min(fr.pixels(vis));
    meta.summary.target_pixels.max  = max(fr.pixels(vis));
    meta.summary.target_pixels.mean = mean(fr.pixels(vis));
    meta.summary.target_angular_size_deg.min = min(fr.ang_size_deg(vis));
    meta.summary.target_angular_size_deg.max = max(fr.ang_size_deg(vis));
end

end
