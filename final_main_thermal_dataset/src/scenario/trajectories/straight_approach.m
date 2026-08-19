function [positions, velocities] = straight_approach(d_start, d_end, frames, dt, config)
% Configurable randomness parameters
    apply_curvature_prob = 0.5;
    curve_range = [0.10, 0.30];

    % Altitude difference between the two orbits, read from config.
    % true_d = sqrt(horiz^2 + alt_diff^2). With a 100 m gap at 600 km this
    % changes range by < 1 %; kept for consistency with cw_relative_motion.
    alt_diff_m   = local_alt_diff(config);
    true_d_start = sqrt(d_start^2 + alt_diff_m^2);
    true_d_end   = sqrt(d_end^2   + alt_diff_m^2);

    positions = zeros(3, frames);
    velocities = zeros(3, frames);
    pos_start = [0; 0; true_d_start];
    pos_end   = [0; 0; true_d_end];
    vel = (pos_end - pos_start) / (frames * dt);
    for i = 1:frames
        alpha = (i - 1) / max(1, frames - 1);
        positions(:, i) = pos_start + alpha * (pos_end - pos_start);
        velocities(:, i) = vel;
    end

    if rand() < apply_curvature_prob
        strength = curve_range(1) + rand() * (curve_range(2) - curve_range(1));

        theta = rand() * 2 * pi;
        R = [cos(theta) -sin(theta) 0; sin(theta) cos(theta) 0; 0 0 1];
        positions = R * positions;
        velocities = R * velocities;

        [positions, velocities] = add_arc_curvature(positions, velocities, dt, config, strength);

        R_inv = R';
        positions = R_inv * positions;
        velocities = R_inv * velocities;
    end

    % Guarantee. The offsets above are already sized from framing_limits, but
    % a curvature bulge is added on top of them and can push the path past the
    % edge. One uniform transverse scale removes the worst violation without
    % kinking the motion; z is untouched, so the range bracket is unchanged.
    [positions, velocities] = fit_to_frame(positions, velocities, config);
end

% -------------------------------------------------------------------------
function alt_diff_m = local_alt_diff(config)
% Read altitude difference (m) from config.orbit. Falls back to 100 m
% (600.0 km chaser / 600.1 km target). Change altitude ONLY in config.m.
    alt_chaser_m = 600e3;
    alt_target_m = 600.1e3;
    if isfield(config, 'orbit')
        if isfield(config.orbit, 'altitude_chaser_m'), alt_chaser_m = config.orbit.altitude_chaser_m; end
        if isfield(config.orbit, 'altitude_target_m'), alt_target_m = config.orbit.altitude_target_m; end
    end
    alt_diff_m = alt_target_m - alt_chaser_m;
end
