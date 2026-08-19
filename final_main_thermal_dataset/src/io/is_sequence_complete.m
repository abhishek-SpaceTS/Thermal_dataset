function complete = is_sequence_complete(seq_dir, num_frames)
    complete = false;
    if ~isfile(fullfile(seq_dir, 'metadata.json')), return; end
    if ~isfile(fullfile(seq_dir, 'labels.csv')), return; end
    if ~isfile(fullfile(seq_dir, 'component_annotations.json')), return; end
    if ~isfile(fullfile(seq_dir, 'videos', 'thermal_gray.mp4')), return; end
    if ~isfile(fullfile(seq_dir, 'videos', 'thermal_rgb.mp4')), return; end

    for i = 1:num_frames
        fname = sprintf('frame%06d.png', i);
        if ~isfile(fullfile(seq_dir, 'thermal_gray', fname)), return; end
        if ~isfile(fullfile(seq_dir, 'thermal_rgb', fname)), return; end
        if ~isfile(fullfile(seq_dir, 'component_masks', fname)), return; end
        if ~isfile(fullfile(seq_dir, 'component_masks_rgb', fname)), return; end
    end

    complete = true;
end
