function write_dataset_json(dataset_root, config, RUN)
%WRITE_DATASET_JSON Write the dataset-level constants, once.
%
%   write_dataset_json(dataset_root, config, RUN)
%
%   Everything that is IDENTICAL in every sequence of every spacecraft lives
%   here: camera intrinsics, sensor band, the DN->Kelvin mapping, the Earth
%   and star model configuration, frame conventions, product roles and the
%   known limitations of the simulation.
%
%   Previously all of this was repeated inside each sequence's metadata.json
%   -- about 65 fields x 110 sequences. Hoisting it removes the duplication
%   and, more importantly, gives the dataset a single place a reader can look
%   to answer "what does a pixel mean" and "what is not modelled".
%
%   Per-sequence metadata.json holds only what VARIES: seeds, trajectory,
%   attitude, illumination, the thermal draw and the Earth placement.
%
%   Rewritten on every run so it can never go stale against the code.

j = struct();

j.name              = 'Synthetic Thermal RSO Dataset';
j.version           = '1.0';
j.created_utc       = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
j.generator_version = local_generator_version();
j.matlab_version    = ['MATLAB ' version('-release')];

% ---- Frame and unit conventions --------------------------------------
% Stated once, explicitly, because every downstream user has to guess
% otherwise. labels.csv poses are CAMERA frame, not ECI.
j.conventions.quaternion   = '[w x y z]';
j.conventions.pose_frame   = 'camera';
j.conventions.angles       = 'degrees';
j.conventions.temperature  = 'kelvin';
j.conventions.bbox         = '[x y width height], 1-based pixels';
j.conventions.image_origin = 'top-left, pixel (1,1) is the first row and column';

% ---- Camera ----------------------------------------------------------
f_px = config.thermal.focal_length / config.thermal.pixel_pitch;
j.camera.resolution_px      = config.thermal.resolution;
j.camera.fov_deg            = config.thermal.fov_deg;
j.camera.focal_length_mm    = config.thermal.focal_length * 1e3;
j.camera.pixel_pitch_um     = config.thermal.pixel_pitch * 1e6;
j.camera.focal_length_px    = f_px;
j.camera.ifov_urad          = config.thermal.pixel_pitch / config.thermal.focal_length * 1e6;
j.camera.half_diagonal_deg  = atand(hypot(config.thermal.resolution(1), ...
                                          config.thermal.resolution(2)) / (2 * f_px));
if isfield(config.thermal, 'bit_depth')
    j.camera.bit_depth = config.thermal.bit_depth;
else
    j.camera.bit_depth = 16;
end
% A run made under cfg.debug_fov_deg uses a different camera from production
% but is otherwise indistinguishable. Say so here rather than stamping an
% alarming note onto every sequence.
j.camera.is_production = ~(isfield(RUN,'debug_fov_deg') && ~isempty(RUN.debug_fov_deg));
if ~j.camera.is_production
    j.camera.fov_source = sprintf('cfg.debug_fov_deg = %g (overrides config_ProximityOps.mat)', ...
        RUN.debug_fov_deg);
else
    j.camera.fov_source = 'config_ProximityOps.mat';
end

% ---- Sensor ----------------------------------------------------------
if isfield(config.thermal, 'band')
    j.sensor.band                 = config.thermal.band;
    j.sensor.wavelength_um        = config.thermal.wavelength_range * 1e6;
    j.sensor.wavelength_centre_um = config.thermal.wavelength_center * 1e6;
    j.sensor.netd_band_default_K  = config.thermal.netd;
end
j.sensor.detector_type = 'uncooled microbolometer';
j.sensor.note = ['Per-sequence NETD and blur are random draws recorded in ' ...
                 'each sequence under "noise"; the value here is the band default.'];

% ---- Radiometry: how a pixel becomes a temperature -------------------
Tmin = RUN.sensor.T_min;
Tmax = RUN.sensor.T_max;
dn_max = 2^j.camera.bit_depth - 1;
j.radiometry.quantity      = 'apparent_temperature';
j.radiometry.unit          = 'K';
j.radiometry.encoding      = 'linear';
j.radiometry.save_window_K = [Tmin, Tmax];
j.radiometry.bit_depth     = j.camera.bit_depth;
j.radiometry.dn_to_kelvin  = sprintf('T = %g + DN * %g / %d', Tmin, Tmax - Tmin, dn_max);
j.radiometry.kelvin_to_dn  = sprintf('DN = round((T - %g) * %d / %g)', Tmin, dn_max, Tmax - Tmin);
j.radiometry.clipping      = 'clamped at both ends; values outside the window are lost, not wrapped';
j.radiometry.quantity_note = ['Pixels carry APPARENT (brightness) temperature, what a camera ' ...
    'inverting radiance at eps=1 would report -- not kinetic temperature. Per-face emissivity ' ...
    'is applied at the pixel via band-centre Planck. Kinetic temperatures are recorded per ' ...
    'sequence under thermal.realised_state_K.'];
