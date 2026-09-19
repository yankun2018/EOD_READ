function [out, mask, V] = oct_devessel(ef, varargin)
%OCT_DEVESSEL  en-face 上检测并抹掉血管投影阴影。
%   对应 exe 里的 enface_deVessel.m + graphcut_BW.m。
%
%   out = OCT_DEVESSEL(ef)
%   [out, mask, V] = OCT_DEVESSEL(ef, 'Name', value, ...)
%
%   ef   : en-face 投影（oct_enface 的输出）
%   out  : 抹掉血管后的 en-face
%   mask : 血管的二值掩膜
%   V    : Frangi 的血管性响应
%
%   视网膜血管会挡住下方的光，在 en-face 上留下树枝状的暗影。做厚度图、
%   反射率分析时这些影子是干扰项，得先去掉。流程：
%     1. Frangi 滤波找暗的管状结构（oct_frangi2d）
%     2. 二值化 + 清掉小连通块（对应 graphcut_BW.m 那一步，见下面的说明）
%     3. （可选）膨胀几个像素，把血管边缘的半影也圈进去
%     4. 掩膜内的像素用扩散填充补回来（各向同性，不留条纹）
%
%   关于 graphcut_BW.m：那个文件只有 1214 字节（约 30~40 行），
%   装不下一个完整的 max-flow/min-cut。从名字和体量看更像是"拿到血管性
%   响应之后做二值化 + 形态学清理"的一层包装，所以这里就按这个来实现。
%   真正的图割（能量最小化）没做 —— 名字对得上，内部实现不保证一致。
%
%   选项：
%     'Coverage'  目标覆盖率：按分位数取 Frangi 响应最高的这一部分当血管
%                 （默认 0.08，即 8%）。视网膜血管在 en-face 上典型占
%                 5~15% 的面积。Frangi 响应高度偏斜（实测中位 0、均值
%                 0.008、最大 1.0），按"相对最大值"设阈值极不稳 ——
%                 0.15*max 只圈到 0.85% 的像素，所以默认走分位数。
%     'Thresh'    改用"相对最大值"的阈值（0~1）。给了它就忽略 Coverage。
%     'MinArea'   小于这个面积的连通块当噪声丢掉（默认 10 像素）
%     'Dilate'    掩膜膨胀半径（默认 0，见下面代码里的权衡说明）
%     'Smooth'    填补后的平滑 sigma，0 = 不平滑（默认 1）
%     'Iter'       扩散填充的迭代轮数（默认 200，够填满几十像素宽的洞）
%     'Frangi'    透传给 oct_frangi2d 的选项 cell（默认 {}）
%     'Mask'      直接给掩膜，跳过检测（默认 []）
%
%   只用基础 MATLAB —— 形态学和连通域都是自己写的，不依赖工具箱。
%
%   参见 oct_enface, oct_frangi2d。

opt.Coverage = 0.10;
opt.Thresh   = [];
opt.MinArea  = 10;
% 膨胀默认关掉。实测两个指标会打架：
%   Dilate=2 时"残余血管性"降得最多（48% vs 38%），但掩膜涨到 16.8%，
%   把血管旁的正常组织也圈进去，填补后血管处比背景亮 6.5（过补偿）；
%   Dilate=0 时掩膜 7.8%（血管典型占 5~15%），亮度差只有 -0.39。
% 去血管是为了让后续定量不受血管干扰，亮度不失真比"抹得干净"更重要。
opt.Dilate  = 0;
opt.Smooth  = 1;
opt.Iter    = 200;
opt.Frangi  = {};
opt.Mask    = [];
opt = oct_parseopt(opt, varargin);

ef = double(ef);
[H, W] = size(ef);

% ---- 1) Frangi 找暗的管状结构 ----------------------------------------
if isempty(opt.Mask)
    V = oct_frangi2d(ef, 'BlackWhite', true, opt.Frangi{:});
    % ---- 2) 二值化 + 去小块 ----
    if ~isempty(opt.Thresh)
        thr = opt.Thresh * max(V(:));
    else
        % 分位数阈值：直接控制覆盖率，不用 prctile（那是统计工具箱的）
        sv = sort(V(:));
        k = max(1, min(numel(sv), round((1 - opt.Coverage) * numel(sv))));
        thr = sv(k);
    end
    mask = V > thr;
    if opt.MinArea > 0
        mask = local_area_open(mask, opt.MinArea);
    end
