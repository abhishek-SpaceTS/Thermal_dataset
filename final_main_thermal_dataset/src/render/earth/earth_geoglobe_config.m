function cfg = earth_geoglobe_config()
%EARTH_GEOGLOBE_CONFIG Defaults for the GeoGlobe Earth background renderer.
%
%   cfg = earth_geoglobe_config()
%
%   Same pattern as star_default_config.m: callers override only what they
%   care about and the renderer fills in the rest.
%
%   RENDER RESOLUTION IS A SINGLE PARAMETER -- cfg.render_size. Everything
%   downstream (focal length in pixels, crop size, upsample factor) derives
%   from it, so moving to a higher-resolution workstation is a one-number
%   change with no code edits. See earth_geoglobe_crop_size() below for the
%   derived quantities.

%% ---- source render size (THE tuning knob) -----------------------------
% Square capture size in pixels. Bounded in practice by the display: on a
% 1080p screen the usable capture clips at 1061 px high (measured 2026-08-03),
% so 1024 is the largest safe square here. A 4K workstation can raise this to
% ~2100 and immediately gain source detail with no other change.
cfg.render_size = 1024;

%% ---- measured optics --------------------------------------------------
% GeoGlobe exposes no field-of-view API, so the native FOV is a MEASURED
% constant, not a documented one. Measured 2026-08-03 by camera-translation
% phase correlation over four baselines (0.25/0.5/1/2 deg of latitude at
% 600 km): shifts 32/64/128/255 px, focal length spread 0.4%.
%
%   Re-measure with earth_geoglobe_measure_fov() after any MATLAB upgrade,
%   basemap change or display change.
cfg.native_fov_deg = 60.209;
cfg.fov_measured_on = '2026-08-03';
cfg.fov_measured_release = '2026a';

%% ---- globe setup ------------------------------------------------------
cfg.basemap  = 'satellite';
% When the streamed basemap is unreachable GeoGlobe substitutes an offline one
% and only warns. true = stop rather than generate frames with the wrong Earth.
cfg.strict_basemap = true;
cfg.terrain  = 'none';        % terrain relief is invisible at these ranges
cfg.visible  = 'on';         % headless capture verified working
cfg.capture  = 'getframe';    % 'getframe' | 'exportapp'  (print is unsupported)

%% ---- settle timing ----------------------------------------------------
% Basemap tiles stream asynchronously. These are bounded waits, NOT the blind
% pause(1)+pause(0.2) the prototype used: the renderer polls for a stable
% frame and gives up at settle_max_s.
cfg.settle_first_s = 8.0;     % first globe creation, once per run
cfg.settle_min_s   = 0.15;    % floor after a camera move
cfg.settle_max_s   = 2.0;     % ceiling before accepting whatever is there
cfg.settle_tol     = 0.5;     % mean |frame difference| considered "stable"

%% ---- roll convention calibration --------------------------------------
% The mathematical roll in earth_geoglobe_camera() is well defined, but
% GeoGlobe's own sign/zero for camroll is not documented. These two knobs
% absorb the difference and are calibrated in Phase C validation; they are
% NOT free parameters to be tuned by eye.
cfg.roll_sign       = 1;
cfg.roll_offset_deg = 0;

%% ---- gimbal lock ------------------------------------------------------
% Near nadir, heading and roll describe the same rotation and GeoGlobe's own
% documentation warns that setting roll can change heading. Frames inside
% this band are flagged in the returned camera struct.
cfg.gimbal_guard_deg = 89.5;

end
