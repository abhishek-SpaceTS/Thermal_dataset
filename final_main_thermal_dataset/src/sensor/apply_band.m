function config = apply_band(config, RUN)
% Set the infrared band (LWIR / MWIR) on the thermal camera.

if nargin < 2 || ~isfield(RUN,'sensor') || ~isfield(RUN.sensor,'band') || ...
        isempty(RUN.sensor.band)
    return;
end

band = upper(strtrim(char(RUN.sensor.band)));

switch band
    case 'LWIR'
        config.thermal.wavelength_range  = [8e-6, 14e-6];
        config.thermal.wavelength_center = 10e-6;
        netd_default = 0.050;
    case 'MWIR'
        config.thermal.wavelength_range  = [3e-6, 5e-6];
        config.thermal.wavelength_center = 4e-6;
        netd_default = 0.020;
    otherwise
        error('apply_band:unknownBand', ...
              'Unknown sensor band "%s". Use "LWIR" or "MWIR".', band);
end

if isfield(RUN.sensor,'netd_K') && ~isempty(RUN.sensor.netd_K)
    config.thermal.netd = RUN.sensor.netd_K;
else
    config.thermal.netd = netd_default;
end

config.thermal.band = band;

fprintf('Sensor band: %s (%.1f-%.1f um, centre %.1f um), NETD %.0f mK\n', ...
    band, config.thermal.wavelength_range(1)*1e6, ...
    config.thermal.wavelength_range(2)*1e6, ...
    config.thermal.wavelength_center*1e6, config.thermal.netd*1e3);

end
