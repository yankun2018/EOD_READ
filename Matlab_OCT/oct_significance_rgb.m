function [rgb, band, info] = oct_significance_rgb(T, varargin)
%OCT_SIGNIFICANCE_RGB  厚度显著性图（偏差图），按 OCT 报告的白/绿/黄/红。
%
%   rgb = OCT_SIGNIFICANCE_RGB(T)
%   [rgb, band, info] = OCT_SIGNIFICANCE_RGB(T, 'Name', value, ...)
%
%   T    : 厚度图
%   band : 每个像素落在哪个带（1=红 2=黄 3=绿 4=白，NaN 处是 NaN）
%   rgb  : 上色结果
%
%   商用 OCT 的显著性图（significance / deviation map）用的是固定四色：
%       红   最薄的 1%     （< 1 百分位）
%       黄   1~5 百分位    （4%）
%       绿   5~95 百分位   （正常那 90%）
%       白   最厚的 5%     （> 95 百分位）
%   这四档是相对**正常人群数据库**的百分位，不是相对本次测量。
%
%   所以 'Norm' 这个参数是关键：
%     * 给了正常库（每区/每像素的均值和标准差）才是真正的临床显著性图；
%     * 不给的话只能退化成"相对本次扫描自己的分布"，那画出来是
%       "这只眼睛内部哪里相对薄/厚"，**不能当诊断用**。默认就是这个退化
%       模式，会在 info.mode 里标成 'self'。
%
%   选项：
%     'Norm'    正常库。可以是
%                 []                 退化模式（默认）
%                 [mu sigma]         全图统一的均值和标准差
%                 struct('mu',M,'sigma',S)  逐像素的图（和 T 同尺寸）
%     'Pct'     分位阈值（默认 [1 5 95]，对应红/黄/绿-白的分界）
%     'NaNColor' NaN 处的颜色（默认 [0 0 0]）
%
%   info : .mode('self'|'norm') .thresholds .fracByBand .colors
%
%   参见 oct_thickness_map, oct_etdrs_grid, oct_report。

opt.Norm     = [];
opt.Pct      = [1 5 95];
opt.NaNColor = [0 0 0];
opt = oct_parseopt(opt, varargin);

T = double(T);
f = isfinite(T);
band = nan(size(T));

% 四色：红、黄、绿、白
COL = [0.85 0.10 0.10;      % 1 红  最薄 1%
       0.95 0.85 0.15;      % 2 黄  1~5%
       0.15 0.70 0.25;      % 3 绿  5~95%
       1.00 1.00 1.00];     % 4 白  最厚 5%

if isempty(opt.Norm)
    % 退化模式：按本次测量自己的分位
    mode = 'self';
    v = sort(T(f));
    if isempty(v), error('oct_significance_rgb:allNaN', '厚度图全是 NaN'); end
    q = @(p) v(min(numel(v), max(1, round(p/100*numel(v)))));
    thr = [q(opt.Pct(1)), q(opt.Pct(2)), q(opt.Pct(3))];
    band(f & T <  thr(1))               = 1;
    band(f & T >= thr(1) & T < thr(2))  = 2;
    band(f & T >= thr(2) & T <= thr(3)) = 3;
    band(f & T >  thr(3))               = 4;
else
    % 正常库模式：算 z 分数再按正态分位切
    mode = 'norm';
    if isstruct(opt.Norm)
        mu = double(opt.Norm.mu); sg = double(opt.Norm.sigma);
        if ~isequal(size(mu), size(T)) || ~isequal(size(sg), size(T))
            error('oct_significance_rgb:normSize', ...
                  '逐像素正常库的 mu/sigma 要和厚度图同尺寸');
        end
    else
        if numel(opt.Norm) ~= 2
            error('oct_significance_rgb:norm', ...
                  '''Norm'' 要是 [mu sigma] 或 struct(''mu'',..,''sigma'',..)');
        end
        mu = opt.Norm(1); sg = opt.Norm(2);
    end
    if any(sg(:) <= 0), error('oct_significance_rgb:sigma', 'sigma 要为正'); end
    z = (T - mu) ./ sg;
    % 正态分位点：1% -> -2.326，5% -> -1.645，95% -> +1.645
    zt = local_norminv(opt.Pct / 100);
    thr = zt;
    band(f & z <  zt(1))              = 1;
    band(f & z >= zt(1) & z < zt(2))  = 2;
    band(f & z >= zt(2) & z <= zt(3)) = 3;
    band(f & z >  zt(3))              = 4;
end

% 上色
R = zeros(size(T)); G = R; B = R;
for k = 1:4
    m = (band == k);
    R(m) = COL(k,1); G(m) = COL(k,2); B(m) = COL(k,3);
end
nf = ~f;
R(nf) = opt.NaNColor(1); G(nf) = opt.NaNColor(2); B(nf) = opt.NaNColor(3);
rgb = uint8(round(cat(3, R, G, B) * 255));

if nargout > 2
    tot = sum(isfinite(band(:)));
    fr = zeros(1, 4);
    for k = 1:4, fr(k) = sum(band(:) == k) / max(tot, 1); end
    info.mode        = mode;
    info.thresholds  = thr;
    info.fracByBand  = fr;
    info.bandNames   = {'红 最薄1%', '黄 1~5%', '绿 5~95%', '白 最厚5%'};
    info.colors      = COL;
end
end

% ======================================================================
function z = local_norminv(p)
%LOCAL_NORMINV  标准正态分位函数（norminv 要统计工具箱，这里自己算）。
% 用 erfinv：z = sqrt(2) * erfinv(2p - 1)
z = sqrt(2) * erfinv(2*double(p) - 1);
end
