function config = apply_star_settings(config, RUN)
% Push config star brightness settings into config.

if nargin < 2 || ~isfield(RUN,'stars')
    return;
end
S = RUN.stars;

if isfield(S,'temp_range') && ~isempty(S.temp_range)
    config.thermal.star_temp_range = S.temp_range;
end

if ~isfield(config.thermal,'star_config') || ~isstruct(config.thermal.star_config)
    config.thermal.star_config = struct();
end

if isfield(S,'mag_limit') && ~isempty(S.mag_limit)
    config.thermal.star_config.mag_limit = S.mag_limit;
end
if isfield(S,'peak_temp_mag0') && ~isempty(S.peak_temp_mag0)
    config.thermal.star_config.peak_temp_mag0 = S.peak_temp_mag0;
end
if isfield(S,'psf_sigma_px') && ~isempty(S.psf_sigma_px)
    config.thermal.star_config.psf_sigma_px = S.psf_sigma_px;
end

map = { 'proper_motion_enabled', 'enable_proper_motion'
        'parallax_enabled',      'enable_parallax'
        'jitter_enabled',        'apply_jitter'
        'variability_enabled',   'apply_variability'
        'epoch_year',            'epoch_year'
        'epoch_day_of_year',     'epoch_day_of_year' };
for k = 1:size(map,1)
    if isfield(S, map{k,1}) && ~isempty(S.(map{k,1}))
        config.thermal.star_config.(map{k,2}) = S.(map{k,1});
    end
end

d = star_default_config();
sr = config.thermal.star_temp_range;
p0 = local_or(config.thermal.star_config, 'peak_temp_mag0', d.peak_temp_mag0);
ml = local_or(config.thermal.star_config, 'mag_limit',      d.mag_limit);
fprintf('Stars: mag limit %.1f, mag-0 peak %.0f K, mapped into [%g %g] K\n', ...
        ml, p0, sr(1), sr(2));

end

function v = local_or(s, f, dflt)
if isfield(s,f) && ~isempty(s.(f)); v = s.(f); else; v = dflt; end
end
