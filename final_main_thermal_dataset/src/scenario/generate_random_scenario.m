function scenario = generate_random_scenario(frames, dt, config)
% NOTE: no rng() call here on purpose. The RNG is seeded exactly once

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
    scenario.altitude_chaser_m = alt_chaser_m;
    scenario.altitude_target_m = alt_target_m;
    scenario.altitude_diff_m = alt_target_m - alt_chaser_m;

    if isfield(config, 'distance_scenarios')
        dist_scenarios = config.distance_scenarios;
    else
        dist_scenarios = {
            'Long-Range Detection', 5000, 3000, {'straight', 'flyby'};
            'Mid-Range Tracking',   3000, 1000, {'straight', 'lateral', 'diagonal'};
            'Approach Tracking',    1000, 300,  {'straight', 'lateral', 'diagonal'};
            'Close Observation',    300, 100,   {'straight', 'lateral', 'diagonal'};
            'Close Inspection',     100, 15,    {'orbit', 'lateral', 'station_keeping'}
        };
    end

    d_idx = randi(size(dist_scenarios, 1));
    scenario.scenario_type = dist_scenarios{d_idx, 1};
    scenario.distance_start = dist_scenarios{d_idx, 2};
    scenario.distance_end = dist_scenarios{d_idx, 3};
    allowed_motions = dist_scenarios{d_idx, 4};

    allowed_motions = [allowed_motions, {'cw_relative_motion'}];

    trajectory_opts(1).name = 'Straight Approach';
    trajectory_opts(1).description = 'Chaser moves directly toward the target.';
    trajectory_opts(1).motion_type = 'straight';
    trajectory_opts(1).supported_tasks = 'Detection, Tracking';

    trajectory_opts(2).name = 'Lateral Approach';
    trajectory_opts(2).description = 'Chaser approaches while moving sideways.';
    trajectory_opts(2).motion_type = 'lateral';
    trajectory_opts(2).supported_tasks = 'Detection, Tracking, Pose Estimation';

    trajectory_opts(3).name = 'Diagonal Approach';
    trajectory_opts(3).description = 'Chaser approaches diagonally toward the target.';
    trajectory_opts(3).motion_type = 'diagonal';
    trajectory_opts(3).supported_tasks = 'Detection, Tracking, Pose Estimation';

    trajectory_opts(4).name = 'Flyby';
    trajectory_opts(4).description = 'Chaser passes the target without stopping.';
    trajectory_opts(4).motion_type = 'flyby';
    trajectory_opts(4).supported_tasks = 'Detection, Tracking';

    trajectory_opts(5).name = 'Inspection Orbit';
    trajectory_opts(5).description = 'Chaser moves around the target at an approximately constant distance.';
    trajectory_opts(5).motion_type = 'orbit';
    trajectory_opts(5).supported_tasks = 'Pose Estimation, Component Analysis, Thermal Health Monitoring';

    trajectory_opts(6).name = 'Station Keeping';
    trajectory_opts(6).description = 'Chaser maintains a nearly fixed relative position with small random drift.';
    trajectory_opts(6).motion_type = 'station_keeping';
    trajectory_opts(6).supported_tasks = 'Component Analysis, Thermal Health Monitoring';

    trajectory_opts(7).name = 'CW Relative Motion';
    trajectory_opts(7).description = 'Physically realistic relative motion using Clohessy-Wiltshire (Hill''s) equations in LVLH frame.';
    trajectory_opts(7).motion_type = 'cw_relative_motion';
    trajectory_opts(7).supported_tasks = 'Detection, Tracking, Proximity Operations';

    valid_opts = [];
    for i = 1:length(trajectory_opts)
        if ismember(trajectory_opts(i).motion_type, allowed_motions)
            valid_opts = [valid_opts, trajectory_opts(i)];
        end
    end

    traj_idx = randi(length(valid_opts));
    selected_traj = valid_opts(traj_idx);
    scenario.trajectory_type = selected_traj.motion_type;
    scenario.trajectory_name = selected_traj.name;

    switch selected_traj.motion_type
        case 'straight'
            [scenario.positions, scenario.velocities] = straight_approach(scenario.distance_start, scenario.distance_end, frames, dt, config);
        case 'lateral'
            [scenario.positions, scenario.velocities] = lateral_approach(scenario.distance_start, scenario.distance_end, frames, dt, config);
        case 'diagonal'
            [scenario.positions, scenario.velocities] = diagonal_approach(scenario.distance_start, scenario.distance_end, frames, dt, config);
        case 'flyby'
            [scenario.positions, scenario.velocities] = flyby(scenario.distance_start, frames, dt, config);
        case 'orbit'
            [scenario.positions, scenario.velocities] = inspection_orbit(scenario.distance_start, frames, dt, config);
        case 'station_keeping'
            [scenario.positions, scenario.velocities] = station_keeping(scenario.distance_start, frames, dt, config);
        case 'cw_relative_motion'
            [scenario.positions, scenario.velocities] = cw_relative_motion(scenario.distance_start, frames, dt, config);
    end

    q = randn(1, 4);
    scenario.initial_quaternion = q / norm(q);

    attitude_scenarios = local_run_setting(config, 'motion', 'tumbling', {
        'Stable',               0.00;
        'Very Slow Tumbling',   0.01;
        'Slow Tumbling',        0.05;
        'Medium Tumbling',      0.15;
        'Fast Tumbling',        0.50;
        'Multi-Axis Tumbling',  0.25
    });

    att_idx = randi(size(attitude_scenarios, 1));
    scenario.attitude_name = attitude_scenarios{att_idx, 1};
    scenario.angular_velocity_magnitude = attitude_scenarios{att_idx, 2};

    if scenario.angular_velocity_magnitude > 0
        dir = randn(3, 1);
        scenario.rotation_axis = dir / norm(dir);

        scenario.angular_velocity = scenario.rotation_axis * scenario.angular_velocity_magnitude;
    else
        scenario.rotation_axis = [0; 0; 1];
        scenario.angular_velocity = [0; 0; 0];
    end

    if exist('star_boresight_rotation', 'file') ~= 2
        addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Renderer'));
    end
    cam_ra   = 360.0 * rand();
    cam_dec  = asind(2.0 * rand() - 1.0);
    cam_roll = 360.0 * rand();
    scenario.deputy_quaternion = rotm2quat(star_boresight_rotation(cam_ra, cam_dec, cam_roll));

    % ---- Sun direction, sampled CONTINUOUSLY on the sphere ---------------
    % This used to pick one of eight axis-aligned vectors. With the camera
    % boresight at +z that produced only three solar phase angles -- 0 deg
    % from [0;0;-1], 180 deg from [0;0;1], and exactly 90 deg from the other
    % six -- so 75% of sequences shared one lighting geometry and nothing in
    % between ever occurred.
    %
    % Solar phase is the Sun-target-camera angle. The camera sits at the
    % origin looking down +z, so the target-to-camera direction is -z and
    %       phase = acos(dot(sun_hat, -z)) = acos(-sun_z)
    % Drawing phase uniformly over [0,180] deg and azimuth uniformly over
    % [0,360) therefore spreads illumination evenly along the axis that
    % actually changes how the target looks.
    %
    % NOTE this is deliberately not an isotropic draw. A uniform direction on
    % the sphere has phase density proportional to sin(phase), which piles
    % about 70% of samples between 45 and 135 deg and leaves front-lit and
    % back-lit geometry rare -- the same concentration near 90 deg the fixed
    % list had, just smoother. Uniform-in-phase gives every lighting condition
    % equal weight, which is what a training set needs. The realised phase is
    % recorded per sequence and per frame, so it can be reweighted to the
    % isotropic prior afterwards if required.
    sun_phase_deg = 180 * rand();
    sun_azim_rad  = 2 * pi * rand();
    sp = sind(sun_phase_deg);
    scenario.sun_vector = [sp * cos(sun_azim_rad); ...
                           sp * sin(sun_azim_rad); ...
                           -cosd(sun_phase_deg)];
    scenario.sun_vector = scenario.sun_vector / norm(scenario.sun_vector);
    scenario.sun_phase_deg = sun_phase_deg;
    scenario.sun_name = local_sun_bin(sun_phase_deg);

    R_eci_to_cam    = quat2rotm(scenario.deputy_quaternion);
    boresight_eci   = R_eci_to_cam.' * [0; 0; 1];
    scenario.earth  = author_earth(config, boresight_eci);

    netd_max = local_run_setting(config, 'sensor', 'netd_max_K', 0.05);
    scenario.netd = rand * netd_max;
    if scenario.netd == 0, scenario.netd_name = 'None';
    elseif scenario.netd < 0.015, scenario.netd_name = 'Low';
    elseif scenario.netd < 0.035, scenario.netd_name = 'Medium';
    else, scenario.netd_name = 'High'; end

    blur_max = local_run_setting(config, 'sensor', 'blur_max_px', 1.5);
    scenario.blur = rand * blur_max;
    if scenario.blur == 0, scenario.blur_name = 'None';
    elseif scenario.blur < 0.5, scenario.blur_name = 'Low';
    elseif scenario.blur < 1.0, scenario.blur_name = 'Medium';
    else, scenario.blur_name = 'High'; end

    scenario.frames = frames;
    if isfield(scenario, 'positions')
        scenario.true_distance_m = sqrt(sum(scenario.positions.^2, 1));
        scenario.horizontal_sep_m = sqrt(max(0, scenario.true_distance_m.^2 - scenario.altitude_diff_m^2));
        if isfield(config, 'camera') && isfield(config.camera, 'pixel_pitch_m') && isfield(config.camera, 'focal_length_m')
            ifov_rad_per_px = config.camera.pixel_pitch_m / config.camera.focal_length_m;
            target_size_m = 2.0; % Rough bounding size for pixel computation
            angular_size = atan(target_size_m ./ scenario.true_distance_m);
            scenario.pixels_on_detector = angular_size / ifov_rad_per_px;
        end
    end
end

function name = local_sun_bin(phase_deg)
% Coarse label for the sampled solar phase, so scenario.sun_name (and the
% sun_bin field in the sequence metadata) stays populated now that the sun is
% no longer chosen from a named list. Bins describe the lighting geometry the
% camera sees, not a body axis.
if     phase_deg <  30, name = 'Front-lit';
elseif phase_deg <  60, name = 'Front-oblique';
elseif phase_deg < 120, name = 'Side-lit';
elseif phase_deg < 150, name = 'Rear-oblique';
else,                   name = 'Back-lit';
end
end


function v = local_run_setting(config, group, field, dflt)
% Read config.run.<group>.<field> from config.m,
v = dflt;
if isfield(config,'run') && isfield(config.run, group) && ...
        isfield(config.run.(group), field) && ~isempty(config.run.(group).(field))
    v = config.run.(group).(field);
end
end