j.radiometry.emissivity_model = 'band-centre Planck inversion';
if isfield(j.sensor, 'wavelength_centre_um')
    j.radiometry.band_centre_um = j.sensor.wavelength_centre_um;
end
if isfield(RUN.sensor,'surroundings_K') && ~isempty(RUN.sensor.surroundings_K)
    j.radiometry.surroundings_K = RUN.sensor.surroundings_K;
else
    [~, ~, env_db] = thermal_database();
    j.radiometry.surroundings_K = env_db.deep_space_K;
end
j.radiometry.surroundings_note = ['Deep space is the COLD LIMIT: it assumes reflective ' ...
    'surfaces see only sky. A blanket facing Earth reflects a ~255 K disc and reads warmer, ' ...
    'so real MLI is view-dependent. Per-face view factors are not modelled.'];

% ---- Earth model -----------------------------------------------------
j.earth.enabled       = logical(RUN.earth.enabled);
j.earth.renderer      = 'GeoGlobe';
j.earth.source        = 'GeoGlobe Satellite Basemap';
j.earth.source_note   = ['Live network basemap. Imagery may change over time, ' ...
                         'so Earth backgrounds are not byte-reproducible after the fact.'];
j.earth.fit_mode      = char(get_field(RUN.earth, 'fit_mode', 'crop'));
if strcmpi(j.earth.fit_mode, 'fill')
    j.earth.fit_mode_note = ['Earth is rendered at GeoGlobe native FOV, NOT the camera FOV. ' ...
        'Background scale is inconsistent with the spacecraft projection; ' ...
        'target labels, bounding boxes, range and pose are unaffected.'];
end
j.earth.thermal_model         = 'simple 4-class engineering model (space/ocean/land/cloud)';
j.earth.thermal_classes       = {'space','ocean','land','cloud'};
j.earth.temps_K               = RUN.earth.temps;
j.earth.texture_amplitude_K   = RUN.earth.texture_amplitude_K;
j.earth.diurnal_amplitude_K   = RUN.earth.diurnal_amplitude_K;
j.earth.diurnal_enabled_per_class = RUN.earth.diurnal_amplitude_K > 0;
j.earth.lst_lag_hours         = RUN.earth.lst_lag_hours;
j.earth.radius_m              = 6371000;
fp = get_field(RUN.earth, 'forced_pitch_deg',   []);
fh = get_field(RUN.earth, 'forced_heading_deg', []);
j.earth.camera_angles_forced = ~isempty(fp) || ~isempty(fh);
if ~isempty(fp); j.earth.forced_pitch_deg   = fp; end
if ~isempty(fh); j.earth.forced_heading_deg = fh; end
if j.earth.camera_angles_forced
    j.earth.camera_angles_note = ['Earth camera pitch/heading are FORCED, not derived from ' ...
        'spacecraft attitude, so Earth is scenery rather than a view-consistent background. ' ...
        'scene_class in each sequence is not meaningful for this run.'];
end

% ---- Star field ------------------------------------------------------
j.stars.enabled          = logical(RUN.stars.enabled);
j.stars.catalog          = 'Hipparcos Main Catalogue';
j.stars.mag_limit        = RUN.stars.mag_limit;
j.stars.peak_temp_mag0_K = RUN.stars.peak_temp_mag0;
j.stars.flux_model       = 'Pogson magnitude';
j.stars.psf              = 'Gaussian';
j.stars.projection       = 'pinhole';
j.stars.sky_floor_K      = RUN.stars.temp_range(1);
j.stars.proper_motion    = logical(RUN.stars.proper_motion_enabled);
j.stars.parallax         = logical(RUN.stars.parallax_enabled);
j.stars.epoch_year       = RUN.stars.epoch_year;

% ---- Thermal model ---------------------------------------------------
j.thermal_model.id       = 'component_database_v1';
j.thermal_model.source   = 'Pipeline/thermal_database.m';
if isempty(RUN.thermal.component_base_K)
    j.thermal_model.mode = 'database';
else
    j.thermal_model.mode = 'legacy';
