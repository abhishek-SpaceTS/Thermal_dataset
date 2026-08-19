function q = report_quality(dataset_root, verbose)
%REPORT_DATASET_QUALITY Audit a generated spacecraft dataset.
%
%   q = report_quality(dataset_root)
%   q = report_quality(dataset_root, false)     % collect, do not print
%
%   Reads back what was written -- sequence metadata.json and labels.csv --
%   and reports the dataset's own quality figures. Everything here is a
%   MEASUREMENT of existing recorded values; nothing is recomputed from the
%   images and no new physical convention is introduced.
%
%   dataset_root is a per-spacecraft folder, e.g.
%       output/M4V
%
%   Sections
%     DATASET      sequence and frame counts, incomplete sequences
%     EARTH        coverage distribution, requested vs actual scene class
%     SUN          solar phase angle coverage, and whether it is still stuck
%                  on the old {0, 90, 180} set
%     SPACECRAFT   visible, invisible, truncated and bbox-failed frames
%     THERMAL      rendered range and the clipping census against the
%                  configured save window, target separated from background
%                  and PSF-blurred target edges separated from the core
%     STARS        sky-floor statistics
%
%   Returns a struct with the same figures so a caller can assert on them.

if nargin < 2; verbose = true; end

q = struct();
seq_dir = fullfile(dataset_root, 'sequences');
if ~isfolder(seq_dir)
    if verbose; fprintf('report_quality: no sequences at %s\n', seq_dir); end
    q.sequences = 0; return;
end

d = dir(fullfile(seq_dir, 'Sequence*'));
d = d([d.isdir]);

S = struct('name', {}, 'meta', {}, 'labels', {});
incomplete = {};
for k = 1:numel(d)
    mp = fullfile(seq_dir, d(k).name, 'metadata.json');
    lp = fullfile(seq_dir, d(k).name, 'labels.csv');
    if ~isfile(mp) || ~isfile(lp)
        incomplete{end+1} = d(k).name; %#ok<AGROW>
        continue;
    end
    try
        m = jsondecode(fileread(mp));
        L = readmatrix(lp, 'NumHeaderLines', 1);
    catch
        incomplete{end+1} = d(k).name; %#ok<AGROW>
        continue;
    end
    if isempty(L) || size(L,1) < 1
        incomplete{end+1} = d(k).name; %#ok<AGROW>
        continue;
    end
    S(end+1).name = d(k).name; %#ok<AGROW>
    S(end).meta   = m;
    S(end).labels = L;
end

% ---- DATASET ---------------------------------------------------------
q.sequences          = numel(S);
q.sequences_found    = numel(d);
q.incomplete         = incomplete;
q.frames             = 0;
for k = 1:numel(S); q.frames = q.frames + size(S(k).labels, 1); end
q.frames_expected = 0;
for k = 1:numel(S)
    if isfield(S(k).meta,'sequence') && isfield(S(k).meta.sequence,'num_frames')
        q.frames_expected = q.frames_expected + S(k).meta.sequence.num_frames;
    end
end
q.frames_missing = max(0, q.frames_expected - q.frames);

% ---- EARTH -----------------------------------------------------------
cov = []; pct_none = []; pct_limb = []; pct_full = []; mism = {};
for k = 1:numel(S)
    e = get_field(S(k).meta, 'earth', struct());
    if isfield(e, 'earth_coverage')
        cov(end+1,:) = [e.earth_coverage.min, e.earth_coverage.max, e.earth_coverage.mean]; %#ok<AGROW>
    end
    if isfield(e, 'frames_pct')
        pct_none(end+1) = e.frames_pct.no_earth; %#ok<AGROW>
        pct_limb(end+1) = e.frames_pct.limb;     %#ok<AGROW>
        pct_full(end+1) = e.frames_pct.full;     %#ok<AGROW>
    end
    if isfield(e,'scene_class_match') && ~isempty(e.scene_class_match) && ~e.scene_class_match
        mism{end+1} = sprintf('%s: requested "%s", actual "%s" (cov %.3f)', ...
            S(k).name, e.scene_class_requested, e.scene_class_actual, ...
            e.earth_coverage.mean); %#ok<AGROW>
    end
end
q.earth.coverage_min  = local_min(cov(:,1));
q.earth.coverage_max  = local_max(cov(:,2));
q.earth.coverage_mean = local_mean(cov(:,3));
q.earth.pct_no_earth  = local_mean(pct_none(:));
q.earth.pct_limb      = local_mean(pct_limb(:));
q.earth.pct_full      = local_mean(pct_full(:));
q.earth.scene_mismatches = mism;

