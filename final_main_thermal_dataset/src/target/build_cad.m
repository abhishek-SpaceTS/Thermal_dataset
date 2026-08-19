function target = build_cad(config)
    fprintf('\nLoading Generic Spacecraft Target: %s\n', config.target.name);

    % Models live in data/spacecraft, two levels up from src/target.
    base_dir = fullfile(project_root(), 'data', 'spacecraft', config.target.name);
    cad_dir  = fullfile(base_dir, 'CAD');

    if ~exist(cad_dir, 'dir')
        error('build_cad:noCad', 'CAD directory not found: %s', cad_dir);
    end

    stl_files_info = dir(fullfile(cad_dir, '*.stl'));
    if isempty(stl_files_info)
        stl_files_info = dir(fullfile(cad_dir, '*.STL'));
    end

    if isempty(stl_files_info)
        error(['No STL files found in: ', cad_dir]);
    end

    files = {stl_files_info.name};
    num_files = length(files);

    comp_map_path = fullfile(base_dir, 'component_map.json');
    if isfile(comp_map_path)
        comp_map_text = fileread(comp_map_path);
        comp_map = jsondecode(comp_map_text);
    else
        fprintf(['  [WARN] No component_map.json for %s -- using generic ' ...
                 'default component mapping (temporary, not spacecraft-specific).\n'], ...
                 config.target.name);
        comp_map = default_component_map();
    end

    therm_prop_path = fullfile(base_dir, 'thermal_properties.json');
    if isfile(therm_prop_path)
        therm_prop_text = fileread(therm_prop_path);
        therm_prop = jsondecode(therm_prop_text);
    else
        fprintf(['  [WARN] No thermal_properties.json for %s -- using generic ' ...
                 'default material properties (temporary, not thermally accurate).\n'], ...
                 config.target.name);
        therm_prop = default_thermal_properties();
    end

    all_vertices = [];
    for k = 1:num_files
        TR = stlread(fullfile(cad_dir, files{k}));
        all_vertices = [all_vertices; TR.Points];
    end
    COM = mean(all_vertices, 1);

    vertices = [];
    faces = [];
    material_id = [];
    components = struct('name', {}, 'vertices', {}, 'faces', {}, 'start_vertex_index', {}, 'end_vertex_index', {}, 'start_face_index', {}, 'end_face_index', {}, 'material_id', {}, 'component_type', {});

    for k = 1:num_files
        filename = files{k};
        filepath = fullfile(cad_dir, filename);

        fprintf('Loading STL: %s\n', filename);

        TR = stlread(filepath);
        V = TR.Points;
        F = TR.ConnectivityList;

        if isfield(comp_map, 'center_com') && comp_map.center_com
            V = V - COM;
        end

        lower_name = lower(filename);
        comp_type = comp_map.default.component_type;
        mat_id = comp_map.default.material_id;
        offset_cad = [0, 0, 0];

        if isfield(comp_map, 'mappings')
            if iscell(comp_map.mappings)
                mappings_array = comp_map.mappings;
            else
                mappings_array = num2cell(comp_map.mappings);
            end

            for m = 1:length(mappings_array)
                mapping = mappings_array{m};
                if contains(lower_name, lower(mapping.pattern))
                    comp_type = mapping.component_type;
                    mat_id = mapping.material_id;
                    if isfield(mapping, 'offset_cad')
                        offset_cad = mapping.offset_cad;

                        if size(offset_cad, 1) > size(offset_cad, 2)
                            offset_cad = offset_cad';
                        end
                    end
                    break;
                end
            end
        end

        if any(offset_cad ~= 0)
            V(:,1) = V(:,1) + offset_cad(1);
            V(:,2) = V(:,2) + offset_cad(2);
            V(:,3) = V(:,3) + offset_cad(3);
        end

        % CAD units -> metres. Previously only 'mm' was handled and everything
        % else fell through as metres, so a model authored in inches loaded
        % 39.37x oversized with no warning. cad_scale overrides for anything
        % not in the table.
        V = V * local_unit_scale(comp_map);

        offset_V = size(vertices, 1);
        offset_F = size(faces, 1);

        num_V = size(V, 1);
        num_F = size(F, 1);

        comp.name = filename;
        comp.component_type = comp_type;
        comp.material_id = mat_id;
        comp.vertices = V;
        comp.faces = F;

        comp.start_face_index = offset_F + 1;
        comp.end_face_index = offset_F + num_F;

        comp.start_vertex_index = offset_V + 1;
        comp.end_vertex_index = offset_V + num_V;

        if k == 1
            components = repmat(comp, 1, num_files);
        else
            components(k) = comp;
        end

        vertices = [vertices; V];
        faces = [faces; F + offset_V];
        material_id = [material_id; mat_id * ones(num_F, 1)];
    end

    num_faces = size(faces, 1);
    face_normals = zeros(num_faces, 3);
    face_area = zeros(num_faces, 1);

    for k = 1:num_faces
        verts = faces(k,:);
        p1 = vertices(verts(1),:);
        p2 = vertices(verts(2),:);
        p3 = vertices(verts(3),:);

        n = cross(p2-p1, p3-p1);
        area = 0.5 * norm(n);

        if norm(n) > 0
            n = n / norm(n);
        end

        face_normals(k,:) = n;
        face_area(k) = area;
    end

    face_mass = therm_prop.default.mass * ones(num_faces, 1);
    face_cp = therm_prop.default.cp * ones(num_faces, 1);
    face_emissivity = therm_prop.default.emissivity * ones(num_faces, 1);
    face_absorptivity = therm_prop.default.absorptivity * ones(num_faces, 1);

    % Per-material property lookup.
    %
    % thermal_properties.json keys its materials by bare class id -- "1", "2".
    % MATLAB field names cannot start with a digit, so jsondecode renames them
    % to x1, x2, ... This used to look up num2str(id), which therefore NEVER
    % matched and left every face on every spacecraft holding the default
    % emissivity, mass, cp and absorptivity. Try the jsondecode form first,
    % then the bare numeral so a hand-built struct still works.
    unique_mats = unique(material_id);
    for i = 1:length(unique_mats)
        m_id = sprintf('x%d', unique_mats(i));
        if ~isfield(therm_prop.materials, m_id)
            m_id = num2str(unique_mats(i));
        end
        if isfield(therm_prop.materials, m_id)
            mat_props = therm_prop.materials.(m_id);
            idx = (material_id == unique_mats(i));

            if isfield(mat_props, 'mass') face_mass(idx) = mat_props.mass; end
            if isfield(mat_props, 'cp') face_cp(idx) = mat_props.cp; end
            if isfield(mat_props, 'emissivity') face_emissivity(idx) = mat_props.emissivity; end
            if isfield(mat_props, 'absorptivity') face_absorptivity(idx) = mat_props.absorptivity; end
        end
    end

    target.vertices = vertices;
    target.faces = faces;
    target.face_normals = face_normals;
    target.face_area = face_area;
    target.face_mass = face_mass;
    target.face_cp = face_cp;
    target.face_emissivity = face_emissivity;
    target.face_absorptivity = face_absorptivity;
    target.material_id = material_id;
    target.face_material = material_id;
    target.components = components;

    % Provenance for the dataset metadata. The authored units are worth
    % recording: a model declared in metres but authored in inches renders 39x
    % oversized, and nothing downstream can detect that after the fact.
    if isfield(comp_map, 'cad_units') && ~isempty(comp_map.cad_units)
        target.cad_units = char(comp_map.cad_units);
    else
        target.cad_units = 'm';
    end
    target.cad_scale_m = local_unit_scale(comp_map);

    fprintf('\nTarget %s Loaded\n', config.target.name);
    fprintf('Vertices : %d\n', size(vertices,1));
    fprintf('Faces    : %d\n', size(faces,1));

    xmin = min(vertices(:,1)); xmax = max(vertices(:,1));
    ymin = min(vertices(:,2)); ymax = max(vertices(:,2));
    zmin = min(vertices(:,3)); zmax = max(vertices(:,3));

    fprintf('\nCAD Size X = %.3f m\n', xmax-xmin);
    fprintf('CAD Size Y = %.3f m\n', ymax-ymin);
    fprintf('CAD Size Z = %.3f m\n', zmax-zmin);