end
j.thermal_model.relaxation_tau = RUN.thermal.relaxation_tau;
j.thermal_model.equation = ['f = max(0, dot(face_normal, sun_direction)); ' ...
    'sunlit: T = base + (sunlit - base) * f; ' ...
    'eclipse: T = eclipse; ' ...
    'both: T = T + variation * jitter(face), jitter deterministic per face'];
j.thermal_model.sampling = ['base/sunlit/eclipse are drawn once per sequence from the ' ...
    '[lo hi] ranges in the database and held fixed for every frame of that sequence; ' ...
    'the drawn values are recorded per sequence under "thermal.realised_state_K"'];

% ---- Taxonomy --------------------------------------------------------
cls = class_definitions();
j.taxonomy.version     = 'v1';
j.taxonomy.num_classes = numel(cls);
j.taxonomy.class_map   = 'class_map.json';
j.taxonomy.class_colors = 'class_colors.json';
j.taxonomy.background_id = 0;

% ---- Products --------------------------------------------------------
j.products.thermal_gray        = 'training';
j.products.thermal_rgb         = 'training';
j.products.component_masks     = 'training';
j.products.component_masks_rgb = 'training';
j.products.visual_gray         = 'display only';
j.products.visual_rgb          = 'display only';
j.products.visual_note = ['visual_* are display-enhanced derivatives of the final 16-bit ' ...
    'thermal image: y = log1p(200*x)/log1p(200), x = DN/65535. Monotone, so relative ' ...
    'brightness ordering is preserved, but the mapping is non-linear in temperature. ' ...
    'Not for training.'];

% ---- Known limitations ----------------------------------------------
% Stated plainly. A user who trains a material classifier on these images
% needs to know the emissivity caveat before, not after.
j.known_limitations.emissivity_in_radiance = true;
j.known_limitations.emissivity_note = ['Per-face emissivity IS applied: pixels carry apparent ' ...
    'temperature, and the reflected environment now uses per-face view factors to Earth. ' ...
    'What remains unmodelled is self-viewing between the spacecraft own faces, and reflected ' ...
    'sunlight (a fraction of a percent of the thermal signal in band).'];

% Reflected environment and fixed-pattern noise are now MODELLED, and these
% flags follow the live configuration rather than a literal -- a dataset that
% declares a limitation it no longer has is worse than one that declares none.
j.known_limitations.reflected_view_factors = local_env_on(RUN);
if j.known_limitations.reflected_view_factors
    j.known_limitations.reflected_note = sprintf(['Per-face view factor to Earth, ' ...
        'mixed in radiance: L = F*L_bb(%g K) + (1-F)*L_bb(%g K). Nadir-facing F = 0.835 ' ...
        'at 600 km, zenith-facing 0. Earth IR is NOT added as a heating term -- the ' ...
        'kinetic temperatures already represent LEO equilibrium.'], ...
        local_env_val(RUN,'earth_ir_K',255), local_env_val(RUN,'deep_space_K',2.7));
else
    j.known_limitations.reflected_note = ['Surroundings treated as a single temperature ' ...
        '(the cold limit), so low-emissivity surfaces render at their coldest plausible value.'];
end

j.known_limitations.fixed_pattern_noise = local_fpn_on(RUN);
if j.known_limitations.fixed_pattern_noise
    j.known_limitations.fpn_note = ['Column, row and pixel offsets plus referenced gain, ' ...
        'drawn once per SEQUENCE so the pattern is identical on every frame of a track and ' ...
        'cannot be averaged out. Column-dominated, as an uncooled array is after NUC. ' ...
        'Dead pixels are off by default because delivered imagery normally has bad-pixel ' ...
        'replacement applied.'];
else
    j.known_limitations.fpn_note = ['No microbolometer fixed-pattern noise (column/row ' ...
        'streaking). Only zero-mean Gaussian NETD and a Gaussian PSF are applied.'];
end
j.known_limitations.thermal_transients = false;
j.known_limitations.transient_note = ['Steady state per frame: no heat storage, conduction or ' ...
    'lag. Sequences are a few seconds long, so this is negligible at the sampled timescale.'];
j.known_limitations.conduction_gradients   = false;
j.known_limitations.earth_albedo_on_target = false;
j.known_limitations.atmospheric_transmission = 1.0;
empty_ids = local_empty_classes(dataset_root, cls);
if ~isempty(empty_ids)
    j.known_limitations.empty_classes = empty_ids;
    j.known_limitations.empty_classes_note = ['These class ids exist in the taxonomy but do ' ...
        'not occur in any generated mask. Measured by scanning component_masks/*.png, so it ' ...
        'reflects what was actually labelled rather than what was merely mapped.'];
end

