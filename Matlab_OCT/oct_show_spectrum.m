function oct_show_spectrum(varargin)
%OCT_SHOW_SPECTRUM  逐条滚动显示原始光谱，等价于 image.gif 那个窗口。
%
%   OCT_SHOW_SPECTRUM
%   OCT_SHOW_SPECTRUM('Name', value, ...)
%
%   对应 Spectrum_read\read_all_bin.cpp 那个循环里的几个 OpenCV 窗口：
%       "光谱"            -> 原始光谱（仓库根目录 image.gif 就是这个窗口的录屏）
%       "减去背景光谱"    -> 减掉前 32 条滑动平均后的干涉条纹
%       "插值后光谱"      -> k 域重采样后的光谱      ('ShowKlin')
%       "光谱FFT_log"     -> 重建出来的那条 A-line   ('ShowAline')
%       "BSCAN_ALINE_TIME"-> A-line 逐列堆成的滚动 B-scan ('ShowBscan')
%   后两个默认是关的，打开就能一边看光谱一边看 B-scan 长出来。
%
%   选项：
%     'File'        数据路径，默认指向 octifft 那份 5951 x 2048 的 CSV。
%     'Format'      透传给 oct_load_spectrum（默认 'auto'）。
%     'AlineLength' 非 CSV 格式时必须给（默认 1664）。
%     'MaxLines'    最多读多少条（默认 600，全读 48 MB 的 CSV 会慢）。
%     'SkipLines'   先跳过多少条（默认 0）。
%     'Range'       [首行 末行]，1-based 闭区间，比 SkipLines/MaxLines 直观；
%                   给了就覆盖那两个。末行给 Inf = 读到文件尾。
%     'BgWindow'    背景滑动平均的条数，0 = 不显示这一路（默认 32，同 C++）。
%     'ShowKlin'    true 时再画一路 k 域插值后的光谱（默认 false）。
%     'ShowAline'   true 时再画一路重建后的 A-line，即 "光谱FFT_log"（默认 false）。
%     'ShowBscan'   true 时另开一个窗口，把 A-line 逐列堆成滚动 B-scan（默认 false）。
%     'BscanCols'   滚动 B-scan 的宽度，写满就回到第一列（默认 1000，同 C++）。
%     'BscanNorm'   B-scan 的灰度归一化方式：
%                   'range'   （默认）先把整个显示区间批量重建好，用这一整块的
%                             min/max 统一归一化。和 oct_recon_demo/"草莓"那版
%                             一个路子，图像不会被逐条拉噪声。
%                   'aline'   每条 A-line 按自己的 min/max 拉满，即 C++
%                             BSCAN_ALINE_TIME 的原始行为（噪声会被放大）。
%                   'running' 随着列填进来，用"已填部分"的 min/max 动态调。
%     'Params'      重建用的参数结构体，默认 oct_recon_params('eod2048')。
%                   ShowKlin / ShowAline / ShowBscan 都用它。
%     'Pause'       每帧停顿秒数（默认 0.02）。
%     'YLim'        纵轴范围，[] 表示按数据自动取（默认 []）。
%     'Style'       'gif'  黑底白线、超扁，复刻 image.gif 的观感（默认）
%                   'plot' 常规带坐标轴的白底图，方便读数
%     'SaveGif'     输出 gif 的路径，'' 表示不存（默认 ''）。
%                   只存光谱那个窗口，B-scan 窗口不进 gif。
%
%   例：
%     oct_show_spectrum                                  % 只看光谱，同 image.gif
%     oct_show_spectrum('MaxLines', 200, 'Style', 'plot')
%     % 光谱 + 重建的 A-line + 滚动 B-scan 一起看：
%     oct_show_spectrum('ShowAline', true, 'ShowBscan', true, 'MaxLines', 1200)
%     % 只看第 2001 ~ 2500 行：
%     oct_show_spectrum('Range', [2001 2500], 'ShowBscan', true)
%     oct_show_spectrum('File', '../test_data/bin', 'AlineLength', 2048)
%     oct_show_spectrum('File', 'D:\data\test2_16bit.raw', 'AlineLength', 1664, ...
%                       'Params', oct_recon_params('strawberry1664'), 'ShowBscan', true)
%
%   想一次算一整幅、还要 en-face 的话用 oct_recon_demo，那个快得多。
%
%   参见 oct_load_spectrum, oct_recon_demo, oct_recon_pipeline。

