function names = discover_spacecraft(spacecraft_root)
    names = {};
    if ~exist(spacecraft_root, 'dir')
        return;
    end
    entries = dir(spacecraft_root);
    entries = entries([entries.isdir]);
    entries = entries(~ismember({entries.name}, {'.', '..'}));
    for k = 1:numel(entries)
        if exist(fullfile(spacecraft_root, entries(k).name, 'CAD'), 'dir')
            names{end+1} = entries(k).name; %#ok<AGROW>
        end
    end
    names = sort(names);
end
