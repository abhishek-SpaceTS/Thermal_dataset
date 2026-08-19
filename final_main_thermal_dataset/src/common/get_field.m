function value = get_field(s, name, default)
%GET_FIELD Read a struct field, falling back to a default.
%
%   value = get_field(s, name, default)
%
%   Treats an empty field as absent, which is the convention config.m uses to
%   mean "use the default". Replaces four private copies of the same helper
%   that had drifted apart in compute_temperatures, report_quality,
%   write_dataset_json and earth_geoglobe_render.

if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
else
    value = default;
end
end
