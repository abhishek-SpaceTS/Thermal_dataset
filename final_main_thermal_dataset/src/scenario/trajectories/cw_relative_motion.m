function [positions, velocities] = cw_relative_motion(d_start, frames, dt, config)
% Earth gravitational parameter (m^3/s^2) and radius (m)
    mu = 3.986004418e14;
    R_earth = 6371e3;

    % Extract altitude difference from config (if present)
    alt_chaser_m = 600e3;      % 600.0 km  (matches cfg.orbit.altitude_chaser_m)
    alt_target_m = 600.1e3;    % 600.1 km  (matches cfg.orbit.altitude_target_m)
    if isfield(config, 'orbit')
        if isfield(config.orbit, 'altitude_chaser_m')
            alt_chaser_m = config.orbit.altitude_chaser_m;
        end
        if isfield(config.orbit, 'altitude_target_m')
            alt_target_m = config.orbit.altitude_target_m;
        end
    end
    alt_diff_m = alt_target_m - alt_chaser_m;
    true_d_start = sqrt(d_start^2 + alt_diff_m^2);

    % Per-axis framing limits. CW dynamics are coupled, so this model keeps its
    % rejection sampling rather than being rescaled after the fact: scaling x
    % and y independently of the propagation would no longer be a solution of
    % the Clohessy-Wiltshire equations. Rejecting and redrawing preserves the
    % dynamics exactly.
    [lim_x_start, lim_y_start] = framing_limits(config, d_start);

    positions = zeros(3, frames);
    velocities = zeros(3, frames);

    valid_trajectory = false;
    attempts = 0;

    while ~valid_trajectory && attempts < 100
        attempts = attempts + 1;

        altitude = alt_chaser_m;
        orbital_radius = R_earth + altitude;

        n = sqrt(mu / (orbital_radius^3));

        z0_cam = true_d_start;
        x0_cam = (rand() - 0.5) * 2 * true_d_start * lim_x_start * 0.5;
        y0_cam = (rand() - 0.5) * 2 * true_d_start * lim_y_start * 0.5;
        pos0_cam = [x0_cam; y0_cam; z0_cam];

        q = randn(4,1); q = q / norm(q);
        R_cam2lvlh = quat2rotm_local(q');

        pos0_lvlh = R_cam2lvlh * pos0_cam;

        total_time = frames * dt;

        max_transverse_v = (true_d_start * min(lim_x_start, lim_y_start)) / total_time * 0.5;

        vx0_cam = (rand() - 0.5) * 2 * max_transverse_v;
        vy0_cam = (rand() - 0.5) * 2 * max_transverse_v;
        vz0_cam = -rand() * (true_d_start / total_time);

        vel0_cam = [vx0_cam; vy0_cam; vz0_cam];
        vel0_lvlh = R_cam2lvlh * vel0_cam;

        pos_cam = zeros(3, frames);
        vel_cam_out = zeros(3, frames);

        x0 = pos0_lvlh(1); y0 = pos0_lvlh(2); z0_lvlh = pos0_lvlh(3);
        vx0 = vel0_lvlh(1); vy0 = vel0_lvlh(2); vz0 = vel0_lvlh(3);

        out_of_bounds = false;

        for i = 1:frames
            t = (i - 1) * dt;

            xt = (4 - 3*cos(n*t))*x0 + (sin(n*t)/n)*vx0 + (2/n)*(1 - cos(n*t))*vy0;
            yt = 6*(sin(n*t) - n*t)*x0 + y0 + (2/n)*(cos(n*t) - 1)*vx0 + (4*sin(n*t) - 3*n*t)/n * vy0;
            zt = z0_lvlh*cos(n*t) + (vz0/n)*sin(n*t);

            vxt = 3*n*sin(n*t)*x0 + cos(n*t)*vx0 + 2*sin(n*t)*vy0;
            vyt = 6*n*(cos(n*t) - 1)*x0 - 2*sin(n*t)*vx0 + (4*cos(n*t) - 3)*vy0;
            vzt = -z0_lvlh*n*sin(n*t) + vz0*cos(n*t);

            p_lvlh = [xt; yt; zt];
            v_lvlh = [vxt; vyt; vzt];

            p_cam = R_cam2lvlh' * p_lvlh;
            v_cam = R_cam2lvlh' * v_lvlh;

            if p_cam(3) < 1.0
                out_of_bounds = true;
                break;
            end

            % Re-evaluated at the CURRENT range, not the starting range: the
            % target's angular radius grows as it closes, so the usable field
            % shrinks along the path.
            [lim_x, lim_y] = framing_limits(config, p_cam(3));
            if abs(p_cam(1) / p_cam(3)) > lim_x || abs(p_cam(2) / p_cam(3)) > lim_y
                out_of_bounds = true;
                break;
            end

            pos_cam(:, i) = p_cam;
            vel_cam_out(:, i) = v_cam;
        end

        if ~out_of_bounds
            valid_trajectory = true;
            positions = pos_cam;
            velocities = vel_cam_out;
        end
    end

    if ~valid_trajectory
        error('CW Relative Motion: Could not find strict FOV-compliant trajectory after maximum attempts.');
    end
end
