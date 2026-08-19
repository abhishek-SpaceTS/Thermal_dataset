function bbox = compute_bbox_from_projection(pixel_uv, resolution)
    valid    = ~isnan(pixel_uv(:,1)) & ~isnan(pixel_uv(:,2));
    uv_valid = pixel_uv(valid, :);

    if isempty(uv_valid)
        bbox = [0, 0, 0, 0];
        return;
    end

    x_min = min(uv_valid(:,1));  y_min = min(uv_valid(:,2));
    x_max = max(uv_valid(:,1));  y_max = max(uv_valid(:,2));

    bbox = round([
        x_min,
        y_min,
        x_max - x_min + 1,
        y_max - y_min + 1
    ]);

    img_w = resolution(1);
    img_h = resolution(2);

    x1 = max(1, bbox(1));
    y1 = max(1, bbox(2));
    x2 = min(img_w, bbox(1) + bbox(3) - 1);
    y2 = min(img_h, bbox(2) + bbox(4) - 1);

    if x1 > x2 || y1 > y2
        bbox = [0, 0, 0, 0];
        return;
    end

    bbox = [x1, y1, x2 - x1 + 1, y2 - y1 + 1];
end
