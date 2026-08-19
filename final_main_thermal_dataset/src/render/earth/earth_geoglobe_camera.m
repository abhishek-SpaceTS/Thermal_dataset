function cam = earth_geoglobe_camera(deputy_pos_eci, R_eci_to_thermal, epoch_utc)
% GeoGlobe camera parameters from the thermal camera state.

p_eci = deputy_pos_eci(:);
if numel(p_eci) ~= 3
    error('earth_geoglobe_camera:badPosition', ...
          'deputy_pos_eci must have 3 elements, got %d.', numel(p_eci));
end

r = norm(p_eci);
if r < 1e6
    error('earth_geoglobe_camera:notGeocentric', ...
          ['deputy_pos_eci has magnitude %.1f m, which is not a geocentric\n' ...
           'position. The thermal pipeline uses a camera-anchored ECI whose\n' ...
           'origin is the spacecraft; the scenario layer must author a true\n' ...
           'geocentric state before calling the GeoGlobe renderer.'], r);
end

validateattributes(R_eci_to_thermal, {'numeric'}, {'size',[3 3],'real','finite'}, ...
                   mfilename, 'R_eci_to_thermal');

if ~isa(epoch_utc, 'datetime')
    epoch_utc = datetime(epoch_utc(1), epoch_utc(2), epoch_utc(3), ...
                         epoch_utc(4), epoch_utc(5), epoch_utc(6));
end

p_ecef = eci2ecef(epoch_utc, p_eci.');
wgs84  = wgs84Ellipsoid('meter');
[lat, lon, alt] = ecef2geodetic(wgs84, p_ecef(1), p_ecef(2), p_ecef(3));

Reci2ecef = dcmeci2ecef('IAU-2000/2006', ...
                        [year(epoch_utc) month(epoch_utc) day(epoch_utc) ...
                         hour(epoch_utc) minute(epoch_utc) second(epoch_utc)]);

b_eci = R_eci_to_thermal.' * [0; 0; 1];
x_eci = R_eci_to_thermal.' * [1; 0; 0];

b = Reci2ecef * b_eci;  b = b / norm(b);
x = Reci2ecef * x_eci;  x = x / norm(x);

sl = sind(lat); cl = cosd(lat);
so = sind(lon); co = cosd(lon);

E = [-so;       co;      0 ];
N = [-sl*co;   -sl*so;   cl];
U = [ cl*co;    cl*so;   sl];

bE = dot(b, E);  bN = dot(b, N);  bU = dot(b, U);

pitch = asind(max(-1, min(1, bU)));
nadir_angle = acosd(max(-1, min(1, dot(b, -U))));

cfg = earth_geoglobe_config();
gimbal_locked = abs(pitch) > cfg.gimbal_guard_deg;

h_ref = cross(U, b);

if norm(h_ref) > 1e-9
    heading = atan2d(bE, bN);

    h = h_ref / norm(h_ref);
    v = cross(b, h);
    roll = atan2d(-dot(x, v), dot(x, h));
else
    heading = 0;
    roll    = atan2d(dot(x, E), dot(x, N));
end

roll = cfg.roll_sign * roll + cfg.roll_offset_deg;
roll = wrap180(roll);

cam.lat_deg        = lat;
cam.lon_deg        = lon;
cam.alt_m          = alt;
cam.heading_deg    = wrap180(heading);
cam.pitch_deg      = pitch;
cam.roll_deg       = roll;
cam.boresight_ecef = b;
cam.right_ecef     = x;
cam.gimbal_locked  = gimbal_locked;
cam.nadir_angle_deg = nadir_angle;
cam.epoch_utc      = epoch_utc;

end

function a = wrap180(a)
a = mod(a + 180, 360) - 180;
end
