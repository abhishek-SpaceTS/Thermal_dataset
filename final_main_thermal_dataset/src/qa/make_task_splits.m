function S = make_task_splits(dataset_root, opts)
%MAKE_TASK_SPLITS  Select the frames of an existing dataset usable per AI task.
%
%   S = make_task_splits(dataset_root)
%   S = make_task_splits(dataset_root, opts)
%
%   One generated dataset serves several tasks, but they do NOT want the same
%   frames. A detector must cope with tiny and half-visible targets -- those
%   are its hard cases. A pose estimator cannot recover orientation from a
%   target clipped by the frame edge. A component segmenter needs every
%   component to occupy enough pixels to be worth a label.
%
%   Rather than regenerate the dataset per task, this writes one index file
%   per task listing the frames that satisfy that task's requirements. The
%   images on disk are untouched.
%
%   WHY EACH THRESHOLD
%   ------------------
%   detection      every frame. Truncated and few-pixel targets are the cases
%                  a real detector has to handle, so excluding them would make
%                  the benchmark easier than reality.
%
%   tracking       whole SEQUENCES, not frames. Tracking is temporal; a
%                  gap-filled frame list would break continuity. A sequence
%                  qualifies when the target is visible in every frame.
%
%   range          every frame with a visible target. Range is recoverable
%                  from apparent size whether or not the target is clipped.
%
%   pose           untruncated, and at least min_px_pose across. Orientation
%                  is carried by the silhouette and the internal thermal
%                  structure; below ~50 px neither is sampled well enough, and
%                  a target cut by the frame edge has no recoverable silhouette.
%
%   segmentation   untruncated, and at least min_px_seg across. A body mask
%                  needs the outline resolved, which takes more pixels than
%                  detecting that something is there.
%
%   component      untruncated, at least min_px_comp across, AND at least
%                  min_components components each holding min_px_per_comp
%                  pixels. A component covering four pixels cannot be
%                  segmented no matter how good the model is, and a frame
%                  showing only one component teaches nothing about the
%                  boundaries between them.
%
%   TRAIN / VAL / TEST IS BY SEQUENCE, NEVER BY FRAME
%   -------------------------------------------------
%   Consecutive frames of one sequence are near-duplicates: 50 frames at 10 Hz
%   span 5 seconds, over which the thermal state is fixed by construction and
%   the pose barely moves. Splitting those frames randomly puts near-copies of
%   the same image in train and test, which inflates every score. The split
%   here is assigned per sequence and every task inherits it, so a sequence is
%   never on both sides of the divide.
%
%   OPTIONS (defaults shown)
%     opts.min_px_pose        50    max bbox dimension, px
%     opts.min_px_seg        100
%     opts.min_px_comp       200
%     opts.min_px_per_comp    20    pixels a component needs to count
%     opts.min_components      2    distinct components required in frame
%     opts.split_fractions  [0.70 0.15 0.15]   train / val / test, by sequence
%     opts.split_seed         42
%     opts.out_dir            <dataset_root>/splits
%
%   OUTPUT
%     One CSV per task in out_dir, columns:
%       spacecraft, sequence, frame_id, split, range_m, bbox_max_px,
%       truncated, in_eclipse, solar_phase_angle_deg, n_components
%     plus splits_summary.json with the counts and the thresholds used.
%
%   The extra columns are there so a task split can be filtered further
%   without re-reading the dataset -- eclipse-only, or a single range band.

if nargin < 2; opts = struct(); end
o = local_defaults(opts, dataset_root);

fprintf('Scanning %s\n', dataset_root);
d = dir(dataset_root);
d = d([d.isdir] & ~startsWith({d.name}, '.'));

rows = struct('sc',{},'seq',{},'frame',{},'range',{},'bbox',{},'trunc',{}, ...
              'ecl',{},'phase',{},'ncomp',{},'vis',{});
seq_keys = {};

for k = 1:numel(d)
    sd = fullfile(dataset_root, d(k).name, 'sequences');
    if ~isfolder(sd); continue; end
    s = dir(fullfile(sd, 'Sequence*')); s = s([s.isdir]);
    for q = 1:numel(s)
        lp = fullfile(sd, s(q).name, 'labels.csv');
        ap = fullfile(sd, s(q).name, 'component_annotations.json');
        if ~isfile(lp); continue; end
        L = readmatrix(lp, 'NumHeaderLines', 1);
        if isempty(L); continue; end

        % components per frame, from the annotations
        ncomp = zeros(size(L,1), 1);
        if isfile(ap)
            try
                A = jsondecode(fileread(ap));
                F = A.frames; if iscell(F); F = [F{:}]; end
                for f = 1:min(numel(F), size(L,1))
                    C = F(f).components; if iscell(C); C = [C{:}]; end
                    if isempty(C); continue; end
                    ncomp(f) = nnz([C.pixel_count] >= o.min_px_per_comp);
                end
            catch ME
                warning('make_task_splits:annotations', ...
                    'Could not read %s: %s', ap, ME.message);
            end
        end

        key = sprintf('%s/%s', d(k).name, s(q).name);
        seq_keys{end+1} = key; %#ok<AGROW>

        for f = 1:size(L,1)
            rows(end+1).sc = d(k).name; %#ok<AGROW>
            rows(end).seq   = s(q).name;
            rows(end).frame = L(f,1);
            rows(end).range = L(f,10);
            rows(end).bbox  = max(L(f,5), L(f,6));
            rows(end).trunc = L(f,20);
            rows(end).ecl   = L(f,19);
            rows(end).phase = L(f,21);
            rows(end).ncomp = ncomp(f);
            rows(end).vis   = L(f,5) > 0 && L(f,6) > 0;
        end
    end
