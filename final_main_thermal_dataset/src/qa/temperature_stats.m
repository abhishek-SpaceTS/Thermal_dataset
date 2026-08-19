function t = temperature_stats(fr, sel)
% min/max/mean face temperature over the selected frames; empty when none.
sel = sel & ~isnan(fr.T_min);
if ~any(sel)
    t = struct('min', [], 'max', [], 'mean', []);
    return;
end
t.min  = min(fr.T_min(sel));
t.max  = max(fr.T_max(sel));
t.mean = mean(fr.T_mean(sel));
end

