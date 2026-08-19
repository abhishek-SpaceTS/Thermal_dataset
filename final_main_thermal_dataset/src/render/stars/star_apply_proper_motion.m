function catalog = star_apply_proper_motion(catalog, epoch_year)
% Shift catalog star positions to epoch_year.

cols = star_columns();
dt = epoch_year - 2000.0;

ra     = catalog(:, cols.RA);
dec    = catalog(:, cols.DEC);
pm_ra  = catalog(:, cols.PM_RA);
pm_dec = catalog(:, cols.PM_DEC);

cos_dec = cos(deg2rad(dec));
cos_dec(abs(cos_dec) < 1e-10) = 1e-10;

catalog(:, cols.RA)  = mod(ra + (pm_ra ./ cos_dec) * dt / 3600000.0, 360.0);
catalog(:, cols.DEC) = dec + pm_dec * dt / 3600000.0;

end
