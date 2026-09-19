function [grade, pooled, info] = oct_deviation_map(T, varargin)
%OCT_DEVIATION_MAP  厚度偏差图，对应 Analy_and_image_show\oct_DeviationMap.py。
%
%   grade = OCT_DEVIATION_MAP(T)
%   [grade, pooled, info] = OCT_DEVIATION_MAP(T, 'Name', value, ...)
%
%   T      : 厚度图（oct_thickness_map 的输出）
%   pooled : [Grid x Grid] 池化后的平均厚度
%   grade  : [Grid x Grid] 偏差分级（见 'Levels'）
%
%   把厚度图池化成粗网格，再和参考厚度比，按偏离比例分级 —— 临床上那种
%   "偏差图 / deviation map"。原脚本固定 24x24（每块 5x18，对应 120x432）。
%
%   选项：
%     'Grid'      池化网格边长（默认 24）
%     'Ref'       参考厚度。'median'（默认）= 用这份数据自己的中位数；
%                 也可以直接给一个数（单位同 T）。
%                 原脚本写死 nom_thickness = 28，那个值配它自己算错的
%                 厚度（144 um / 59 px）都不对，全图会被判成"偏差 >99%"。
%     'Levels'    分级阈值（相对偏差，默认 [0.05 0.10 0.25 0.50]）。
%                 grade 取 1..numel(Levels)+1，1 = 最接近参考值。
%     'Unit'      仅用于 info 里记录（默认 'um'）
%
%   info : .ref .levels .grid .blockSize .pooledMedian .fracByLevel
%
%   原脚本的分级判据有个死分支：
%       if   >0.99  -> 99
%       elseif >0.95 -> 95
%       elseif >0.5  -> 10
%       elseif >1    -> 5        % 永远走不到：>1 的早被第一条抓走了
%       else         -> 1
%   这里换成一组从小到大、可配置的阈值。
%
%   参见 oct_thickness_map, oct_analy_demo。

opt.Grid   = 24;
opt.Ref    = 'median';
opt.Levels = [0.05 0.10 0.25 0.50];
opt.Unit   = 'um';
opt = oct_parseopt(opt, varargin);

T = double(T);
[H, W] = size(T);
g = opt.Grid;
if g < 1 || g > min(H, W)
    error('oct_deviation_map:grid', '''Grid'' 要在 1~%d 之间，给的是 %d', min(H,W), g);
end

bh = floor(H / g);
bw = floor(W / g);
if bh < 1 || bw < 1
    error('oct_deviation_map:tooSmall', ...
          '厚度图 %dx%d 撑不起 %dx%d 的网格', H, W, g, g);
end

% 池化（忽略 NaN；整块都是 NaN 就留 NaN）
pooled = nan(g, g);
for i = 1:g
    rows = (i-1)*bh + (1:bh);
    for j = 1:g
        cols = (j-1)*bw + (1:bw);
        blk = T(rows, cols);
        blk = blk(isfinite(blk));
        if ~isempty(blk), pooled(i, j) = mean(blk); end
    end
end

% 参考厚度
if ischar(opt.Ref) || isstring(opt.Ref)
    if ~strcmpi(opt.Ref, 'median')
        error('oct_deviation_map:ref', '''Ref'' 只能是 ''median'' 或一个数');
    end
    v = pooled(isfinite(pooled));
    if isempty(v)
        error('oct_deviation_map:allNaN', '池化之后全是 NaN');
    end
    ref = median(v);
else
    ref = double(opt.Ref);
    if ~isfinite(ref) || ref == 0
        error('oct_deviation_map:ref', '参考厚度要是个非 0 的有限数');
    end
end

% 分级
lv = sort(opt.Levels(:).');
rel = abs(pooled - ref) / abs(ref);
grade = ones(g, g);
for k = 1:numel(lv)
    grade(rel > lv(k)) = k + 1;
end
grade(~isfinite(pooled)) = NaN;

if nargout > 2
    info.ref          = ref;
    info.levels       = lv;
    info.grid         = g;
    info.blockSize    = [bh bw];
    info.unit         = opt.Unit;
    info.pooledMedian = median(pooled(isfinite(pooled)));
    fr = zeros(1, numel(lv)+1);
    tot = sum(isfinite(grade(:)));
    for k = 1:numel(lv)+1
        fr(k) = sum(grade(:) == k) / max(tot, 1);
    end
    info.fracByLevel = fr;
end
end