opt.File        = '';      % 空 = 用 oct_find_data('spectrum') 自动找
opt.Format      = 'auto';
opt.AlineLength = 1664;
opt.MaxLines    = 600;
opt.SkipLines   = 0;
opt.Range       = [];
opt.BgWindow    = 32;
opt.ShowKlin    = false;
opt.ShowAline   = false;
opt.ShowBscan   = false;
opt.BscanCols   = 1000;
opt.BscanNorm   = 'range';
opt.Params      = [];
opt.Pause       = 0.02;
opt.YLim        = [];
opt.Style       = 'gif';
opt.SaveGif     = '';
opt = oct_parseopt(opt, varargin);

if isempty(opt.File), opt.File = oct_find_data('spectrum'); end
if ~exist(opt.File, 'file')
    % 注意用 '%s' 占位而不是把路径直接拼进格式串 —— 路径里的反斜杠
    % 会被 error/sprintf 当成转义（\U 之类会报警告甚至吞掉字符）
    error('oct_show_spectrum:noFile', ...
          ['找不到数据: %s\n' ...
           '光谱数据应该在 data\\spectrum\\ 下，或者用 ''File'' 直接指一份'], ...
          opt.File);
end

% 需要重建时，往前多读 bgLines 条当背景滑动窗口的上下文，算完丢掉。
% 不然区间头部那几条没减背景，B-scan 左边会有一条明显偏亮的竖带。
needRecon0 = opt.ShowKlin || opt.ShowAline || opt.ShowBscan;
if isempty(opt.Range), first = opt.SkipLines + 1; else, first = opt.Range(1); end
padLines = 0;
if needRecon0
    % 先拿一份默认参数问一下 bgLines 有多少（真正的 p 要等知道 N 才定）
    pTmp = opt.Params;
    if isempty(pTmp), pTmp = oct_recon_params('eod2048'); end
    padLines = min(max(pTmp.bgLines, 0), first - 1);
end

fprintf('读取 %s ...\n', opt.File);
if isempty(opt.Range)
    loadArgs = {'MaxLines', opt.MaxLines + padLines, ...
                'SkipLines', opt.SkipLines - padLines};
else
    lastWanted = opt.Range(2);
    loadArgs = {'Range', [first - padLines, lastWanted]};
end
[raw, info] = oct_load_spectrum(opt.File, ...
    'Format', opt.Format, 'AlineLength', opt.AlineLength, loadArgs{:});

pre  = min(padLines, max(size(raw, 1) - 1, 0));   % 实际拿到的前置行数
data = raw(pre+1:end, :);                         % 要显示的那一段
fprintf('  %d 条 A-line x %d 点 (%s)，对应原文件第 %d ~ %d 行', ...
        size(data,1), info.nPoint, info.format, first, first + size(data,1) - 1);
if pre > 0
    fprintf('（另读了前 %d 条做背景上下文）', pre);
end
fprintf('\n');

[nLine, N] = size(data);
if nLine == 0
    % 最常见的原因是 Range/SkipLines 超出了文件的实际条数
    tot = size(oct_load_spectrum(opt.File, 'Format', opt.Format, ...
                                 'AlineLength', opt.AlineLength), 1);
    error('oct_show_spectrum:empty', ...
          ['没读到数据。%s 一共 %d 条 A-line，' ...
           '但请求的是第 %d 条往后（Range/SkipLines 超出范围了）'], ...
          opt.File, tot, first);
end