% ---- SUN -------------------------------------------------------------
ph = [];
for k = 1:numel(S)
    if size(S(k).labels,2) >= 21; ph = [ph; S(k).labels(:,21)]; end %#ok<AGROW>
end
q.sun.n            = numel(ph);
q.sun.phase_min    = local_min(ph);
q.sun.phase_max    = local_max(ph);
q.sun.phase_mean   = local_mean(ph);
q.sun.phase_unique = numel(unique(round(ph,1)));
% The old sampler produced only 0, 90 and 180 deg. Anything more than a
% handful of samples away from those three values proves it is continuous.
if isempty(ph)
    q.sun.only_0_90_180 = NaN;
else
    near = min(abs(ph(:) - [0 90 180]), [], 2);
    q.sun.only_0_90_180 = all(near < 2);
    q.sun.pct_away_from_axes = 100 * mean(near >= 2);
end

% ---- SPACECRAFT ------------------------------------------------------
vis = 0; invis = 0; trunc = 0; bboxfail = 0;
for k = 1:numel(S)
    L = S(k).labels;
    v = L(:,5) > 0 & L(:,6) > 0;
    vis   = vis   + nnz(v);
    invis = invis + nnz(~v);
    if size(L,2) >= 20; trunc = trunc + nnz(L(:,20)); end
    if isfield(S(k).meta,'summary') && isfield(S(k).meta.summary,'frames_bbox_failed')
        bboxfail = bboxfail + S(k).meta.summary.frames_bbox_failed;
    end
end
q.spacecraft.visible_frames   = vis;
q.spacecraft.invisible_frames = invis;
q.spacecraft.truncated_frames = trunc;
q.spacecraft.bbox_failures    = bboxfail;

% ---- THERMAL ---------------------------------------------------------
w = []; sT = []; bgb = 0; bga = 0; tb = 0; ta = 0; cb = 0;
nbg = 0; ntg = 0; ncore = 0;
for k = 1:numel(S)
    if ~isfield(S(k).meta,'summary') || ~isfield(S(k).meta.summary,'clipping'); continue; end
    c = S(k).meta.summary.clipping;
    w  = c.window_K(:)';
    sT(end+1,:) = [c.scene_T_min, c.scene_T_max]; %#ok<AGROW>
    bgb = bgb + c.background.pixels_below_T_min;
    bga = bga + c.background.pixels_above_T_max;
    tb  = tb  + c.target.pixels_below_T_min;
    ta  = ta  + c.target.pixels_above_T_max;
    cb  = cb  + c.target_core.pixels_below_T_min;
    % recover pixel totals from the recorded percentages
    if c.background.percentage_below > 0
        nbg = nbg + 100*c.background.pixels_below_T_min/c.background.percentage_below;
    end
    if c.target.percentage_below > 0
        ntg = ntg + 100*c.target.pixels_below_T_min/c.target.percentage_below;
    end
    if c.target_core.percentage_below > 0
        ncore = ncore + 100*c.target_core.pixels_below_T_min/c.target_core.percentage_below;
    end
end
q.thermal.window_K   = w;
q.thermal.rendered_min = local_min(sT(:,1));
q.thermal.rendered_max = local_max(sT(:,2));
q.thermal.background.pixels_below_T_min = bgb;
q.thermal.background.pixels_above_T_max = bga;
q.thermal.target.pixels_below_T_min     = tb;
q.thermal.target.pixels_above_T_max     = ta;
q.thermal.target_core.pixels_below_T_min = cb;
q.thermal.target.percentage_below      = local_pct(tb, ntg);
q.thermal.target.percentage_above      = local_pct(ta, ntg);
q.thermal.target_core.percentage_below = local_pct(cb, ncore);
q.thermal.background.percentage_below  = local_pct(bgb, nbg);

% ---- STARS -----------------------------------------------------------
% The sky floor is star_range(1) == T_min; anything above it in a background
% pixel is star flux. Reported from the recorded scene minimum rather than
% re-reading images.
q.stars.sky_floor_K = NaN;
if ~isempty(w); q.stars.sky_floor_K = w(1); end
q.stars.background_pixels_below_floor = bgb;

if verbose; local_print(q); end
end


function local_print(q)
fprintf('\n=================================================\n');
fprintf('DATASET QUALITY REPORT\n');
fprintf('=================================================\n');