end

function s = local_unit_scale(comp_map)
% Metres per CAD unit. cad_scale wins if present, then cad_units, else 1.
%
% Cassini was authored in inches but declared "m", so it loaded 39.37x too
% large -- a 705 m spacecraft. Its HGA measures 157.5 units against a real
% 4.0 m dish, i.e. exactly 1.000 inch per unit, which is how the error was
% identified. Unrecognised unit strings now warn instead of silently
% defaulting to metres.
s = 1.0;
if isfield(comp_map, 'cad_scale') && ~isempty(comp_map.cad_scale)
    s = comp_map.cad_scale;
    return;
end
if ~isfield(comp_map, 'cad_units') || isempty(comp_map.cad_units)
    return;
end
switch lower(strtrim(char(comp_map.cad_units)))
    case {'m', 'metre', 'meter'};      s = 1.0;
    case {'mm', 'millimetre'};         s = 1e-3;
    case {'cm', 'centimetre'};         s = 1e-2;
    case {'in', 'inch', 'inches'};     s = 0.0254;
    case {'ft', 'foot', 'feet'};       s = 0.3048;
    otherwise
        warning('build_cad:unknownUnits', ...
            ['Unrecognised cad_units "%s"; treating the model as metres. ' ...
             'Set cad_units to m/mm/cm/in/ft or give an explicit cad_scale.'], ...
            char(comp_map.cad_units));
