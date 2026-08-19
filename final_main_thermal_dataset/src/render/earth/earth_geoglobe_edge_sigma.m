function sigma = earth_geoglobe_edge_sigma(config, gg_info)
% Smoothing scale for the GeoGlobe Earth layer, px.

sigma = [];
if isfield(config,'run') && isfield(config.run,'earth') && ...
        isfield(config.run.earth,'edge_softness_px')
    sigma = config.run.earth.edge_softness_px;
end

if isempty(sigma)
    up = 1;
    if isstruct(gg_info) && isfield(gg_info,'upsample') && ~isempty(gg_info.upsample)
        up = gg_info.upsample;
    end
    sigma = max(0, up / 2);
end

sigma = max(0, sigma);

end
