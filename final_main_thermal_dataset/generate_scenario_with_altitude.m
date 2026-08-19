function scenario = generate_scenario_with_altitude(config, seed_idx)
%GENERATE_SCENARIO_WITH_ALTITUDE  Generate scenario trajectory with altitude difference
%
%   This is an ENHANCED VERSION of generate_random_scenario that properly
%   incorporates altitude difference between chaser and target.
%
%   Input:
%     config    - Configuration structure (from config.m)
%     seed_idx  - Seed index for reproducibility
%
%   Output:
%     scenario  - Scenario structure with position, attitude, etc.
%
%   Key difference from original:
%     - Includes altitude difference in 3D trajectory calculation
%     - Computes true 3D distance = sqrt(horiz^2 + alt_diff^2)
%     - Affects target rendering size and appearance

if nargin < 2 || isempty(seed_idx)
    seed_idx = 1;
end

% Extract altitudes
alt_chaser_m = 600e3;      % Default: can come from config.orbit.altitude_chaser_m
alt_target_m = 600.1e3;      % Default: can come from config.orbit.altitude_target_m

if isfield(config, 'orbit')
    if isfield(config.orbit, 'altitude_chaser_m')
        alt_chaser_m = config.orbit.altitude_chaser_m;
    end
    if isfield(config.orbit, 'altitude_target_m')
        alt_target_m = config.orbit.altitude_target_m;
    end
end

alt_diff_m = alt_target_m - alt_chaser_m;

fprintf('\nDEBUG: Altitude configuration\n');
fprintf('  Chaser altitude:      %.1f km\n', alt_chaser_m/1e3);
fprintf('  Target altitude:      %.1f km\n', alt_target_m/1e3);
fprintf('  Altitude difference:  %.1f km\n', alt_diff_m/1e3);

% =====================================================================
% EXAMPLE: Close Inspection with altitude effect
% =====================================================================

% Horizontal distances (from config)
dist_start_m = 250;
dist_end_m = 100;
num_frames = 50;

% Create frame times
frame_times = (0:(num_frames-1))' / config.fps;
t_norm = frame_times / max(frame_times);  % Normalized 0-1

% Horizontal separation (decreases linearly)
horizontal_sep = dist_start_m + (dist_end_m - dist_start_m) * t_norm;

% TRUE 3D distance (with altitude difference)
true_distance = sqrt(horizontal_sep.^2 + alt_diff_m^2);

fprintf('\n=================================================================\n');
fprintf('TRAJECTORY: Close Inspection with Altitude Difference\n');
fprintf('=================================================================\n');
fprintf('Frame | Horiz (m) | Alt Diff (m) | True 3D (m) | True 3D (km)\n');
fprintf('%s\n', repmat('-', 1, 65));

for frame_idx = 1:min(10,num_frames)
    fprintf('%5d | %9.1f | %12.1f | %11.1f | %11.2f\n', ...
        frame_idx, horizontal_sep(frame_idx), alt_diff_m, ...
        true_distance(frame_idx), true_distance(frame_idx)/1e3);
end

if num_frames > 10
    fprintf('  ...\n');
    for frame_idx = (num_frames-4):num_frames
        fprintf('%5d | %9.1f | %12.1f | %11.1f | %11.2f\n', ...
            frame_idx, horizontal_sep(frame_idx), alt_diff_m, ...
            true_distance(frame_idx), true_distance(frame_idx)/1e3);
    end
end

fprintf('\n');

% =====================================================================
% IMPACT ON RENDERING
% =====================================================================

% IFOV (Instantaneous Field Of View)
focal_length_m = 0.5;      % 500 mm
pixel_pitch_m = 15e-6;     % 15 um
ifov_rad_per_px = pixel_pitch_m / focal_length_m;

% Target physical size (assume 2m spacecraft)
target_size_m = 2.0;

% Angular size
angular_size = atan(target_size_m ./ true_distance);

% Projected size on detector (pixels)
pixels_on_detector = angular_size / ifov_rad_per_px;

fprintf('RENDERING IMPACT:\n');
fprintf('  Target physical size: %.2f m\n', target_size_m);
fprintf('  IFOV:                 %.2f urad/px\n\n', ifov_rad_per_px*1e6);

fprintf('Frame | True 3D Dist (m) | Angular Size (urad) | Pixels on Detector\n');
fprintf('%s\n', repmat('-', 1, 72));

for frame_idx = [1, 10, 20, 30, 40, 50]
    if frame_idx <= num_frames
        fprintf('%5d | %16.1f | %19.2f | %18.2f\n', ...
            frame_idx, true_distance(frame_idx), ...
            angular_size(frame_idx)*1e6, pixels_on_detector(frame_idx));
    end
end

fprintf('\n');

% =====================================================================
% COMPARISON: WITH vs WITHOUT altitude difference
% =====================================================================

fprintf('=================================================================\n');
fprintf('COMPARISON: WITH vs WITHOUT Altitude Difference\n');
fprintf('=================================================================\n\n');

% Without altitude (old implementation)
pixels_without_alt = atan(target_size_m ./ horizontal_sep) / ifov_rad_per_px;

fprintf('Frame | Horiz Only (px) | With Alt Diff (px) | Reduction (%%)\n');
fprintf('%s\n', repmat('-', 1, 65));

for frame_idx = [1, 10, 20, 30, 40, 50]
    if frame_idx <= num_frames
        pct_reduction = (pixels_without_alt(frame_idx) - pixels_on_detector(frame_idx)) ...
                       / pixels_without_alt(frame_idx) * 100;
        fprintf('%5d | %15.2f | %18.2f | %13.2f\n', ...
            frame_idx, pixels_without_alt(frame_idx), ...
            pixels_on_detector(frame_idx), pct_reduction);
    end
end

fprintf('\n');
fprintf('KEY INSIGHT:\n');
fprintf('  Altitude difference causes target to render SMALLER than configured distance suggests\n');
fprintf('  Effect increases with larger altitude differences\n');
fprintf('  At Close Inspection (100-250m), 200km altitude diff is HIGHLY SIGNIFICANT\n\n');

% Store results in scenario struct
scenario.frames = num_frames;
scenario.horizontal_sep_m = horizontal_sep;
scenario.altitude_diff_m = alt_diff_m;
scenario.true_distance_m = true_distance;
scenario.pixels_on_detector = pixels_on_detector;
scenario.altitude_chaser_m = alt_chaser_m;
scenario.altitude_target_m = alt_target_m;

end
