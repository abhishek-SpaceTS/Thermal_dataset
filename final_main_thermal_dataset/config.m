function cfg = config(varargin)
%CONFIG  The single source of configuration for the thermal dataset generator.
%
%   cfg = config();            % return the configuration (what the pipeline does)
%   cfg = config('verbose');   % also print the resolved parameter summary
%
%   Every value here is READ BY THE GENERATOR. Nothing is kept for reference:
%   the chief/deputy orbit blocks, visible camera, lidar, radar, RF, materials
%   and path tables that the old Phase 0 file carried are gone, because no
%   file under src/ ever read them and an unread setting is a setting that
%   will eventually be believed.
%
%   Two things are DERIVED and deliberately not settable here:
%     field of view    src/sensor/camera_intrinsics.m, from detector and lens
%     wavelength band  src/sensor/apply_band.m, from cfg.sensor.band
%   Configuring either separately would let it disagree with the hardware,
%   which is exactly what the old file did (values 4 um / 3-5 um while the
%   comments and the summary print both claimed 8-14 um LWIR).
%
%   Temperatures are not here either -- they live in
%   src/target/thermal_database.m, one row per component class.
%
%   Sections:
%     1  what to generate      spacecraft, counts, resume flags
%     2  range brackets        distance and allowed motion per bracket
%     3  framing               how close to the frame edge the target may go
%     4  target motion         tumbling profiles
%     5  star field
%     6  Earth background
%     7  thermal camera        detector, lens, band, noise, save window
%     8  thermal model         how surface temperatures are applied
%     9  outputs and display
%    10  reproducibility

want_verbose = any(strcmpi(varargin, 'verbose'));

%% =========================================================================
%  SECTION 1: WHAT TO GENERATE
%  =========================================================================

% Which spacecraft: "ALL", or a folder name under data/spacecraft
% (case-insensitive). Options: ALL | M4V | Rosetta | Cassini Assembly |
% CloudSat (C) | CubeSat - ICECube | Deep Space 1 | Juno (A) | Kepler (A) |
% Magellan | NEAR Shoemaker
cfg.spacecraft = "ALL";

% true = quick check, 1 sequence x 5 frames per spacecraft (ignores counts).
cfg.debug_mode = false;

% How much to generate, and the playback rate / scenario time step.
cfg.num_sequences       = 30;
cfg.frames_per_sequence = 50;
cfg.fps                 = 10;

% overwrite = redo existing sequences; resume = skip ones already complete.
cfg.overwrite = true;
cfg.resume    = true;

% Orbital altitudes of the chaser (observer) and target (RSO), metres.
% These set the Earth-geometry (limb angle, view factors) and the altitude
% difference that separates the two vehicles in the LVLH frame.
%
% The altitude gap is deliberately small (100 m) so that the true 3D range
% sqrt(horiz^2 + alt_diff^2) barely differs from the bracket distance, keeping
% full close-range diversity across all trajectory types. All trajectory files
% read this value automatically -- change altitude ONLY here.
cfg.orbit.altitude_chaser_m = 600000;    % 600.0 km
cfg.orbit.altitude_target_m = 601000;    % 601.0 km  (1 km higher than chaser)

%% =========================================================================
%  SECTION 2: RANGE BRACKETS
%  =========================================================================
%  {name, start_m, end_m, allowed motions}. ONE ROW IS DRAWN UNIFORMLY per
%  sequence (generate_random_scenario.m line 16), so this list is also the
%  range DISTRIBUTION of the dataset -- six rows means each bracket gets a
%  sixth of the sequences no matter how wide it is.
%
%  To weight the mix, repeat a row: a bracket listed twice is drawn twice as
%  often. To shift the dataset toward resolved targets, drop the far rows.
%
%  How large the target actually renders is set by IFOV = pixel_pitch /
%  focal_length, not by the bracket. Run show_distances to see the ladder for
%  the optics currently in Section 7.
%  =========================================================================

