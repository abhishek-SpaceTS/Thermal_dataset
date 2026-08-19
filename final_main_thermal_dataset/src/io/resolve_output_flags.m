function OUT = resolve_output_flags(RUN)
% Which artefacts a run should write.

names = { 'thermal_gray', 'thermal_rgb', 'visual_gray', 'visual_rgb', ...
          'component_masks', 'component_masks_rgb', 'videos', ...
          'labels_csv', 'annotations_json', 'run_verification' };

has_out = isfield(RUN, 'output');
for k = 1:numel(names)
    n = names{k};
    if has_out && isfield(RUN.output, n) && ~isempty(RUN.output.(n))
        OUT.(n) = logical(RUN.output.(n));
    else
        OUT.(n) = true;
    end
end

OUT.visual_log_gain = [];
if isfield(RUN, 'visual') && isfield(RUN.visual, 'log_gain') && ...
        ~isempty(RUN.visual.log_gain)
    OUT.visual_log_gain = RUN.visual.log_gain;
end

% Display mapping for visual_*: 'linear' (temperature-faithful, matches
% thermal_rgb) or 'log' (lifts faint stars, crushes the bright end).
OUT.visual_mode = 'linear';
if isfield(RUN, 'visual') && isfield(RUN.visual, 'mode') && ~isempty(RUN.visual.mode)
    OUT.visual_mode = lower(char(RUN.visual.mode));
end

off = names(~cellfun(@(n) OUT.(n), names));
if ~isempty(off)
    fprintf('Outputs disabled: %s\n', strjoin(off, ', '));
    if OUT.videos && ~OUT.thermal_gray && ~OUT.thermal_rgb
        fprintf('  note: videos enabled but no source frames -- none will be written\n');
    end
    if OUT.run_verification && ~OUT.labels_csv
        fprintf('  note: verification enabled but needs labels_csv -- will be skipped\n');
    end
end

end
