function catalog = star_apply_parallax(catalog, day_of_year)
% Apply annual parallax from Earth's orbital position.

cols = star_columns();

ra      = catalog(:, cols.RA);
dec     = catalog(:, cols.DEC);
plx_mas = catalog(:, cols.PLX);
valid   = plx_mas > 0.0;

if ~any(valid)
    return;
end

plx_deg = plx_mas / 3600000.0;
omega   = 2.0 * pi * (day_of_year - 1.0) / 365.25;

ra_r  = deg2rad(ra);
dec_r = deg2rad(dec);

f_ra  = -sin(ra_r)*cos(omega) + cos(ra_r)*sin(omega);
f_dec = -sin(dec_r).*cos(ra_r)*cos(omega) - sin(dec_r).*sin(ra_r)*sin(omega);

cos_dec = cos(dec_r);
cos_dec(abs(cos_dec) < 1e-10) = 1e-10;

ra(valid)  = mod(ra(valid) + plx_deg(valid).*f_ra(valid)./cos_dec(valid), 360.0);
dec(valid) = dec(valid) + plx_deg(valid).*f_dec(valid);

catalog(:, cols.RA)  = ra;
catalog(:, cols.DEC) = dec;

end