cfg.distance_scenarios = {
    'Long-Range Detection', 10000, 5000, {'straight', 'flyby'};
    'Far Approach',          5000, 1000, {'straight', 'flyby', 'lateral', 'diagonal', 'cw_relative_motion'};
    'Approach Tracking',     1000,  500, {'straight', 'lateral', 'diagonal', 'cw_relative_motion'};
    'Close Approach',         500,  250, {'straight', 'lateral', 'diagonal', 'cw_relative_motion'};
    'Close Observation',      250,  150, {'straight', 'lateral', 'diagonal', 'cw_relative_motion'};
    'Close Inspection',       150,  100, {'orbit', 'lateral', 'station_keeping', 'cw_relative_motion'}
};

%% =========================================================================
%  SECTION 3: FRAMING
%  =========================================================================
%  How close to the frame edge a trajectory is allowed to put the target.
%
%  true  = the whole body stays inside the frame. The target's angular radius
%          is reserved out of the half-field, so the reservation scales with
%          range: a few pixels at 12 km, most of the frame at 100 m.
%  false = only the pixel margin below is reserved, so the target may be
%          truncated by the edge. Truncation is realistic training data; a
%          target entirely OUTSIDE the frame is not, and is excluded either way.
%
%  Enforced PER AXIS. The horizontal and vertical fields differ on a
%  non-square detector, and using the horizontal number for both is what used
%  to render targets off the top and bottom of the frame with a valid pose and
%  an empty mask -- 45 % of inspection_orbit frames. See
%  src/scenario/framing_limits.m.
%
%  A body larger than the frame cannot be contained: it is centred and
%  truncated, which is the only physical option.
%  =========================================================================

cfg.framing.keep_target_fully_inside = false;

% Pixels of clear space kept between the target and the frame border, so the
% PSF skirt and the bounding box do not touch the edge.
cfg.framing.edge_margin_px = 4;

%% =========================================================================
%  SECTION 4: TARGET MOTION
%  =========================================================================

% Where the TARGET's attitude comes from.
%
%   "sampled" - draw a tumbling profile below and integrate a constant body
%               rate about a random axis. Independent per sequence, which is
%               what a training set wants.
%
%   "hil"     - read the propagated attitude from the ProximityOps HIL
%               Phase 1 truth files instead, sampled onto our frame times
%               (slerp, see src/scenario/hil_state_at.m). The tumbling list
%               below is then ignored and motion.tumbling_name records
%               "HIL propagated".
%
%               Only the target ATTITUDE is taken. Range still comes from the
%               distance brackets and the camera attitude is still drawn, so
%               sequences stay varied. For an exact frame-by-frame match of
%               HIL geometry use validate_against_hil.m, which takes position
%               and attitude both.
cfg.attitude.source = "sampled";

% Phase_1_Truth folder written by the HIL run_phase1_all.m. Only read when
% attitude.source is "hil", or by validate_against_hil.m.
cfg.attitude.hil_dir = 'C:\ProximityOps_HIL\Phase_1_Truth';

% Seconds into the HIL trajectory at which a sequence starts. Sequence k
% begins at hil_start_s + (k-1)*frames_per_sequence/fps, so consecutive
% sequences walk along the HIL pass instead of repeating one instant.
cfg.attitude.hil_start_s = 0;

% Tumbling profiles {name, rad/s}; one drawn per sequence, random axis.
% Ignored when attitude.source is "hil".
cfg.motion.tumbling = {
    'Stable',               0.00;
    'Very Slow Tumbling',   0.01;
    'Slow Tumbling',        0.05;
    'Medium Tumbling',      0.15;
    'Fast Tumbling',        0.50;
    'Multi-Axis Tumbling',  0.25
};

% The sun direction is NOT configured. generate_random_scenario.m samples it
% continuously on the sphere: solar phase uniform over [0,180] deg, azimuth
% uniform over [0,360). The eight axis-aligned vectors that used to be listed
% produced only three phase angles against the +z boresight -- 0, 90 and
% 180 deg -- with 6 of the 8 landing on exactly 90, so there was no
% illumination geometry in between.
%
% Each sequence records its realised geometry under illumination.*:
% sun_direction_cam, sun_phase_nominal_deg, solar_phase_angle_deg, sun_bin.

%% =========================================================================
%  SECTION 5: STAR FIELD
%  =========================================================================

% false = no star field; the sky becomes a flat floor at T_min.
cfg.stars.enabled = true;

% [blank-sky floor, ceiling] in K.
% Floor MUST equal cfg.sensor.T_min or the sky stops being black.
cfg.stars.temp_range = [130 400];