% ---- Write -----------------------------------------------------------
if ~exist(dataset_root, 'dir'); mkdir(dataset_root); end
path = fullfile(dataset_root, 'dataset_info.json');
fid = fopen(path, 'w');
if fid == -1
    warning('write_dataset_json:cannotWrite', 'Could not write %s', path);
    return;
end
fprintf(fid, '%s', jsonencode(j, 'PrettyPrint', true));
fclose(fid);
fprintf('Wrote %s\n', path);

end


function v = local_generator_version()
% Short identity for the code that produced the dataset. Not a git repo, so
% hash the files that actually determine the output.
files = {'generate_rso_dataset.m', 'config.m', 'compute_temperatures.m', ...
         fullfile('Pipeline','thermal_database.m'), ...
         fullfile('Pipeline','class_definitions.m')};
root = fileparts(fileparts(mfilename('fullpath')));
acc = '';
for k = 1:numel(files)
    p = fullfile(root, files{k});
    if isfile(p); acc = [acc fileread(p)]; end %#ok<AGROW>
end
if isempty(acc); v = 'unknown'; return; end
md = java.security.MessageDigest.getInstance('SHA-1');
h  = typecast(md.digest(uint8(acc)), 'uint8');
v  = lower(sprintf('%02x', h(1:5)));
end


function ids = local_empty_classes(dataset_root, cls)
% Class ids that do not occur in any GENERATED MASK.
%
% This used to read the component_map.json files, which missed two cases: a
% class populated by filename pattern rather than an explicit mapping entry
% was wrongly reported as empty, and a mapping that existed but whose geometry
% never projected into frame was wrongly reported as present. Reading the
% masks answers the question that actually matters -- did this class ever
% appear in a label?
%
% Masks are written before dataset_info.json is refreshed on the NEXT run, so on a
% first-ever run this falls back to the mapping scan. The value is therefore
% correct from the second run onward, and the source is recorded either way.
ids = [];
all_ids = [cls.id]; all_ids = all_ids(all_ids > 0);

seen = [];
sc_root = dataset_root;
n_masks = 0;
if isfolder(sc_root)
    d = dir(fullfile(sc_root, '**', 'component_masks', '*.png'));
    for k = 1:numel(d)
        try
            v = unique(imread(fullfile(d(k).folder, d(k).name)));
        catch
            continue;
        end
        seen = union(seen, double(v(:))');
        n_masks = n_masks + 1;
    end
end

if n_masks > 0
    ids = setdiff(all_ids, seen);
else
    ids = local_unmapped_classes(dataset_root, all_ids);   % first run only
end
ids = ids(:)';
end


function ids = local_unmapped_classes(dataset_root, all_ids)
% Fallback for a first run, before any mask exists: ids with no explicit
% component_map.json entry anywhere in the fleet.
used = [];
sc_root = fullfile(fileparts(fileparts(dataset_root)), 'data', 'spacecraft');
if ~isfolder(sc_root); ids = all_ids; return; end
d = dir(sc_root);
for k = 1:numel(d)
    if ~d(k).isdir || startsWith(d(k).name, '.'); continue; end
    p = fullfile(sc_root, d(k).name, 'component_map.json');
    if ~isfile(p); continue; end
    try
        m = jsondecode(fileread(p));
    catch
        continue;
    end
    if isfield(m, 'mappings')
        mp = m.mappings;
        if iscell(mp)
            for q = 1:numel(mp); used(end+1) = mp{q}.material_id; end %#ok<AGROW>
        else
            used = [used, [mp.material_id]]; %#ok<AGROW>
        end
    end
    if isfield(m, 'default') && isfield(m.default, 'material_id')
        used(end+1) = m.default.material_id; %#ok<AGROW>
    end
end
ids = setdiff(all_ids, unique(used));
end


function tf = local_env_on(RUN)
tf = true;
if isfield(RUN,'sensor') && isfield(RUN.sensor,'surroundings_K') && ...
        ~isempty(RUN.sensor.surroundings_K)
    tf = false;                       % explicit scalar override wins
elseif isfield(RUN,'environment') && isfield(RUN.environment,'enabled')
    tf = logical(RUN.environment.enabled);
end
end

function tf = local_fpn_on(RUN)
tf = false;
if isfield(RUN,'sensor') && isfield(RUN.sensor,'fpn_enabled')
    tf = logical(RUN.sensor.fpn_enabled);
end
end

function v = local_env_val(RUN, f, dflt)
v = dflt;
if isfield(RUN,'environment') && isfield(RUN.environment,f) && ~isempty(RUN.environment.(f))
    v = RUN.environment.(f);
end
end
