function [positions, velocities] = add_arc_curvature(positions, velocities, dt, config, curvature_strength)
    frames = size(positions, 2);

    for i = 1:frames
        alpha = (i - 1) / max(1, frames - 1);

        current_range = positions(3, i);

        % The caller rotates the path by a random angle about z before calling
        % this and rotates back afterwards, so a bulge written into x here can
        % land on either image axis. It must therefore respect the TIGHTER
        % limit, not the horizontal one.
        [lim_x, lim_y] = framing_limits(config, current_range);
        max_safe_offset = current_range * min(lim_x, lim_y);

        bulge_shape = sin(alpha * pi);
        sideways_bulge = bulge_shape * curvature_strength * max_safe_offset;

        positions(1, i) = positions(1, i) + sideways_bulge;
    end

    for i = 1:frames
        if i < frames
            velocities(:, i) = (positions(:, i+1) - positions(:, i)) / dt;
        else
            if i > 1
                velocities(:, i) = velocities(:, i-1);
            end
        end
    end
end