end
end


function comp_map = default_component_map()
    comp_map.cad_units = 'm';
    comp_map.center_com = true;

    % Patterns and the id -> slug mapping both come from class_definitions.
    [classes, generic_patterns] = class_definitions();
    slug_by_id = containers.Map({classes.id}, {classes.slug});

    mappings = struct('pattern', {}, 'component_type', {}, 'material_id', {});
    for i = 1:size(generic_patterns, 1)
        mappings(end+1).pattern        = generic_patterns{i,1}; %#ok<AGROW>
        mappings(end).component_type   = slug_by_id(generic_patterns{i,2});
        mappings(end).material_id      = generic_patterns{i,2};
    end

    unknown_id = classes(strcmp({classes.slug}, 'unknown')).id;
    comp_map.mappings = mappings;
    comp_map.default.component_type = slug_by_id(unknown_id);
    comp_map.default.material_id = unknown_id;
end

function therm_prop = default_thermal_properties()
    % Fallback material table, used only when a spacecraft has no
    % thermal_properties.json of its own. Mass, specific heat, emissivity and
    % absorptivity come from thermal_database.m -- the same single
    % source the temperature model reads, so a spacecraft without its own JSON
    % and one with a matching JSON behave identically. The field names are
    % 'x<material_id>' because MATLAB struct fields cannot begin with a digit.
    th = thermal_database();
    mat = struct();
    for k = 1:numel(th)
        c = th(k);
        if c.id == 0; continue; end
        mat.(sprintf('x%d', c.id)) = struct('name', c.name, 'mass', c.mass, ...
            'cp', c.cp, 'emissivity', c.emissivity, 'absorptivity', c.absorptivity);
    end

    therm_prop.materials = mat;

    % An unrecognised part inherits the Unknown class, located by slug so that
    % reordering or extending the taxonomy cannot silently repoint it.
    classes = class_definitions();
    unknown_id = classes(strcmp({classes.slug}, 'unknown')).id;
    u = th([th.id] == unknown_id);
    therm_prop.default = struct('mass', u.mass, 'cp', u.cp, ...
        'emissivity', u.emissivity, 'absorptivity', u.absorptivity);
end
