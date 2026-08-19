function image = star_render_psf(image, cx, cy, peak_temp, sigma, img_w, img_h)
% Add one star's 2-D Gaussian PSF to an image, in place.

hw = ceil(3 * sigma);
x0 = floor(cx) - hw; x1 = floor(cx) + hw + 1;
y0 = floor(cy) - hw; y1 = floor(cy) + hw + 1;

xc = max(x0, 0); xC = min(x1, img_w);
yc = max(y0, 0); yC = min(y1, img_h);

if xc >= xC || yc >= yC
    return;
end

[xx, yy] = meshgrid(xc:xC-1, yc:yC-1);
gauss = peak_temp * exp(-((xx - cx).^2 + (yy - cy).^2) / (2.0 * sigma^2));

xs = (xc:xC-1) + 1;
ys = (yc:yC-1) + 1;
image(ys, xs) = image(ys, xs) + gauss;

end
