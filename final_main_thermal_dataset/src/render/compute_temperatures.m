function [face_temperature_K, node_temperature_K, component_temperature] = ...
    compute_temperatures(target, target_quat, sun_vec, in_eclipse, tcfg)
% Per-face temperatures from geometry, attitude and the real sun direction.
%
% All temperatures come from Pipeline/thermal_database.m. Nothing in
% this file, or anywhere else in the project, hard-codes a component
% temperature.
%
%   f = max(0, dot(face_normal, sun_direction))          incidence cosine
%
%   sunlit:   T = base(comp) + (sunlit(comp) - base(comp)) * f
%   eclipse:  T = eclipse(comp)
%   both:     T = T + variation(comp) * jitter(face)
%
% base / sunlit / eclipse are per-sequence draws from the [lo hi] ranges in
% the database -- see sample_thermal_state.m. They arrive in tcfg.realised,
% fixed for the whole sequence so nothing flickers between frames. When absent
% (standalone use outside the pipeline) the range midpoints are used.
%
% jitter(face) is uniform in [-1,+1] and deterministic: a hash of the face
% index, so a face keeps the same offset in every frame of every run.
%
% tcfg comes from cfg.thermal in config.m.
%
% LEGACY MODE. Setting cfg.thermal.component_base_K to a non-empty vector
% restores the pre-database model exactly:
%     T = base(comp) + solar_gain_K * f,  eclipse: T = eclipse_temp_K
% It is kept so datasets generated before the database can be reproduced.
%
% NOTE ON tau. It reads as a thermal time constant but is not one: it uses a
% fixed reference temperature rather than the previous frame's, takes no dt
% and keeps no state, so it cannot produce thermal lag. It is a contrast
% compressor around env.reference_K. The database values are meant to be
% taken literally, so tau defaults to 1 (no compression) in database mode; it
% still defaults to 2 in legacy mode, where it was load-bearing for keeping
% the old, hotter equilibria inside the 200-400 K save window.

if nargin < 4
    in_eclipse = false;
end

if isempty(which('thermal_database'))
    addpath(fullfile(fileparts(mfilename('fullpath')), 'Pipeline'));
end

target_quat = normalize_quaternion(target_quat);
sun_unit = validate_vector3(sun_vec, 'sun_vec');
sun_unit = sun_unit / norm(sun_unit);

num_faces = size(target.faces, 1);
face_temperature_K = zeros(num_faces, 1);

if nargin < 5; tcfg = struct(); end

[~, ~, env] = thermal_database();
reference_K = env.reference_K;

legacy_base_K = get_field(tcfg, 'component_base_K', []);
legacy_mode   = ~isempty(legacy_base_K);

if legacy_mode
    tau            = get_field(tcfg, 'relaxation_tau',  2);
    solar_gain_K   = get_field(tcfg, 'solar_gain_K',   80);
    eclipse_temp_K = get_field(tcfg, 'eclipse_temp_K', 250);
    legacy_base_K  = legacy_base_K(:);
    num_materials  = numel(legacy_base_K);
else
    tau           = get_field(tcfg, 'relaxation_tau', 1);
    state         = get_field(tcfg, 'realised', sample_thermal_state());
    base_K        = state.base_K;
    sunlit_K      = state.sunlit_K;
    eclipse_K     = state.eclipse_K;
    variation_K   = state.variation_K;
    num_materials = numel(base_K);
end

R_body_to_rel = quat2rotm(target_quat);

