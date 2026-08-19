function [vis_gray, vis_rgb] = make_visual(img_gray_16, log_gain, mode)
% Display view of a final 16-bit thermal frame, for HUMAN viewing only.
%
%   [vis_gray, vis_rgb] = make_visual(img_gray_16, log_gain, mode)
%
%   mode 'linear' (default)
%       Brightness is proportional to TEMPERATURE, the same mapping
%       thermal_rgb uses. A grey level therefore means the same Kelvin here
%       as in the false-colour image, and equal temperature steps are equally
%       visible anywhere in the range.
%
%   mode 'log'
%       y = log1p(a*x) / log1p(a),  x = DN/65535
%       Lifts the dark end so faint stars register, at the cost of the bright
%       end. Measured over a 200-400 K window at a = 200, everything from
%       275 K (spacecraft in eclipse) to 370 K (sunlit power module) is
%       squeezed into 39 of 255 levels -- Earth and spacecraft both read as
%       near-white. Linear gives 121 levels over the same span.
%       Use this only when faint stars matter more than scene contrast.
%
%   Neither mode touches thermal_gray, which stays the linear 16-bit Kelvin
%   ground truth used for training.

if nargin < 2; log_gain = []; end
if nargin < 3 || isempty(mode); mode = 'linear'; end

% 'scene' mode knee. 235 K is above every star pixel (the field tops out near
% 230 K after PSF blur) and below the coldest Earth class (cloud at 230-240),
% so the lift lands on stars and essentially nothing else.
SCENE_KNEE_K = 235;
SCENE_GAMMA  = 0.30;

x = double(img_gray_16) / 65535;

switch lower(char(mode))
    case 'linear'
        % x already is (T - T_min)/(T_max - T_min); nothing to do.

    case 'scene'
        % Linear ABOVE a knee, lifted below it.
        %
        % Stars sit within ~1 K of the sky floor -- the bottom 0.6% of a
        % 200-400 K window -- so a linear map leaves them at DN 3-19 and they
        % disappear. Applying gamma or log to the WHOLE range does show them,
        % but it also pushes Earth past DN 172, which is where the hot
        % colormap turns yellow. That is the washed-out look.
        %
        % So the curve is split. Above the knee it is exactly linear, leaving
        % Earth and the spacecraft with the same colours thermal_rgb gives
        % them. Below the knee a gamma lifts the near-floor pixels where only
        % stars live. The two halves meet at the knee, so there is no visible
        % seam.
        xk = (SCENE_KNEE_K - 200) / 200;      % knee as a fraction of the window
        g  = SCENE_GAMMA;
        lo = x < xk;
        x(lo) = xk * (x(lo) / xk).^g;         % below: lifted
        % above: unchanged, i.e. identical to 'linear'

    case 'log'
        a = 200.0;
        if ~isempty(log_gain); a = log_gain; end
        x = log1p(a * x) / log1p(a);

    otherwise
        error('make_visual:badMode', ...
              'mode must be "linear", "scene" or "log", got "%s".', char(mode));
end

vis_gray = uint8(x * 255);

cmap = hot(256);
idx  = min(max(round(x * 255) + 1, 1), 256);
[h, w] = size(x);
vis_rgb = cat(3, ...
    reshape(uint8(cmap(idx,1)*255), h, w), ...
    reshape(uint8(cmap(idx,2)*255), h, w), ...
    reshape(uint8(cmap(idx,3)*255), h, w));

end