% ---- 各路曲线 -------------------------------------------------------
panels = {'原始光谱'};
if opt.BgWindow > 0
    panels{end+1} = sprintf('减去背景（滑动 %d 条）', opt.BgWindow);
end
if opt.ShowKlin
    panels{end+1} = 'k 域插值后';
end
alinePanel = 0;
if opt.ShowAline
    panels{end+1} = '重建后的 A-line (log)';
    alinePanel = numel(panels);     % 这一路的横轴是深度，不是采样点
end
nPanel = numel(panels);

% ShowKlin / ShowAline / ShowBscan 都要重建参数
needRecon = needRecon0;
p = opt.Params; kin = [];
if needRecon
    if isempty(p)
        % 按数据宽度挑一个合适的预设
        if N == 1664, p = oct_recon_params('strawberry1664');
        else,         p = oct_recon_params('eod2048');
        end
    end
    p.alineLength = N;
    kin = oct_recon_prep(p);
    nbBg = max(p.bgLines, 0);
    depth = N;
    if p.halfOnly, depth = floor(N / 2); end
end

% ---- 画布 -----------------------------------------------------------
isGifStyle = strcmpi(opt.Style, 'gif');
fig = figure('Name', 'OCT 光谱', 'NumberTitle', 'off', 'Color', 'k');
if isGifStyle
    % image.gif 是 2344 x 480，整体很扁
    set(fig, 'Position', [80, 300, 1172, 160 * nPanel]);
else
    set(fig, 'Color', 'w', 'Position', [80, 200, 1000, 260 * nPanel]);
end

ax = gobjects(nPanel, 1);
h  = gobjects(nPanel, 1);
x  = 1:N;
% 不用 subplot：它会删掉位置和新面板重叠的已有 axes，而下面又要手动摆位置，
% 面板数一多（4 个）就会把前面的 axes 干掉。直接建 axes 最省事。
for k = 1:nPanel
    if isGifStyle
        % 贴满画布，跟 OpenCV 窗口一样没有白边
        pos = [0, (nPanel-k)/nPanel, 1, 1/nPanel];
    else
        hh  = 0.88 / nPanel;
        pos = [0.09, 0.06 + (nPanel-k)*hh + 0.18*hh, 0.88, 0.74*hh];
    end
    ax(k) = axes('Parent', fig, 'Position', pos);
    h(k)  = line(ax(k), x, zeros(1, N));
    if isGifStyle
        set(ax(k), 'Color', 'k', 'XColor', 'none', 'YColor', 'none', ...
                   'XTick', [], 'YTick', [], 'Box', 'off');
        set(h(k), 'Color', 'w', 'LineWidth', 1);
    else
        set(h(k), 'Color', [0 0.35 0.75], 'LineWidth', 0.8);
        grid(ax(k), 'on');
        ylabel(ax(k), panels{k});
        if k == nPanel, xlabel(ax(k), '采样点 (camera pixel)'); end
    end
    if k == alinePanel
        set(h(k), 'XData', 1:depth);     % A-line 那一路横轴是深度 bin
        xlim(ax(k), [1 depth]);
        if ~isGifStyle, xlabel(ax(k), '深度 (bin)'); end
    else
        xlim(ax(k), [1 N]);
    end
end

ttl = [];
if ~isGifStyle
    ttl = title(ax(1), '');
end

% ---- 纵轴范围 -------------------------------------------------------
lim = cell(nPanel, 1);
if ~isempty(opt.YLim)
    [lim{:}] = deal(opt.YLim);
