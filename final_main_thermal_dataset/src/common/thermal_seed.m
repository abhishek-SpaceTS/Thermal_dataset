function s = thermal_seed(random_seed, spacecraft_name, seq_name)
% Stable seed for one sequence's thermal draw.
%
% Derived from the run seed plus the spacecraft and sequence names, so the
% same sequence always gets the same temperatures no matter what ran before
% it -- unlike the global rng stream, which resume and --overwrite shift.
% An empty cfg.random_seed means "shuffle", so the thermal state shuffles too.
if isempty(random_seed)
    base = randi([0, 2^31-1]);
else
    base = double(random_seed);
end
key = [char(spacecraft_name) '/' char(seq_name)];
h = 5381;
for k = 1:numel(key)
    h = mod(h * 33 + double(key(k)), 4294967296);   % djb2, reduced each step
end
s = mod(base + h, 4294967296);
end


