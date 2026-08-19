function img16 = to_gray16(thermal_image, T_min, T_max, component_mask) %#ok<INUSD>
% Clamp temperatures to the fixed window, then scale to 0-1.
    clamped = min(max(thermal_image, T_min), T_max);
    normalized = (clamped - T_min) / (T_max - T_min);

    img16 = uint16(normalized * 65535);
end
