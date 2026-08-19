function [positions, velocities] = station_keeping(d_start, frames, dt, config)
% Maintain position with a small random walk

    % Altitude difference between the two orbits, read from config.
    alt_diff_m   = local_alt_diff(config);
    true_d_start = sqrt(d_start^2 + alt_diff_m^2);

    positions = zeros(3, frames);
    velocities = zeros(3, frames);

    curr_pos = [0; 0; true_d_start];

    max_drift_velocity = 0.01;

    for i = 1:frames
        vx = (rand() - 0.5) * 2 * max_drift_velocity;
        vy = (rand() - 0.5) * 2 * max_drift_velocity;
        vz = (rand() - 0.5) * 2 * max_drift_velocity;

        vel = [vx; vy; vz];

        curr_pos = curr_pos + vel * dt;

        positions(:, i) = curr_pos;
        velocities(:, i) = vel;
    end

    % The drift is centimetres over a sequence, so this normally does nothing.
    % Applied for uniformity: every model returns a framed path.
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
