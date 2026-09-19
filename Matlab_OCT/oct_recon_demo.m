function [bscans, cscan] = oct_recon_demo(varargin)
%OCT_RECON_DEMO  读原始光谱 -> 重建 -> 滚动显示 B-scan（可选 en-face C-scan）。
%
%   oct_recon_demo
%   oct_recon_demo('Name', value, ...)
%   [bscans, cscan] = oct_recon_demo(...)
%
%   对应 faster_3dim_scan_vulkan\main.cpp 里的 RunDemo0 / RunDemo1：
%     Mode = 'aline'  逐条 A-line 刷新一列，看得清每一步（= RunDemo0）
%     Mode = 'batch'  一次算一整幅 B-scan（= RunDemo1，MATLAB 下快得多，默认）
%   en-face 那一路是 RunDemo2 里被注释掉的 cscan_mat32 累加，这里补全了。
%
%   选项：
%     'File'         原始数据路径。默认找 vulkan 工程的 test2_16bit.raw，
%                    找不到就退回 octifft 的 CSV 并自动切到 'eod2048' 预设。
%     'Format'       透传给 oct_load_spectrum（默认 'auto'）。
%     'Preset'       oct_recon_params 的预设名（默认按 File 自动选）。
%     'Params'       直接给一个参数结构体，给了就忽略 'Preset'。
%     'BscanWidth'   每幅 B-scan 多少条 A-line（默认取自参数）。
%     'MaxBscans'    最多重建几幅（默认 20，Inf = 全部）。
%     'SkipLines'    从原文件第 SkipLines+1 条 A-line 开始（默认 0）。
%     'Range'        [首行 末行] A-line 闭区间，1-based；给了就覆盖
%                    SkipLines / MaxBscans。凑不满一整幅的尾巴会丢掉。
%     'Mode'         'batch'（默认）或 'aline'。
%     'ShowEnface'   true 时另开一个窗口累加 en-face（默认 true）。
%     'EnfaceMargin' en-face 投影时上下各裁掉多少行（C++ 里是 100，默认 100）。
%     'Pause'        每幅之间停顿秒数（默认 0.01）。
%     'Return'       true 时把所有 B-scan 收集到 bscans 里返回（默认 nargout>0）。
%
%   返回：
%     bscans  [depth x width x nBscan] 重建后的 log 幅度（未归一化）
%     cscan   [nBscan x width] en-face 投影
%
%   例：
%     oct_recon_demo('File', 'D:\data\test2_16bit.raw')
%     oct_recon_demo('Mode', 'aline', 'MaxBscans', 1)
%     oct_recon_demo('Preset', 'eod2048', 'BscanWidth', 500)
%     % 只重建第 2001 ~ 4000 条 A-line：
%     oct_recon_demo('Range', [2001 4000], 'BscanWidth', 500)
%
%   参见 oct_recon_params, oct_recon_pipeline, oct_show_spectrum。

[vulkanRaw, hasRaw] = oct_find_data('strawberry', 'Quiet', true);
[octiftCsv, hasCsv] = oct_find_data('spectrum',   'Quiet', true);

opt.File         = '';
opt.Format       = 'auto';
opt.Preset       = '';
opt.Params       = [];
opt.BscanWidth   = [];
opt.MaxBscans    = 20;
opt.SkipLines    = 0;
opt.Range        = [];
opt.Mode         = 'batch';
opt.ShowEnface   = true;
opt.EnfaceMargin = 100;
opt.Pause        = 0.01;
opt.Return       = [];
opt = oct_parseopt(opt, varargin);

