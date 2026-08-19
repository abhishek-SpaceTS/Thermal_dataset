function thermal_image = render_star_background(thermal_image, camera, config, star_range)
% Physically-based star field background image.

defaults = star_default_config();
fields = fieldnames(defaults);
for k = 1:numel(fields)
    if ~isfield(config, fields{k}) || isempty(config.(fields{k}))
        config.(fields{k}) = defaults.(fields{k});
    end
end

cols = star_columns();

catalog = star_catalog_load(config.catalog_file, config.mag_limit);

f_px = local_focal_length_px(camera);
half_diag_deg = atand(hypot(camera.image_width, camera.image_height) / (2.0 * f_px));
search_radius_deg = half_diag_deg * config.search_radius_pad;
nearby = star_catalog_cone_search(catalog, camera.ra_deg, camera.dec_deg, search_radius_deg);

if config.enable_proper_motion
    nearby = star_apply_proper_motion(nearby, config.epoch_year);
end

if config.enable_parallax
    nearby = star_apply_parallax(nearby, config.epoch_day_of_year);
end

visible = star_project_to_pixels(nearby, camera.ra_deg, camera.dec_deg, camera.roll_deg, camera);

img_w = camera.image_width;
img_h = camera.image_height;

if isempty(visible)
    return;
end

if isfield(config, 'seed') && ~isempty(config.seed)
    rng_stream = RandStream('mt19937ar', 'Seed', config.seed);
else
    rng_stream = RandStream.getGlobalStream();
end

for i = 1:size(visible, 1)
    star_mag   = visible(i, cols.MAG);
    star_e_ra  = visible(i, cols.E_RA);
    star_e_dec = visible(i, cols.E_DEC);
    hp_scat    = visible(i, cols.HP_SCAT);
    hp_max     = visible(i, cols.HP_MAX);
    hp_min     = visible(i, cols.HP_MIN);
    px = visible(i, cols.PX);
    py = visible(i, cols.PY);

    if config.apply_jitter
        [px, py] = local_jitter(px, py, star_e_ra, star_e_dec, camera, rng_stream);
    end

    if config.apply_variability && hp_scat > config.variable_scat_threshold && (hp_min - hp_max) > 0
        eff_mag = hp_max + rand(rng_stream) * (hp_min - hp_max);
    else
        eff_mag = star_mag;
    end

    if eff_mag > config.mag_limit + 0.5
        continue;
    end

    peak_temp = local_magnitude_to_peak_temp(eff_mag, config.peak_temp_mag0, ...
                                              star_range(2), star_range(1));
    sigma = local_magnitude_to_sigma(eff_mag, config.psf_sigma_px);

    thermal_image = star_render_psf(thermal_image, px, py, peak_temp, sigma, img_w, img_h);
end

thermal_image = min(thermal_image, star_range(2));

end

function f_px = local_focal_length_px(camera)
% Focal length in pixels, resolved exactly the way
if isfield(camera, 'focal_length_px') && ~isempty(camera.focal_length_px)
    f_px = camera.focal_length_px;
else
    diag_px = hypot(camera.image_width, camera.image_height);
    f_px = (diag_px / 2.0) / tan(deg2rad(camera.fov_deg / 2.0));
end
end

function [px, py] = local_jitter(px, py, e_ra_mas, e_dec_mas, camera, rng_stream)
% Sub-pixel position shift from catalog e_ra/e_dec errors.
f_px = local_focal_length_px(camera);
mas_to_rad = pi / (180.0 * 3600.0 * 1000.0);
sx = e_ra_mas  * mas_to_rad * f_px;
sy = e_dec_mas * mas_to_rad * f_px;
px = px + randn(rng_stream) * max(sx, 1e-6);
py = py + randn(rng_stream) * max(sy, 1e-6);
end

function peak_temp = local_magnitude_to_peak_temp(magnitude, peak_temp_mag0, max_temp, background_temp)
% Apparent-temperature analog of
flux_ratio = 10.0 ^ (0.4 * (0.0 - magnitude));
headroom   = max_temp - background_temp;
peak_temp  = min(max(peak_temp_mag0 * flux_ratio, 0), headroom);
end

function sigma = local_magnitude_to_sigma(magnitude, psf_sigma_px)
% Port of star_renderer.magnitude_to_sigma:
sigma = psf_sigma_px * (10.0 ^ (0.1 * (3.5 - magnitude)));
sigma = min(max(sigma, 0.5), 8.0);
end
