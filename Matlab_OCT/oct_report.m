function out = oct_report(varargin)
%OCT_REPORT  生成一张 OCT 黄斑分析报告图（对着商用报告的排版做的）。
%
%   out = OCT_REPORT
%   out = OCT_REPORT('Name', value, ...)
%
%   一张图里放六块，都是眼科 OCT 报告上的标准内容：
%     1  厚度地形图        伪彩色，冷色薄暖色厚
%     2  ETDRS 九分区靶心图 三个同心圆（1/3/6 mm）+ 各区平均厚度
%     3  显著性图          白/绿/黄/红四带
%     4  en-face C-scan    看血管和中心凹位置
%     5  过中心凹的 B-scan  带 7 条分层线
%     6  厚度剖面曲线      过中心凹的水平和垂直切线
%
%   选项：
%     'Vol'     原始体数据（默认 test_data 下那份）
%     'Analy'   分层结果，或 'seg' 表示现场分层（默认 test_data 下那份）
%     'Eye'     'OD'（默认）/ 'OS'，决定靶心图上鼻/颞的方向
%     'Top'/'Bot'  厚度用哪两层（默认 ilm -> rpe 全层）
%     'PixY'/'PixX'  两个横向的像素间距，mm（默认 6/120 和 6/432）
%     'Range'   厚度色标区间，[] = 按数据 2%~98% 分位（默认 []）
%     'Norm'    正常库，透传给 oct_significance_rgb。不给就是相对自身
%               的分位（只能看"这只眼内部哪里相对薄"，不能当诊断）
%     'Show'    开窗（默认 true）
%     'Save'    保存报告图的路径，'' = 不存（默认 ''）
%
%   out : .etdrs .thickness .cscan .fovea .sig
%
%   参见 oct_etdrs_grid, oct_thickness_rgb, oct_significance_rgb。

opt.Vol   = '';            % 空 = 用 oct_find_data 自动找
opt.Analy = '';
opt.Eye   = 'OD';
opt.Top   = 'ilm';
opt.Bot   = 'rpe';
opt.PixY  = 6/120;
opt.PixX  = 6/432;
opt.Range = [];
opt.Norm  = [];
opt.Show  = true;
opt.Save  = '';
opt = oct_parseopt(opt, varargin);

% ---- 数据 ------------------------------------------------------------
if isempty(opt.Vol), opt.Vol = oct_find_data('volume'); end
if isempty(opt.Analy) && ~strcmpi(opt.Analy, 'seg')
    opt.Analy = oct_find_data('analy');
end
[vol, vi] = oct_volume_read(opt.Vol);
if strcmpi(opt.Analy, 'seg')
    bd = cell(1, vi.nBscan);
    for i = 1:vi.nBscan, bd{i} = oct_layer_seg(vol(:,:,i)); end
else
    bd = oct_layer_import(opt.Analy, 'Depth', vi.depth);
end
if isstruct(bd), bd = num2cell(bd); end

T = oct_thickness_map(bd, 'Top', opt.Top, 'Bot', opt.Bot);
cscan = squeeze(sum(vol, 1)).';

res = oct_etdrs_grid(T, 'Eye', opt.Eye, 'PixY', opt.PixY, 'PixX', opt.PixX);
cy = res.center(1); cx = res.center(2);

% 色标区间：地形图和靶心图共用一套，这样两张图能对着看
rng = opt.Range;
if isempty(rng)
    v = sort(T(isfinite(T)));
    rng = [v(max(1,round(0.02*numel(v)))), v(max(1,round(0.98*numel(v))))];
end

% 拉成正方形（扫描是 6x6 mm，采样却是 120 x 432）
side = size(T, 2);
ri = min(size(T,1), max(1, ceil((1:side)/side*size(T,1))));
Tsq = T(ri, :);
Csq = cscan(ri, :);

topo = oct_thickness_rgb(Tsq, 'Range', rng);
[sigRgb, ~, si] = oct_significance_rgb(Tsq, 'Norm', opt.Norm);
bull = oct_etdrs_rgb(res, 'Range', rng);

iy = min(max(round(cy),1), size(T,1));
ix = min(max(round(cx),1), size(T,2));
bscan = local_bscan_rgb(vol(:,:,iy), bd{iy});

