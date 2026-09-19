function [rgb, cmap] = oct_thickness_rgb(T, varargin)
%OCT_THICKNESS_RGB  厚度地形图上色，按 OCT 报告的惯例（冷色薄、暖色厚）。
%
%   rgb = OCT_THICKNESS_RGB(T)
%   [rgb, cmap] = OCT_THICKNESS_RGB(T, 'Name', value, ...)
%
%   T    : 厚度图
%   rgb  : uint8 RGB 图
%   cmap : 用到的 256 色表（可以拿去画色条）
%
%   商用 OCT 的厚度地形图都是"冷色 = 薄、暖色 = 厚"：
%   深蓝 -> 青 -> 绿 -> 黄 -> 红 -> 白。绿色一般落在正常厚度附近。
%
%   选项：
%     'Range'   [lo hi] 映射区间，[] = 用数据的 2%~98% 分位（默认 []）
%     'Style'   'oct'（默认）报告那套冷到暖；'jet' 经典 jet；'gray' 灰度
%     'NaNColor' NaN 处的颜色（默认 [0 0 0]）
%
%   参见 oct_thickness_map, oct_significance_rgb, oct_report。

opt.Range    = [];
opt.Style    = 'oct';
opt.NaNColor = [0 0 0];
opt = oct_parseopt(opt, varargin);

T = double(T);
f = isfinite(T);
if ~any(f(:))
    rgb = repmat(uint8(reshape(opt.NaNColor, 1, 1, 3)), size(T,1), size(T,2));
    cmap = zeros(256, 3);
    return;
end

if isempty(opt.Range)
    v = sort(T(f));
    lo = v(max(1, round(0.02*numel(v))));
    hi = v(max(1, round(0.98*numel(v))));
else
    lo = opt.Range(1); hi = opt.Range(2);
end
if hi <= lo, hi = lo + 1; end

cmap = local_cmap(opt.Style);
n = size(cmap, 1);

idx = round((T - lo) / (hi - lo) * (n-1)) + 1;
idx = min(max(idx, 1), n);
idx(~f) = 1;

R = reshape(cmap(idx, 1), size(T));
G = reshape(cmap(idx, 2), size(T));
B = reshape(cmap(idx, 3), size(T));
R(~f) = opt.NaNColor(1);
G(~f) = opt.NaNColor(2);
B(~f) = opt.NaNColor(3);

rgb = uint8(round(cat(3, R, G, B) * 255));
end

% ======================================================================
function c = local_cmap(style)
switch lower(style)
    case 'oct'
        % 报告上那套：深蓝 -> 青 -> 绿 -> 黄 -> 红 -> 白
        key = [0.00  0.00 0.00 0.30
               0.18  0.00 0.45 0.90
               0.36  0.00 0.85 0.85
               0.52  0.10 0.75 0.20
               0.68  0.95 0.95 0.10
               0.86  0.90 0.15 0.05
               1.00  1.00 1.00 1.00];
    case 'jet'
        key = [0.000 0.00 0.00 0.55
               0.125 0.00 0.00 1.00
               0.375 0.00 1.00 1.00
               0.625 1.00 1.00 0.00
               0.875 1.00 0.00 0.00
               1.000 0.55 0.00 0.00];
    case 'gray'
        key = [0 0 0 0; 1 1 1 1];
    otherwise
        error('oct_thickness_rgb:style', '未知 Style ''%s''', style);
end
x = linspace(0, 1, 256).';
c = [interp1(key(:,1), key(:,2), x, 'linear'), ...
     interp1(key(:,1), key(:,3), x, 'linear'), ...
     interp1(key(:,1), key(:,4), x, 'linear')];
c = min(max(c, 0), 1);
end