fprintf('\nDATASET\n');
fprintf('  sequences            : %d (of %d folders)\n', q.sequences, q.sequences_found);
fprintf('  frames               : %d (expected %d)\n', q.frames, q.frames_expected);
fprintf('  missing frames       : %d\n', q.frames_missing);
fprintf('  incomplete sequences : %d', numel(q.incomplete));
if ~isempty(q.incomplete); fprintf('  [%s]', strjoin(q.incomplete, ', ')); end
fprintf('\n');

fprintf('\nEARTH\n');
fprintf('  no-Earth frames      : %.1f %%\n', q.earth.pct_no_earth);
fprintf('  limb frames          : %.1f %%\n', q.earth.pct_limb);
fprintf('  full-Earth frames    : %.1f %%\n', q.earth.pct_full);
fprintf('  coverage min/max/mean: %.3f / %.3f / %.3f\n', ...
    q.earth.coverage_min, q.earth.coverage_max, q.earth.coverage_mean);
fprintf('  scene class mismatch : %d\n', numel(q.earth.scene_mismatches));
for k = 1:numel(q.earth.scene_mismatches)
    fprintf('      %s\n', q.earth.scene_mismatches{k});
end

fprintf('\nSUN\n');
fprintf('  phase min/max/mean   : %.1f / %.1f / %.1f deg\n', ...
    q.sun.phase_min, q.sun.phase_max, q.sun.phase_mean);
fprintf('  unique phase values  : %d of %d frames\n', q.sun.phase_unique, q.sun.n);
if islogical(q.sun.only_0_90_180)
    if q.sun.only_0_90_180
        fprintf('  RESTRICTED to 0/90/180 : YES  <-- continuous sampling is NOT active\n');
    else
        fprintf('  RESTRICTED to 0/90/180 : no (%.0f%% of frames are >2 deg away)\n', ...
            q.sun.pct_away_from_axes);
    end
end

fprintf('\nSPACECRAFT\n');
fprintf('  visible frames       : %d\n', q.spacecraft.visible_frames);
fprintf('  invisible frames     : %d\n', q.spacecraft.invisible_frames);
fprintf('  truncated (clipped)  : %d\n', q.spacecraft.truncated_frames);
fprintf('  bbox failures        : %d\n', q.spacecraft.bbox_failures);

fprintf('\nTHERMAL\n');
if ~isempty(q.thermal.window_K)
    fprintf('  configured window    : %g - %g K\n', q.thermal.window_K(1), q.thermal.window_K(2));
end
fprintf('  rendered min/max     : %.1f / %.1f K\n', q.thermal.rendered_min, q.thermal.rendered_max);
fprintf('  background below Tmin: %d px (%.2f %%)\n', ...
    q.thermal.background.pixels_below_T_min, q.thermal.background.percentage_below);
fprintf('  background above Tmax: %d px\n', q.thermal.background.pixels_above_T_max);
fprintf('    NOT scene loss: blank sky sits AT T_min by design, so detector\n');
fprintf('    noise puts about half the sky pixels below it and they clamp to\n');
fprintf('    DN 0 -- which is what a black background means. The figures that\n');
fprintf('    matter are the target rows below.\n');
fprintf('  target below Tmin    : %d px (%.2f %%)  <- includes PSF-blurred edges\n', ...
    q.thermal.target.pixels_below_T_min, q.thermal.target.percentage_below);
fprintf('  target CORE below    : %d px (%.2f %%)  <- mask eroded 2 px, PSF excluded\n', ...
    q.thermal.target_core.pixels_below_T_min, q.thermal.target_core.percentage_below);
fprintf('  target above Tmax    : %d px (%.2f %%)\n', ...
    q.thermal.target.pixels_above_T_max, q.thermal.target.percentage_above);

fprintf('\nSTARS\n');
fprintf('  sky floor            : %g K (background maps to DN 0 here)\n', q.stars.sky_floor_K);
fprintf('  background below floor: %d px\n', q.stars.background_pixels_below_floor);
fprintf('\n=================================================\n');
end
function v = local_min(x);  if isempty(x); v = NaN; else; v = min(x(:));  end; end
function v = local_max(x);  if isempty(x); v = NaN; else; v = max(x(:));  end; end
function v = local_mean(x); if isempty(x); v = NaN; else; v = mean(x(:)); end; end
function v = local_pct(n, tot); if tot <= 0; v = 0; else; v = 100*n/tot; end; end
