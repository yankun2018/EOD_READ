function [img, gt, info] = oct_layer_gt(path)
%OCT_LAYER_GT  从原 exe 输出的彩色叠加图里取回灰度 B-scan 和 7 条边界。
%
%   [img, gt] = OCT_LAYER_GT(path)
%   [img, gt, info] = OCT_LAYER_GT(path)
%
%   Desktop\pic_md 下那 120 张 PNG 是 EOD_read_seg.exe 的输出：B-scan 上
%   已经画好了 7 条分层线。每张 432 列，每条线在每列恰好一个纯色像素，
%   所以能把它们完整取回来当 ground truth 用。
%
%   img  : [H x W] 灰度 B-scan。彩线盖住的像素用同列上下邻域线性插值补回来。
%   gt   : 结构体，字段名和 oct_layer_seg 的输出一致（ilm/rnfl/.../rpe），
%          各是 1 x W。某列没有该颜色时是 NaN（末尾几张的 blue/green 会
%          走出图外，img_0117 的 blue 少了 46 列）。
%   info : .size .nFound 每层找到的列数 .colors 用到的 RGB
%
%   颜色与层的对应是按实测平均深度排的（由浅到深）：
%     红 ILM | 黄 RNFL/GCL | 品红 IPL/INL | 橙 INL/OPL
%     粉 OPL/ONL | 绿 IS/OS | 蓝 RPE/BM
%
%   参见 oct_layer_seg, oct_layer_demo。

if ~exist(path, 'file')
    error('oct_layer_gt:noFile', '找不到图: %s', path);
end

% 层序（由浅到深）、字段名、叠加线的 RGB
names  = {'ilm', 'rnfl', 'ipl', 'inl', 'opl', 'isos', 'rpe'};
colors = [255 0 0; 255 255 0; 255 0 255; 255 125 0; 255 0 125; 0 255 0; 0 0 255];

a = double(imread(path));
if ndims(a) ~= 3 || size(a,3) < 3 %#ok<ISMAT>
    error('oct_layer_gt:notRGB', '需要 RGB 图: %s', path);
end
a = a(:, :, 1:3);
[H, W, ~] = size(a);

mask = false(H, W);
gt = struct();
nFound = zeros(1, 7);
for i = 1:7
    c = colors(i, :);
    m = (a(:,:,1) == c(1)) & (a(:,:,2) == c(2)) & (a(:,:,3) == c(3));
    mask = mask | m;
    y = nan(1, W);
    [ys, xs] = find(m);
    for x = unique(xs).'
        y(x) = mean(ys(xs == x));     % 线有粗细时取该列的重心
    end
    gt.(names{i}) = y;
    nFound(i) = sum(~isnan(y));
end

% ---- 恢复灰度：彩线处按同列上下邻域插值补回来 ------------------------
g = mean(a, 3);
g(mask) = NaN;
rows = (1:H).';
for x = 1:W
    col = g(:, x);
    bad = isnan(col);
    if ~any(bad), continue; end
    good = ~bad;
    if ~any(good)
        col(:) = 0;
    else
        col(bad) = interp1(rows(good), col(good), rows(bad), 'linear', 'extrap');
    end
    g(:, x) = col;
end
img = g;

if nargout > 2
    info.size   = [H W];
    info.nFound = nFound;
    info.names  = names;
    info.colors = colors;
end
end
