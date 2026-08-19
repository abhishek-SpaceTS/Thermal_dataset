function [positions, velocities] = diagonal_approach(d_start, d_end, frames, dt, config)
% Configurable randomness parameters
    apply_curvature_prob = 0.5;
    curve_range = [0.05, 0.20];

    % Altitude difference between the two orbits, read from config.
    alt_diff_m   = local_alt_diff(config);
    true_d_start = sqrt(d_start^2 + alt_diff_m^2);
    true_d_end   = sqrt(d_end^2   + alt_diff_m^2);

    positions = zeros(3, frames);
    velocities = zeros(3, frames);
    % Diagonal motion uses BOTH axes, and on a 1280 x 1024 detector they have
    % different limits (2.200 deg against 1.760 deg). Using the horizontal
    % number for y is what used to throw the target off the top of the frame
    % on this model.
    [limx_s, limy_s] = framing_limits(config, true_d_start);
    [limx_e, limy_e] = framing_limits(config, true_d_end);
    pos_start = [-true_d_start * limx_s;  true_d_start * limy_s; true_d_start];
    pos_end   = [ true_d_end   * limx_e; -true_d_end   * limy_e; true_d_end];
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
