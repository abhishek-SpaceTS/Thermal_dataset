function [ra_deg, dec_deg, roll_deg] = star_camera_from_eci(R_eci_to_thermal)
% Derive star-tracker RA/DEC/roll from this pipeline's

z_cam_in_eci = R_eci_to_thermal' * [0; 0; 1];
x_cam_in_eci = R_eci_to_thermal' * [1; 0; 0];

ra_deg  = mod(atan2d(z_cam_in_eci(2), z_cam_in_eci(1)), 360.0);
dec_deg = asind(max(-1, min(1, z_cam_in_eci(3))));

R0  = star_boresight_rotation(ra_deg, dec_deg, 0.0);
Xc0 = R0(1, :)';
Yc0 = R0(2, :)';

roll_deg = atan2d(-dot(x_cam_in_eci, Yc0), dot(x_cam_in_eci, Xc0));

end
