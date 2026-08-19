function H = hil_trajectory(hil_dir)
%HIL_TRAJECTORY  Load Phase 1 truth from the ProximityOps HIL simulator.
%
%   H = hil_trajectory(hil_dir)
%
%   hil_dir is the Phase_1_Truth folder written by run_phase1_all.m, e.g.
%   'C:\ProximityOps_HIL\Phase_1_Truth'. Three files are required:
%
%       chief_trajectory.mat    struct 'trajectory'
%                               t, position, velocity, quaternion, ang_velocity
%       deputy_trajectory.mat   struct 'deputy_trajectory'
%                               t, position_eci, velocity_eci, position_rtn,
%                               velocity_rtn, separation, quaternion, ang_velocity
%       sun_vector.mat          struct 'sun_ephemeris'
%                               t, sun_vec, solar_constant
%
%   Returns H with the columns this generator needs, all on one time base:
%
%       H.t             [N x 1]  seconds from scenario start
%       H.chief_pos     [N x 3]  ECI position of the TARGET, metres
%       H.chief_quat    [N x 4]  target attitude, unit, SCALAR FIRST
%       H.chief_omega   [N x 3]  target body rate, rad/s
%       H.deputy_pos    [N x 3]  ECI position of the OBSERVER, metres
%       H.deputy_quat   [N x 4]  observer attitude, unit, SCALAR FIRST
%       H.sun_vec       [N x 3]  Sun direction in ECI, unit
%       H.separation    [N x 1]  chief-deputy range, metres
%       H.dt, H.n, H.source
%
%   QUATERNION CONVENTION
%   ---------------------
%   The HIL main_config.m comment claims [qx qy qz qs] with the scalar LAST.
%   The propagated arrays are not stored that way: the chief starts at
%   [1 0 0 0], which is the identity only if the scalar is FIRST, and HIL's
%   own renderer passes them straight to quat2rotm, which is scalar-first.
%   They are therefore read scalar-first here -- the same convention as
%   quat_multiply and quat2rotm in this project, so no conversion is applied.
%   The comment in that file is wrong, not the data.
%
%   The quaternions are renormalised on load. A propagated quaternion drifts
%   off the unit sphere by a little each step, and a non-unit quaternion
%   silently scales the rendered model.
%
%   See hil_state_at for sampling this onto frame times.

if nargin < 1 || isempty(hil_dir)
    error('hil_trajectory:noDir', 'A Phase_1_Truth directory is required.');
end
hil_dir = char(hil_dir);

need = {'chief_trajectory.mat', 'deputy_trajectory.mat', 'sun_vector.mat'};
for k = 1:numel(need)
    p = fullfile(hil_dir, need{k});
    if ~isfile(p)
        error('hil_trajectory:missingFile', ...
            ['%s not found.\nRun Phase_1_Truth/run_phase1_all.m in the HIL ' ...
             'project first -- Phase 2 there reads these same files, and they ' ...
             'are only rewritten when Phase 1 is re-run.'], p);
    end
end

C = load(fullfile(hil_dir, 'chief_trajectory.mat'));
D = load(fullfile(hil_dir, 'deputy_trajectory.mat'));
S = load(fullfile(hil_dir, 'sun_vector.mat'));

c = local_pick(C, {'trajectory', 'chief_trajectory'}, 'chief_trajectory.mat');
d = local_pick(D, {'deputy_trajectory'},              'deputy_trajectory.mat');
s = local_pick(S, {'sun_ephemeris', 'sun_vector'},    'sun_vector.mat');

H.t           = c.t(:);
H.chief_pos   = c.position;
H.chief_quat  = local_unit_quat(c.quaternion);
H.chief_omega = local_field(c, 'ang_velocity', zeros(numel(H.t), 3));
H.deputy_pos  = d.position_eci;
H.deputy_quat = local_unit_quat(d.quaternion);
H.sun_vec     = s.sun_vec ./ vecnorm(s.sun_vec, 2, 2);

if isfield(d, 'separation') && ~isempty(d.separation)
    H.separation = d.separation(:);
else
    H.separation = vecnorm(H.chief_pos - H.deputy_pos, 2, 2);
end

n = numel(H.t);
sizes = [size(H.chief_pos,1), size(H.chief_quat,1), size(H.deputy_pos,1), ...
         size(H.deputy_quat,1), size(H.sun_vec,1), numel(H.separation)];
if any(sizes ~= n)
    error('hil_trajectory:lengthMismatch', ...
        ['The three Phase 1 files disagree on length (%s against %d time ' ...
         'samples). They were probably written by different Phase 1 runs; ' ...
         're-run run_phase1_all.m so all three are regenerated together.'], ...
        mat2str(sizes), n);
end

H.n      = n;
H.dt     = median(diff(H.t));
H.source = hil_dir;

end


% -----------------------------------------------------------------------------
function v = local_pick(S, names, fname)
% The Phase 1 scripts name their saved struct inconsistently between versions,
% so accept any of the known names rather than assuming one.
for k = 1:numel(names)
    if isfield(S, names{k})
        v = S.(names{k});
        return;
    end
end
error('hil_trajectory:badStruct', ...
    '%s contains %s; expected one of: %s.', fname, ...
    strjoin(fieldnames(S)', ', '), strjoin(names, ', '));
end

function v = local_field(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end

function q = local_unit_quat(q)
% Renormalise, and reject anything that is not a 4-column quaternion array.
if size(q, 2) ~= 4
    error('hil_trajectory:quatShape', ...
        'Quaternion array is %s; expected N x 4.', mat2str(size(q)));
end
nq = vecnorm(q, 2, 2);
if any(nq < 1e-9)
    error('hil_trajectory:zeroQuat', 'Trajectory contains a zero quaternion.');
end
q = q ./ nq;
end
