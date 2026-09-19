function out = oct_analy_demo(varargin)
%OCT_ANALY_DEMO  C-scan + 层厚图 + 偏差图，对应 Analy_and_image_show 那三个脚本。
%
%   out = OCT_ANALY_DEMO
%   out = OCT_ANALY_DEMO('Name', value, ...)
%
%   直接吃仓库里 test_data 下那两份真实数据：
%     od-3dscan-macular-...-001.dat        原始体数据 120 x 432 x 700
%     od-3dscan-macular-...-001_analy.dat  原 exe 的分层结果
%
%   三张图分别对应：
%     oct_cscan.py        -> C-scan（全深度投影）
%     oct_thickness.py    -> 层厚图
%     oct_DeviationMap.py -> 偏差图 + 叠在 C-scan 上
%
%   选项：
%     'Vol'      原始体数据路径（默认 test_data 下那份）
%     'Analy'    分层结果路径（默认同上）。设 'seg' 就不读文件、
%                改用 oct_layer_seg 现场分层，可以和原 exe 的结果对比。
%     'Top'/'Bot' 层厚图用哪两层（默认 ilm -> rpe，全视网膜）
%     'Grid'     偏差图的网格（默认 24，同原脚本）
%     'Ref'      参考厚度（默认 'median'）
%     'Show'     开窗显示（默认 true）
%     'SaveDir'  存 PNG 的目录（默认 ''）
%     'Square'   存图时把 C-scan / 厚度图拉成正方形（默认 true）。
%                扫描区域是 6x6 mm，但采样是 120 幅 x 432 A-line，
%                所以原始比例是 1:3.6，拉方了才是真实的视野形状。
%                原脚本最后那句 cv2.resize(image,(432,432)) 就是这件事。
%
%   out : .cscan .thickness .grade .pooled .info
%
%   参见 oct_volume_read, oct_thickness_map, oct_deviation_map。

opt.Vol     = '';          % 空 = 用 oct_find_data 自动找
opt.Analy   = '';
opt.Top     = 'ilm';
opt.Bot     = 'rpe';
opt.Grid    = 24;
opt.Ref     = 'median';
opt.Show    = true;
opt.SaveDir = '';
opt.Square  = true;
opt = oct_parseopt(opt, varargin);

% ---- 体数据 ----------------------------------------------------------
if isempty(opt.Vol),   opt.Vol   = oct_find_data('volume'); end
if isempty(opt.Analy), opt.Analy = oct_find_data('analy');  end
fprintf('读体数据 %s\n', opt.Vol);
[vol, vi] = oct_volume_read(opt.Vol);
fprintf('  %d x %d x %d（深度 x A-line x B-scan）\n', vi.depth, vi.nAline, vi.nBscan);

% ---- 分层 ------------------------------------------------------------
if strcmpi(opt.Analy, 'seg')
    fprintf('现场分层（oct_layer_seg）...\n');
    t0 = tic;
    bd = cell(1, vi.nBscan);
    for i = 1:vi.nBscan
        bd{i} = oct_layer_seg(vol(:, :, i));
    end
    fprintf('  %.1f s\n', toc(t0));
else
    fprintf('读分层 %s\n', opt.Analy);
    bd = oct_layer_import(opt.Analy, 'Depth', vi.depth);
    fprintf('  %d 幅\n', numel(bd));
end

% 统一成 cell：oct_layer_seg 那条路给的是 cell，oct_layer_import 给的是
% struct 数组，下面一律按 bd{i} 用
if isstruct(bd), bd = num2cell(bd); end

% ---- C-scan（全深度投影，对应 oct_cscan.py）--------------------------
% 原脚本是 700 层逐个相加再归一化，这里等价地一次求和
cscan = squeeze(sum(vol, 1)).';        % [nBscan x nAline]
fprintf('\nC-scan %d x %d，值域 %.0f~%.0f\n', size(cscan,1), size(cscan,2), ...
        min(cscan(:)), max(cscan(:)));

% ---- 层厚图 ----------------------------------------------------------
[T, ti] = oct_thickness_map(bd, 'Top', opt.Top, 'Bot', opt.Bot);
fprintf('层厚 %s -> %s: 中位 %.1f %s（5%%~95%% %.1f~%.1f），有效 %.0f%%\n', ...
        ti.top, ti.bot, ti.median, ti.unit, ti.p5, ti.p95, 100*ti.valid);

% ---- 偏差图 ----------------------------------------------------------
[grade, pooled, di] = oct_deviation_map(T, 'Grid', opt.Grid, 'Ref', opt.Ref);
fprintf('偏差图 %dx%d（每块 %dx%d），参考厚度 %.1f %s\n', ...
        di.grid, di.grid, di.blockSize(1), di.blockSize(2), di.ref, ti.unit);
fprintf('  各级占比: ');
fprintf('%.0f%% ', 100*di.fracByLevel);
fprintf('（阈值 '); fprintf('%.0f%% ', 100*di.levels); fprintf('）\n');

out.cscan = cscan; out.thickness = T;
out.grade = grade; out.pooled = pooled;
out.info  = struct('vol', vi, 'thickness', ti, 'deviation', di);

