function [positions, velocities] = fit_to_frame(positions, velocities, config)
%FIT_TO_FRAME  Shrink a path's transverse extent until every frame is framed.
%
%   [positions, velocities] = fit_to_frame(positions, velocities, config)
%
%   Applied at the end of the kinematic trajectory models. It finds the worst
%   framing violation over the whole path and scales the transverse (x, y)
%   components of every sample by one constant factor so that violation
%   disappears.
%
%   One factor for the whole path, not a per-sample clamp: a clamp would put
%   a kink in the motion wherever it bit, and the target would appear to stick
%   to the frame edge. A uniform scale keeps the shape of the trajectory --
%   straight stays straight, an arc keeps its curvature ratio -- and only
%   reduces how far off-axis it swings.
%
%   z is never touched, so the range profile and therefore the distance
%   bracket are exactly preserved.
%
%   This is a guarantee, not the primary mechanism: the models already size
%   their offsets from framing_limits. It catches the case where a curvature
%   bulge is added on top of an offset that was already at the limit, which is
%   how flyby used to put ~1 % of its frames outside the field.

n = size(positions, 2);
if n == 0
    return;
end

worst = 1.0;
for i = 1:n
    z = positions(3, i);
    if z <= 0
        continue;
    end
    [lim_x, lim_y] = framing_limits(config, z);

    if lim_x > 0
        rx = abs(positions(1, i) / z) / lim_x;
        if rx > worst; worst = rx; end
    end
    if lim_y > 0
        ry = abs(positions(2, i) / z) / lim_y;
        if ry > worst; worst = ry; end
    end
end

if worst > 1.0
    s = 1.0 / worst;
    positions(1:2, :)  = positions(1:2, :)  * s;
    velocities(1:2, :) = velocities(1:2, :) * s;
end

end
