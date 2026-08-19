function write_class_maps(dataset_root)
%WRITE_CLASS_MAPS Write class_map.json and class_colors.json for a spacecraft.
%
%   Both files are DERIVED from src/target/class_definitions.m and rewritten
%   every run. They used to be hard-coded behind an ~isfile guard, which left
%   every existing spacecraft folder holding a stale copy after a taxonomy
%   change.

cls = class_definitions();

    lines = cell(1, numel(cls));
    for ci = 1:numel(cls)
        sep = ','; if ci == numel(cls); sep = ''; end
        lines{ci} = sprintf('  "%d": "%s"%s', cls(ci).id, cls(ci).name, sep);
    end
    class_map_str = ['{' newline strjoin(lines, newline) newline '}'];

    class_map_path = fullfile(dataset_root, 'class_map.json');
    fid_cm = fopen(class_map_path, 'w');
    if fid_cm ~= -1
        fprintf(fid_cm, '%s', class_map_str);
        fclose(fid_cm);
    else
        warning('Could not write %s', class_map_path);
    end

    lines = cell(1, numel(cls));
    for ci = 1:numel(cls)
        sep = ','; if ci == numel(cls); sep = ''; end
        lines{ci} = sprintf('  "%s": [%d, %d, %d]%s', cls(ci).name, ...
            cls(ci).rgb(1), cls(ci).rgb(2), cls(ci).rgb(3), sep);
    end
    class_colors_str = ['{' newline strjoin(lines, newline) newline '}'];

    class_colors_path = fullfile(dataset_root, 'class_colors.json');
    fid_cc = fopen(class_colors_path, 'w');
    if fid_cc ~= -1
        fprintf(fid_cc, '%s', class_colors_str);
        fclose(fid_cc);
    else
        warning('Could not write %s', class_colors_path);
    end

    fprintf('Loading configuration...\n');
end