% Star BRIGHTNESS knob: peak of a magnitude-0 star. Higher = brighter.
%
% A star's peak is added on top of the sky floor and then clamped to the
% headroom (ceiling - floor), so its DN is peak/headroom. Widening the window
% therefore DIMS every star unless this is scaled with it. Scaled each time
% the window widened: 3200 over 200 K, 4000 over 250 K, now 4320 over 270 K.
% Same ratio throughout, so the star field renders bit-identically and the
% saturation cut-off stays at mag ~3.0.
cfg.stars.peak_temp_mag0 = 4320;

% Faintest star rendered. 9.0 = 83392 stars; ~6.5 = naked-eye only, faster.
cfg.stars.mag_limit = 9.0;

% Star PSF sigma in px at reference magnitude 3.5. [] = renderer default (1.5).
cfg.stars.psf_sigma_px = [];

% Correct catalogue J2000 positions to the observation epoch.
cfg.stars.proper_motion_enabled = true;
cfg.stars.parallax_enabled      = true;
cfg.stars.epoch_year            = 2025.0;
cfg.stars.epoch_day_of_year     = 1;

% Sub-pixel position noise from the catalogue's own e_ra/e_dec uncertainties.
cfg.stars.jitter_enabled = true;

% Vary known variable stars between their Hp max/min.
cfg.stars.variability_enabled = true;

%% =========================================================================
%  SECTION 6: EARTH BACKGROUND
%  =========================================================================
%  NOTE: the orbit altitude the Earth layer uses is 600 km, HARDCODED at
%  src/scenario/author_earth.m line 18. It is not read from this file.
%  =========================================================================

% false = no Earth layer. true costs ~3-5 s/frame and needs a network
% connection. The Mapping Toolbox licence is single-seat -- do not run a
% second MATLAB during generation.
cfg.earth.enabled = true;

% How often Earth is [outside frame, on the horizon, filling frame].
% Weights, normalised. Limb-weighted so most frames show a horizon arc.
%
% "none" is hard to achieve while fit_mode is "fill": that mode draws
% GeoGlobe's whole ~60 deg view regardless of the camera field, so Earth can
% appear even when the sampled geometry places it outside the frame. The
% mismatch is recorded per sequence as earth.scene_class_match.
cfg.earth.scene_class_mix = [0.20, 0.60, 0.20];

% How the GeoGlobe image is fitted to the camera field. GeoGlobe has no FOV
% control and always draws ~60.3 deg (measured, see earth_geoglobe_config.m).
%
%   "crop" - take the centre tan(fov/2)/tan(60.313/2) of it, so Earth is in
%            the SAME camera as the spacecraft and stars. Physically correct,
%            but at a narrow field that is a tiny crop upsampled heavily, so
%            Earth is soft and the horizon nearly straight.
%
%   "fill" - skip the crop and resize the whole ~60.3 deg view into the frame.
%            Earth looks sharper and the horizon is visibly curved. BUT the
%            Earth layer is then a ~60 deg image behind a spacecraft projected
%            at the cfg field, so the two disagree about the camera.
%            Backgrounds are for looks, not geometry: bounding boxes, range
%            and pose stay correct, Earth scale does not.
%
% Recorded in metadata as earth.fit_mode so frames stay self-describing.
cfg.earth.fit_mode = "fill";

% Forced Earth camera angles (scenery override).
% [] = derive pitch/heading from the spacecraft attitude, so Earth sits where
% the camera is actually looking. That is the physically correct behaviour and
% is what scene_class_mix steers.
%
% Setting a number FORCES that angle instead. Two consequences, both
% deliberate: scene_class_mix stops having any effect, and Earth no longer
% corresponds to the camera attitude at all. Pair with fit_mode = "fill".
% Useful pitches at 600 km: the horizon is at -24 deg.
cfg.earth.forced_pitch_deg   = [];
cfg.earth.forced_heading_deg = [];

