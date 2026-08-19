function print_multi_spacecraft_report(sc_summary)
    n = numel(sc_summary);
    n_ok = 0;
    total_sequences = 0;
    total_frames = 0;

    fprintf('\n\n');
    fprintf('=================================================\n');
    fprintf('MULTI-SPACECRAFT DATASET GENERATION - FINAL REPORT\n');
    fprintf('=================================================\n\n');

    fprintf('Spacecraft discovered : %d\n', n);
    fprintf('Spacecraft processed  : %d\n\n', n);

    fprintf('%-24s %-8s %-12s %-10s %s\n', 'Spacecraft', 'Status', 'Sequences', 'Frames', 'Dataset Location');
    fprintf('%s\n', repmat('-', 1, 110));
    for i = 1:n
        s = sc_summary(i);
        if strcmp(s.status, 'OK')
            n_ok = n_ok + 1;
        end
        total_sequences = total_sequences + s.sequences_generated;
        total_frames = total_frames + s.frames_generated;
        fprintf('%-24s %-8s %-12d %-10d %s\n', s.name, s.status, ...
            s.sequences_generated, s.frames_generated, s.dataset_path);
    end
    fprintf('%s\n\n', repmat('-', 1, 110));

    fprintf('Successful : %d / %d\n', n_ok, n);
    fprintf('Failed     : %d / %d\n', n - n_ok, n);
    fprintf('Total sequences generated : %d\n', total_sequences);
    fprintf('Total frames generated    : %d\n\n', total_frames);

    fprintf('Failures:\n');
    any_fail = false;
    for i = 1:n
        if ~strcmp(sc_summary(i).status, 'OK')
            any_fail = true;
            fprintf('  %-24s : %s\n', sc_summary(i).name, sc_summary(i).error);
        end
    end
    if ~any_fail
        fprintf('  None.\n');
    end

    fprintf('\n=================================================\n');
end
