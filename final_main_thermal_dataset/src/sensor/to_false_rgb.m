function img_rgb = to_false_rgb(thermal_image, T_min, T_max, component_mask) %#ok<INUSD>
% Same fixed-window mapping as the gray16 output, colorized with hot().
    clamped    = min(max(thermal_image, T_min), T_max);
    normalized = (clamped - T_min) / (T_max - T_min);

    cmap   = hot(256);
    idx    = min(max(round(normalized * 255) + 1, 1), 256);
    [h, w] = size(thermal_image);

    r_map = uint8(cmap(:,1) * 255);
    g_map = uint8(cmap(:,2) * 255);
    b_map = uint8(cmap(:,3) * 255);

    img_rgb = zeros(h, w, 3, 'uint8');
    img_rgb(:,:,1) = reshape(r_map(idx), h, w);
    img_rgb(:,:,2) = reshape(g_map(idx), h, w);
    img_rgb(:,:,3) = reshape(b_map(idx), h, w);
end