% Surface temperatures [ocean, land, cloud/ice] in K. Land is its NIGHT
% value; the daytime rise comes from diurnal_amplitude_K below.
%
% The renderer classifies the basemap into only three surface types, so the
% eight real surface classes are folded onto them by temperature range:
%
%   ocean       273-303 K   open water, pole to tropics
%   land        278-333 K   union of vegetation 278-308, agricultural
%                           283-313, rocky/bare 283-323 and desert 293-333
%   cloud/ice   203-273 K   cloud tops 203-273 and snow/ice 223-273, which
%                           the classifier cannot separate -- both are white
%
% Land is one class covering 55 K because RGB cannot tell desert from forest.
% What saves this is that the texture term is driven by basemap luminance,
% and the correlation happens to be right: desert is bright AND hot,
% vegetation is dark AND cooler, so brighter ground renders warmer.
%
%   value = base +/- texture + diurnal * mu^0.25
%     ocean      288 +/-15 +  2  ->  273 - 305 K
%     land       288 +/-10 + 35  ->  278 - 333 K
%     cloud/ice  238 +/-35 +  0  ->  203 - 273 K
cfg.earth.epsilon = 0.98;
cfg.earth.temps = [288, 288, 238];

% Within-class variation [ocean, land, cloud/ice] in K; all zero = flat Earth.
% These are large because a GeoGlobe view at 600 km spans ~60 deg -- thousands
% of km, often 40 deg of latitude. Ocean was +/-2 K, sized for a small
% footprint, which rendered the sea as one featureless plate (measured IQR
% 0.3 K). Real SST across that swath varies 273-303 K.
cfg.earth.texture_amplitude_K = [15, 10, 35];

% Smoothing of the Earth layer in px. [] = match the upsample; 0 = hard limb.
cfg.earth.edge_softness_px = [];

% Day/night rise in K added as amp*mu^0.25, PER CLASS [ocean land cloud].
% Thermal inertia sets these: ocean 0.5-3 K over a day, vegetated land 10-20,
% desert 30-50, cloud tops ~0 because their temperature comes from altitude.
% A single scalar is still accepted and applied to every class.
% All zeros = no terminator; the night side renders as warm as the day side.
cfg.earth.diurnal_amplitude_K = [2, 35, 0];

% Ground thermal lag behind the sun, hours. Only bites when diurnal > 0.
cfg.earth.lst_lag_hours = 2.0;

% Smallest connected Earth region kept, px. Removes false Earth speckle.
cfg.earth.min_blob_px = 5000;

%% =========================================================================
%  SECTION 7: THERMAL CAMERA
%  =========================================================================
%  The physical detector and lens.
%
%  FIELD OF VIEW IS DERIVED, NEVER CONFIGURED. src/sensor/camera_intrinsics.m
%  computes it per axis from the detector and the lens:
%
%      fov_h = 2*atand(width_px  * pixel_pitch / (2 * focal_length))
%      fov_v = 2*atand(height_px * pixel_pitch / (2 * focal_length))
%
%  PIXELS ON TARGET are set by IFOV = pixel_pitch / focal_length and by
%  nothing else. Detector size changes how much sky is covered, not how large
%  the target renders. Increasing the resolution alone does not magnify.
%  Run show_distances to see the ladder for whatever is set here.
%  =========================================================================

cfg.camera.resolution_px  = [1280 1024];   % [width height] px
cfg.camera.focal_length_m = .500;             % 500 mm
cfg.camera.pixel_pitch_m  = 15e-6;         % 15 um
cfg.camera.bit_depth      = 16;            % 0-65535 DN

% Camera mounting relative to the spacecraft body, degrees [roll pitch yaw].
% Zero means the camera boresight is the body +z axis.
cfg.camera.mount_rpy_deg  = [0 0 0];

% Optical point-spread sigma in px, applied to the rendered frame. This is
% why a far target reads cold as well as small: a 5 px object convolved with
% sigma 1.5 px loses most of its peak.
cfg.camera.psf_sigma_px   = 1.5;

% ---- Band and noise -----------------------------------------------------
% Infrared band: "LWIR" (8-14 um, NETD 50 mK) or "MWIR" (3-5 um, NETD 20 mK).
% This one switch sets wavelength range, band centre and default NETD
% together, in src/sensor/apply_band.m, so they cannot disagree.
cfg.sensor.band = "LWIR";

% Explicit detector NETD in K. [] = use the band default above.
cfg.sensor.netd_K = [];

% Optical PSF inside the renderer, px. [] = built-in 1.5; 0 = no blur.
cfg.sensor.psf_sigma_px = [];

