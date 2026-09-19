function [stats, res] = oct_layer_demo(varargin)
%OCT_LAYER_DEMO  在 pic_md 那批图上跑分层、画叠加图、和 GT 比误差。
%
%   oct_layer_demo
%   oct_layer_demo('Name', value, ...)
%   [stats, res] = oct_layer_demo(...)
%
%   Desktop\pic_md 下 120 张是 EOD_read_seg.exe 的输出（B-scan + 7 条线）。
%   oct_layer_gt 把灰度和线都取回来，这里用灰度重新跑一遍分层，再拿原来的
%   线当 ground truth 对分。
%
%   选项：
%     'Dir'      图目录（默认 Desktop\Desktop\pic_md）
%     'Files'    只跑这些（下标或文件名 cell），[] = 全部
%     'Show'     显示模式：'overlay' 逐张画对比图（默认）
%                           'none'    只算数字
%     'Pause'    每张之间停顿秒数（默认 0.3，'none' 时忽略）
%     'Offsets'  透传给 oct_layer_seg，zeros(1,7) 看未校正结果
%     'SaveDir'  非空时把叠加图存成 PNG 到该目录（默认 ''）
%
%   返回：
%     stats  .perLayer(7) 各层平均 |误差|
%            .overall     总平均
%            .bias(7)     有符号偏差，正 = 比 GT 深
%     res    每张的 {bd, gt, file}
%
%   例：
%     oct_layer_demo('Files', 60)                    % 只看第 60 张
%     oct_layer_demo('Show', 'none')                 % 全部 120 张，只要数字
%     oct_layer_demo('Show','none','Offsets',zeros(1,7))   % 看未校正的偏差
%
%   参见 oct_layer_seg, oct_layer_gt。

opt.Dir     = '';          % 空 = 用 oct_find_data('bscan') 自动找
opt.Files   = [];
opt.Show    = 'overlay';
opt.Pause   = 0.3;
opt.Offsets = [];
opt.SaveDir = '';
opt = oct_parseopt(opt, varargin);

if isempty(opt.Dir), opt.Dir = oct_find_data('bscan'); end
if ~exist(opt.Dir, 'dir')
    error('oct_layer_demo:noDir', '找不到图目录: %s', opt.Dir);
end
d = dir(fullfile(opt.Dir, '*.png'));
if isempty(d)
    error('oct_layer_demo:noPng', '%s 下没有 png', opt.Dir);
end
files = sort({d.name});

if ~isempty(opt.Files)
    if isnumeric(opt.Files)
        files = files(opt.Files);
    else
        if ischar(opt.Files), opt.Files = {opt.Files}; end
        files = opt.Files;
    end
end
n = numel(files);

names  = {'ilm', 'rnfl', 'ipl', 'inl', 'opl', 'isos', 'rpe'};
labels = {'ILM', 'RNFL/GCL', 'IPL/INL', 'INL/OPL', 'OPL/ONL', 'IS/OS', 'RPE/BM'};
cols   = [1 0 0; 1 1 0; 1 0 1; 1 .49 0; 1 0 .49; 0 1 0; 0 0 1];

segArgs = {};
if ~isempty(opt.Offsets), segArgs = {'Offsets', opt.Offsets}; end

doShow = ~strcmpi(opt.Show, 'none');
fig = [];
if doShow
    fig = figure('Name', 'OCT 分层', 'NumberTitle', 'off', 'Color', 'k');
    set(fig, 'Position', [100, 80, 1150, 760]);
end
if ~isempty(opt.SaveDir) && ~exist(opt.SaveDir, 'dir'), mkdir(opt.SaveDir); end

err  = nan(n, 7);      % 各张各层的平均 |误差|
bias = nan(n, 7);      % 有符号
res  = cell(n, 1);

fprintf('跑 %d 张（%s）...\n', n, opt.Dir);
t0 = tic;
for i = 1:n
    f = fullfile(opt.Dir, files{i});
    [img, gt] = oct_layer_gt(f);
    bd = oct_layer_seg(img, segArgs{:});
    res{i} = struct('bd', bd, 'gt', gt, 'file', files{i});

    for k = 1:7
        a = bd.(names{k}); b = gt.(names{k}); ok = ~isnan(b);
        dd = a(ok) - b(ok);
        err(i, k)  = mean(abs(dd));
        bias(i, k) = mean(dd);
    end

    if doShow && ishandle(fig)
        clf(fig);
        ax1 = axes('Parent', fig, 'Position', [0.02 0.06 0.46 0.88]);
        imagesc(ax1, img); colormap(ax1, gray(256)); axis(ax1, 'image');
        set(ax1, 'XTick', [], 'YTick', []);
        title(ax1, sprintf('%s — 我的结果', files{i}), 'Color', 'w', 'Interpreter', 'none');
        hold(ax1, 'on');
        for k = 1:7
            plot(ax1, 1:numel(bd.(names{k})), bd.(names{k}), '-', ...
                 'Color', cols(k,:), 'LineWidth', 1.1);
        end
        hold(ax1, 'off');

        ax2 = axes('Parent', fig, 'Position', [0.52 0.06 0.46 0.88]);
        imagesc(ax2, img); colormap(ax2, gray(256)); axis(ax2, 'image');
        set(ax2, 'XTick', [], 'YTick', []);
        title(ax2, sprintf('原 exe 的线（GT）— 本张平均 %.2f px', mean(err(i,:))), 'Color', 'w');
        hold(ax2, 'on');
        for k = 1:7
            plot(ax2, 1:numel(gt.(names{k})), gt.(names{k}), '-', ...
                 'Color', cols(k,:), 'LineWidth', 1.1);
        end
        hold(ax2, 'off');
        drawnow limitrate;

        if ~isempty(opt.SaveDir)
            [~, base] = fileparts(files{i});
            exportgraphics(fig, fullfile(opt.SaveDir, [base '_cmp.png']), 'Resolution', 110);
        end
        if opt.Pause > 0, pause(opt.Pause); end
    end
end
el = toc(t0);

stats.perLayer = mean(err, 1);
stats.overall  = mean(err(:));
stats.bias     = mean(bias, 1);
stats.names    = names;
stats.err      = err;

fprintf('\n耗时 %.1f s（%.2f s/张）\n\n', el, el/n);
fprintf('层          标签        平均|误差|   有符号偏差   最差单张\n');
for k = 1:7
    fprintf('  %-6s %-11s %8.2f %12.2f %11.2f\n', ...
            names{k}, labels{k}, stats.perLayer(k), stats.bias(k), max(err(:,k)));
end
fprintf('\n总体平均 |误差| = %.2f px（图高 %d px）\n', stats.overall, size(res{1}.bd.ilm, 2) * 0 + 700);
end
