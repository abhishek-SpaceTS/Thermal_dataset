function [lim_x, lim_y] = framing_limits(config, range_m)
%FRAMING_LIMITS  Largest |x|/z and |y|/z that keep the target inside the frame.
%
%   [lim_x, lim_y] = framing_limits(config, range_m)
%
%   Returns TANGENT ratios, so a target at camera-frame position [x;y;z] is
%   framed when abs(x/z) <= lim_x and abs(y/z) <= lim_y.
%
%   Why this exists
%   ---------------
%   Every trajectory model used to bound BOTH transverse axes with
%   config.thermal.fov -- which is the HORIZONTAL field, derived from
%   resolution_px(1). That was harmless while the detector was square
%   (1024 x 1024, both fields 6.01 deg) and became a real defect at
%   1280 x 1024, where the fields are 2.200 deg horizontal against 1.760 deg
%   vertical. The vertical bound was then 25 % too loose, so a target sitting
%   near the top or bottom of its allowed box rendered completely off-frame:
%   a sequence with a valid pose, range and bounding box in labels.csv but an
%   empty mask and no target pixels. inspection_orbit was worst hit, because
%   it puts the target on a circle of radius d*tan(fov_h/2) and therefore
%   crosses the vertical limit twice per revolution -- 45 % of its frames.
%
%   Two things are reserved out of the half-field:
%
%     * the target's own angular radius, so the BODY is inside the frame and
%       not merely its centroid. A fixed fractional margin cannot do this:
%       at 12 km M4V spans a few pixels, at 100 m it spans a third of the
%       frame, so the reservation has to scale as radius/range.
%
%     * a few pixels of edge margin, which keeps the PSF skirt and the
%       bounding box off the border.
%
%   Set cfg.framing.keep_target_fully_inside = false to reserve only the edge
%   margin and allow targets to be truncated by the frame edge. Truncated
%   targets are realistic training data; zero-pixel targets are not, and that
%   case stays excluded either way.

if nargin < 2 || isempty(range_m)
    error('framing_limits:noRange', 'range_m is required.');
end

% Half-field tangents, per axis. fov_h/fov_v come from camera_intrinsics;
% fall back to the legacy single fov so an older config still runs.
if isfield(config.thermal, 'fov_h') && isfield(config.thermal, 'fov_v')
    t_x = tan(config.thermal.fov_h / 2);
    t_y = tan(config.thermal.fov_v / 2);
else
    t_x = tan(config.thermal.fov / 2);
    t_y = t_x;
end

keep_inside = true;
margin_px   = 4;

% Settings from config.m arrive as config.run.framing: generate_spacecraft_dataset
% builds its own config (thermal, target, distance_scenarios) and attaches the
% whole of config.m under .run, which is how every other group is reached --
% config.run.earth, config.run.sensor, config.run.motion.
%
% This used to read config.framing only. That field is never set on the
% pipeline's config, so both knobs below silently fell back to the defaults
% here and NOTHING in config.m could change them. The defaults happened to
% match the shipped values, so the rendered output was correct and the dead
% setting left no trace. config.framing is still accepted second, for callers
% that build a config by hand.
F = struct();
if isfield(config, 'run') && isfield(config.run, 'framing')
    F = config.run.framing;
elseif isfield(config, 'framing')
    F = config.framing;
end

if isfield(F, 'keep_target_fully_inside') && ~isempty(F.keep_target_fully_inside)
    keep_inside = logical(F.keep_target_fully_inside);
end
if isfield(F, 'edge_margin_px') && ~isempty(F.edge_margin_px)
    margin_px = F.edge_margin_px;
end

% Edge margin expressed as an angle: margin_px * pixel_pitch / focal_length.
t_margin = 0;
if isfield(config.thermal, 'pixel_pitch') && isfield(config.thermal, 'focal_length') && ...
        config.thermal.focal_length > 0
    t_margin = margin_px * config.thermal.pixel_pitch / config.thermal.focal_length;
end

% The target's angular radius at this range. tan(theta) ~= r/z to well under
% a pixel at every bracket, and the circumscribing radius is conservative.
t_target = 0;
if keep_inside && isfield(config, 'target') && ...
        isfield(config.target, 'bounding_radius_m') && ~isempty(config.target.bounding_radius_m)
    t_target = config.target.bounding_radius_m / max(range_m, eps);
end

reserve = t_target + t_margin;
lim_x = t_x - reserve;
lim_y = t_y - reserve;

% A target larger than the frame cannot be fully contained -- at 100 m a 6 m
% spacecraft nearly fills it. Centre it rather than returning a negative
% limit, and let it be truncated, which is the only physical option.
lim_x = max(lim_x, 0);
lim_y = max(lim_y, 0);

end
