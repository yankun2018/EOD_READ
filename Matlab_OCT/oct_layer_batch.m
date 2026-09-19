function stats = oct_layer_batch(inDir, outDir, varargin)
%OCT_LAYER_BATCH  批量跑分层，把结果写到指定目录。
%
%   stats = OCT_LAYER_BATCH(inDir, outDir)
%   stats = OCT_LAYER_BATCH(inDir, outDir, 'Name', value, ...)
%
%   inDir 下的 PNG 逐张跑 oct_layer_seg，输出写到 outDir：
%     gray_clean\     把叠加线抹掉、插值补回的干净灰度图（真正的"原图"）
%     seg_overlay\    我的 7 条分层线画在灰度图上
%     seg_compare\    我的结果 / 原线 并排对比（只在输入带线时生成）
%     layers.dat      分层结果，EOD 的 _analy.dat 格式（见 oct_layer_export）
%     layers.csv      逐张逐层的深度，纯文本
%     report.txt      和原线的误差汇总（只在输入带线时生成）
%
%   输入图带不带分层线都行：
%   * 带线（比如 pic_md / pic_md_origin\pic_bscan 那批，是原 exe 的输出）——
%     线会被抹掉当 ground truth，同时报误差。
%   * 不带线（真正的裸 B-scan）—— 直接分层，跳过误差那部分。
%
%   选项：
%     'Files'    只跑这些（下标或文件名 cell），[] = 全部
%     'Save'     要写哪些，cell，可选 'gray','overlay','compare','dat','csv'
%                默认全写
%     'Offsets'  透传给 oct_layer_seg
%     'NPoint'   layers.dat 每条线多少点（默认 1024，同原系统）
%
%   参见 oct_layer_seg, oct_layer_gt, oct_layer_export。

opt.Files   = [];
opt.Save    = {'gray', 'overlay', 'compare', 'dat', 'csv'};
opt.Offsets = [];
opt.NPoint  = 1024;
opt = oct_parseopt(opt, varargin);

if ~exist(inDir, 'dir')
    error('oct_layer_batch:noDir', '输入目录不存在: %s', inDir);
end
d = dir(fullfile(inDir, '*.png'));
if isempty(d), error('oct_layer_batch:noPng', '%s 下没有 png', inDir); end
files = sort({d.name});
if ~isempty(opt.Files)
    if isnumeric(opt.Files), files = files(opt.Files);
    else
        if ischar(opt.Files), opt.Files = {opt.Files}; end
        files = opt.Files;
    end
end
n = numel(files);

want = @(k) any(strcmpi(k, opt.Save));
sub = {};
if want('gray'),    sub{end+1} = 'gray_clean';  end
if want('overlay'), sub{end+1} = 'seg_overlay'; end
if want('compare'), sub{end+1} = 'seg_compare'; end
if ~exist(outDir, 'dir'), mkdir(outDir); end
for i = 1:numel(sub)
    p = fullfile(outDir, sub{i});
    if ~exist(p, 'dir'), mkdir(p); end
end

names  = {'ilm', 'rnfl', 'ipl', 'inl', 'opl', 'isos', 'rpe'};
labels = {'ILM', 'RNFL/GCL', 'IPL/INL', 'INL/OPL', 'OPL/ONL', 'IS/OS', 'RPE/BM'};
cols   = [1 0 0; 1 1 0; 1 0 1; 1 .49 0; 1 0 .49; 0 1 0; 0 0 1];
cols8  = uint8(round(cols * 255));

segArgs = {};
if ~isempty(opt.Offsets), segArgs = {'Offsets', opt.Offsets}; end

bdAll = cell(1, n);
err   = nan(n, 7);
hasGT = false(n, 1);

fprintf('输入 %s\n输出 %s\n跑 %d 张...\n', inDir, outDir, n);
t0 = tic;
for i = 1:n
    f = fullfile(inDir, files{i});
    [img, gt, gi] = oct_layer_gt(f);
    hasGT(i) = any(gi.nFound > 0);        % 输入里有没有叠加线
    bd = oct_layer_seg(img, segArgs{:});
    bdAll{i} = bd;

    [~, base] = fileparts(files{i});

    if want('gray')
        imwrite(uint8(max(min(img, 255), 0)), ...
                fullfile(outDir, 'gray_clean', [base '.png']));
    end
    if want('overlay')
        imwrite(local_burn(img, bd, names, cols8), ...
                fullfile(outDir, 'seg_overlay', [base '.png']));
    end
    if want('compare') && hasGT(i)
        A = local_burn(img, bd, names, cols8);
        B = local_burn(img, gt, names, cols8);
        gap = zeros(size(A,1), 12, 3, 'uint8');
        imwrite([A, gap, B], fullfile(outDir, 'seg_compare', [base '.png']));
    end

    if hasGT(i)
        for k = 1:7
            a = bd.(names{k}); b = gt.(names{k}); ok = ~isnan(b);
            err(i, k) = mean(abs(a(ok) - b(ok)));
        end
    end
    if mod(i, 20) == 0 || i == n
        fprintf('  %d/%d\n', i, n);
    end
