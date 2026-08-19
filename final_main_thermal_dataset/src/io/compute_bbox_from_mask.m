function bbox = compute_bbox_from_mask(component_mask)
%COMPUTE_BBOX_FROM_MASK  Bounding box of the rendered target, [x y w h].
%
%   bbox = compute_bbox_from_mask(component_mask)
%
%   1-based pixel coordinates, matching the component mask and the 16-bit
%   frame. Returns [0 0 0 0] when nothing was rendered.
%
%   WHY NOT FROM THE PROJECTION
%   ---------------------------
%   This replaces compute_bbox_from_projection, which took the extent of every
%   projected vertex. That includes faces the renderer then threw away by
%   back-face culling or the depth test. On a closed convex body the two agree.
%   These models are not closed convex bodies: they carry single-sided solar
%   panels, booms and wires, and a panel turned away from the camera puts no
%   pixels in the image while its vertices still stretched the box.
%
%   Measured over the 1500-frame run, 296 frames (19.7 %) had a box that
%   disagreed with their own mask, the worst by 643 px. It tracked mesh
%   complexity -- 88 on Cassini, 62 on Juno, 2 on CloudSat -- and NOT
%   truncation: 139 of the 296 were not truncated at all.
%
%   Taking it from the mask makes the box and the mask consistent by
%   construction, and gives the box a single clear meaning: the extent of what
%   is actually visible. That is the MODAL box. If an AMODAL box is ever
%   wanted -- the full extent including occluded and culled parts -- it should
%   be added as separate columns rather than by changing this one, so the two
%   can never be confused.

if isempty(component_mask) || ~any(component_mask(:))
    bbox = [0, 0, 0, 0];
    return;
end

cols = any(component_mask ~= 0, 1);
rows = any(component_mask ~= 0, 2);

x1 = find(cols, 1, 'first');
x2 = find(cols, 1, 'last');
y1 = find(rows, 1, 'first');
y2 = find(rows, 1, 'last');

bbox = [x1, y1, x2 - x1 + 1, y2 - y1 + 1];

end
