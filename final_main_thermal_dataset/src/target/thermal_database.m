function [thermal, lut, env] = thermal_database()
%THERMAL_COMPONENT_DATABASE Thermal-optical properties, one row per class.
%
%   [thermal, lut, env] = thermal_database()
%
%   EDIT ONLY THIS FILE to change how components behave thermally. No other
%   file in the project contains a component temperature.
%
%   This file deliberately holds NO taxonomy. Which classes exist, what they
%   are called and what colour their mask is all live in class_definitions.m.
%   The two files are joined on the class id, which is permanent. The split is
%   deliberate: that file answers "what can appear in a mask", this one
%   answers "how hot is it". Changing one should never require touching the
%   other.
%
%   TEMPERATURES ARE RANGES, NOT POINTS
%     Each of base / sunlit / eclipse is a [lo hi] interval. Once per
%     sequence, sample_thermal_state.m draws one value from each interval, and
%     every frame in that sequence uses those drawn values. So two sequences
%     of the same spacecraft differ slightly in absolute temperature -- as two
%     real passes would, depending on beta angle, season, duty cycle and how
%     long the vehicle has been in sunlight -- while staying inside the
%     physically plausible band. Within a sequence the values are FIXED, so
%     nothing flickers frame to frame.
%
%   THE MODEL APPLIED PER FACE
%
%     Let f = max(0, dot(face_normal, sun_direction))  in [0,1] -- 1 at the
%     sub-solar point, 0 on any face pointing away from the sun.
%
%       sunlit:   T = base + (sunlit - base) * f
%       eclipse:  T = eclipse
%       both:     T = T + variation_K * jitter(face)
%
%     jitter(face) is uniform in [-1,+1] and DETERMINISTIC -- a hash of the
%     face index, not a random draw. A given face keeps the same offset in
%     every frame of every run, so surfaces look textured rather than
%     flickering, and datasets stay bit-reproducible.
%
%     base is therefore the temperature of an unlit face on the sunward side,
%     sunlit the temperature of a face square-on to the sun, and eclipse the
%     temperature in Earth's shadow where incidence angle no longer matters.
%
%   INTERNAL HEAT
%     heat_W is the steady electrical dissipation of the component. It is not
%     added as a separate term: it is already reflected in the three
%     temperature ranges, and is precisely why OBC, Power Module and Battery
%     barely move in eclipse (293-303 K) while a passive Boom falls to 240 K.
%     It is recorded as the engineering justification for those ranges.
%
%   WHY THESE RANGES (LEO, ~600 km, ~35 min eclipse)
%     Three things set a component's thermal signature: how much sun it sees,
%     how well it is coupled to the warm bus, and how much thermal mass it has.
%
%       Internally dissipating avionics (OBC, Power Module, Battery) are
%       conductively tied to the structure and self-heating, so they are the
%       warmest and the narrowest -- an eclipse barely registers.
%
%       The bus sits in the middle: large mass, MLI-wrapped, actively managed
%       around room temperature.
%
%       Externally mounted, low-mass, thermally isolated items swing hardest.
%       Solar arrays are the extreme case: a thin, high-absorptivity plate
%       with almost no thermal mass reaches ~360 K in sun and collapses toward
%       ~200 K within minutes of eclipse entry. The unlit rear substrate runs
%       colder than the cell side in both states. Booms, MLI blankets and
%       antenna reflectors behave the same way, less severely.
%
%       Radiators are the coldest thing on the vehicle by design -- low
%       absorptivity, high emissivity optical solar reflectors whose whole
%       purpose is to sit below everything they are cooling.
%
%   OUTPUTS
%     thermal  struct array ordered by class id, fields:
%                .id .name
%                .base_K .sunlit_K .eclipse_K   each a 1x2 [lo hi] in K
%                .variation_K .heat_W .mass .cp .emissivity .absorptivity
%              Includes id 0 (Background = deep space, a degenerate range).
%              Never rendered from geometry, but present so the table covers
%              every class in the taxonomy.
%     lut      struct of arrays indexed DIRECTLY by material_id
%              (1 = Bus ... N = Thruster), i.e. id 0 is dropped. base_K,
%              sunlit_K and eclipse_K are Nx2; the rest are Nx1. This is what
%              sample_thermal_state draws from.
%     env      scene-level reference temperatures, so no caller needs a
%              literal:
%                .reference_K   pivot for the legacy relaxation_tau contrast
%                               compressor, and the fill value for mesh nodes
%                               with no attached face area
%                .deep_space_K  cosmic microwave background
%
%   ADDING A COMPONENT
%     1. Add the class to class_definitions.m (id, name, slug, rgb, patterns).
%     2. Add a row here with the SAME id, at the end.
%     3. Nothing else. The renderer, the sampler and the fallback material
%        table all pick it up with no code change.
%
%   See also SAMPLE_THERMAL_STATE, CLASS_DEFINITIONS, COMPUTE_MODEL_TEMPERATURES.

