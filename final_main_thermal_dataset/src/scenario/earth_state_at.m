function es = earth_state_at(e, t_sec)
% Evaluate the authored Earth state at one frame time.

es = e;

if isfield(e, 'geocentric_pos_eci') && e.motion_enabled && t_sec ~= 0
    p0 = e.geocentric_pos_eci(:);
    [w1, w2] = perpendicular_basis(p0 / norm(p0));
    psi = deg2rad(e.orbit_normal_psi_deg);
    nrm = w1 * cos(psi) + w2 * sin(psi);
    a   = e.orbital_rate_rad_s * t_sec;
    es.geocentric_pos_eci = p0 * cos(a) + cross(nrm, p0) * sin(a);
end

if isfield(e, 'epoch_utc')
    es.epoch_utc = e.epoch_utc + seconds(t_sec);
end

