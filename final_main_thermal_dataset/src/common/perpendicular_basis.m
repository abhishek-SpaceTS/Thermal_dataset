function [u1, u2] = perpendicular_basis(d)
%PERPENDICULAR_BASIS Two unit vectors spanning the plane normal to d.
%
%   [u1, u2] = perpendicular_basis(d)
%
%   Picks the world axis least aligned with d as a seed so the cross products
%   never degenerate. Used to sweep a circle about an arbitrary direction --
%   Earth's orbital motion and the authored Earth placement both need it.
%   Was duplicated as a private subfunction in author_earth and earth_state_at.

d = d(:) / norm(d);
seed = [1; 0; 0];
if abs(d(1)) > 0.9
    seed = [0; 1; 0];
end
u1 = cross(d, seed); u1 = u1 / norm(u1);
u2 = cross(d, u1);   u2 = u2 / norm(u2);
end