% Row 15 is a RETIRED id, kept so it can never be reused -- see the reserved
% ids note in class_definitions.m. No filename pattern maps to it and no mask
% contains it. It carries Unknown's values so that if geometry were ever
% pointed at it by hand it would still render sanely instead of as NaN.
%
% RTG (22) is the one class whose three temperature ranges are IDENTICAL. It
% is heated by radioisotope decay, not by the sun, so its temperature does not
% depend on illumination: base = sunlit = eclipse. With base == sunlit the
% incidence term (sunlit - base) * cos collapses to zero, which is exactly the
% behaviour wanted -- an RTG reads the same in full sun and in eclipse.
%
% EDIT THE RTG TEMPERATURE HERE. 360 K is the configured value; change all
% three ranges together to keep it illumination-independent. Note that a real
% GPHS-RTG fin runs 470-520 K; 360 K is the value this dataset specifies.
% heat_W is the ~4400 W THERMAL output of a GPHS-RTG (about 300 W electrical),
% not avionics dissipation.
%
% id, name,               base_lo,hi   sunlit_lo,hi   eclipse_lo,hi  var  heat  mass    cp   emis  absorp
T = {
    0, 'Background',    2.7,   2.7,    2.7,   2.7,    2.7,   2.7,  0,    0,   0.0,     0,  0.00,  0.00
    1,  'Bus',          288,   292,    325,   335,    275,   285,  3,   20,   5.0,   900,  0.85,  0.65
    2,  'Solar Panel',       288,   292,    350,   365,    190,   210,  5,    0,   1.0,   750,  0.90,  0.85
    3,  'Camera',            283,   287,    310,   320,    245,   255,  3,    5,   1.0,   500,  0.80,  0.60
    4,  'OBC',               298,   302,    320,   330,    293,   298,  2,   15,   2.0,   850,  0.88,  0.70
    5,  'Power Module',      303,   307,    335,   345,    298,   303,  3,   20,   3.0,   800,  0.90,  0.75
    6,  'Reaction Wheel',    293,   297,    320,   330,    280,   290,  3,   10,   2.0,   450,  0.75,  0.60
    7,  'High Gain Antenna', 283,   287,    310,   320,    245,   255,  3,    0,   2.0,   800,  0.80,  0.60
    8,  'Gold MLI',          288,   292,    335,   345,    215,   225,  5,    0,   0.5,   800,  0.05,  0.25
    9,  'Silver MLI',        283,   287,    315,   325,    205,   215,  5,    0,   0.5,   800,  0.05,  0.15
   10,  'Lander',            288,   292,    320,   330,    265,   275,  3,    5,   8.0,   850,  0.88,  0.75
   11,  'Boom',              283,   287,    310,   320,    235,   245,  3,    0,   1.0,   700,  0.75,  0.50
   12,  'Radiator',          248,   252,    265,   275,    215,   225,  2,    0,   1.0,   900,  0.90,  0.20
   13,  'Vents',             278,   282,    295,   305,    245,   255,  2,    0,   1.0,   800,  0.85,  0.85
   14,  'Unknown',           288,   292,    315,   325,    275,   285,  3,    0,   2.0,   900,  0.85,  0.65
   15,  'Reserved',          288,   292,    315,   325,    275,   285,  3,    0,   2.0,   900,  0.85,  0.65
   16,  'Low Gain Antenna',  283,   287,    305,   315,    245,   255,  3,    0,   0.3,   800,  0.80,  0.55
   17,  'Fuel Tank',         288,   292,    315,   325,    265,   275,  3,    0,  12.0,  1200,  0.10,  0.25
   18,  'Battery',           293,   297,    310,   320,    288,   293,  2,   15,   4.0,   950,  0.88,  0.70
   19,  'Star Tracker',      283,   287,    300,   310,    245,   255,  3,    5,   1.5,   850,  0.85,  0.25
   20,  'Sun Sensor',        288,   292,    315,   325,    255,   265,  3,    2,   0.2,   800,  0.80,  0.60
   21,  'Thruster',          288,   292,    335,   345,    255,   265,  5,    0,   0.8,   500,  0.75,  0.55
   22,  'RTG',               358,   362,    358,   362,    358,   362,  2, 4400,  56.0,   500,  0.90,  0.25
};