% ---- 显示 ------------------------------------------------------------
if opt.Show
    fig = figure('Name', 'OCT 分析图', 'NumberTitle', 'off', 'Color', 'k');
    set(fig, 'Position', [60, 80, 1180, 760]);
    pos = [0.03 0.53 0.30 0.42; 0.36 0.53 0.30 0.42; ...
           0.69 0.53 0.30 0.42; 0.03 0.05 0.30 0.42; ...
           0.36 0.05 0.30 0.42; 0.69 0.05 0.30 0.42];
    dat = {cscan, T, pooled, grade, local_overlay(cscan, grade), ...
           local_bscan_with_layers(vol(:,:,round(vi.nBscan/2)), bd{round(vi.nBscan/2)})};
    ttl = {'C-scan（全深度投影）', ...
           sprintf('层厚 %s->%s (%s)', ti.top, ti.bot, ti.unit), ...
           sprintf('池化 %dx%d', di.grid, di.grid), ...
           '偏差分级', '偏差叠在 C-scan 上', '中间那幅 B-scan + 分层'};
    for k = 1:6
        ax = axes('Parent', fig, 'Position', pos(k,:));
        if k == 5 || k == 6
            image(ax, dat{k});
        else
            imagesc(ax, dat{k});
            colormap(ax, gray(256));
        end
        axis(ax, 'image'); set(ax, 'XTick', [], 'YTick', []);
        title(ax, ttl{k}, 'Color', 'w', 'FontSize', 9);
    end
end

% ---- 存图 ------------------------------------------------------------
if ~isempty(opt.SaveDir)
    if ~exist(opt.SaveDir, 'dir'), mkdir(opt.SaveDir); end
    sq = @(x) x;
    if opt.Square
        side = size(cscan, 2);                  % 拉到 nAline x nAline
        sq = @(x) local_resize_nn(x, side, side);
    end
    imwrite(local_n8(sq(cscan)), fullfile(opt.SaveDir, 'oct_cscan.png'));
    imwrite(local_n8(sq(T)),     fullfile(opt.SaveDir, 'oct_thickness.png'));
    imwrite(local_n8(pooled),    fullfile(opt.SaveDir, 'oct_thickness_pooled.png'));
    imwrite(local_n8(sq(grade)), fullfile(opt.SaveDir, 'oct_deviation_grade.png'));
    ov = local_overlay(cscan, grade);
    if opt.Square
        ov = cat(3, local_resize_nn(ov(:,:,1), side, side), ...
                    local_resize_nn(ov(:,:,2), side, side), ...
                    local_resize_nn(ov(:,:,3), side, side));
    end
    imwrite(ov, fullfile(opt.SaveDir, 'oct_DeviationMap.png'));
    mid = round(vi.nBscan/2);
    imwrite(local_bscan_with_layers(vol(:,:,mid), bd{mid}), ...
            fullfile(opt.SaveDir, 'oct_bscan_layers.png'));
    fprintf('\nPNG 已存到 %s\n', opt.SaveDir);
end
end

% ======================================================================
function rgb = local_overlay(cscan, grade)
%LOCAL_OVERLAY  把偏差分级用颜色叠到 C-scan 上（对应原脚本最后 cv2.add 那段）。
g = local_n8(cscan);
[H, W] = size(g);
% 分级放大到 C-scan 尺寸（最近邻，保持块状）
[gh, gw] = size(grade);
ri = min(gh, max(1, ceil((1:H)/H * gh)));
ci = min(gw, max(1, ceil((1:W)/W * gw)));
G = grade(ri, ci);

% 1 级绿、往上越红
lut = [  0 200   0;      % 1 最接近参考
       160 220   0;      % 2
       255 200   0;      % 3
       255 110   0;      % 4
       255   0   0];     % 5+
rgb = repmat(g, 1, 1, 3);
for k = 1:size(lut, 1)
    m = (G == k);
    if ~any(m(:)), continue; end
    for ch = 1:3
        t = rgb(:, :, ch);
        % 半透明叠加，底下的 C-scan 还看得见
        t(m) = uint8(0.45*double(t(m)) + 0.55*lut(k, ch));
        rgb(:, :, ch) = t;
    end
end
end

% ======================================================================
function rgb = local_bscan_with_layers(b, bd)
%LOCAL_BSCAN_WITH_LAYERS  一幅 B-scan 画上 7 条分层线。
names = {'ilm','rnfl','ipl','inl','opl','isos','rpe'};
cols  = uint8([255 0 0; 255 255 0; 255 0 255; 255 125 0; 255 0 125; 0 255 0; 0 0 255]);
g = local_n8(b);
rgb = repmat(g, 1, 1, 3);
[H, W] = size(g);
for k = 1:7
    if ~isfield(bd, names{k}), continue; end
    y = bd.(names{k});
    for x = 1:min(W, numel(y))
        r = round(y(x));
        if ~isfinite(r) || r < 1 || r > H, continue; end
        rgb(r, x, 1) = cols(k,1);
        rgb(r, x, 2) = cols(k,2);
        rgb(r, x, 3) = cols(k,3);
    end
end
end

% ======================================================================
function o = local_resize_nn(im, h, w)
%LOCAL_RESIZE_NN  最近邻缩放（imresize 要图像处理工具箱）。
[H, W] = size(im);
ri = min(H, max(1, ceil((1:h) / h * H)));
ci = min(W, max(1, ceil((1:w) / w * W)));
o = im(ri, ci);
end

% ======================================================================
function u = local_n8(v)
v = double(v);
f = isfinite(v);
if ~any(f), u = zeros(size(v), 'uint8'); return; end
lo = min(v(f)); hi = max(v(f));
if hi <= lo, u = zeros(size(v), 'uint8'); return; end
v(~f) = lo;
u = uint8((v - lo) / (hi - lo) * 255);
end