% Extra defocus drawn once per sequence.
cfg.sensor.scenario_blur_enabled = true;

% Upper bound of that draw, px: blur ~ U(0, blur_max_px).
cfg.sensor.blur_max_px = 1.5;

% Detector noise, added after blur.
cfg.sensor.netd_enabled = true;

% Upper bound of the per-sequence noise draw, K: netd ~ U(0, netd_max_K).
cfg.sensor.netd_max_K = 0.05;

% ---- Fixed 16-bit save window, K ----------------------------------------
% Everything outside CLIPS. Keep T_min equal to stars.temp_range(1), or the
% sky stops mapping to DN 0 and stops being black.
%
% WHY 130 AND NOT 200. The floor was 200 K when the old thermal model never
% rendered below 250 K, so it never fired. The component database models
% eclipse properly, and a solar array in shadow is genuinely cold:
%
%     Solar Panel        eclipse 190-210 K, +/-5  ->  185 K worst case
%     Silver MLI         eclipse 205-215 K, +/-5  ->  200 K worst case
%
% At a 200 K floor those clipped to DN 0 -- the same value as empty sky -- so
% the mask claimed a solar panel where the image showed vacuum. Measured on
% M4V: 21 of 40 sequences affected, losing 33.5 % of the target's pixels.
%
% APPARENT temperatures reach lower still than kinetic ones. Emissivity is
% applied at the pixel, and a low-emissivity surface reports mostly what it
% reflects -- deep space -- rather than its own heat:
%
%     Silver MLI  eclipse 200 K kinetic, eps 0.05  ->  141 K apparent
%     Gold MLI    eclipse 210 K kinetic, eps 0.05  ->  146 K apparent
%     Fuel Tank   eclipse 262 K kinetic, eps 0.10  ->  185 K apparent
%
% so the floor moved 200 -> 150 -> 130 K. Quantisation is 4.12 mK per DN,
% still 12x finer than the 50 mK detector NETD.
cfg.sensor.T_min = 130;
cfg.sensor.T_max = 400;

% ---- Reflected environment ----------------------------------------------
% A low-emissivity surface reports mostly what it REFLECTS, so what it faces
% matters as much as how hot it is. With this on, each face gets its own
% environment temperature from its view factor to Earth:
%
%   sin(rho) = R_earth / (R_earth + altitude)      66 deg at 600 km
%   F        = fraction of the face's hemisphere filled by Earth
%   L_env    = F * L_bb(earth_ir_K) + (1-F) * L_bb(2.7 K)
%
% mixed in RADIANCE, not temperature -- Planck is far too non-linear at 10 um
% for a temperature average to be meaningful.
%
% Effect on gold MLI (eps 0.05, 215 K kinetic): about 146 K facing deep
% space, about 230 K facing Earth. The same blanket swings ~80 K within one
% tumble, which is what a real instrument sees and what the previous cold
% limit could not express.
%
% false = every face reflects deep space, the old cold limit. Set this to
% reproduce datasets generated before the environment model existed.
cfg.environment.enabled = true;

% Effective Earth brightness temperature in band, K. Earth's outgoing
% longwave flux of ~240 W/m^2 corresponds to a 255 K radiator, which is the
% standard figure and what the surface classes in Section 6 average to.
cfg.environment.earth_ir_K = 255;

% What a face sees when it is not looking at Earth, K.
cfg.environment.deep_space_K = 2.7;

% NOT MODELLED, deliberately:
%   * Earth IR as a HEATING term. The kinetic temperatures in
%     thermal_database.m are already realistic LEO equilibrium values -- a
%     blanket sits at 215 K in eclipse BECAUSE Earth IR holds it there.
%     Adding it again as an input would double-count it.
%   * Reflected sunlight. In the 8-14 um band the solar contribution is a
%     fraction of a percent of the thermal signal.
%   * Self-viewing between the spacecraft's own faces.

% Temperature of whatever a reflective surface sees, K.
% [] = USE PER-FACE VIEW FACTORS (the default and active path). The renderer
% (environment_temperature.m) calculates exactly how much of Earth's ~255 K disc
% each face sees, so real MLI is physically view-dependent.
% Setting a number here disables per-face calculation and FORCES a scalar
% background temperature for every face instead.
cfg.sensor.surroundings_K = [];

