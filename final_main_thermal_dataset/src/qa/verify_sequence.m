function verify_sequence(seq_dir, num_frames, bbox_areas, resolution, OUT)
% Check one generated sequence is complete and coherent.

    if nargin < 5 || isempty(OUT)
        OUT = struct();
    end
    want = @(n) ~isfield(OUT, n) || OUT.(n);

    fprintf('\n--- Running Verification ---\n');
    pass = true;

    % Highest legal mask value follows the taxonomy, not a hard-coded 14.
    cls = class_definitions();
    max_class_id = max([cls.id]);

    for i = 1:num_frames
        fname = sprintf('frame%06d.png', i);
        if want('thermal_gray') && ~isfile(fullfile(seq_dir, 'thermal_gray', fname))
            fprintf('  FAIL: missing thermal_gray/%s\n', fname); pass = false;
        end
        if want('thermal_rgb') && ~isfile(fullfile(seq_dir, 'thermal_rgb', fname))
            fprintf('  FAIL: missing thermal_rgb/%s\n', fname); pass = false;
        end

        if want('component_masks')
            mask_path = fullfile(seq_dir, 'component_masks', fname);
            if ~isfile(mask_path)
                fprintf('  FAIL: missing component_masks/%s\n', fname); pass = false;
            else
                mask = imread(mask_path);
                vals = unique(mask);
                if any(vals > max_class_id) || any(vals < 0)
                    fprintf('  FAIL: invalid values in component_masks/%s\n', fname); pass = false;
                end
            end
        end

        if want('component_masks_rgb')
            mask_rgb_path = fullfile(seq_dir, 'component_masks_rgb', fname);
            if ~isfile(mask_rgb_path)
                fprintf('  FAIL: missing component_masks_rgb/%s\n', fname); pass = false;
            else
                mask_rgb = imread(mask_rgb_path);
                if size(mask_rgb,3) ~= 3
                    fprintf('  FAIL: component_masks_rgb is not 3 channels\n'); pass = false;
                end
            end
        end

        if want('visual_gray') && ~isfile(fullfile(seq_dir, 'visual_gray', fname))
            fprintf('  FAIL: missing visual_gray/%s\n', fname); pass = false;
        end
        if want('visual_rgb') && ~isfile(fullfile(seq_dir, 'visual_rgb', fname))
            fprintf('  FAIL: missing visual_rgb/%s\n', fname); pass = false;
        end
    end

    required = {};
    if want('labels_csv'); required{end+1} = 'labels.csv'; end
    if want('videos')
        if want('thermal_gray'); required{end+1} = fullfile('videos','thermal_gray.mp4'); end
        if want('thermal_rgb');  required{end+1} = fullfile('videos','thermal_rgb.mp4');  end
    end
    if want('annotations_json'); required{end+1} = 'component_annotations.json'; end
    for f = required
        if ~isfile(fullfile(seq_dir, f{1}))
            fprintf('  FAIL: missing %s\n', f{1}); pass = false;
        end
    end
    if pass, fprintf('  OK  All expected files were generated.\n'); end

    data   = readmatrix(fullfile(seq_dir, 'labels.csv'), 'NumHeaderLines', 1);
    bboxes = data(:, 3:6);
    pixel_counts = data(:, 18);

    total_frames = size(bboxes, 1);
    visible_frames = 0;
    invisible_frames = 0;

    for i = 1:total_frames
        bx = bboxes(i,1); by = bboxes(i,2); bw = bboxes(i,3); bh = bboxes(i,4);
        if bw <= 0 || bh <= 0 || bx == 0 || by == 0
            invisible_frames = invisible_frames + 1;
        else
            visible_frames = visible_frames + 1;
            if bx + bw - 1 > resolution(1) || by + bh - 1 > resolution(2)
                fprintf('  FAIL: bbox exceeds image bounds at frame %d\n', i); pass = false;
            end
        end
    end

    fprintf('  Visible frames: %d / %d\n', visible_frames, total_frames);
    fprintf('  Invisible frames: %d / %d\n', invisible_frames, total_frames);

    if visible_frames == 0
        fprintf('  FAIL: every frame is invisible.\n'); pass = false;
    end

    if all(pixel_counts == 0)
        fprintf('  FAIL: spacecraft_pixel_count is zero for the entire sequence.\n'); pass = false;
    end

    if invisible_frames / total_frames > 0.5
        fprintf('  FAIL: invisible-frame ratio exceeds intended threshold (50%%).\n'); pass = false;
    end

    if pass, fprintf('  OK  Bounding boxes valid and follow visibility policy.\n'); end

    half = floor(num_frames/2);
    area_start = mean(bbox_areas(1:half));
    area_end   = mean(bbox_areas(half+1:end));
    if area_end <= area_start
        fprintf('  WARN: apparent size did not increase (start=%.0f end=%.0f) - check trajectory sign\n', ...
            area_start, area_end);
    else
        fprintf('  OK  Apparent target size increased as range decreased.\n');
    end

    if pass
        fprintf('=== Verification PASSED ===\n');
    else
        fprintf('=== Verification FAILED - review messages above ===\n');
    end
end
