function S = hil_state_at(H, t_query)
%HIL_STATE_AT  Sample a loaded HIL trajectory at arbitrary frame times.
%
%   S = hil_state_at(H, t_query)
%
%   H is from hil_trajectory. t_query is a vector of times in seconds from
%   scenario start. Returns arrays with one row per query time:
%
%       S.t, S.chief_pos, S.chief_quat, S.chief_omega,
%       S.deputy_pos, S.deputy_quat, S.sun_vec, S.separation
%
%   Positions, rates and the Sun vector are linearly interpolated. ATTITUDE
%   IS SLERPED, not lerped: linear interpolation of two quaternions leaves
%   the unit sphere, and renormalising afterwards still sweeps the angle
%   non-uniformly. At the HIL sample rate of 10 Hz the difference is small,
%   but it is not zero, and this function must stay correct if either side
%   changes its frame rate.
%
%   Sign continuity is enforced before interpolating. q and -q are the same
%   rotation, and a propagator can flip between them for free; slerping
%   across a flip takes the long way round and swings the model through a
%   large spurious rotation in one frame.
%
%   Querying outside the trajectory is an error rather than a clamp -- a
%   silently clamped frame would render a stationary target and look like a
%   physically valid still.

t = H.t;
tq = t_query(:);

if any(tq < t(1) - 1e-9) || any(tq > t(end) + 1e-9)
    error('hil_state_at:outOfRange', ...
        ['Requested t = [%.3f, %.3f] s but the HIL trajectory spans ' ...
         '[%.3f, %.3f] s (%d samples at %.3f s). Shorten the sequence, ' ...
         'move the start time, or re-run HIL Phase 1 over a longer span.'], ...
        min(tq), max(tq), t(1), t(end), H.n, H.dt);
end

S.t          = tq;
S.chief_pos  = interp1(t, H.chief_pos,   tq, 'linear');
S.deputy_pos = interp1(t, H.deputy_pos,  tq, 'linear');
S.chief_omega= interp1(t, H.chief_omega, tq, 'linear');
S.separation = interp1(t, H.separation,  tq, 'linear');

sv = interp1(t, H.sun_vec, tq, 'linear');
S.sun_vec = sv ./ vecnorm(sv, 2, 2);

S.chief_quat  = local_slerp_series(t, H.chief_quat,  tq);
S.deputy_quat = local_slerp_series(t, H.deputy_quat, tq);

end


% -----------------------------------------------------------------------------
function Q = local_slerp_series(t, q, tq)
n = numel(tq);
Q = zeros(n, 4);
for k = 1:n
    i = find(t <= tq(k), 1, 'last');
    if isempty(i); i = 1; end
    if i >= numel(t)
        Q(k,:) = q(end,:);
        continue;
    end
    span = t(i+1) - t(i);
    if span <= 0
        Q(k,:) = q(i,:);
        continue;
    end
    Q(k,:) = local_slerp(q(i,:), q(i+1,:), (tq(k) - t(i)) / span);
end
end

function q = local_slerp(q0, q1, u)
% Shortest-arc spherical linear interpolation, scalar-first quaternions.
d = dot(q0, q1);
if d < 0            % q and -q are the same rotation; take the short way
    q1 = -q1;
    d  = -d;
end
if d > 0.9995       % nearly parallel: lerp is numerically safer than slerp
    q = q0 + u * (q1 - q0);
    q = q / norm(q);
    return;
end
th0 = acos(min(1, max(-1, d)));
th  = th0 * u;
q2  = q1 - q0 * d;
q2  = q2 / norm(q2);
q   = q0 * cos(th) + q2 * sin(th);
q   = q / norm(q);
end
