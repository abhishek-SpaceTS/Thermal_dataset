function run_generation()
%RUN_GENERATION  Generate the synthetic thermal RSO dataset.
%
%   run_generation()
%
%   The single entry point. Reads config.m, discovers the spacecraft under
%   data/spacecraft, and generates one dataset per spacecraft into output/.
%
%   Pipeline, in order:
%     config.m                    what to generate
%     discover_spacecraft         which models exist
%     write_dataset_json          dataset-level constants, once
%     generate_spacecraft_dataset per spacecraft: sequences and frames
%     report_quality              audit what was written
%
%   Everything configurable lives in config.m. Component temperatures live in
%   src/target/thermal_database.m, one row per class.

    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), 'src')));

% Pipeline helpers live in Pipeline/ (one function per file, as MATLAB
    addpath(fullfile(fileparts(mfilename('fullpath'))));

    RUN = config();
    debug_mode = RUN.debug_mode;

    selected_spacecraft = RUN.spacecraft;

    reproducible_seed = RUN.random_seed;
    if isempty(reproducible_seed)
        rng('shuffle');
    else
        rng(reproducible_seed);
    end

    this_file = mfilename('fullpath');
    if isempty(this_file)
        project_root = pwd;
    else
        project_root = fileparts(this_file);
    end

    spacecraft_root = fullfile(project_root, 'data', 'spacecraft');
    spacecraft_names = discover_spacecraft(spacecraft_root);

    fprintf('=================================================\n');
    fprintf('MULTI-SPACECRAFT DATASET GENERATION\n');
    fprintf('=================================================\n');
    fprintf('Spacecraft root: %s\n', spacecraft_root);
    fprintf('Discovered %d spacecraft:\n', numel(spacecraft_names));
    for sc_idx = 1:numel(spacecraft_names)
        fprintf('  - %s\n', spacecraft_names{sc_idx});
    end
    fprintf('\n');

    if isempty(spacecraft_names)
        warning('No spacecraft folders (with a CAD/ subfolder) found in: %s', spacecraft_root);
        return;
    end

    spacecraft_names = select_spacecraft(spacecraft_names, selected_spacecraft);

    % Dataset-level constants, written once at output/. Everything identical
    % across every sequence lives there instead of being repeated 110 times.

    % Resolve output directory: cfg.output.dataset_dir if set, else 'dataset'
    % subfolder under the project root.
    if isfield(RUN, 'output') && isfield(RUN.output, 'dataset_dir') && ...
            ~isempty(RUN.output.dataset_dir)
        dataset_out_dir = RUN.output.dataset_dir;
    else
        dataset_out_dir = fullfile(project_root, 'dataset');
    end
    if ~exist(dataset_out_dir, 'dir')
        mkdir(dataset_out_dir);
    end
    fprintf('Output directory: %s\n\n', dataset_out_dir);

    try
        % apply_band must run first: it sets band, wavelength range and
        % centre. Passing the raw base config left the whole sensor block --
        % and the band centre the emissivity model needs -- unset.
        dj_cfg.thermal = camera_intrinsics(RUN);
        dj_cfg = apply_band(dj_cfg, RUN);
        write_dataset_json(dataset_out_dir, dj_cfg, RUN);
    catch ME
        warning('Could not write dataset_info.json: %s', ME.message);
    end

    if debug_mode
        num_sequences = 1;
        frames_per_sequence = 5;
        fprintf('**************************************************\n');
        fprintf('DEBUG MODE ENABLED\n');
        fprintf('Generating only %d sequence(s) x %d frame(s) for EVERY spacecraft (verification run).\n', ...
            num_sequences, frames_per_sequence);
        fprintf('**************************************************\n');
    else
        num_sequences = RUN.num_sequences;
        frames_per_sequence = RUN.frames_per_sequence;
        fprintf('Generating full dataset for every spacecraft:\n');
        fprintf('Number of sequences per spacecraft: %d\n', num_sequences);
    end

    fps = RUN.fps;
    T_min = RUN.sensor.T_min; T_max = RUN.sensor.T_max;

    n_sc = numel(spacecraft_names);
    sc_summary = struct('name', cell(1, n_sc), 'status', cell(1, n_sc), ...
        'sequences_generated', cell(1, n_sc), 'frames_generated', cell(1, n_sc), ...
        'dataset_path', cell(1, n_sc), 'error', cell(1, n_sc));

    for sc_idx = 1:n_sc
        spacecraft_name = spacecraft_names{sc_idx};

        fprintf('\n=================================================\n');
        fprintf('[%d/%d] SPACECRAFT: %s\n', sc_idx, n_sc, spacecraft_name);
        fprintf('=================================================\n');

        sc_summary(sc_idx).name = spacecraft_name;
        sc_summary(sc_idx).sequences_generated = 0;
        sc_summary(sc_idx).frames_generated = 0;
        sc_summary(sc_idx).dataset_path = '';
        sc_summary(sc_idx).error = '';

        try
            [n_seq_ok, n_frames_ok, dataset_root] = generate_spacecraft_dataset( ...
                dataset_out_dir, spacecraft_name, num_sequences, frames_per_sequence, fps, T_min, T_max, RUN);

            sc_summary(sc_idx).status = 'OK';
            sc_summary(sc_idx).sequences_generated = n_seq_ok;
            sc_summary(sc_idx).frames_generated = n_frames_ok;
            sc_summary(sc_idx).dataset_path = dataset_root;
        catch ME
            sc_summary(sc_idx).status = 'FAILED';
            sc_summary(sc_idx).error = ME.message;
            fprintf('\n  [FAILED] %s : %s\n', spacecraft_name, ME.message);
            disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
    end

    print_multi_spacecraft_report(sc_summary);
end

