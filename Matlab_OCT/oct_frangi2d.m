function [J, scaleOut, dirOut] = oct_frangi2d(I, varargin)
%OCT_FRANGI2D  Frangi 血管增强滤波（2D），复刻 exe 里的 FrangiFilter2D.m。
%
%   J = OCT_FRANGI2D(I)
%   [J, scale, dir] = OCT_FRANGI2D(I, 'Name', value, ...)
%
%   I : 二维图（en-face 投影）。J : 血管性响应，归一化到 [0,1]。
%   scale : 每个像素响应最强时的 sigma。dir : 该处血管方向（弧度）。
%
%   算法是 Frangi et al. 1998（MICCAI, LNCS 1496:130）：
%   在多个尺度上算 Hessian，取特征值 |λ1| <= |λ2|，然后
%       Rb = λ1/λ2          管状程度（血管 Rb 接近 0，斑点 Rb 接近 1）
%       S  = sqrt(λ1²+λ2²)  结构强度（背景噪声 S 很小）
%       V  = exp(-Rb²/2β²) · (1 - exp(-S²/2c²))
%   逐尺度取最大响应。
%
%   被封进 EOD_read_seg.exe 的那三个文件 FrangiFilter2D.m / Hessian2D.m /
%   eig2image.m 是 Dirk-Jan Kroon 在 MATLAB File Exchange 上那个包
%   （"Hessian based Frangi Vesselness filter"），算法本身是公开的。
%   这里把三个合成一个文件，Hessian2D 和 eig2image 作为局部函数。
%
%   选项（名字沿用原包的叫法）：
%     'ScaleRange'  尺度范围 [最小 最大]（默认 [1 8]）
%     'ScaleRatio'  尺度步长（默认 1）
%     'BetaOne'     β，压制斑点状结构（默认 0.5）
%     'BetaTwo'     c，压制背景噪声（默认 15）
%     'BlackWhite'  true = 找暗血管（默认 true）
%                   OCT 的 en-face 上血管是投影阴影，所以是暗的。
%     'Normalize'   把输出拉到 [0,1]（默认 true）
%
%   只用基础 MATLAB —— 原包里用的 imfilter 是图像处理工具箱的，
%   这里换成自己的对称边界卷积。
%
%   参见 oct_enface, oct_devessel。

opt.ScaleRange = [1 8];
opt.ScaleRatio = 1;
opt.BetaOne    = 0.5;
opt.BetaTwo    = 15;
opt.BlackWhite = true;
opt.Normalize  = true;
opt = oct_parseopt(opt, varargin);

I = double(I);
if ndims(I) ~= 2 %#ok<ISMAT>
    error('oct_frangi2d:dims', '要二维图，给的是 %s', mat2str(size(I)));
end

sigmas = opt.ScaleRange(1):opt.ScaleRatio:opt.ScaleRange(2);
if isempty(sigmas), sigmas = opt.ScaleRange(1); end
sigmas = sort(sigmas);

beta = 2 * opt.BetaOne^2;
c    = 2 * opt.BetaTwo^2;

[H, W] = size(I);
allV = zeros(H, W, numel(sigmas));
allD = zeros(H, W, numel(sigmas));

for k = 1:numel(sigmas)
    s = sigmas(k);
    [Dxx, Dxy, Dyy] = local_hessian2d(I, s);

    % 尺度归一化，不然大 sigma 的响应天然偏小
    Dxx = s^2 * Dxx;
    Dxy = s^2 * Dxy;
    Dyy = s^2 * Dyy;

    [lam1, lam2, Ix, Iy] = local_eig2image(Dxx, Dxy, Dyy);

    allD(:, :, k) = atan2(Ix, Iy);

    % Rb = λ1/λ2，|λ1| <= |λ2|。血管处 λ1≈0 所以 Rb≈0、exp(-Rb/β)≈1；
    % 斑点处 λ1≈λ2 所以 Rb≈1，被压下去。分母必须是大的那个 λ2。
    lam2s = lam2;
    lam2s(lam2s == 0) = eps;
    Rb = (lam1 ./ lam2s).^2;
    S2 = lam1.^2 + lam2.^2;

    V = exp(-Rb / beta) .* (1 - exp(-S2 / c));

    % 极性看的是 λ2（绝对值大的那个，即垂直于管走向的曲率）：
    % 暗管在亮背景上，横切面是"亮-暗-亮"，二阶导为正，所以 λ2 > 0。
    if opt.BlackWhite
        V(lam2 < 0) = 0;                % 只留暗管
    else
        V(lam2 > 0) = 0;                % 只留亮管
    end
    V(~isfinite(V)) = 0;
    allV(:, :, k) = V;