% Column indices into T, named so the parsing below survives a reordering.
c.id = 1; c.name = 2; c.base = 3:4; c.sun = 5:6; c.ecl = 7:8;
c.var = 9; c.heat = 10; c.mass = 11; c.cp = 12; c.emis = 13; c.absorp = 14;

n = size(T,1);
thermal = struct('id', {}, 'name', {}, 'base_K', {}, 'sunlit_K', {}, ...
    'eclipse_K', {}, 'variation_K', {}, 'heat_W', {}, 'mass', {}, 'cp', {}, ...
    'emissivity', {}, 'absorptivity', {});
for k = 1:n
    thermal(k).id           = T{k,c.id};
    thermal(k).name         = T{k,c.name};
    thermal(k).base_K       = [T{k,c.base}];
    thermal(k).sunlit_K     = [T{k,c.sun}];
    thermal(k).eclipse_K    = [T{k,c.ecl}];
    thermal(k).variation_K  = T{k,c.var};
    thermal(k).heat_W       = T{k,c.heat};
    thermal(k).mass         = T{k,c.mass};
    thermal(k).cp           = T{k,c.cp};
    thermal(k).emissivity   = T{k,c.emis};
    thermal(k).absorptivity = T{k,c.absorp};
end

% Deep space and the relaxation pivot, so that no other file in the project
% contains a bare temperature literal.
env.deep_space_K = T{1, c.base(1)};
env.reference_K  = 300;

if nargout < 2
    return;
end

% Arrays indexed by material_id (1..N). Row 1 of T is class id 0, which
% carries no geometry, so it is dropped -- lut.base_K(1,:) is the Bus.
body = 2:n;
lut.id           = cell2mat(T(body, c.id));
lut.name         = T(body, c.name);
lut.base_K       = cell2mat(T(body, c.base));
lut.sunlit_K     = cell2mat(T(body, c.sun));
lut.eclipse_K    = cell2mat(T(body, c.ecl));
lut.variation_K  = cell2mat(T(body, c.var));
lut.heat_W       = cell2mat(T(body, c.heat));
lut.mass         = cell2mat(T(body, c.mass));
lut.cp           = cell2mat(T(body, c.cp));
lut.emissivity   = cell2mat(T(body, c.emis));
lut.absorptivity = cell2mat(T(body, c.absorp));

% Indexing by material_id only works while the ids in T are the contiguous run
% 0,1,...,N. Appending rows in order keeps that true; this catches an id
% inserted out of sequence, which would otherwise silently shift every
% component's properties by one.
if ~isequal(lut.id(:)', 1:numel(body))
    error('thermal_database:nonContiguousIds', ...
        ['Class ids in T must be contiguous and start at 0 (found %s). ' ...
         'Append new rows with the next free id.'], mat2str(lut.id(:)'));
end

% Every range must be ordered lo <= hi, or sampling silently inverts.
for f = {'base_K','sunlit_K','eclipse_K'}
    bad = find(lut.(f{1})(:,1) > lut.(f{1})(:,2), 1);
    if ~isempty(bad)
        error('thermal_database:badRange', ...
            '%s for "%s" is [%g %g]; ranges must be [lo hi].', ...
            f{1}, lut.name{bad}, lut.(f{1})(bad,1), lut.(f{1})(bad,2));
    end
end

end
