function [img, info] = earth_geoglobe_render(scene)
% Earth background image from a persistent GeoGlobe.

persistent FIG GLOBE RSIZE

cfg = earth_geoglobe_config();

if nargin < 1 || isempty(scene); scene = struct(); end
render_size = get_field(scene, 'render_size', cfg.render_size);
out_size    = get_field(scene, 'out_size',    1024);
if isfield(scene, 'fov_deg')
    fov_deg = scene.fov_deg;
else
    fov_deg = 6.012004;
end

t_all = tic;

if isfield(scene, 'R_eci_to_thermal') && isfield(scene, 'deputy_pos_eci')
    cam = earth_geoglobe_camera(scene.deputy_pos_eci, scene.R_eci_to_thermal, ...
                                get_field(scene, 'epoch_utc', datetime(2025,1,1,12,0,0)));
    lat = cam.lat_deg; lon = cam.lon_deg; alt = cam.alt_m;
    hdg = cam.heading_deg; pit = cam.pitch_deg; rol = cam.roll_deg;
    gimbal = cam.gimbal_locked;
else
    lat = get_field(scene, 'lat_deg', 0);
    lon = get_field(scene, 'lon_deg', 0);
    hdg = get_field(scene, 'heading_deg', 0);
    pit = get_field(scene, 'pitch_deg', -90);
    rol = get_field(scene, 'roll_deg', 0);
    gimbal = abs(pit) > cfg.gimbal_guard_deg;

    if isfield(scene, 'horizon_offset_halffov') && ~isempty(scene.horizon_offset_halffov)
        Re_h  = 6378137;
        alt_h = get_field(scene, 'alt_m', 600e3);
        rho_h = asind(Re_h/(Re_h+alt_h));
        fov_h = fov_deg; if isempty(fov_h); fov_h = cfg.native_fov_deg; end
        pit   = -(90 - rho_h) + scene.horizon_offset_halffov * (fov_h/2);
    end

    if isfield(scene, 'earth_angular_radius_deg') && ~isempty(scene.earth_angular_radius_deg)
        Re  = 6378137;
        rho = max(0.05, min(89.9, scene.earth_angular_radius_deg));
        alt = Re/sind(rho) - Re;
    else
        alt = get_field(scene, 'alt_m', 600e3);
    end
end

need_new = isempty(FIG) || ~isvalid(FIG) || isempty(GLOBE) || ~isvalid(GLOBE) ...
           || isempty(RSIZE) || RSIZE ~= render_size;

if need_new
    if ~isempty(FIG) && isvalid(FIG); delete(FIG); end
    FIG = uifigure('Name','Earth Background Renderer', ...
                   'Position',[30 30 render_size render_size], ...
                   'Visible', cfg.visible);
    GLOBE = geoglobe(FIG, 'Basemap', cfg.basemap, 'Terrain', cfg.terrain);
    RSIZE = render_size;
    drawnow;
    pause(cfg.settle_first_s);

    actual = char(string(GLOBE.Basemap));
    if ~strcmpi(actual, cfg.basemap)
        msg = sprintf(['GeoGlobe fell back to basemap "%s" instead of "%s".\n' ...
                       'This almost always means the streamed basemap could not ' ...
                       'be reached (no network).\nRendered frames would NOT be ' ...
                       'satellite imagery.'], actual, cfg.basemap);
        if cfg.strict_basemap
            delete(FIG); FIG = []; GLOBE = []; RSIZE = [];
            error('earth_geoglobe_render:basemapFallback', '%s', msg);
        else
            warning('earth_geoglobe_render:basemapFallback', '%s', msg);
        end
    end
end

campos(GLOBE, lat, lon);
camheight(GLOBE, alt);
camheading(GLOBE, hdg);
campitch(GLOBE, pit);
camroll(GLOBE, rol);
drawnow;

t0 = tic;
pause(cfg.settle_min_s);
prev = local_capture(FIG, cfg.capture);
while toc(t0) < cfg.settle_max_s
    pause(cfg.settle_min_s);
    cur = local_capture(FIG, cfg.capture);
    if isequal(size(cur), size(prev)) && ...
            mean(abs(double(cur(:)) - double(prev(:)))) < cfg.settle_tol
        prev = cur; break;
    end
    prev = cur;
end
t_settle = toc(t0);

t1 = tic;
raw = prev;
t_capture = toc(t1);

[H, W, ~] = size(raw);
native = cfg.native_fov_deg;

% Output shape. out_size may be a scalar (square, the historical form) or
% [rows cols] for a non-square detector.
if isscalar(out_size)
    out_h = out_size; out_w = out_size;
else
    out_h = out_size(1); out_w = out_size(2);
end
aspect = out_w / out_h;

% Crop a region with the OUTPUT's aspect ratio, not a square one. Resizing a
% square capture into a non-square frame would squash Earth and bend the limb;
% cropping keeps the pixel scale isotropic. Physically this is what a detector
% with fewer rows than columns sees -- less sky vertically, same angular scale.
if isempty(fov_deg) || fov_deg >= native
    box_w   = min(W, H * aspect);
    fov_out = native;
else
    frac    = tand(fov_deg/2) / tand(native/2);
    box_w   = max(8, frac * min(H, W));
    box_w   = min(box_w, H * aspect);
    fov_out = fov_deg;
end
box_h  = box_w / aspect;
crop_w = max(8, round(box_w));
crop_h = max(8, round(box_h));
r0 = max(1, round((H - crop_h)/2) + 1);
c0 = max(1, round((W - crop_w)/2) + 1);
crop = raw(r0:min(H, r0+crop_h-1), c0:min(W, c0+crop_w-1), :);

% crop_px stays the WIDTH, so info.upsample keeps its old meaning.
crop_px = crop_w;

img = imresize(crop, [out_h out_w]);

g = max(img, [], 3);
info.earth_coverage = nnz(g > 45) / numel(g);
info.lat_deg = lat;  info.lon_deg = lon;  info.alt_m = alt;
info.heading_deg = hdg; info.pitch_deg = pit; info.roll_deg = rol;
info.gimbal_locked = gimbal;
info.render_size = render_size;
info.crop_px = crop_px;
info.upsample = out_w / crop_px;
info.fov_deg = fov_out;
info.native_fov_deg = native;
info.t_settle_s = t_settle;
info.t_capture_s = t_capture;
info.t_total_s = toc(t_all);
info.globe_created = need_new;

end

function I = local_capture(fig, method)
switch lower(method)
    case 'getframe'
        F = getframe(fig); I = F.cdata;
    case 'exportapp'
        p = fullfile(tempdir, 'earth_geoglobe_frame.png');
        exportapp(fig, p); I = imread(p);
    otherwise
        error('earth_geoglobe_render:badCapture', ...
              'Unsupported capture method "%s".', method);
end
end