else
    nProbe = min(nLine, max(64, opt.BgWindow * 2));
    probe = data(1:nProbe, :);
    lo = min(probe(:)); hi = max(probe(:));
    if hi <= lo, hi = lo + 1; end
    pad = 0.05 * (hi - lo);
    lim{1} = [lo - pad, hi + pad];
    for k = 2:nPanel
        if k == 2 && opt.BgWindow > 0
            % 减背景后只剩干涉条纹，比原始光谱小一两个数量级，
            % 按原始幅度猜会把条纹压成一条直线 —— 直接实测一下
            nb = opt.BgWindow;
            bgp = probe - filter(ones(1, nb)/nb, 1, probe, [], 1);
            if nProbe > nb
                bgp = bgp(nb+1:end, :);    % 前 nb 行窗口不完整，残差偏小，不算
            end
            a = max(abs(bgp(:)));
            if ~isfinite(a) || a <= 0, a = 0.35 * (hi - lo); end
            lim{k} = [-1.15*a, 1.15*a];
        else
            lim{k} = lim{1};
        end
    end
end
% ---- 整个区间一次性批量重建 -----------------------------------------
% 以前是每帧调一次 oct_recon_pipeline（一次只算 1 条），慢，而且拿不到
% 全区间的灰度范围，只能逐条归一化。现在先整块算完：
%   * 归一化可以用全区间统一的 min/max（和"草莓"那版一个路子）
%   * 一次批量 ifft 代替 nLine 次小调用，快一两个数量级
recon = []; gLo = 0; gHi = 1;
if needRecon
    bytes = nLine * depth * 4;      % 存成 single
    if bytes > 400e6
        fprintf(['  注意：区间有 %d 条，重建结果要占 %.0f MB。\n' ...
                 '  只是想看图的话用 oct_recon_demo 更合适。\n'], nLine, bytes/1e6);
    end
    t0 = tic;
    recon = zeros(nLine, depth, 'single');
    CH = 4096;                      % 分块只为了控峰值内存，结果和整块算一致
    for c0 = 1:CH:nLine
        c1 = min(c0 + CH - 1, nLine);
        % 这一块在 raw 里的位置，往前再借 nbBg 条做背景窗口
        lo  = max(1, pre + c0 - nbBg);
        prc = (pre + c0) - lo;
        rr  = oct_recon_pipeline(raw(lo:(pre + c1), :), p, kin);
        recon(c0:c1, :) = single(rr(prc+1:end, :));
    end
    gLo = double(min(recon(:))); gHi = double(max(recon(:)));
    if gHi <= gLo, gHi = gLo + 1; end
    fprintf('  重建 %d 条用了 %.2f s（%.0f A-line/s），灰度范围 %.3f ~ %.3f\n', ...
            nLine, toc(t0), nLine/max(toc(t0), eps), gLo, gHi);
end
clear raw

% A-line 那一路是 log 幅度，量级和光谱完全不同，直接用上面的全区间范围
if alinePanel > 0 && isempty(opt.YLim)
    lim{alinePanel} = [gLo - 0.02*(gHi-gLo), gHi + 0.05*(gHi-gLo)];
end
for k = 1:nPanel
    ylim(ax(k), lim{k});
end

% ---- 滚动 B-scan 窗口（对应 C++ 的 "BSCAN_ALINE_TIME"）--------------
figB = []; imgB = []; axB = []; bscan = []; colIdx = 1;
normMode = lower(opt.BscanNorm);
if ~any(strcmp(normMode, {'range', 'aline', 'running'}))
    error('oct_show_spectrum:bscanNorm', ...
          '''BscanNorm'' 只能是 ''range'' / ''aline'' / ''running''，给的是 ''%s''', ...
          opt.BscanNorm);
end
if opt.ShowBscan
    cols = min(opt.BscanCols, max(nLine, 1));   % 区间比 BscanCols 短就别留空白
    switch normMode
        case 'aline'
            bscan = zeros(depth, cols);         % 逐条归一化到 [0,1]
            cl = [0 1];
        otherwise
            bscan = gLo * ones(depth, cols);    % 存原始 log 值，未填的当底噪
            cl = [gLo gHi];
    end
    figB = figure('Name', 'BSCAN_ALINE_TIME', 'NumberTitle', 'off', 'Color', 'k');
    set(figB, 'Position', [80, 60, 1100, 420]);
    axB  = axes('Parent', figB);
    imgB = imagesc(axB, bscan, cl);
    colormap(axB, gray(256));
    set(axB, 'XTick', [], 'YTick', [], 'Position', [0 0 1 1]);