end
el = toc(t0);

% ---- layers.dat ----
if want('dat')
    p = fullfile(outDir, 'layers.dat');
    nb = oct_layer_export(p, bdAll, 'NPoint', opt.NPoint);
    fprintf('\nlayers.dat  %d 字节（%d 幅 x 7 x %d uint32 + 16 头）\n', nb, n, opt.NPoint);
end

% ---- layers.csv ----
if want('csv')
    p = fullfile(outDir, 'layers.csv');
    fid = fopen(p, 'w');
    fprintf(fid, 'file,column');
    for k = 1:7, fprintf(fid, ',%s', names{k}); end
    fprintf(fid, '\n');
    for i = 1:n
        bd = bdAll{i};
        W = numel(bd.ilm);
        for x = 1:W
            fprintf(fid, '%s,%d', files{i}, x);
            for k = 1:7, fprintf(fid, ',%.2f', bd.(names{k})(x)); end
            fprintf(fid, '\n');
        end
    end
    fclose(fid);
    dd = dir(p);
    fprintf('layers.csv  %.1f MB（%d 行）\n', dd.bytes/1e6, n*numel(bdAll{1}.ilm));
end

% ---- report.txt ----
% 不用 nanmean（那是统计工具箱的），基础 MATLAB 的 mean 带 'omitnan'
stats.perLayer = mean(err, 1, 'omitnan');
stats.overall  = mean(err(:), 'omitnan');
stats.nGT      = sum(hasGT);
stats.err      = err;
stats.files    = files;

if any(hasGT)
    p = fullfile(outDir, 'report.txt');
    fid = fopen(p, 'w');
    fprintf(fid, 'OCT 视网膜 7 层分割 —— 批处理报告\n');
    fprintf(fid, '生成时间: %s\n', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, '输入: %s (%d 张，其中 %d 张带原分层线)\n', inDir, n, sum(hasGT));
    fprintf(fid, '耗时: %.1f s (%.3f s/张)\n\n', el, el/n);
    fprintf(fid, '和原 exe 的线相比，各层平均 |误差| (px):\n');
    for k = 1:7
        fprintf(fid, '  %-6s %-11s %6.2f   (最差单张 %5.2f)\n', ...
                names{k}, labels{k}, stats.perLayer(k), max(err(:,k)));
    end
    fprintf(fid, '  %-18s %6.2f\n\n', '总体', stats.overall);
    allE = sort(err(~isnan(err)));
    q90 = allE(max(1, ceil(0.90 * numel(allE))));   % 不用 prctile（统计工具箱的）
    fprintf(fid, '逐张逐层误差分布: 中位 %.2f | 90%% %.2f | 最大 %.2f\n\n', ...
            median(allE), q90, max(allE));
    fprintf(fid, '逐张总误差:\n');
    for i = 1:n
        if hasGT(i)
            fprintf(fid, '  %-16s %6.2f\n', files{i}, mean(err(i,:)));
        end
    end
    fclose(fid);
    fprintf('report.txt  写好了\n');
end

fprintf('\n耗时 %.1f s (%.3f s/张)\n', el, el/n);
if any(hasGT)
    fprintf('和原线相比: 总体平均 %.2f px\n', stats.overall);
    for k = 1:7
        fprintf('  %-6s %-11s %.2f\n', names{k}, labels{k}, stats.perLayer(k));
    end
end
end

% ======================================================================
function rgb = local_burn(img, bd, names, cols8)
%LOCAL_BURN  把 7 条线画到灰度图上，返回 uint8 RGB。
g = uint8(max(min(img, 255), 0));
rgb = repmat(g, 1, 1, 3);
[H, W, ~] = size(rgb);
for k = 1:7
    y = bd.(names{k});
    for x = 1:min(W, numel(y))
        r = round(y(x));
        if ~isfinite(r) || r < 1 || r > H, continue; end
        rgb(r, x, 1) = cols8(k, 1);
        rgb(r, x, 2) = cols8(k, 2);
        rgb(r, x, 3) = cols8(k, 3);
    end
end
end
