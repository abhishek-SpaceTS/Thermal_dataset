function T_app = apparent_temperature(T_kin, emissivity, T_surroundings, wavelength_m, wavelength_range)
%APPARENT_TEMPERATURE Kinetic temperature -> what a thermal camera reports.
%
%   T_app = apparent_temperature(T_kin, emissivity, T_surroundings, wavelength_m)
%
%   A thermal camera does not measure temperature. It measures RADIANCE and
%   inverts it assuming the surface is a perfect emitter. A real surface emits
%   only a fraction eps of blackbody radiance and reflects the rest of its
%   surroundings, so the camera reports
%
%       L_meas = eps * L_bb(T_kin) + (1 - eps) * L_bb(T_surroundings)
%       T_app  = L_bb^-1( L_meas )
%
%   Evaluated at the sensor's BAND CENTRE using the Planck law, because the
%   detector is band-limited (8-14 um for LWIR) rather than a total-power
%   instrument. Using Stefan-Boltzmann instead would be wrong by ~44 K at
%   eps = 0.05, so the distinction matters for MLI.
%
%   The constants that multiply Planck's law cancel in the inversion, so only
%   the shape term is needed:
%
%       L(T) = 1 / (exp(c2 / (lambda*T)) - 1)
%       T_app = (c2/lambda) / ln(1 + 1/L_meas)
%
%   WHY THIS EXISTS
%     Low-emissivity surfaces behave like mirrors in the thermal infrared. A
%     gold MLI blanket at 290 K with eps = 0.05 reports about 181 K, not 290,
%     because 95% of what the camera sees is reflected deep space. This is why
%     real spacecraft show their blankets as dark patches, and why a rendered
%     image built from kinetic temperature alone gets the brightness ordering
%     of its own components wrong.
%
%   INPUTS
%     T_kin           kinetic (true) surface temperature, K. Any array shape.
%     emissivity      per-element emissivity in (0, 1]. Scalar or same size.
%     T_surroundings  temperature of whatever the surface reflects, K. In orbit
%                     this is deep space unless Earth fills the view; see the
%                     caveat below.
%     wavelength_m    band centre in metres, e.g. 10e-6 for LWIR.
%
%   OUTPUT
%     T_app           apparent (brightness) temperature, K, same size as T_kin.
%                     Equals T_kin exactly when emissivity is 1.
%
%   CAVEAT ON T_surroundings
%     Using deep space is the COLD LIMIT: it assumes every reflective surface
%     sees only sky. A real blanket facing Earth reflects a ~255 K disc and
%     reads much warmer, so real MLI is strongly view-dependent. Modelling that
%     properly needs per-face view factors, which this does not attempt.
%     cfg.sensor.surroundings_K raises the value if the cold limit is too
%     extreme for your scene.
%
%   See also THERMAL_COMPONENT_DATABASE, COMPUTE_MODEL_TEMPERATURES.

c2 = 1.4387768775e-2;                       % second radiation constant, m*K

if nargin < 4 || isempty(wavelength_m)
    error('apparent_temperature:noWavelength', ...
        'Band centre wavelength is required; it must come from the sensor config.');
end
if any(emissivity(:) <= 0) || any(emissivity(:) > 1)
    error('apparent_temperature:badEmissivity', ...
        'Emissivity must be in (0, 1]; got %g to %g.', ...
        min(emissivity(:)), max(emissivity(:)));
end

% BAND-INTEGRATED when a wavelength range is supplied, band-centre otherwise.
%
% A real LWIR detector integrates 8-14 um, and Planck varies about 40 % across
% that span at 300 K. For a perfect emitter both routes give apparent = kinetic,
% so the choice only matters where emissivity is low and a hot surface is mixed
% with a cold environment -- which is MLI, the material this dataset most needs
% right. Band centre is kept so datasets generated before this can be
% reproduced exactly; see cfg.sensor.planck_mode.
if nargin >= 5 && ~isempty(wavelength_range)
    L_surf = planck_band('L', T_kin,          wavelength_range);
    L_env  = planck_band('L', T_surroundings, wavelength_range);
    L_meas = emissivity .* L_surf + (1 - emissivity) .* L_env;
    T_app  = planck_band('T', max(L_meas, realmin), wavelength_range);
    T_app  = reshape(T_app, size(emissivity .* T_kin));
    return;
end

k = c2 / wavelength_m;                      % K, so L(T) = 1/(exp(k/T)-1)

% Planck shape term. exp overflows to Inf for very cold T, which correctly
% gives L = 0: a 2.7 K source radiates nothing at 10 um.
L = @(T) 1 ./ (exp(k ./ T) - 1);

L_meas = emissivity .* L(T_kin) + (1 - emissivity) .* L(T_surroundings);

% Guard the inversion. L_meas can underflow to 0 only if both the surface and
% its surroundings radiate nothing in band, in which case the reported
% temperature is the smallest the encoding can express rather than a divide.
L_meas = max(L_meas, realmin);

T_app = k ./ log(1 + 1 ./ L_meas);

end
