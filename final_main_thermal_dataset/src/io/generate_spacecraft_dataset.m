function [sequences_completed, frames_completed, dataset_root] = generate_spacecraft_dataset( ...
        project_root, spacecraft_name, num_sequences, frames_per_sequence, fps, T_min, T_max, RUN)

    sequences_completed = 0;
    frames_completed = 0;

    % project_root here is already the resolved dataset output directory
    % (cfg.output.dataset_dir or fallback), passed in from run_generation.m.
    dataset_root = fullfile(project_root, spacecraft_name);
    base_dir     = fullfile(dataset_root, 'sequences');

    if ~exist(base_dir, 'dir')
        mkdir(base_dir);
    end

    % class_map.json and class_colors.json are DERIVED from
    config = struct();
    config.thermal = camera_intrinsics(RUN);
    config.target.name = spacecraft_name;
    config = apply_band(config, RUN);
    config = apply_star_settings(config, RUN);
    if isfield(RUN,'distance_scenarios') && ~isempty(RUN.distance_scenarios)
        config.distance_scenarios = RUN.distance_scenarios;
    end
    config.run = RUN;
    config.resume    = RUN.resume;
    config.overwrite = RUN.overwrite;
    % Propagate orbital altitudes so every trajectory file reads them from
    % config.orbit (set ONLY in config.m, never hardcoded in trajectory files).
    if isfield(RUN, 'orbit')
        config.orbit = RUN.orbit;
    end

    manifest_path = fullfile(dataset_root, 'sequence_index.csv');
    manifest_header = 'sequence_id,scenario_type,trajectory_name,trajectory_type,distance_start_m,distance_end_m,num_frames,angular_velocity_mag,sun_vector,blur,netd';

    if isfile(manifest_path)
        fid_check = fopen(manifest_path, 'r');
        first_line = fgetl(fid_check);
        fclose(fid_check);
        if ~ischar(first_line) || ~strcmp(strtrim(first_line), manifest_header)
            delete(manifest_path);
        end
    end

    seq_names_to_generate = {};
    for seq_idx = 1:num_sequences
        seq_name = sprintf('Sequence%03d', seq_idx);
        seq_dir  = fullfile(base_dir, seq_name);
        should_generate = true;
        if exist(seq_dir, 'dir') == 7
            if config.overwrite
                should_generate = true;
            elseif config.resume
                if is_sequence_complete(seq_dir, frames_per_sequence)
                    should_generate = false;
                else
                    should_generate = true;
                end
            else
                should_generate = false;
            end
        end
        if should_generate
            seq_names_to_generate{end+1} = seq_name;
        end
    end

    if isfile(manifest_path) && ~isempty(seq_names_to_generate)
        existing = readtable(manifest_path, 'TextType', 'string');
        if height(existing) > 0 && ...
                any(strcmp('sequence_id', existing.Properties.VariableNames))
            keep_mask = ~ismember(string(existing.sequence_id), ...
                                  string(seq_names_to_generate));
            existing = existing(keep_mask, :);
            writetable(existing, manifest_path);
        end
    end

    write_header = ~isfile(manifest_path);
    if write_header
        fid_manifest = fopen(manifest_path, 'a');
        fprintf(fid_manifest, '%s\n', manifest_header);
        fclose(fid_manifest);
    end

    % class_map.json / class_colors.json, derived from class_definitions.m.
    % dataset_info.json's taxonomy block names both files, so without this the
    % dataset shipped integer mask ids that nothing in the output could
    % decode -- a reader had to open the MATLAB source to interpret them.
    write_class_maps(dataset_root);

    fprintf('Building CAD model for %s...\n', spacecraft_name);
    target_cad = build_cad(config);

    % Circumscribing radius about the CAD origin, in metres. framing_limits
    % reserves this out of the half-field so the trajectory models keep the
    % whole BODY in frame rather than just its centroid -- which matters
    % because the target spans a few pixels at 12 km and a third of the frame
    % at 100 m, so no fixed fractional margin can serve both.
    config.target.bounding_radius_m = max(sqrt(sum(target_cad.vertices.^2, 2)));
    fprintf('Bounding radius : %.3f m (reserved from the field of view)\n', ...
        config.target.bounding_radius_m);

    for seq_idx = 1:num_sequences
        seq_name = sprintf('Sequence%03d', seq_idx);

        if ~any(strcmp(seq_names_to_generate, seq_name))
            fprintf('Sequence %s already complete (or skipping). Skipping.\n', seq_name);
            continue;
        end

        try
            scenario_valid = false;
            attempts = 0;
            while ~scenario_valid && attempts < 20
                scenario = generate_random_scenario(frames_per_sequence, 1.0/fps, config);

                visible_frames = 0;
                sample_indices = round(linspace(1, frames_per_sequence, min(10, frames_per_sequence)));
                % Full half-FOV per axis, no artificial safety margin. This is
                % a scenario ACCEPTANCE test, not a render clip: it rejects
                % trajectories that would fly the target out of frame. Nothing
                % here reduces what the renderer draws.
                %
                % PER AXIS. This used to compare both angles against
                % config.thermal.fov/2, which is the HORIZONTAL half-field, so
                % on a non-square detector it accepted trajectories whose y
                % offset was up to fov_h/fov_v too large -- the same defect the
                % trajectory models had. The models now bound themselves
                % correctly via framing_limits, so this rejects nothing extra
                % in practice; it is aligned so the two cannot drift apart.
                fov_half_x = config.thermal.fov_h / 2;
                fov_half_y = config.thermal.fov_v / 2;

                for s_idx = 1:length(sample_indices)
                    f = sample_indices(s_idx);
                    curr_pos = scenario.positions(:, f);

                    angle_x = abs(atan(curr_pos(1)/curr_pos(3)));
                    angle_y = abs(atan(curr_pos(2)/curr_pos(3)));

                    if angle_x < fov_half_x && angle_y < fov_half_y
                        visible_frames = visible_frames + 1;
                    end
                end

                if visible_frames >= (length(sample_indices) * 0.5)
                    scenario_valid = true;
                else
                    attempts = attempts + 1;
                end
            end

            if ~scenario_valid
                error('Could not generate a valid scenario within FOV after %d attempts', attempts);
            end

        seq_dir  = fullfile(base_dir, seq_name);

        if exist(seq_dir, 'dir')
            fprintf('Sequence %s is incomplete or being overwritten. Deleting...\n', seq_name);
            try rmdir(seq_dir, 's'); catch ME, warning('Could not remove existing %s: %s', seq_dir, ME.message); end
        end
        gray_dir  = fullfile(seq_dir, 'thermal_gray');
        rgb_dir   = fullfile(seq_dir, 'thermal_rgb');
        visual_gray_dir = fullfile(seq_dir, 'visual_gray');
        visual_rgb_dir  = fullfile(seq_dir, 'visual_rgb');
        video_dir = fullfile(seq_dir, 'videos');
        mask_dir  = fullfile(seq_dir, 'component_masks');
        mask_rgb_dir = fullfile(seq_dir, 'component_masks_rgb');
        OUT = resolve_output_flags(RUN);

        mkdir(seq_dir);
        if OUT.thermal_gray,        mkdir(gray_dir);        end
        if OUT.thermal_rgb,         mkdir(rgb_dir);         end
        if OUT.component_masks,     mkdir(mask_dir);        end
        if OUT.component_masks_rgb, mkdir(mask_rgb_dir);    end
        if OUT.visual_gray,         mkdir(visual_gray_dir); end
        if OUT.visual_rgb,          mkdir(visual_rgb_dir);  end
        if OUT.videos,              mkdir(video_dir);       end

        fprintf('\n=================================================\n');
        fprintf('Generating %s (%d frames)...\n', seq_name, frames_per_sequence);
        fprintf('Trajectory: %s [%s] (%.0f m -> %.0f m)\n', scenario.trajectory_name, scenario.trajectory_type, scenario.distance_start, scenario.distance_end);

        fid = -1;
        clean_fid = [];  %#ok<NASGU>
        if OUT.labels_csv
            labels_path = fullfile(seq_dir, 'labels.csv');
            fid = fopen(labels_path, 'w');
            if fid == -1
                error('Failed to open %s for writing. File may be locked.', labels_path);
            end
            clean_fid = onCleanup(@() fclose(fid));
            % Poses are CAMERA frame; quaternions are [w x y z]. The last three
            % columns were appended, so a parser reading by index still works.
            fprintf(fid, ['frame_id,timestamp,' ...
                          'bbox_x,bbox_y,bbox_width,bbox_height,' ...
                          'rel_pos_x,rel_pos_y,rel_pos_z,' ...
                          'range_m,' ...
                          'quat_w,quat_x,quat_y,quat_z,' ...
                          'velocity_x,velocity_y,velocity_z,spacecraft_pixel_count,' ...
                          'in_eclipse,truncated,solar_phase_angle_deg\n']);
        end

        % Detector non-uniformity, drawn ONCE for the whole sequence so it is
        % identical on every frame -- that is what makes it un-averageable and
        % therefore realistic. Seeded off the same spacecraft+sequence hash the
        % thermal draw uses, on its own RNG stream, so it cannot shift the
        % scenario draws.
        fpn = fixed_pattern_noise(config.thermal.resolution([2 1]), ...
                                  thermal_seed(RUN.random_seed, spacecraft_name, seq_name), RUN);
        if fpn.enabled
            fprintf('  FPN: col %.0f mK, row %.0f mK, pixel %.0f mK, gain %.2f%%, %d dead px\n', ...
                fpn.column_K*1e3, fpn.row_K*1e3, fpn.pixel_K*1e3, fpn.gain_pct, fpn.n_dead);
        end

        curr_quat = scenario.initial_quaternion;
        curr_time = 0;
        dt = 1.0 / fps;
        bbox_areas = zeros(1, frames_per_sequence);

        % ---- Target attitude source ------------------------------------
        % "sampled" integrates a constant body rate about a random axis at
        % the bottom of the frame loop. "hil" replaces that with the
        % propagated attitude from the HIL Phase 1 truth, resampled onto
        % this sequence's frame times. Sequence k starts hil_start_s +
        % (k-1)*duration into the pass, so sequences walk along it rather
        % than all rendering the same instant.
        %
        % Only the ATTITUDE is taken here. Range still comes from the
        % distance bracket and the camera attitude is still drawn, so this
        % stays a varied dataset. validate_against_hil.m is the mode that
        % takes HIL position and attitude together.
        hil_quat = [];
        if strcmpi(local_setting(RUN, 'attitude', 'source', "sampled"), 'hil')
            hil_dir = local_setting(RUN, 'attitude', 'hil_dir', '');
            t0 = local_setting(RUN, 'attitude', 'hil_start_s', 0) + ...
                 (seq_idx - 1) * frames_per_sequence * dt;
            Hs = hil_state_at(hil_trajectory(hil_dir), ...
                              t0 + (0:frames_per_sequence-1) * dt);
            hil_quat  = Hs.chief_quat;
            curr_quat = hil_quat(1, :);      % frame 1 uses row 1
            scenario.attitude_name = 'HIL propagated';

            % Effective body rate, measured from consecutive quaternions
            % rather than read from the file. HIL stores ang_velocity as
            % zeros for both craft even though the attitude clearly evolves
            % -- its chief turns ~0.033 deg per 0.1 s step -- so trusting
            % that column would record a tumbling target as perfectly stable
            % in the metadata.
            if frames_per_sequence > 1
                dth = zeros(1, frames_per_sequence-1);
                for q_i = 1:frames_per_sequence-1
                    c_dot = abs(dot(hil_quat(q_i,:), hil_quat(q_i+1,:)));
                    dth(q_i) = 2 * acos(min(1, c_dot));
                end
                scenario.angular_velocity_magnitude = mean(dth) / dt;
            else
                scenario.angular_velocity_magnitude = 0;
            end
            fprintf('  Attitude: HIL propagated, t = %.1f - %.1f s\n', ...
                    t0, t0 + (frames_per_sequence-1)*dt);
        end

        seq_annotations = struct();
        seq_annotations.sequence_id = seq_name;
        seq_annotations.frames = {};

        % One thermal draw per sequence. thermal_database.m stores
        % base/sunlit/eclipse as ranges; this collapses them to the values
        % this whole sequence will use, so a pass has a consistent thermal
        % state while different passes vary. Seeded on spacecraft + sequence
        % rather than the global stream, so resume/skip cannot shift it.
        seq_thermal_seed = thermal_seed(RUN.random_seed, spacecraft_name, seq_name);
        config.run.thermal.realised = sample_thermal_state(seq_thermal_seed);

        % Per-frame quantities collected for the sequence metadata. Illumination
        % and the rendered temperature spread cannot be recovered afterwards
        % from the images, so they are accumulated as frames are written.
        fr = struct();
        fr.in_eclipse   = false(1, frames_per_sequence);
        fr.truncated    = false(1, frames_per_sequence);
        fr.visible      = false(1, frames_per_sequence);
        fr.range_m      = nan(1, frames_per_sequence);
        fr.pixels       = zeros(1, frames_per_sequence);
        fr.ang_size_deg = nan(1, frames_per_sequence);
        fr.phase_deg    = nan(1, frames_per_sequence);
        fr.earth_cov    = nan(1, frames_per_sequence);
        fr.bbox_fail    = false(1, frames_per_sequence);
        % Clipping census, measured on the Kelvin field BEFORE the save window
        % is applied. Target and background are separated by the component
        % mask; target_core additionally erodes the mask so that PSF-blurred
        % edge pixels -- which mix target radiance with the cold sky and can
        % read far below any real face temperature -- are excluded.
        fr.px_below_tmin_bg     = zeros(1, frames_per_sequence);
        fr.px_below_tmin_tgt    = zeros(1, frames_per_sequence);
        fr.px_below_tmin_core   = zeros(1, frames_per_sequence);
        fr.px_above_tmax_bg     = zeros(1, frames_per_sequence);
        fr.px_above_tmax_tgt    = zeros(1, frames_per_sequence);
        fr.px_at_floor_bg       = zeros(1, frames_per_sequence);
        fr.n_bg                 = zeros(1, frames_per_sequence);
        fr.n_tgt                = zeros(1, frames_per_sequence);
        fr.n_core               = zeros(1, frames_per_sequence);
        fr.scene_T_min          = nan(1, frames_per_sequence);
        fr.scene_T_max          = nan(1, frames_per_sequence);
        fr.T_min        = nan(1, frames_per_sequence);
        fr.T_max        = nan(1, frames_per_sequence);
        fr.T_mean       = nan(1, frames_per_sequence);

        % Component names and mask colours both come from class_definitions;
        % index 1 of comp_names is class id 1, so Background (id 0) is dropped.
        cls = class_definitions();
        comp_names = {cls(2:end).name};
        colors_lut = uint8(reshape([cls.rgb], 3, []).');
        R_lut = colors_lut(:, 1);
        G_lut = colors_lut(:, 2);
        B_lut = colors_lut(:, 3);

        for i_frame = 1:frames_per_sequence
            try
                curr_pos = scenario.positions(:, i_frame);
                velocity = scenario.velocities(:, i_frame);

                deputy_pos_eci = zeros(3, 1);

                deputy_quat  = scenario.deputy_quaternion;
                R_cam_to_eci = quat2rotm(deputy_quat)';
                dep_conj     = [deputy_quat(1), -deputy_quat(2:4)];

                chief_pos_eci  = R_cam_to_eci * curr_pos;
                chief_quat_eci = quat_multiply(dep_conj, curr_quat);
                sun_vec_eci    = R_cam_to_eci * scenario.sun_vector(:);

                % Orbit geometry is ALWAYS evaluated; only the BACKGROUND
                % render is optional. The reflected-environment model needs
                % altitude and nadir whether or not Earth is drawn, and
                % gating the geometry on the background would make switching
                % the backdrop off silently change every surface temperature.
                % earth_state.enabled is what rasterise_frame tests before
                % drawing, so the two stay independent.
                earth_state = earth_state_at(scenario.earth, curr_time);
                earth_state.enabled = RUN.earth.enabled;

                evalc(['projection = project_to_camera(target_cad, chief_pos_eci, ' ...
                       'chief_quat_eci, deputy_pos_eci, deputy_quat, config);']);

                evalc(['[thermal_image, component_mask, frame_info] = rasterise_frame(' ...
                       'config, 1, chief_pos_eci, chief_quat_eci, deputy_pos_eci, deputy_quat, ' ...
                       'sun_vec_eci, target_cad, earth_state);']);

                % Bounding box from the RENDERED MASK, not from the projected
                % vertices.
                %
                % compute_bbox_from_projection used every projected vertex,
                % including faces the renderer then discarded by back-face
                % culling or the depth test. On a closed convex body the two
                % agree, but these models carry single-sided panels, booms and
                % wires: a panel facing away contributes nothing to the image
                % while its vertices still widened the box. Measured over 1500
                % frames, 296 (19.7 %) disagreed with their own mask, worst
                % case 643 px, and it tracked mesh complexity -- 88 on Cassini
                % and 62 on Juno against 2 on CloudSat -- not truncation.
                %
                % Deriving it from the mask makes box and mask consistent by
                % construction, and makes the box mean "what is visible",
                % which is what a detector should be trained on.
                bbox = compute_bbox_from_mask(component_mask);

                if RUN.sensor.scenario_blur_enabled && scenario.blur > 0
                    thermal_image = imgaussfilt(thermal_image, scenario.blur);
                end
                if RUN.sensor.netd_enabled && scenario.netd > 0
                    thermal_image = thermal_image + scenario.netd .* randn(size(thermal_image));
                end

                % Fixed-pattern noise LAST, because it is a property of the
                % detector rather than of the scene or the optics: gain acts on
                % whatever reached the array, and a stuck pixel overrides
                % everything.
                if fpn.enabled
                    thermal_image = fpn.nuc_ref_K + ...
                        (thermal_image - fpn.nuc_ref_K) .* fpn.gain + fpn.offset;
                    if any(fpn.dead(:))
                        thermal_image(fpn.dead) = fpn.dead_value(fpn.dead);
                    end
                end

                frame_name  = sprintf('frame%06d.png', i_frame);
                img_gray_16 = [];
                if OUT.thermal_gray || OUT.visual_gray || OUT.visual_rgb
                    img_gray_16 = to_gray16(thermal_image, T_min, T_max, component_mask);
                end
                if OUT.thermal_gray
                    imwrite(img_gray_16, fullfile(gray_dir, frame_name));
                end

                if OUT.thermal_rgb
                    img_rgb = to_false_rgb(thermal_image, T_min, T_max, component_mask);
                    imwrite(img_rgb, fullfile(rgb_dir, frame_name));
                end

                if OUT.component_masks
                    imwrite(uint8(component_mask), fullfile(mask_dir, frame_name));
                end

                if OUT.component_masks_rgb
                    mask_indices = component_mask + 1;
                    mask_rgb = cat(3, R_lut(mask_indices), G_lut(mask_indices), B_lut(mask_indices));
                    imwrite(mask_rgb, fullfile(mask_rgb_dir, frame_name));
                end

                if OUT.visual_gray || OUT.visual_rgb
                    [vis_gray, vis_rgb] = make_visual(img_gray_16, ...
                        OUT.visual_log_gain, OUT.visual_mode);
                    if OUT.visual_gray
                        imwrite(vis_gray, fullfile(visual_gray_dir, frame_name));
                    end
                    if OUT.visual_rgb
                        imwrite(vis_rgb, fullfile(visual_rgb_dir, frame_name));
                    end
                end

                range_m = norm(curr_pos);
                spacecraft_pixel_count = sum(component_mask(:) > 0);

                % ---- Per-frame quantities -------------------------------
                % Computed before the CSV row so both labels.csv and the
                % sequence metadata read the same values.
                res = config.thermal.resolution;
                fr.range_m(i_frame) = range_m;
                fr.pixels(i_frame)  = spacecraft_pixel_count;
                fr.visible(i_frame) = bbox(3) > 0 && bbox(4) > 0;

                % Target clipped by the frame edge. At close range the craft
                % overflows a 6 deg field, and a half-visible target must not
                % be scored like a whole one.
                fr.truncated(i_frame) = fr.visible(i_frame) && ...
                    (bbox(1) <= 1 || bbox(2) <= 1 || ...
                     bbox(1) + bbox(3) - 1 >= res(1) || bbox(2) + bbox(4) - 1 >= res(2));

                if fr.visible(i_frame)
                    fr.ang_size_deg(i_frame) = ...
                        max(bbox(3), bbox(4)) * config.thermal.pixel_pitch / ...
                        config.thermal.focal_length * 180 / pi;
                end

                % Solar phase angle: the Sun-target-camera angle. 0 deg is
                % fully front-lit, 90 deg side-lit with a terminator across the
                % target, 180 deg backlit. The camera sits at the origin of the
                % camera frame, so the target-to-camera direction is -curr_pos.
                sun_unit_cam = scenario.sun_vector(:) / norm(scenario.sun_vector);
                if range_m > 0
                    fr.phase_deg(i_frame) = ...
                        acosd(max(-1, min(1, dot(-curr_pos(:)/range_m, sun_unit_cam))));
                end

                % Illumination state and rendered temperature spread, both
                % computed inside the renderer and returned on frame_info.
                if isstruct(frame_info)
                    if isfield(frame_info,'in_eclipse')
                        fr.in_eclipse(i_frame) = frame_info.in_eclipse;
                    end
                    if isfield(frame_info,'face_T_min_K')
                        fr.T_min(i_frame)  = frame_info.face_T_min_K;
                        fr.T_max(i_frame)  = frame_info.face_T_max_K;
                        fr.T_mean(i_frame) = frame_info.face_T_mean_K;
                    end
                    % Reflected-environment model actually used. Constant
                    % across a sequence, but captured from the render rather
                    % than re-derived from config so the metadata records
                    % what ran, not what was requested.
                    if isfield(frame_info,'environment')
                        fr.environment = frame_info.environment;
                    end
                    if isfield(frame_info,'earth') && isstruct(frame_info.earth) ...
                            && isfield(frame_info.earth,'coverage')
                        fr.earth_cov(i_frame) = frame_info.earth.coverage;
                    end
                end

                % A bbox failure is a target with projected pixels but no
                % usable box, or a box that runs outside the detector.
                fr.bbox_fail(i_frame) = (spacecraft_pixel_count > 0 && ~fr.visible(i_frame)) ...
                    || (fr.visible(i_frame) && (bbox(1) < 1 || bbox(2) < 1 || ...
                        bbox(1)+bbox(3)-1 > res(1) || bbox(2)+bbox(4)-1 > res(2)));

                % Clipping census on the Kelvin field, before the save window.
                is_tgt = component_mask > 0;
                is_bg  = ~is_tgt;
                core   = is_tgt;
                if any(is_tgt(:))
                    core = imerode(is_tgt, strel('disk', 2));
                end
                fr.n_bg(i_frame)   = nnz(is_bg);
                fr.n_tgt(i_frame)  = nnz(is_tgt);
                fr.n_core(i_frame) = nnz(core);
                % Two thresholds. The bare comparison answers "outside the
                % window" literally, but the sky floor IS T_min, so Gaussian
                % kernel normalisation leaves blank sky at T_min - 1e-9 and a
                % literal count reports most of the background as clipped.
                % The second uses one quantisation step, (T_max-T_min)/65535,
                % the project's own radiometric resolution: a pixel only loses
                % real information if it falls more than one DN outside.
                dn_step = (T_max - T_min) / 65535;
                fr.px_below_tmin_bg(i_frame)   = nnz(thermal_image(is_bg)  < T_min - dn_step);
                fr.px_below_tmin_tgt(i_frame)  = nnz(thermal_image(is_tgt) < T_min - dn_step);
                fr.px_below_tmin_core(i_frame) = nnz(thermal_image(core)   < T_min - dn_step);
                fr.px_above_tmax_bg(i_frame)   = nnz(thermal_image(is_bg)  > T_max + dn_step);
                fr.px_above_tmax_tgt(i_frame)  = nnz(thermal_image(is_tgt) > T_max + dn_step);
                fr.px_at_floor_bg(i_frame)     = nnz(thermal_image(is_bg)  < T_min);
                fr.scene_T_min(i_frame) = min(thermal_image(:));
                fr.scene_T_max(i_frame) = max(thermal_image(:));

                if fid ~= -1
                    fprintf(fid, ['%d,%.4f,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,' ...
                                  '%.6f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f,%d,' ...
                                  '%d,%d,%.3f\n'], ...
                        i_frame, curr_time, ...
                        bbox(1), bbox(2), bbox(3), bbox(4), ...
                        curr_pos(1), curr_pos(2), curr_pos(3), ...
                        range_m, ...
                        curr_quat(1), curr_quat(2), curr_quat(3), curr_quat(4), ...
                        velocity(1), velocity(2), velocity(3), spacecraft_pixel_count, ...
                        fr.in_eclipse(i_frame), fr.truncated(i_frame), fr.phase_deg(i_frame));
                end

                frame_data = struct();
                frame_data.frame_id = i_frame;
                frame_data.in_eclipse = fr.in_eclipse(i_frame);
                frame_data.truncated  = fr.truncated(i_frame);
                frame_data.spacecraft_pixel_count = spacecraft_pixel_count;

                % Earth camera for THIS frame. Pitch and heading change frame
                % to frame when derived from the spacecraft attitude, so they
                % belong here rather than in the per-sequence metadata. Without
                % them a frame cannot be reproduced or checked after the fact.
                if isstruct(frame_info) && isfield(frame_info,'earth') && ...
                        isstruct(frame_info.earth) && frame_info.earth.enabled
                    fe = frame_info.earth;
                    cam_fields = {'lat_deg','lon_deg','alt_m','heading_deg', ...
                                  'pitch_deg','roll_deg','fov_deg','crop_px', ...
                                  'upsample','gimbal_locked'};
                    for cf = 1:numel(cam_fields)
                        if isfield(fe, cam_fields{cf})
                            frame_data.earth_camera.(cam_fields{cf}) = fe.(cam_fields{cf});
                        end
                    end
                    frame_data.earth_coverage = fe.coverage;
                    frame_data.earth_pixels   = fe.n_pixels;
                end

                visible_comps = {};
                for c_id = 1:numel(comp_names)
                    c_mask = component_mask == c_id;
                    c_pixels = sum(c_mask(:));
                    if c_pixels > 0
                        c_data = struct();
                        c_data.name = comp_names{c_id};

                        [r, c] = find(c_mask);
                        rmin = min(r); rmax = max(r);
                        cmin = min(c); cmax = max(c);
                        c_data.bounding_box = [cmin, rmin, cmax - cmin + 1, rmax - rmin + 1];
                        c_data.pixel_count = c_pixels;

                        c_temps = thermal_image(c_mask);
                        t_stat = struct();
                        t_stat.min = min(c_temps);
                        t_stat.max = max(c_temps);
                        t_stat.mean = mean(c_temps);
                        t_stat.std = std(c_temps);
                        c_data.temperature = t_stat;

                        visible_comps{end+1} = c_data;
                    end
                end
                frame_data.visible_component_count = length(visible_comps);
                frame_data.total_component_count = numel(comp_names);
                frame_data.components = visible_comps;

                seq_annotations.frames{end+1} = frame_data;

            catch frame_err
                fprintf('\n  [ERROR] Frame %d failed: %s\n', i_frame, frame_err.message);
                fprintf('  Generating blank fallback files for frame %d to maintain sequence integrity.\n', i_frame);

                frame_name  = sprintf('frame%06d.png', i_frame);
                res = config.thermal.resolution;

                if OUT.thermal_gray
                    imwrite(zeros(res(2), res(1), 'uint16'), fullfile(gray_dir, frame_name));
                end
                if OUT.thermal_rgb
                    imwrite(zeros(res(2), res(1), 3, 'uint8'), fullfile(rgb_dir, frame_name));
                end
                if OUT.component_masks
                    imwrite(zeros(res(2), res(1), 'uint8'), fullfile(mask_dir, frame_name));
                end
                if OUT.component_masks_rgb
                    imwrite(zeros(res(2), res(1), 3, 'uint8'), fullfile(mask_rgb_dir, frame_name));
                end
                if OUT.visual_gray
                    imwrite(zeros(res(2), res(1), 'uint8'), fullfile(visual_gray_dir, frame_name));
                end
                if OUT.visual_rgb
                    imwrite(zeros(res(2), res(1), 3, 'uint8'), fullfile(visual_rgb_dir, frame_name));
                end

                if fid ~= -1
                    fprintf(fid, '%d,%.4f,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0\n', ...
                        i_frame, curr_time);
                end

                err_frame = struct();
                err_frame.frame_id = i_frame;
                err_frame.spacecraft_pixel_count = 0;
                err_frame.visible_component_count = 0;
                err_frame.total_component_count = numel(comp_names);
                err_frame.components = {};
                seq_annotations.frames{end+1} = err_frame;

                bbox = [0, 0, 0, 0];
                range_m = 0;
            end

            bbox_areas(i_frame) = bbox(3) * bbox(4);

            if ~isempty(hil_quat)
                % Propagated attitude: read the next frame's quaternion
                % rather than integrating a body rate. Assigned at the END of
                % the loop like the sampled case, so frame i uses row i.
                if i_frame < frames_per_sequence
                    curr_quat = hil_quat(i_frame + 1, :);
                end
            elseif norm(scenario.angular_velocity) > 0
                angle = norm(scenario.angular_velocity) * dt;
                axis  = scenario.angular_velocity / norm(scenario.angular_velocity);
                dq    = [cos(angle/2), (axis' * sin(angle/2))];
                curr_quat = quat_multiply(curr_quat, dq);
                curr_quat = curr_quat / norm(curr_quat);
            end

            curr_time = curr_time + dt;

            if mod(i_frame, 10) == 0 || i_frame == 1
                fprintf('  Frame %3d/%3d | range=%6.1f m | bbox=[%d,%d,%d,%d]\n', ...
                    i_frame, frames_per_sequence, range_m, bbox(1), bbox(2), bbox(3), bbox(4));
            end
        end
        clear clean_fid;


        mctx = struct('seq_name', seq_name, 'spacecraft_name', spacecraft_name, ...
            'scenario', scenario, 'config', config, 'RUN', RUN, 'target_cad', target_cad, ...
            'fr', fr, 'frames_per_sequence', frames_per_sequence, 'fps', fps, ...
            'T_min', T_min, 'T_max', T_max, 'seq_thermal_seed', seq_thermal_seed);
        meta = build_sequence_metadata(mctx);

        json_str = jsonencode(meta, 'PrettyPrint', true);
        fid_meta = fopen(fullfile(seq_dir, 'metadata.json'), 'w');
        if fid_meta ~= -1
            fprintf(fid_meta, '%s', json_str);
            fclose(fid_meta);
        else
            warning('Could not write metadata.json. File may be locked.');
        end

        if OUT.annotations_json
            fid_ann = fopen(fullfile(seq_dir, 'component_annotations.json'), 'w');
            if fid_ann ~= -1
                fprintf(fid_ann, '%s', jsonencode(seq_annotations, 'PrettyPrint', true));
                fclose(fid_ann);
            else
                warning('Could not write component_annotations.json. File may be locked.');
            end
        end

        if strcmp(scenario.trajectory_type, 'cw_relative_motion')
            actual_dist_start = norm(scenario.positions(:,1));
            actual_dist_end = norm(scenario.positions(:,end));
        else
            actual_dist_start = scenario.distance_start;
            actual_dist_end = scenario.distance_end;
        end
        sun_str = sprintf('[%.3f %.3f %.3f]', scenario.sun_vector(1), scenario.sun_vector(2), scenario.sun_vector(3));
        fid_manifest = fopen(manifest_path, 'a');
        if fid_manifest ~= -1
            fprintf(fid_manifest, '%s,%s,%s,%s,%g,%g,%d,%g,%s,%g,%g\n', ...
                seq_name, scenario.scenario_type, scenario.trajectory_name, scenario.trajectory_type, actual_dist_start, actual_dist_end, ...
                frames_per_sequence, norm(scenario.angular_velocity), sun_str, scenario.blur, scenario.netd);
            fclose(fid_manifest);
        else
            warning('Could not append to %s. File may be locked by another program (e.g., Excel).', manifest_path);
        end

        if OUT.videos
            fprintf('\nWriting preview videos...\n');
            if OUT.thermal_gray
                write_preview_video(gray_dir, fullfile(video_dir, 'thermal_gray.mp4'), fps, false);
            else
                fprintf('  skipped thermal_gray.mp4 (output.thermal_gray is false)\n');
            end
            if OUT.thermal_rgb
                write_preview_video(rgb_dir, fullfile(video_dir, 'thermal_rgb.mp4'), fps, true);
            else
                fprintf('  skipped thermal_rgb.mp4 (output.thermal_rgb is false)\n');
            end
        end

        if OUT.run_verification
            if OUT.labels_csv
                verify_sequence(seq_dir, frames_per_sequence, bbox_areas, config.thermal.resolution, OUT);
            else
                fprintf('\n  skipped verification (needs output.labels_csv)\n');
            end
        end

        sequences_completed = sequences_completed + 1;
        frames_completed = frames_completed + frames_per_sequence;
        catch ME
            warning('Sequence %03d failed: %s', seq_idx, ME.message);
            fail_path = fullfile(dataset_root, 'failed_sequences.txt');
            fid_fail = fopen(fail_path, 'a');
            if fid_fail > 0
                fprintf(fid_fail, 'Sequence%03d: %s\n', seq_idx, ME.message);
                fclose(fid_fail);
            end
            continue;
        end
    end

    fprintf('\n=================================================\n');
    fprintf('Dataset generation complete for %s! (%d/%d sequences)\n', ...
        spacecraft_name, sequences_completed, num_sequences);
    fprintf('=================================================\n');

    % Audit what was actually written: Earth coverage against the requested
    % scene class, solar phase coverage, visibility, and the clipping census.
    try
        report_quality(dataset_root);
    catch ME
        warning('Dataset quality report failed: %s', ME.message);
    end
end



% -----------------------------------------------------------------------------
function v = local_setting(RUN, group, field, dflt)
% Read RUN.<group>.<field>, falling back to dflt when absent or empty.
% RUN here is the whole of config.m, so this is the same access pattern as
% local_run_setting in generate_random_scenario -- see framing_limits.m for
% what happens when a leaf function reads the wrong level of the config.
v = dflt;
if isfield(RUN, group) && isfield(RUN.(group), field) && ~isempty(RUN.(group).(field))
    v = RUN.(group).(field);
end
if isstring(v) || ischar(v)
    v = char(v);
end
end