% Widen the camera for inspection: [] = the real optics, or 8 / 10 / 15 / 20.
%
% CLEARED FOR PRODUCTION. Setting this replaces the real optics: it keeps the
% detector and pitch but rewrites the focal length to hit the requested FOV
% exactly, so the recorded optics would describe a lens that does not exist,
% and dataset.json stamps is_production = false.
cfg.debug_fov_deg = [];

%% =========================================================================
%  SECTION 8: THERMAL MODEL
%  =========================================================================
%  THERE ARE NO TEMPERATURES IN THIS FILE. They all live in
%  src/target/thermal_database.m, one row per component class, as [lo hi]
%  ranges for base / sunlit / eclipse plus a per-face variation. To make a
%  component hotter or colder, edit that file, not this one.
%
%  What the renderer does with them, per face:
%
%        f = max(0, dot(face_normal, sun_direction))
%        sunlit:   T = base + (sunlit - base) * f
%        eclipse:  T = eclipse
%        both:     T = T + variation * jitter(face)
%
%  Once per sequence, src/target/sample_thermal_state.m draws one value from
%  each range; every frame of that sequence then uses the same values, so a
%  pass has a consistent thermal state while different passes vary
%  realistically. The draw is seeded on cfg.random_seed + spacecraft +
%  sequence name, so it is reproducible and unaffected by resume skipping.
%  =========================================================================

% LEGACY OVERRIDE. Setting component_base_K to a non-empty column vector
% (one row per class, id 0 excluded) switches back to the pre-database model
% exactly: T = base + solar_gain_K * f, eclipse: T = eclipse_temp_K, then the
% relaxation_tau compression, with tau defaulting to 2. Kept only so datasets
% generated before the database can be reproduced. Leave EMPTY for normal use.
cfg.thermal.component_base_K = [];

% Legacy model only -- ignored unless component_base_K is set above.
% Temperature rise at the sub-solar point, K.
cfg.thermal.solar_gain_K = 80;

% Legacy model only -- ignored unless component_base_K is set above.
% Absolute temperature of every face while in Earth's shadow, K.
cfg.thermal.eclipse_temp_K = 250;

% Contrast compressor around 300 K: T = 300 + (T - 300)/tau.
%   1 = none. The database values render literally. This is the default in
%       database mode, because those values are meant to be taken at face
%       value -- a 250 K radiator should read 250 K, not 275 K.
%   2 = halve all contrast. The default in legacy mode, where it was
%       load-bearing: the old bases plus an 80 K solar gain reached 440 K and
%       saturated about 22 % of target pixels without it.
%
% Despite the name this is NOT a thermal time constant: it uses a fixed
% reference rather than the previous frame, takes no dt and keeps no state,
% so it cannot produce lag.
cfg.thermal.relaxation_tau = 1;

%% =========================================================================
%  SECTION 9: OUTPUTS AND DISPLAY
%  =========================================================================

% Root folder where the dataset is written.
% Each spacecraft gets a sub-folder: <dataset_dir>/<spacecraft_name>/sequences/
% '' or [] = default subfolder 'dataset' inside the project root.
% Set to an absolute path to save anywhere on disk.
cfg.output.dataset_dir = 'C:\Users\lenovo\Desktop\main_thermal_dataset\final_main_thermal_dataset\dataset';

% Which artefacts to write. videos needs thermal_*; run_verification needs
% labels_csv.
cfg.output.thermal_gray        = true;
cfg.output.thermal_rgb         = true;
cfg.output.visual_gray         = false;
cfg.output.visual_rgb          = false;
cfg.output.component_masks     = true;
cfg.output.component_masks_rgb = true;
cfg.output.videos              = true;
cfg.output.labels_csv          = true;
cfg.output.annotations_json    = true;
cfg.output.run_verification    = true;

% How visual_gray / visual_rgb map temperature to brightness. DISPLAY ONLY --
% thermal_gray stays the linear 16-bit Kelvin ground truth either way, and is
% what models should be trained on.
%
%   "scene"  - linear above 235 K, lifted below it. Earth and spacecraft get
%              exactly the thermal_rgb colours, AND faint stars stay visible.
%              5x more visible star pixels than plain linear.
%   "linear" - proportional to temperature everywhere. Faint stars fall to
%              DN 3-19 and disappear.
%   "log"    - lifts the whole range. Shows the most stars, but pushes Earth
%              past DN 172 where the hot colormap turns yellow.
cfg.visual.mode = "scene";

