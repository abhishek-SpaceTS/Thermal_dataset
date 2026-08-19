function visible = star_project_to_pixels(catalog, ra_deg, dec_deg, roll_deg, camera)
% Project catalog RA/DEC to sensor pixel coordinates.

cols = star_columns();

img_w = camera.image_width;
img_h = camera.image_height;
if isfield(camera, 'focal_length_px') && ~isempty(camera.focal_length_px)
    f_px = camera.focal_length_px;
else
    diag_px = sqrt(img_w^2 + img_h^2);
    f_px = (diag_px / 2.0) / tan(deg2rad(camera.fov_deg / 2.0));
end
cx = img_w / 2.0;
cy = img_h / 2.0;

R = star_boresight_rotation(ra_deg, dec_deg, roll_deg);

ra  = deg2rad(catalog(:, cols.RA));
dec = deg2rad(catalog(:, cols.DEC));
v_j2000 = [cos(dec).*cos(ra), cos(dec).*sin(ra), sin(dec)];

v_cam = (R * v_j2000')';

Zc       = v_cam(:, 3);
in_front = Zc > 0;

px = nan(size(Zc));
py = nan(size(Zc));
px(in_front) = f_px * (v_cam(in_front, 1) ./ Zc(in_front)) + cx;
py(in_front) = f_px * (v_cam(in_front, 2) ./ Zc(in_front)) + cy;

in_sensor = in_front & px >= 0 & px < img_w & py >= 0 & py < img_h;

visible = [catalog(in_sensor, :), px(in_sensor), py(in_sensor)];

[~, order] = sort(visible(:, cols.MAG), 'ascend');
visible = visible(order, :);

end
