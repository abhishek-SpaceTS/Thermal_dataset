function names = select_spacecraft(names, selection)
% "ALL" keeps the discovered list untouched. Any other value keeps only
    selection = strtrim(char(selection));

    if strcmpi(selection, 'ALL')
        return;
    end

    match = strcmpi(names, selection);

    if ~any(match)
        available = sprintf('  - %s\n', names{:});
        error('generate_tracking_dataset_v1:spacecraftNotFound', ...
              ['Requested spacecraft "%s" was not found.\n\n' ...
               'Available spacecraft:\n%s'], selection, available);
    end

    names = names(match);

    fprintf('Spacecraft selection: "%s" -> generating %d of %d discovered.\n\n', ...
        names{1}, numel(names), numel(match));
end
