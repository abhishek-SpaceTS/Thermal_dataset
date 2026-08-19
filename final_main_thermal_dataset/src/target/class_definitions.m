function [classes, patterns] = class_definitions()
%CLASS_DEFINITIONS The single source of truth for the component taxonomy.
%
%   [classes, patterns] = class_definitions()
%
%   EDIT ONLY THIS FILE to change WHICH classes exist and how they are
%   labelled. Everything downstream reads from here:
%
%     generate_rso_dataset.m       writes class_map.json and class_colors.json,
%                                  and builds comp_names + the mask RGB LUT
%     build_cad.m     maps STL filenames -> class id and slug
%     verify_sequence.m        upper bound on legal mask values
%     compute_temperatures.m component names in the summary table
%
%   THERMAL PROPERTIES ARE NOT HERE. Temperatures, heat, mass, specific heat,
%   emissivity and absorptivity live in thermal_database.m, joined
%   to this file on the class id. The split is deliberate: this file answers
%   "what can appear in a mask", that one answers "how hot is it". Changing
%   the thermal behaviour of a component should not touch the label taxonomy,
%   and vice versa.
%
%   OUTPUTS
%     classes   struct array, one per class, ordered by id:
%                 .id      integer, 0 = Background. IDs are PERMANENT --
%                          append new ones, never renumber. Existing datasets
%                          store these values in their mask PNGs.
%
%   RESERVED IDS
%     15  was 'Solar Panel Back', withdrawn. Front and back are two sides of
%         one component, not two components, so the label would have depended
%         on the array's orientation rather than on what the part is. All
%         solar array geometry is class 2; the illuminated/shaded difference
%         comes from the incidence term in the temperature model, which
%         already has the face normal and the sun direction. The id stays
%         defined and is NEVER reused, so any historical mask value keeps its
%         original meaning. No filename pattern maps to it.
%                 .name    display name used in masks, colours and metadata
%                 .slug    snake_case component_type stored on each CAD part
%                 .rgb     1x3 uint8 colour for component_masks_rgb
%     patterns  Nx2 cell {filename_substring, class_id} for the generic
%               filename matcher. Checked in order, FIRST MATCH WINS, and only
%               when a spacecraft's own component_map.json has no explicit
%               entry. Lower-case; matching is case-insensitive.
%
%   ADDING A CLASS
%     1. Append a row to C below with the next free id.
%     2. Add filename patterns to P. Put them ABOVE any more generic
%        substring that would swallow them ('fuel_tank' before 'main').
%     3. Add a row with the same id to thermal_database.m.
%     4. Nothing else. The JSONs, the mask colours and the bound check all
%        follow automatically.
%
%   See TAXONOMY_V1.md / TAXONOMY_V2.md for the design rationale.

% id, name, slug, R, G, B
C = {
    0,  'Background',        'background',          0,   0,   0
    1,  'Bus',               'spacecraft_bus',    255,   0,   0
    2,  'Solar Panel',       'solar_panel',         0, 255,   0
    3,  'Camera',            'camera',              0,   0, 255
    4,  'OBC',               'obc',               255, 255,   0
    5,  'Power Module',      'power_module',      255,   0, 255
    6,  'Reaction Wheel',    'reaction_wheel',      0, 255, 255
    7,  'High Gain Antenna', 'high_gain_antenna', 255, 128,   0
    8,  'Gold MLI',          'gold_mli',          255, 215,   0
    9,  'Silver MLI',        'silver_mli',        192, 192, 192
   10,  'Lander',            'lander',            128,   0, 128
   11,  'Boom',              'boom',                0, 128, 128
   12,  'Radiator',          'radiator',          128, 128,   0
   13,  'Vents',             'vents',               0,   0, 128
   14,  'Unknown',           'unknown',           128, 128, 128
   15,  'Reserved',          'reserved_15',         0, 160,  80
   16,  'Low Gain Antenna',  'low_gain_antenna',  255, 160, 122
   17,  'Fuel Tank',         'fuel_tank',          70, 130, 180
   18,  'Battery',           'battery',           255, 105, 180
   19,  'Star Tracker',      'star_tracker',       75,   0, 130
   20,  'Sun Sensor',        'sun_sensor',        240, 230, 140
   21,  'Thruster',          'thruster',          165,  42,  42
   22,  'RTG',               'rtg',               255,  69,   0
};

classes = struct('id', {}, 'name', {}, 'slug', {}, 'rgb', {});
for k = 1:size(C,1)
    classes(k).id   = C{k,1};
    classes(k).name = C{k,2};
    classes(k).slug = C{k,3};
    classes(k).rgb  = uint8([C{k,4} C{k,5} C{k,6}]);
end

if nargout < 2
    return;
end

% Generic filename patterns. Only reached when a spacecraft's own
% component_map.json has no matching entry -- see the mapping tiers in
% TAXONOMY_V1.md section 5.
%
% ORDER IS LOAD-BEARING: first match wins, so this table runs from most to
% least specific. 'fuel_tank' must precede 'main' or main_tank.stl becomes a
% Bus, and 'star_tracker' must precede 'sensor' or it becomes a Camera. The
% panel_* entries all resolve to class 2 now, so their order among themselves
% no longer matters, but they still sit above bare 'panel' for clarity.
P = {
    % -- compound names, most specific first --------------------------------
    % Every face of a solar array is class 2. Front and back were briefly two
    % classes; that is an orientation, not a component, so a pixel's label
    % would have depended on which way the array happened to be facing. The
    % renderer already separates the two sides through the incidence term --
    % a face pointing away from the sun gets the base temperature.
    'solar_panel_back',   2
    'solar_panel_front',  2
    'panel_back',         2
    'panel_rear',         2
    'array_back',         2
    'substrate',          2
    'panel_front',        2
    % RTG must precede 'rw' -- 'rw' is a two-letter substring that would
    % otherwise never collide here, but keeping the specific name first is the
    % rule this table follows throughout.
    'rtg',               22
    'thermoelectric',    22
    'gphs',              22
    'radioisotope',      22
    'star_tracker',      19
    'startracker',       19
    'sun_sensor',        20
    'sunsensor',         20
    'coarse_sun',        20
    'fuel_tank',         17
    'prop_tank',         17
    'propellant',        17
    'low_gain',          16
    'high_gain',          7
    'gold_mli',           8
    'foil_gold',          8
    'silver_mli',         9
    'foil_silver',        9
    'reaction_wheel',     6
    'power_module',       5

    % -- single words -------------------------------------------------------
    'battery',           18
    'batt',              18
    'tank',              17
    'thruster',          21
    'nozzle',            21
    'rcs',               21
    'lga',               16
    'hga',                7
    'dish',               7
    'reflector',          7
    'antenna',            7
    'radiator',          12
    'lander',            10
    'probe',             10
    'huygens',           10
    'camera',             3
    'optic',              3
    'sensor',             3
    'obc',                4
    'power',              5
    'wheel',              6
    'rw',                 6
    'boom',              11
    'arm',               11
    'mast',              11
    'strut',             11
    'vent',              13
    'panel',              2
    'solar',              2
    'wing',               2
    'array',              2

    % -- catch-alls last ----------------------------------------------------
    'bus',                1
    'body',               1
    'main',               1
};
patterns = P;

end