end

if isempty(rows)
    error('make_task_splits:empty', 'No labelled frames found under %s', dataset_root);
end
fprintf('  %d frames in %d sequences\n', numel(rows), numel(seq_keys));

% ---- train / val / test, assigned per SEQUENCE -------------------------
% Its own RandStream so the assignment does not depend on, or disturb, any
% other random draw, and is stable if sequences are added later in a
% different order (the key list is sorted first).
seq_keys = sort(seq_keys);
rs = RandStream('threefry', 'Seed', o.split_seed);
u  = rand(rs, 1, numel(seq_keys));
fr = cumsum(o.split_fractions(:)') / sum(o.split_fractions);
split_of = containers.Map();
for k = 1:numel(seq_keys)
    if     u(k) <= fr(1); lbl = 'train';
    elseif u(k) <= fr(2); lbl = 'val';
    else                  lbl = 'test';
    end
    split_of(seq_keys{k}) = lbl;
end

split_col = cell(numel(rows),1);
for k = 1:numel(rows)
    split_col{k} = split_of(sprintf('%s/%s', rows(k).sc, rows(k).seq));
end

bbox  = [rows.bbox]';
trunc = [rows.trunc]';
ncomp = [rows.ncomp]';
vis   = [rows.vis]';

% ---- task masks --------------------------------------------------------
M = struct();
M.detection    = vis;
M.range        = vis;
M.pose         = vis & trunc == 0 & bbox >= o.min_px_pose;
M.segmentation = vis & trunc == 0 & bbox >= o.min_px_seg;
M.component    = vis & trunc == 0 & bbox >= o.min_px_comp & ncomp >= o.min_components;

% Tracking is sequence-level: keep whole sequences in which every frame is
% visible. Selecting individual frames would tear the temporal continuity
% that makes a tracking benchmark meaningful.
seq_ok = containers.Map();
for k = 1:numel(rows)
    key = sprintf('%s/%s', rows(k).sc, rows(k).seq);
    if ~isKey(seq_ok, key); seq_ok(key) = true; end
    if ~rows(k).vis; seq_ok(key) = false; end
end
M.tracking = false(numel(rows),1);
for k = 1:numel(rows)
    M.tracking(k) = seq_ok(sprintf('%s/%s', rows(k).sc, rows(k).seq));
end

% ---- write -------------------------------------------------------------
if ~isfolder(o.out_dir); mkdir(o.out_dir); end
tasks = fieldnames(M);
S = struct();
S.thresholds = o;
S.total_frames = numel(rows);
S.total_sequences = numel(seq_keys);

fprintf('\n%-14s %8s %7s   %s\n', 'task', 'frames', 'pct', 'train / val / test');
fprintf('%s\n', repmat('-', 1, 56));
for t = 1:numel(tasks)
    m = M.(tasks{t});
    idx = find(m);
    fid = fopen(fullfile(o.out_dir, [tasks{t} '.csv']), 'w');
    fprintf(fid, ['spacecraft,sequence,frame_id,split,range_m,bbox_max_px,' ...
                  'truncated,in_eclipse,solar_phase_angle_deg,n_components\n']);
    for i = idx'
        fprintf(fid, '%s,%s,%d,%s,%.2f,%d,%d,%d,%.2f,%d\n', ...
            rows(i).sc, rows(i).seq, rows(i).frame, split_col{i}, ...
            rows(i).range, round(rows(i).bbox), rows(i).trunc, ...
            rows(i).ecl, rows(i).phase, rows(i).ncomp);
    end
    fclose(fid);
    ntr = nnz(m & strcmp(split_col,'train'));
    nva = nnz(m & strcmp(split_col,'val'));
    nte = nnz(m & strcmp(split_col,'test'));
    S.counts.(tasks{t}) = struct('total', nnz(m), 'train', ntr, 'val', nva, 'test', nte);
    fprintf('%-14s %8d %6.1f%%   %d / %d / %d\n', tasks{t}, nnz(m), ...
        100*nnz(m)/numel(rows), ntr, nva, nte);
end

fid = fopen(fullfile(o.out_dir, 'splits_summary.json'), 'w');
fprintf(fid, '%s', jsonencode(S, 'PrettyPrint', true));
fclose(fid);
fprintf('\nWrote %d index files to %s\n', numel(tasks)+1, o.out_dir);

end


function o = local_defaults(opts, dataset_root)
o.min_px_pose       = 50;
o.min_px_seg        = 100;
o.min_px_comp       = 200;
o.min_px_per_comp   = 20;
o.min_components    = 2;
o.split_fractions   = [0.70 0.15 0.15];
o.split_seed        = 42;
o.out_dir           = fullfile(dataset_root, 'splits');
f = fieldnames(opts);
for k = 1:numel(f); o.(f{k}) = opts.(f{k}); end
end