out.etdrs = res; out.thickness = T; out.cscan = cscan;
out.fovea = [cy cx]; out.sig = si; out.range = rng;

% ---- 打印数字（报告的文字部分）--------------------------------------
fprintf('\n================ OCT 黄斑分析 ================\n');
fprintf('眼别 %s   扫描 %.1f x %.1f mm   %d 幅 x %d A-line x %d 深度\n', ...
        res.eye, opt.PixY*vi.nBscan, opt.PixX*vi.nAline, ...
        vi.nBscan, vi.nAline, vi.depth);
fprintf('厚度定义 %s -> %s\n', opt.Top, opt.Bot);
fprintf('中心凹位置 (B-scan %.1f, A-line %.1f)\n', cy, cx);
fprintf('----------------------------------------------\n');
fprintf('中心点厚度      %6.1f um\n', res.centerPoint);
fprintf('中心区 (1mm)    %6.1f um\n', res.mean(1));
fprintf('6mm 圆内平均    %6.1f um\n', res.avgAll);
fprintf('体积 1/3/6 mm   %.3f / %.3f / %.3f mm^3\n', res.volume);
fprintf('----------------------------------------------\n');
fprintf('        上      鼻      下      颞\n');
fprintf('内环  %6.1f  %6.1f  %6.1f  %6.1f\n', res.mean(2:5));
fprintf('外环  %6.1f  %6.1f  %6.1f  %6.1f\n', res.mean(6:9));
fprintf('----------------------------------------------\n');
if ~res.covered
    fprintf('注意：6mm 外环超出扫描范围，外环统计不完整\n');
end
if strcmp(si.mode, 'self')
    fprintf('注意：显著性图是相对本次扫描自身的分位（没给正常库），\n');
    fprintf('      只能看这只眼内部哪里相对薄/厚，不能当诊断依据。\n');
end
fprintf('==============================================\n\n');