% Vectorised: incidence cosine for every face at once.
normals_rel = (R_body_to_rel * target.face_normals')';
cos_sun     = max(0, normals_rel * sun_unit);

% An unmapped or out-of-range material falls back to class 1, as before.
material = target.face_material(:);
material(material < 1 | material > num_materials) = 1;

if legacy_mode
    if in_eclipse
        target_temp_K = eclipse_temp_K * ones(num_faces, 1);
    else
        target_temp_K = legacy_base_K(material) + solar_gain_K * cos_sun;
    end
else
    if in_eclipse
        target_temp_K = eclipse_K(material);
    else
        b = base_K(material);
        target_temp_K = b + (sunlit_K(material) - b) .* cos_sun;
    end
    target_temp_K = target_temp_K + ...
        variation_K(material) .* face_jitter(num_faces);
end

face_temperature_K = reference_K + (target_temp_K - reference_K) / tau;

% Outputs 2 and 3 cost ~104 ms/frame on a 450k-face model and the renderer
% asks for neither. Compute them only when a caller actually wants them.
node_temperature_K = [];
component_temperature = table();
if nargout < 2
    return;
end

node_temperature_K = face_to_node_temperature( ...
    target.faces, ...
    target.face_area, ...
    face_temperature_K, ...
    size(target.vertices, 1), ...
    reference_K);

component_temperature = summarize_component_temperatures( ...
    target.face_material, ...
    face_temperature_K);

end

function node_temperature_K = face_to_node_temperature( ...
    faces, ...
    face_area, ...
    face_temperature_K, ...
    num_nodes, ...
    reference_K)

node_heat_sum = zeros(num_nodes, 1);
node_weight_sum = zeros(num_nodes, 1);

for local_vertex = 1:3
    node_id = faces(:, local_vertex);
    weight = face_area;

    node_heat_sum = node_heat_sum + ...
        accumarray( ...
            node_id, ...
            face_temperature_K .* weight, ...
            [num_nodes 1], ...
            @sum, ...
            0);

    node_weight_sum = node_weight_sum + ...
        accumarray( ...
            node_id, ...
            weight, ...
            [num_nodes 1], ...
            @sum, ...
            0);
end

% Nodes with no attached face area (unreferenced vertices) get the scene
% reference temperature rather than a literal.
node_temperature_K = reference_K * ones(num_nodes, 1);
valid_nodes = node_weight_sum > 0;
node_temperature_K(valid_nodes) = ...
    node_heat_sum(valid_nodes) ./ node_weight_sum(valid_nodes);

end

function component_temperature = summarize_component_temperatures( ...
    material_id, ...
    face_temperature_K)

cls = class_definitions();
component_names = {cls(2:end).name}';

num_components = numel(component_names);
face_count = zeros(num_components, 1);
mean_temperature_K = zeros(num_components, 1);
min_temperature_K = zeros(num_components, 1);
max_temperature_K = zeros(num_components, 1);

for component_id = 1:num_components
    is_component = material_id == component_id;
    temps = face_temperature_K(is_component);

    face_count(component_id) = nnz(is_component);

    if isempty(temps)
        mean_temperature_K(component_id) = NaN;
        min_temperature_K(component_id) = NaN;
        max_temperature_K(component_id) = NaN;
    else
        mean_temperature_K(component_id) = mean(temps);
        min_temperature_K(component_id) = min(temps);
        max_temperature_K(component_id) = max(temps);
    end
end

component_temperature = table( ...
    component_names, ...
    face_count, ...
    mean_temperature_K, ...
    min_temperature_K, ...
    max_temperature_K, ...
    'VariableNames', { ...
        'Component', ...
        'Faces', ...
        'Mean_K', ...
        'Min_K', ...
        'Max_K'});

end

function j = face_jitter(num_faces)
% Deterministic per-face offset, uniform in [-1, +1].
%
% Knuth multiplicative hash of the face index, not a random draw: it must not
% consume the global rng stream (that would shift every downstream scenario
% draw) and it must be identical in every frame, or surfaces would flicker
% instead of looking textured. xor-shifting the high bits down first stops the
% low-order bits of consecutive indices from staying correlated.
% Done in double then reduced mod 2^32, because uint32 multiplication in
% MATLAB saturates instead of wrapping -- it would pin almost every face to
% the same value. index * 2654435761 stays under 2^53 for any real mesh.
h = mod((1:num_faces)' * 2654435761, 4294967296);
h = uint32(h);
h = bitxor(h, bitshift(h, -16));
j = 2 * (double(h) / 4294967295) - 1;
end


function v = validate_vector3(v, name)

if ~isnumeric(v) || numel(v) ~= 3
    error('%s must be a numeric 3-element vector.', name)
end

v = v(:);

if any(~isfinite(v)) || norm(v) <= eps
    error('%s must be finite and non-zero.', name)
end

end

function quat = normalize_quaternion(quat)

if ~isnumeric(quat) || numel(quat) ~= 4
    error('target_rel_pose must be a 4-element quaternion [qw qx qy qz].')
end

quat = reshape(quat, 1, 4);

if any(~isfinite(quat)) || norm(quat) <= eps
    error('target_rel_pose quaternion must be finite and non-zero.')
end

quat = quat / norm(quat);

end
