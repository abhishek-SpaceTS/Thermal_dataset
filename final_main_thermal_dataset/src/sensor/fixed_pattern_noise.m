function fpn = fixed_pattern_noise(img_size, seed, cfg)
%FIXED_PATTERN_NOISE  Detector non-uniformity pattern, fixed for a sequence.
%
%   fpn = fixed_pattern_noise([h w], seed, cfg)
%
%   Returns a struct applied as
%
%       img = fpn.nuc_ref_K + (img - fpn.nuc_ref_K) .* fpn.gain + fpn.offset;
%       img(fpn.dead) = fpn.dead_value(fpn.dead);
%
%   GAIN IS REFERENCED, NOT ABSOLUTE. A two-point non-uniformity correction is
%   exact at its calibration temperatures and degrades with distance from them,
%   so gain error acts on the signal RELATIVE to that reference. Multiplying
%   absolute Kelvin instead makes a 0.5 % gain error worth 650 mK in 130 K sky
%   -- larger than every other sensor effect combined, which is what an earlier
%   draft did and what the blank-sky sigma exposed.
%
%   WHY THIS MATTERS MORE THAN NETD
%   -------------------------------
%   NETD is temporal: it is redrawn every frame, so it averages away over a
%   track and a network learns to ignore it. Fixed-pattern noise does not move.
%   The same stripes sit on every frame a detector ever takes, they are
%   spatially structured, and at small target sizes they look like edges. A
%   model trained on clean synthetic imagery learns to trust pixel-level
%   structure that a real microbolometer does not deliver, and that is the
%   first thing to break on real data.
%
%   FOUR COMPONENTS, all of which a real uncooled microbolometer shows after
%   non-uniformity correction:
%
%     column offset   the dominant term. Each detector column runs through its
%                     own ROIC amplifier, so residual offsets appear as
%                     vertical striping.
%     row offset      the same effect on row select, weaker.
%     pixel offset    residual DSNU -- per-pixel offset the NUC did not remove.
%     gain            multiplicative, so striping grows with scene level. This
%                     is why FPN is more visible against Earth than against sky.
%     dead pixels     a small fraction stuck at a fixed value regardless of
%                     scene. Real arrays ship with them.
%
%   THE PATTERN IS FIXED PER SEQUENCE, NOT PER FRAME. Within a sequence it
%   cannot be averaged out, which is the realistic part. Across sequences it is
%   redrawn, so the dataset teaches invariance to non-uniformity in general
%   rather than to one particular detector. A single physical camera would have
%   one pattern forever; that is the right choice for a deployment and the
%   wrong one for a training set.
%
%   RNG ISOLATION. The pattern is drawn from a dedicated RandStream seeded from
%   the sequence, never the global stream. Drawing from the global stream would
%   shift every trajectory, attitude and Sun sample downstream of it, silently
%   changing scenarios that have nothing to do with the sensor model.

h = img_size(1); w = img_size(2);

p = struct('enabled', true, 'fpn_column_K', 0.075, 'fpn_row_K', 0.025, ...
           'fpn_pixel_K', 0.050, 'fpn_gain_pct', 0.05, 'dead_pixel_frac', 0, 'fpn_nuc_ref_K', 300);
if nargin >= 3 && ~isempty(cfg) && isfield(cfg, 'sensor')
    s = cfg.sensor;
    m = {'fpn_enabled','enabled'; 'fpn_column_K','fpn_column_K'; ...
         'fpn_row_K','fpn_row_K'; 'fpn_pixel_K','fpn_pixel_K'; ...
         'fpn_gain_pct','fpn_gain_pct'; 'dead_pixel_frac','dead_pixel_frac'; ...
         'fpn_nuc_ref_K','fpn_nuc_ref_K'};
    for k = 1:size(m,1)
        if isfield(s, m{k,1}) && ~isempty(s.(m{k,1}))
            p.(m{k,2}) = s.(m{k,1});
        end
    end
end

fpn = struct('offset', zeros(h,w), 'gain', ones(h,w), ...
             'dead', false(h,w), 'dead_value', zeros(h,w), ...
             'enabled', p.enabled, 'seed', seed, ...
             'column_K', p.fpn_column_K, 'row_K', p.fpn_row_K, ...
             'pixel_K', p.fpn_pixel_K, 'gain_pct', p.fpn_gain_pct, ...
             'dead_frac', p.dead_pixel_frac, 'n_dead', 0, 'nuc_ref_K', p.fpn_nuc_ref_K);

if ~p.enabled
    return;
end

st = RandStream('threefry', 'Seed', mod(uint64(seed), 2^31));

col = p.fpn_column_K * randn(st, 1, w);
row = p.fpn_row_K    * randn(st, h, 1);
pix = p.fpn_pixel_K  * randn(st, h, w);
fpn.offset = pix + repmat(col, h, 1) + repmat(row, 1, w);

fpn.gain = 1 + (p.fpn_gain_pct/100) * randn(st, h, w);

if p.dead_pixel_frac > 0
    fpn.dead = rand(st, h, w) < p.dead_pixel_frac;
    % Stuck pixels sit anywhere in the window, not only at the rails: a
    % partially stuck bolometer reports a plausible but scene-independent
    % value, which is harder for a model than an obvious black dot.
    lo = 130; hi = 400;
    if nargin >= 3 && ~isempty(cfg) && isfield(cfg,'sensor')
        if isfield(cfg.sensor,'T_min'); lo = cfg.sensor.T_min; end
        if isfield(cfg.sensor,'T_max'); hi = cfg.sensor.T_max; end
    end
    fpn.dead_value = lo + (hi - lo) * rand(st, h, w);
    fpn.n_dead = nnz(fpn.dead);
end

end