% Gain for "log" mode only; ignored when mode is "linear".
cfg.visual.log_gain = 200.0;

%% =========================================================================
%  SECTION 10: REPRODUCIBILITY
%  =========================================================================

% [] = seed from the clock. An integer fixes the trajectory, attitude, sun
% direction, blur and NETD draws. GeoGlobe's streamed Earth tiles are NOT
% reproducible either way.
%
% SET FOR PUBLICATION. With [] no sequence can ever be regenerated and the
% metadata can only record that fact.
cfg.random_seed = 42;

if want_verbose
    local_print_summary(cfg);
end

end


%% =========================================================================
%  SUMMARY PRINTOUT
%  =========================================================================
function local_print_summary(cfg)

fov_h = 2 * atand(cfg.camera.resolution_px(1) * cfg.camera.pixel_pitch_m / ...
                  (2 * cfg.camera.focal_length_m));
fov_v = 2 * atand(cfg.camera.resolution_px(2) * cfg.camera.pixel_pitch_m / ...
                  (2 * cfg.camera.focal_length_m));
ifov  = cfg.camera.pixel_pitch_m / cfg.camera.focal_length_m;

line = repmat('=', 1, 68);
fprintf('\n%s\nDATASET CONFIGURATION\n%s\n\n', line, line);

fprintf('  Thermal camera:\n');
fprintf('    Resolution     : %d x %d px\n', ...
    cfg.camera.resolution_px(1), cfg.camera.resolution_px(2));
fprintf('    Focal length   : %.1f mm\n', cfg.camera.focal_length_m*1e3);
fprintf('    Pixel pitch    : %.1f um\n', cfg.camera.pixel_pitch_m*1e6);
fprintf('    Field of view  : %.4f x %.4f deg   (DERIVED)\n', fov_h, fov_v);
fprintf('    IFOV           : %.1f urad/px\n', ifov*1e6);
fprintf('    Band           : %s\n', cfg.sensor.band);
fprintf('    Bit depth      : %d bits (0 to %d DN)\n', ...
    cfg.camera.bit_depth, 2^cfg.camera.bit_depth - 1);
fprintf('    Save window    : %g - %g K  (%.2f mK per DN)\n', ...
    cfg.sensor.T_min, cfg.sensor.T_max, ...
    (cfg.sensor.T_max - cfg.sensor.T_min)/65535*1e3);
fprintf('    PSF sigma      : %.1f px\n\n', cfg.camera.psf_sigma_px);

fprintf('  Range brackets (uniform draw, %d rows):\n', ...
    size(cfg.distance_scenarios,1));
for k = 1:size(cfg.distance_scenarios,1)
    d_far = cfg.distance_scenarios{k,2};
    fprintf('    %-22s %6.0f - %5.0f m   target ~%.0f px across\n', ...
        cfg.distance_scenarios{k,1}, d_far, cfg.distance_scenarios{k,3}, ...
        2.0 / (d_far * ifov));
end
fprintf('\n');

fprintf('  Scene:\n');
fprintf('    Star field     : %s\n', local_onoff(cfg.stars.enabled));
fprintf('    Earth layer    : %s  (fit_mode "%s")\n', ...
    local_onoff(cfg.earth.enabled), cfg.earth.fit_mode);
fprintf('    Keep target in : %s  (margin %d px)\n\n', ...
    local_onoff(cfg.framing.keep_target_fully_inside), ...
    cfg.framing.edge_margin_px);

fprintf('  Generation:\n');
fprintf('    Spacecraft     : %s\n', cfg.spacecraft);
fprintf('    Sequences      : %d x %d frames at %d fps\n', ...
    cfg.num_sequences, cfg.frames_per_sequence, cfg.fps);
if isempty(cfg.random_seed)
    fprintf('    Random seed    : [] (NOT reproducible)\n');
else
    fprintf('    Random seed    : %d\n', cfg.random_seed);
end
fprintf('\n%s\n\n', line);

end


function s = local_onoff(tf)
if tf
    s = 'ON';
else
    s = 'OFF';
end
end