end

% ---- 滚动播放 -------------------------------------------------------
% 数据是每条都填进去的（B-scan 逐列生长这点不变），但"往屏幕推"这件事
% 按 ~30 Hz 节流：一次 drawnow 加一次 CData 拷贝要好几毫秒，801 条全推
% 就是白等十秒，而人眼在 30 Hz 以上根本分不出来。
% 两种情况仍然每帧都推：用户显式给了 Pause（说明是想一帧一帧看），
% 以及要存 gif（每一帧都得进文件）。
gifFirst = true;
lastPush = tic;
alwaysPush = (opt.Pause > 0) || ~isempty(opt.SaveGif);
for i = 1:nLine
    if ~ishandle(fig), break; end            % 用户关窗就停
    doPush = alwaysPush || i == nLine || toc(lastPush) > 1/30;

    % ---- B-scan 的列：每条都要填，和推不推屏无关 ----
    if opt.ShowBscan && ishandle(figB)
        aline = double(recon(i, :));
        if strcmp(normMode, 'aline')
            mn = min(aline); mx = max(aline);
            if mx > mn
                bscan(:, colIdx) = (aline - mn).' / (mx - mn);
            else
                bscan(:, colIdx) = 0;
            end
        else
            bscan(:, colIdx) = aline.';     % 原始 log 值，靠 CLim 定灰度
        end
        colIdx = colIdx + 1;
        if colIdx > size(bscan, 2), colIdx = 1; end
    end

    if ~doPush
        if opt.Pause > 0, pause(opt.Pause); end
        continue;
    end

    % ---- 下面都是"推屏"的活儿 ----
    cur = data(i, :);
    set(h(1), 'YData', cur);

    kp = 2;
    if opt.BgWindow > 0
        % 和 C++ 一致：拿"包含当前条在内的最近 BgWindow 条"做平均再相减
        i0 = max(1, i - opt.BgWindow + 1);
        set(h(kp), 'YData', cur - mean(data(i0:i, :), 1));
        kp = kp + 1;
    end
    if opt.ShowKlin
        y = cur(:).';
        set(h(kp), 'YData', y(kin.idx) + kin.frac .* (y(kin.idx+1) - y(kin.idx)));
        kp = kp + 1;
    end
    if opt.ShowAline
        set(h(kp), 'YData', double(recon(i, :)));
    end
    if opt.ShowBscan && ishandle(figB)
        set(imgB, 'CData', bscan);
        if strcmp(normMode, 'running')
            nFilled = min(i, size(bscan, 2));      % 只看已经填过的列
            seen = bscan(:, 1:nFilled);
            rLo = min(seen(:)); rHi = max(seen(:));
            if rHi > rLo, set(axB, 'CLim', [rLo rHi]); end
        end
    end
    lastPush = tic;

    if ~isempty(ttl)
        set(ttl, 'String', sprintf('A-line %d / %d', i, nLine));
    end

    if isempty(opt.SaveGif)
        drawnow limitrate;
    else
        drawnow;
        frame = getframe(fig);
        % 不用 rgb2ind（那是图像处理工具箱的），这两种风格转灰度就够了
        idx = uint8(mean(double(frame2im(frame)), 3));
        map = gray(256);
        if gifFirst
            imwrite(idx, map, opt.SaveGif, 'gif', 'LoopCount', Inf, ...
                    'DelayTime', max(opt.Pause, 0.02));
            gifFirst = false;
        else
            imwrite(idx, map, opt.SaveGif, 'gif', 'WriteMode', 'append', ...
                    'DelayTime', max(opt.Pause, 0.02));
        end
    end

    if opt.Pause > 0
        pause(opt.Pause);
    end
end

if ~isempty(opt.SaveGif)
    fprintf('gif 已写入 %s\n', opt.SaveGif);
end
end
