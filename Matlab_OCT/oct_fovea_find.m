function [cy, cx, info] = oct_fovea_find(T, varargin)
%OCT_FOVEA_FIND  从全层厚度图上自动定位中心凹。
%
%   [cy, cx] = OCT_FOVEA_FIND(T)
%   [cy, cx, info] = OCT_FOVEA_FIND(T, 'Name', value, ...)
%
%   T       : 全层厚度图（oct_thickness_map 的输出，ILM->RPE）
%   cy, cx  : 中心凹位置（行 = B-scan 序号，列 = A-line 序号，亚像素）
%
%   中心凹是视网膜最薄的地方，所以在全层厚度图上找最小值就行。三点注意：
%     * 先平滑。逐点的最小值会被噪声和分层小毛刺带跑。
%     * 只在中央区域找（'Margin'）。图像边缘常因分层失败而异常薄，
%       不限制范围的话很容易定位到角上去。
%     * 亚像素。在最小值附近做加权质心，避免量化到整数格点。
%
%   选项：
%     'Sigma'   平滑的高斯 sigma（默认 [3 8]，纵向 x 横向）。
%               纵向只有 120 幅、横向有 432 条，所以横向可以平滑更多。
%     'Margin'  搜索区域距边缘的比例（默认 0.25，即只在中间一半里找）
%     'Refine'  亚像素细化的窗口半径（默认 [4 12]）
%
%   info : .minThickness .searchBox .smoothed
%
%   参见 oct_thickness_map, oct_etdrs_grid。

opt.Sigma  = [3 8];
opt.Margin = 0.25;
opt.Refine = [4 12];
opt = oct_parseopt(opt, varargin);

T = double(T);
[H, W] = size(T);

% NaN 用中位数补上，免得平滑把洞扩散开
v = T(isfinite(T));
if isempty(v), error('oct_fovea_find:allNaN', '厚度图全是 NaN'); end
F = T; F(~isfinite(F)) = median(v);

S = local_gauss2(F, opt.Sigma(1), opt.Sigma(end));

% 只在中央区域找
m = opt.Margin;
r0 = max(1, round(m*H)); r1 = min(H, round((1-m)*H));
c0 = max(1, round(m*W)); c1 = min(W, round((1-m)*W));
sub = S(r0:r1, c0:c1);
[~, li] = min(sub(:));
[ri, ci] = ind2sub(size(sub), li);
cy0 = r0 + ri - 1;
cx0 = c0 + ci - 1;

% 亚像素：在最小值附近用"深度反转后的权重"做质心
ry = opt.Refine(1); rx = opt.Refine(end);
wy = max(1, cy0-ry):min(H, cy0+ry);
wx = max(1, cx0-rx):min(W, cx0+rx);
patch = S(wy, wx);
wgt = max(patch(:)) - patch;           % 越薄权重越大
if sum(wgt(:)) <= 0
    cy = cy0; cx = cx0;
else
    [XX, YY] = meshgrid(wx, wy);
    cy = sum(YY(:) .* wgt(:)) / sum(wgt(:));
    cx = sum(XX(:) .* wgt(:)) / sum(wgt(:));
end

if nargout > 2
    info.minThickness = S(cy0, cx0);
    info.searchBox    = [r0 r1 c0 c1];
    info.intPeak      = [cy0 cx0];
    info.smoothed     = S;
end
end

% ======================================================================
function out = local_gauss2(im, sy, sx)
out = im;
if sy > 0
    r = max(1, ceil(4*sy)); t = -r:r;
    k = exp(-t.^2/(2*sy^2)).'; k = k/sum(k);
    out = local_conv2sym(out, k);
end
if sx > 0
    r = max(1, ceil(4*sx)); t = -r:r;
    k = exp(-t.^2/(2*sx^2)); k = k/sum(k);
    out = local_conv2sym(out, k);
end
end

function out = local_conv2sym(im, k)
[kh, kw] = size(k);
ph = floor(kh/2); pw = floor(kw/2);
[H, W] = size(im);
ri = local_reflect((1:H+2*ph) - ph, H);
ci = local_reflect((1:W+2*pw) - pw, W);
out = conv2(im(ri, ci), k, 'same');
out = out(ph+1:ph+H, pw+1:pw+W);
end

function idx = local_reflect(i, N)
if N == 1, idx = ones(size(i)); return; end
p = 2*N;
j = mod(i-1, p);
j(j < 0) = j(j < 0) + p;
big = j >= N;
j(big) = p - 1 - j(big);
idx = j + 1;
end
