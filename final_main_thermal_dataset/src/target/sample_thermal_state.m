function state = sample_thermal_state(seed)
%SAMPLE_THERMAL_STATE Draw one thermal state from the database ranges.
%
%   state = sample_thermal_state(seed)
%   state = sample_thermal_state()      % midpoints, fully deterministic
%
%   thermal_database.m stores base / sunlit / eclipse as [lo hi]
%   intervals. This function collapses each interval to a single value, and
%   the result is what every frame of one sequence uses.
%
%   WHY ONCE PER SEQUENCE, NOT PER FRAME
%     Drawing per frame would make a component's temperature jump between
%     consecutive frames of the same pass -- physically wrong (a 5 kg bus
%     cannot change 4 K in 100 ms) and visible as flicker in the rendered
%     video. Drawing once per spacecraft would make every sequence identical
%     and throw away the variability the ranges exist to express. Once per
%     sequence is the level at which the spread is real: two passes differ by
%     beta angle, season, duty cycle and how long the vehicle has been in
%     sunlight, and those are constant within a pass.
%
%   REPRODUCIBILITY
%     The draw uses its own RandStream keyed on `seed`, so it neither consumes
%     nor perturbs the global rng stream that scenario generation uses. The
%     same seed always yields the same state, independent of how many
%     sequences ran before it or whether resume skipped any -- which the
%     global stream cannot promise.
%
%     Call with no argument (or []) for the midpoint of every range. That is
%     the deterministic default used when compute_temperatures is
%     invoked standalone, outside the dataset pipeline.
%
%   INPUT
%     seed   non-negative integer, or [] / omitted for midpoints. The dataset
%            pipeline passes a value derived from cfg.random_seed, the
%            spacecraft name and the sequence index.
%
%   OUTPUT
%     state  struct of Nx1 column vectors indexed by material_id (1 = Bus):
%              .base_K .sunlit_K .eclipse_K   the drawn scalars
%              .variation_K                   copied through unchanged
%              .seed                          what produced this draw
%              .name                          class names, for reporting
%
%   See also THERMAL_COMPONENT_DATABASE, COMPUTE_MODEL_TEMPERATURES.

if nargin < 1
    seed = [];
end

[~, lut] = thermal_database();

if isempty(seed)
    u = 0.5 * ones(size(lut.base_K, 1), 3);   % midpoint of every range
else
    % threefry is a counter-based generator: cheap to create per sequence and
    % well separated for nearby seeds, unlike seeding mt19937ar with 1,2,3...
    rs = RandStream('threefry', 'Seed', mod(double(seed), 2^32));
    u = rand(rs, size(lut.base_K, 1), 3);
end

state.base_K      = lerp(lut.base_K,    u(:,1));
state.sunlit_K    = lerp(lut.sunlit_K,  u(:,2));
state.eclipse_K   = lerp(lut.eclipse_K, u(:,3));
state.variation_K = lut.variation_K;
state.name        = lut.name;
state.seed        = seed;

end


function v = lerp(range_nx2, u)
% Linear interpolation between the lo and hi column at fraction u.
v = range_nx2(:,1) + (range_nx2(:,2) - range_nx2(:,1)) .* u(:);
end
