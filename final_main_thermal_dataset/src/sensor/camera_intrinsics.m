function thermal = camera_intrinsics(cfg)
%CAMERA_INTRINSICS Thermal camera geometry, derived from config.m.
%
%   thermal = camera_intrinsics(cfg)
%
%   Replaces load_base_config, which read Phase_0_Scenario/config_ProximityOps.mat
%   and returned twelve structs of which the generator used one. Of that one,
%   only four values were never overwritten downstream: resolution, focal
%   length, pixel pitch and bit depth. They now live in config.m and this
%   function derives the rest.
%
%   Field of view is DERIVED, never configured. It is a consequence of the
%   detector and the lens:
%
%       fov = 2 * atand(resolution * pixel_pitch / 2 / focal_length)
%
%   Configuring it separately would let it disagree with the optics, which is
%   exactly what the old debug FOV override did.
%
%   The band-dependent fields (wavelength range and centre, NETD) are NOT set
%   here; apply_band fills them from cfg.sensor.band.

c = cfg.camera;

thermal.resolution   = c.resolution_px;
thermal.focal_length = c.focal_length_m;
thermal.pixel_pitch  = c.pixel_pitch_m;
thermal.bit_depth    = c.bit_depth;
thermal.psf_sigma    = c.psf_sigma_px;

% Field of view from the detector dimensions. BOTH axes are published: a
% non-square detector has two different fields, and the trajectory models used
% to bound the vertical axis with the horizontal number, which let targets
% render off the top and bottom of the frame. See framing_limits.m.
%
%   1280 x 1024, 15 um, 500 mm  ->  2.200 deg horizontal, 1.760 deg vertical
%
% thermal.fov / thermal.fov_deg stay HORIZONTAL, which is what every existing
% caller means by "the FOV".
width_px  = c.resolution_px(1);
height_px = c.resolution_px(2);
thermal.fov_deg   = 2 * atand(width_px  * c.pixel_pitch_m / (2 * c.focal_length_m));
thermal.fov_v_deg = 2 * atand(height_px * c.pixel_pitch_m / (2 * c.focal_length_m));
thermal.fov_h_deg = thermal.fov_deg;
thermal.fov       = deg2rad(thermal.fov_deg);
thermal.fov_h     = thermal.fov;
thermal.fov_v     = deg2rad(thermal.fov_v_deg);

% Camera mounting, kept as separate fields because project_to_camera builds a
% rotation per axis.
thermal.mount_roll_deg  = c.mount_rpy_deg(1);
thermal.mount_pitch_deg = c.mount_rpy_deg(2);
thermal.mount_yaw_deg   = c.mount_rpy_deg(3);

end