% ---- 数据源 + 预设 ---------------------------------------------------
if isempty(opt.File)
    if hasRaw && exist(vulkanRaw, 'file')
        opt.File = vulkanRaw;
        if isempty(opt.Preset), opt.Preset = 'strawberry1664'; end
    elseif hasCsv && exist(octiftCsv, 'file')
        opt.File = octiftCsv;
        if isempty(opt.Preset), opt.Preset = 'eod2048'; end
        fprintf(['没找到 test2_16bit.raw，改用 octifft 的 CSV + ''eod2048'' 预设。\n' ...
                 '这份是单反射面在深度上来回扫的标定数据（不是组织），' ...
                 '约 26%% 的 A-line 量程内没有反射面。\n']);
    else
        error(['找不到默认数据。用 ''File'' 指一份：\n' ...
               '  %s\n  %s'], vulkanRaw, octiftCsv);
    end
end
if isempty(opt.Preset), opt.Preset = 'strawberry1664'; end

if isempty(opt.Params)
    p = oct_recon_params(opt.Preset);
else
    p = opt.Params;
end
if ~isempty(opt.BscanWidth)
    p.bscanWidth = opt.BscanWidth;
end

% ---- 读数据 ----------------------------------------------------------
% Range 给的是 A-line 区间，换算成 SkipLines + 幅数
skipLines = opt.SkipLines;
if ~isempty(opt.Range)
    if numel(opt.Range) ~= 2
        error('oct_recon_demo:range', '''Range'' 要给 [首行 末行] 两个数');
    end
    skipLines = opt.Range(1) - 1;
    if isfinite(opt.Range(2))
        nWant = opt.Range(2) - opt.Range(1) + 1;
        opt.MaxBscans = floor(nWant / p.bscanWidth);
        if opt.MaxBscans < 1
            error('oct_recon_demo:range', ...
                  ['Range 只有 %d 条 A-line，不够一幅 B-scan（需要 %d 条）。\n' ...
                   '把区间放大，或者用 ''BscanWidth'' 把每幅调窄。'], ...
                  nWant, p.bscanWidth);
        end
    else
        opt.MaxBscans = Inf;
    end
end
maxLines = Inf;
if isfinite(opt.MaxBscans)
    maxLines = opt.MaxBscans * p.bscanWidth;
end
fprintf('读取 %s ...\n', opt.File);
[data, info] = oct_load_spectrum(opt.File, 'Format', opt.Format, ...
    'AlineLength', p.alineLength, 'MaxLines', maxLines, 'SkipLines', skipLines);
fprintf('  %d 条 A-line x %d 点 (%s)，对应原文件第 %d ~ %d 行\n', ...
        info.nLine, info.nPoint, info.format, skipLines + 1, skipLines + info.nLine);

if info.nPoint ~= p.alineLength
    fprintf('  注意：数据宽度 %d 和预设的 alineLength %d 不一致，按数据来。\n', ...
            info.nPoint, p.alineLength);
    p.alineLength = info.nPoint;
end

nBscan = floor(size(data, 1) / p.bscanWidth);
if nBscan == 0
    error(['数据只有 %d 条 A-line，不够一幅 B-scan（需要 %d 条）。\n' ...
           '把 ''BscanWidth'' 调小试试。'], size(data, 1), p.bscanWidth);
end
if isfinite(opt.MaxBscans)
    nBscan = min(nBscan, opt.MaxBscans);
end

k = oct_recon_prep(p);
depth = p.alineLength;
if p.halfOnly, depth = floor(p.alineLength / 2); end

wantReturn = opt.Return;
if isempty(wantReturn), wantReturn = nargout > 0; end
if wantReturn
    bscans = zeros(depth, p.bscanWidth, nBscan);
else
    bscans = [];
end
cscan = zeros(nBscan, p.bscanWidth);

% ---- 窗口 ------------------------------------------------------------
figB = figure('Name', 'B-scan', 'NumberTitle', 'off', 'Color', 'k');
set(figB, 'Position', [60, 260, 900, 700]);
axB  = axes('Parent', figB);
imgB = imagesc(axB, zeros(depth, p.bscanWidth));
colormap(axB, gray(256));
axis(axB, 'image');
set(axB, 'XTick', [], 'YTick', []);
ttlB = title(axB, '', 'Color', 'w');

axC  = [];
imgC = [];
if opt.ShowEnface
    figC = figure('Name', 'en-face C-scan', 'NumberTitle', 'off', 'Color', 'k');
    set(figC, 'Position', [980, 260, 560, 560]);
    axC  = axes('Parent', figC);
    imgC = imagesc(axC, zeros(nBscan, p.bscanWidth));
    colormap(axC, gray(256));
    axis(axC, 'image');
    set(axC, 'XTick', [], 'YTick', []);
    title(axC, 'en-face', 'Color', 'w');
end

m = min(opt.EnfaceMargin, floor((depth - 1) / 2));
rows = (m + 1):(depth - m);

fprintf('重建 %d 幅 B-scan（%s 模式）...\n', nBscan, opt.Mode);
tic;

% ---- 主循环 ----------------------------------------------------------
nb = max(p.bgLines, 0);
for b = 1:nBscan
    if ~ishandle(figB), break; end
    r0 = (b - 1) * p.bscanWidth;

    switch lower(opt.Mode)
        case 'batch'
            % RunDemo1：整幅一起算。
            % 往前多喂 nb 条，让背景滑动平均能跨过 B-scan 边界，算完再丢掉。
            % C++ 的 RunDemo1/RunDemo2 是一个 batch 喂一次，背景窗口在每个
            % batch 的头部重置；这里如果按幅重置，第 2 幅往后整幅都会偏亮，
            % 而且和 'aline' 模式的结果对不上。垫一下两种模式就完全一致了。
            lo  = max(1, r0 + 1 - nb);
            pre = (r0 + 1) - lo;
            res = oct_recon_pipeline(data(lo:(r0 + p.bscanWidth), :), p, k);
            img = res(pre+1:end, :).';

        case 'aline'
            % RunDemo0：一条一条算、一列一列刷新
            img = zeros(depth, p.bscanWidth);
            for i = 1:p.bscanWidth
                r  = r0 + i;
                lo = max(1, r - nb);         % 带上前 nb 条，背景相减才有窗口
                one = oct_recon_pipeline(data(lo:r, :), p, k);
                img(:, i) = one(end, :).';
                set(imgB, 'CData', img);
                set(axB, 'CLim', local_clim(img));
                set(ttlB, 'String', sprintf('B-scan %d/%d  A-line %d/%d', ...
                                            b, nBscan, i, p.bscanWidth));
                drawnow limitrate;
            end

        otherwise
            error('oct_recon_demo:mode', '未知 Mode ''%s''', opt.Mode);
    end

    % 双向扫描：偶数幅左右翻转，跟 C++ 的 lr_swap 一样
    if p.flipAlternate && mod(b, 2) == 0
        img = fliplr(img);
    end

    if wantReturn
        bscans(:, :, b) = img;
    end

    set(imgB, 'CData', img);
    set(axB, 'CLim', local_clim(img));
    set(ttlB, 'String', sprintf('B-scan %d / %d', b, nBscan));

    % en-face：按列在深度方向求和，掐掉上下各 EnfaceMargin 行
    cscan(b, :) = sum(img(rows, :), 1);
    if opt.ShowEnface && ~isempty(axC) && ishandle(axC)
        set(imgC, 'CData', cscan);
        set(axC, 'CLim', local_clim(cscan(1:b, :)));
    end

    drawnow limitrate;
    if opt.Pause > 0, pause(opt.Pause); end
end

fprintf('完成，耗时 %.2f s\n', toc);
end

% ------------------------------------------------------------------
function c = local_clim(img)
% 和 C++ 的 minMaxIdx + convertTo 一样，按当前帧的动态范围拉满
lo = min(img(:));
hi = max(img(:));
if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
    c = [0 1];
else
    c = [lo hi];
end
end