end

[J, idx] = max(allV, [], 3);

if nargout > 1
    scaleOut = reshape(sigmas(idx), H, W);
end
if nargout > 2
    dirOut = zeros(H, W);
    for k = 1:numel(sigmas)
        m = (idx == k);
        tmp = allD(:, :, k);
        dirOut(m) = tmp(m);
    end
end

if opt.Normalize
    mx = max(J(:));
    if mx > 0, J = J / mx; end
end
end

% ======================================================================
function [Dxx, Dxy, Dyy] = local_hessian2d(I, sigma)
%LOCAL_HESSIAN2D  用高斯二阶导算 Hessian（对应 exe 里的 Hessian2D.m）。
if sigma < 1, sigma = 1; end
r = round(3 * sigma);
[X, Y] = ndgrid(-r:r, -r:r);
E = exp(-(X.^2 + Y.^2) / (2 * sigma^2));
Gxx = 1/(2*pi*sigma^4) * (X.^2/sigma^2 - 1) .* E;
Gxy = 1/(2*pi*sigma^6) * (X .* Y) .* E;
Gyy = Gxx.';
Dxx = local_conv2sym(I, Gxx);
Dxy = local_conv2sym(I, Gxy);
Dyy = local_conv2sym(I, Gyy);
end

% ======================================================================
function [lam1, lam2, Ix, Iy] = local_eig2image(Dxx, Dxy, Dyy)
%LOCAL_EIG2IMAGE  2x2 对称矩阵逐像素求特征值/特征向量
%（对应 exe 里的 eig2image.m）。返回时 |lam1| <= |lam2|。
tmp = sqrt((Dxx - Dyy).^2 + 4 * Dxy.^2);

v2x = 2 * Dxy;
v2y = Dyy - Dxx + tmp;
mag = sqrt(v2x.^2 + v2y.^2);
nz = (mag ~= 0);
v2x(nz) = v2x(nz) ./ mag(nz);
v2y(nz) = v2y(nz) ./ mag(nz);

% 另一个特征向量和它正交
v1x = -v2y;
v1y =  v2x;

mu1 = 0.5 * (Dxx + Dyy + tmp);
mu2 = 0.5 * (Dxx + Dyy - tmp);

swap = abs(mu1) > abs(mu2);

lam1 = mu1;  lam1(swap) = mu2(swap);
lam2 = mu2;  lam2(swap) = mu1(swap);

Ix = v1x;  Ix(swap) = v2x(swap);
Iy = v1y;  Iy(swap) = v2y(swap);
end

% ======================================================================
function out = local_conv2sym(im, k)
%LOCAL_CONV2SYM  conv2 'same' + 对称边界（原包用的 imfilter 要工具箱）。
[kh, kw] = size(k);
ph = floor(kh/2); pw = floor(kw/2);
[H, W] = size(im);
% 用周期性反射算延拓索引。早先写的是
%     ri = [ph+1:-1:2, 1:H, H-1:-1:H-ph]  再把非法值滤掉
% 那个在核比图还大时会塌掉（滤完宽度不够，后面切片越界）——
% 自测拿 6 行的小图配 sigma=6（核半径 18）就撞上了。
ri = local_reflect((1:H+2*ph) - ph, H);
ci = local_reflect((1:W+2*pw) - pw, W);
out = conv2(im(ri, ci), k, 'same');
out = out(ph+1:ph+H, pw+1:pw+W);
end

% ======================================================================
function idx = local_reflect(i, N)
%LOCAL_REFLECT  把任意整数索引折回 [1,N]（symmetric：边界像素重复）。
if N == 1, idx = ones(size(i)); return; end
p = 2*N;
j = mod(i-1, p);
j(j < 0) = j(j < 0) + p;
big = j >= N;
j(big) = p - 1 - j(big);
idx = j + 1;
end
