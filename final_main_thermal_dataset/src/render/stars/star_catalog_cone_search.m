function nearby = star_catalog_cone_search(catalog, boresight_ra_deg, boresight_dec_deg, radius_deg)
% Return catalog rows within radius_deg of boresight.

cols = star_columns();

ra_b  = deg2rad(boresight_ra_deg);
dec_b = deg2rad(boresight_dec_deg);
bx = cos(dec_b) * cos(ra_b);
by = cos(dec_b) * sin(ra_b);
bz = sin(dec_b);

ra_all  = deg2rad(catalog(:, cols.RA));
dec_all = deg2rad(catalog(:, cols.DEC));
sx = cos(dec_all) .* cos(ra_all);
sy = cos(dec_all) .* sin(ra_all);
sz = sin(dec_all);

dot_prod  = max(min(bx.*sx + by.*sy + bz.*sz, 1.0), -1.0);
cos_limit = cos(deg2rad(radius_deg));

nearby = catalog(dot_prod >= cos_limit, :);

end
