function [positions, velocities] = inspection_orbit(d_start, frames, dt, config)
% Orbit the target at a constant distance

    % Altitude difference between the two orbits, read from config.
    alt_diff_m   = local_alt_diff(config);
    true_d_start = sqrt(d_start^2 + alt_diff_m^2);

    positions = zeros(3, frames);
    velocities = zeros(3, frames);

    total_angle = pi;
    omega = total_angle / (frames * dt);

    % The orbit projects to a circle in the image, so its radius must satisfy
    % the TIGHTER of the two axes. This model was the worst affected by the
    % old single-FOV bound: a circle of radius d*tan(fov_h/2) leaves the frame
    % through the top and bottom twice per revolution, which put 45 % of its
    % frames off-image on a 1280 x 1024 detector.
    [lim_x, lim_y] = framing_limits(config, true_d_start);
    R = true_d_start * min(lim_x, lim_y);

    for i = 1:frames
        t = (i - 1) * dt;
        angle = omega * t;

        x = R * cos(angle);
        y = R * sin(angle);
        z = sqrt(true_d_start^2 - R^2);
        positions(:, i) = [x; y; z];

        vx = -R * omega * sin(angle);
        vy = R * omega * cos(angle);
        vz = 0;
        velocities(:, i) = [vx; vy; vz];
    end

    % z = sqrt(d^2 - R^2) is slightly less than d, so the projected ratio x/z
    % is slightly larger than the R/d the radius was sized from. Small, but it
    % is exactly the kind of few-percent overshoot that put targets on the
    % frame border, so close it.
    [positions, velocities] = fit_to_frame(positions, velocities, config);
end

% -------------------------------------------------------------------------
function alt_diff_m = local_alt_diff(config)
% Read altitude difference (m) from config.orbit. Falls back to 100 m.
% Change altitude ONLY in config.m.
    alt_chaser_m = 600e3;
    alt_target_m = 600.1e3;
    if isfield(config, 'orbit')
        if isfield(config.orbit, 'altitude_chaser_m'), alt_chaser_m = config.orbit.altitude_chaser_m; end
        if isfield(config.orbit, 'altitude_target_m'), alt_target_m = config.orbit.altitude_target_m; end
    end
    alt_diff_m = alt_target_m - alt_chaser_m;
end