else
    mask = logical(opt.Mask);
    V = zeros(H, W);
end

% ---- 3) 膨胀，把血管边缘半影也圈进来 ----------------------------------
if opt.Dilate > 0
    mask = local_dilate(mask, opt.Dilate);
end

% ---- 4) 用掩膜外的邻域把血管位置填回来 -------------------------------
% 各向同性的扩散填充：把掩膜边界的值一圈一圈往里推。
% 一开始用的是逐列线性插值，快但有方向性 —— 填出来的补丁在 en-face 上
% 留下一道道横条纹，视觉上比血管还显眼。扩散没这个毛病。
out = local_inpaint(ef, mask, opt.Iter);

% 补丁和原图的接缝会有台阶，只在掩膜内抹一下
if opt.Smooth > 0
    sm = local_gauss2(out, opt.Smooth, opt.Smooth);
    out(mask) = sm(mask);
end
end

% ======================================================================
function out = local_inpaint(im, mask, iter)
%LOCAL_INPAINT  扩散式填补：反复用 8 邻域的有效像素均值填空洞。
out = im;
out(mask) = NaN;
if ~any(mask(:)), return; end

k = ones(3, 3); k(2, 2) = 0;          % 8 邻域
for t = 1:iter
    bad = isnan(out);
    if ~any(bad(:)), break; end
    v = out; v(bad) = 0;
    cnt = conv2(double(~bad), k, 'same');
    sm  = conv2(v, k, 'same');
    fillable = bad & (cnt > 0);
    if ~any(fillable(:)), break; end
    out(fillable) = sm(fillable) ./ cnt(fillable);
end
% 还没填上的（整块被围住）用全局背景兜底
left = isnan(out);
if any(left(:))
    bg = im(~mask);
    out(left) = mean(bg(isfinite(bg)));
end

% 填完再多做几轮"只在掩膜内"的平滑，让补丁内部平顺、接缝不突兀
for t = 1:3
    sm  = conv2(out, k/8, 'same');
    ed  = conv2(ones(size(out)), k/8, 'same');   % 边界归一化
    sm  = sm ./ max(ed, eps);
    out(mask) = sm(mask);
end
end

% ======================================================================
function m = local_dilate(m, r)
%LOCAL_DILATE  用圆形结构元膨胀（不依赖 imdilate）。
if r <= 0, return; end
[dx, dy] = meshgrid(-ceil(r):ceil(r), -ceil(r):ceil(r));
se = (dx.^2 + dy.^2) <= r^2;
m = conv2(double(m), double(se), 'same') > 0;
end

% ======================================================================
function m = local_area_open(m, minArea)
%LOCAL_AREA_OPEN  丢掉面积小于 minArea 的 8-连通块（不依赖 bwareaopen）。
[H, W] = size(m);
lab = zeros(H, W);
cur = 0;
% 用栈做泛洪，避免递归深度问题
for i = 1:H
    for j = 1:W
        if ~m(i, j) || lab(i, j) > 0, continue; end
        cur = cur + 1;
        stack = [i, j];
        px = zeros(0, 2);
        lab(i, j) = cur;
        while ~isempty(stack)
            p = stack(end, :); stack(end, :) = [];
            px(end+1, :) = p; %#ok<AGROW>
            for di = -1:1
                for dj = -1:1
                    a = p(1) + di; b = p(2) + dj;
                    if a < 1 || a > H || b < 1 || b > W, continue; end
                    if m(a, b) && lab(a, b) == 0
                        lab(a, b) = cur;
                        stack(end+1, :) = [a, b]; %#ok<AGROW>
                    end
                end
            end
        end
        if size(px, 1) < minArea
            for t = 1:size(px, 1)
                m(px(t,1), px(t,2)) = false;
            end
        end
    end
end
end

% ======================================================================
function out = local_gauss2(im, sy, sx)
%LOCAL_GAUSS2  可分离二维高斯，对称边界。
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

% ======================================================================
function out = local_conv2sym(im, k)
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
