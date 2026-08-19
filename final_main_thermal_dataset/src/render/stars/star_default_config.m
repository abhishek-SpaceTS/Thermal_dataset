function config = star_default_config()
% Default settings for render_star_background.

this_dir = fileparts(mfilename('fullpath'));

config.catalog_file = fullfile(project_root(), 'data', 'star_catalog', 'hipparcos_main_full.csv');
config.mag_limit     = 9.0;

config.enable_proper_motion = true;
config.epoch_year           = 2025.0;
config.enable_parallax      = true;
config.epoch_day_of_year    = 1;

config.apply_jitter            = true;
config.apply_variability       = true;
config.variable_scat_threshold = 0.03;
config.psf_sigma_px            = 1.5;

config.peak_temp_mag0 = 400.0;
config.background_temp = 2.7;
config.max_temp = 400.0;

config.search_radius_pad = 1.1;

end
