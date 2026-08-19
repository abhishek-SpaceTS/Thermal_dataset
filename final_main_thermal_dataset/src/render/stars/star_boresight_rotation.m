function R = star_boresight_rotation(ra_deg, dec_deg, roll_deg)
% Rotation matrix from J2000 into the camera frame.

ra   = deg2rad(ra_deg);
dec  = deg2rad(dec_deg);
roll = deg2rad(roll_deg);

Zc = [cos(dec)*cos(ra); cos(dec)*sin(ra); sin(dec)];
Xc = [-sin(ra); cos(ra); 0];
Yc = cross(Zc, Xc);
Yc = Yc / norm(Yc);

cr = cos(roll); sr = sin(roll);
Xc_r = cr*Xc - sr*Yc;
Yc_r = sr*Xc + cr*Yc;

R = [Xc_r'; Yc_r'; Zc'];

end