% ---- 排版 ------------------------------------------------------------
if opt.Show || ~isempty(opt.Save)
    fig = figure('Name', 'OCT 黄斑分析报告', 'NumberTitle', 'off', ...
                 'Color', [0.08 0.08 0.10]);
    set(fig, 'Position', [40, 40, 1320, 840]);
    if ~opt.Show, set(fig, 'Visible', 'off'); end

    tc = [0.92 0.92 0.92];
    % 1 地形图
    ax = axes('Parent', fig, 'Position', [0.035 0.53 0.27 0.40]);
    image(ax, topo); axis(ax,'image'); set(ax,'XTick',[],'YTick',[]);
    title(ax, sprintf('厚度地形图  %s->%s (%.0f~%.0f um)', ...
          opt.Top, opt.Bot, rng(1), rng(2)), 'Color', tc, 'FontSize', 9);
    local_colorbar(fig, [0.035 0.505 0.27 0.016], rng);

    % 2 靶心图
    ax = axes('Parent', fig, 'Position', [0.345 0.53 0.27 0.40]);
    image(ax, bull); axis(ax,'image'); set(ax,'XTick',[],'YTick',[]);
    title(ax, sprintf('ETDRS 九分区 (%s, 1/3/6 mm)', res.eye), ...
          'Color', tc, 'FontSize', 9);

    % 3 显著性图
    ax = axes('Parent', fig, 'Position', [0.655 0.53 0.27 0.40]);
    image(ax, sigRgb); axis(ax,'image'); set(ax,'XTick',[],'YTick',[]);
    title(ax, sprintf('显著性图 (%s)', si.mode), 'Color', tc, 'FontSize', 9);
    local_siglegend(fig, [0.655 0.495 0.27 0.028], si);

    % 4 C-scan
    ax = axes('Parent', fig, 'Position', [0.035 0.06 0.27 0.38]);
    imagesc(ax, Csq); colormap(ax, gray(256)); axis(ax,'image');
    set(ax,'XTick',[],'YTick',[]); hold(ax,'on');
    plot(ax, cx, cy*side/size(T,1), 'r+', 'MarkerSize', 10, 'LineWidth', 1.2);
    hold(ax,'off');
    title(ax, 'en-face C-scan（红十字 = 中心凹）', 'Color', tc, 'FontSize', 9);

    % 5 B-scan
    ax = axes('Parent', fig, 'Position', [0.345 0.06 0.27 0.38]);
    image(ax, bscan); axis(ax,'image'); set(ax,'XTick',[],'YTick',[]);
    title(ax, sprintf('过中心凹的 B-scan（第 %d 幅）', iy), ...
          'Color', tc, 'FontSize', 9);

    % 6 厚度剖面
    ax = axes('Parent', fig, 'Position', [0.665 0.09 0.26 0.33]);
    xs = ((1:size(T,2)) - cx) * opt.PixX;
    ys = ((1:size(T,1)) - cy) * opt.PixY;
    plot(ax, xs, T(iy,:), '-', 'Color', [0.30 0.70 1.00], 'LineWidth', 1.1);
    hold(ax,'on');
    plot(ax, ys, T(:,ix), '-', 'Color', [1.00 0.60 0.25], 'LineWidth', 1.1);
    hold(ax,'off');
    set(ax, 'Color', [0.14 0.14 0.17], 'XColor', tc, 'YColor', tc, ...
            'GridColor', [0.4 0.4 0.4]);
    grid(ax,'on'); xlabel(ax, '距中心凹 (mm)', 'Color', tc, 'FontSize', 8);
    ylabel(ax, sprintf('厚度 (um)'), 'Color', tc, 'FontSize', 8);
    legend(ax, {'水平', '垂直'}, 'TextColor', tc, 'Color', [0.14 0.14 0.17], ...
           'EdgeColor', [0.4 0.4 0.4], 'FontSize', 8, 'Location', 'south');
    title(ax, '厚度剖面', 'Color', tc, 'FontSize', 9);

    % 顶部文字
    annotation(fig, 'textbox', [0.02 0.955 0.96 0.04], 'String', ...
        sprintf(['OCT 黄斑分析  |  %s  |  中心点 %.0f um  |  中心区 %.0f um  |  ' ...
                 '6mm 平均 %.0f um  |  体积 %.2f mm^3'], ...
                res.eye, res.centerPoint, res.mean(1), res.avgAll, res.volume(3)), ...
        'Color', tc, 'FontSize', 11, 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center');

    if ~isempty(opt.Save)
        exportgraphics(fig, opt.Save, 'Resolution', 130, ...
                       'BackgroundColor', [0.08 0.08 0.10]);
        fprintf('报告图已存到 %s\n', opt.Save);
    end
    if ~opt.Show, close(fig); end
end
end

% ======================================================================
function local_colorbar(fig, pos, rng)
ax = axes('Parent', fig, 'Position', pos);
[~, cmap] = oct_thickness_rgb([0 1], 'Range', [0 1]);
image(ax, permute(uint8(round(cmap*255)), [3 1 2]));
set(ax, 'XTick', [1 128 256], ...
        'XTickLabel', {sprintf('%.0f', rng(1)), ...
                       sprintf('%.0f', mean(rng)), ...
                       sprintf('%.0f', rng(2))}, ...
        'YTick', [], 'XColor', [0.92 0.92 0.92], 'FontSize', 7);
end

% ======================================================================
function local_siglegend(fig, pos, si)
ax = axes('Parent', fig, 'Position', pos);
strip = reshape(si.colors, [1 4 3]);
image(ax, uint8(round(strip*255)));
lbl = {'<1%', '1-5%', '5-95%', '>95%'};
set(ax, 'XTick', 1:4, 'XTickLabel', lbl, 'YTick', [], ...
        'XColor', [0.92 0.92 0.92], 'FontSize', 7);
end

% ======================================================================
function rgb = local_bscan_rgb(b, bd)
names = {'ilm','rnfl','ipl','inl','opl','isos','rpe'};
cols  = uint8([255 0 0; 255 255 0; 255 0 255; 255 125 0; 255 0 125; 0 255 0; 0 0 255]);
g = double(b);
lo = min(g(:)); hi = max(g(:));
if hi <= lo, hi = lo + 1; end
u = uint8((g - lo)/(hi - lo)*255);
rgb = repmat(u, 1, 1, 3);
[H, W] = size(u);
for k = 1:7
    if ~isfield(bd, names{k}), continue; end
    y = bd.(names{k});
    for x = 1:min(W, numel(y))
        r = round(y(x));
        if ~isfinite(r) || r < 1 || r > H, continue; end
        rgb(r,x,1) = cols(k,1); rgb(r,x,2) = cols(k,2); rgb(r,x,3) = cols(k,3);
    end
end
end
