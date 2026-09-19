function [ef, out, mask] = oct_enface_demo(varargin)
%OCT_ENFACE_DEMO  B-scan 堆成体数据 -> 分层 -> en-face -> 血管检测 -> 去血管。
%
%   oct_enface_demo
%   [ef, out, mask] = oct_enface_demo('Name', value, ...)
%
%   把 exe 里剩下那几个文件串起来跑一遍：
%     DIJK_SEG.m        -> oct_layer_seg      分层
%     （投影）           -> oct_enface         en-face
%     FrangiFilter2D.m  -> oct_frangi2d       血管增强
%     Hessian2D.m       ↗
%     eig2image.m       ↗
%     enface_deVessel.m -> oct_devessel       去血管
%     graphcut_BW.m     ↗（二值化那一步）
%
%   选项：
%     'Dir'      B-scan 目录（默认 Desktop\pic_md_origin\pic_bscan）
%     'Slab'     en-face 用哪个板层（默认 'deep'，即 IS/OS->RPE，
%                血管投影阴影在这层最清楚）
%     'Show'     true 开窗显示（默认 true）
%     'SaveDir'  非空时把 PNG 存到该目录（默认 ''）
%     'Devessel' 透传给 oct_devessel 的选项 cell（默认 {}）
%
%   例：
%     oct_enface_demo
%     oct_enface_demo('Slab', 'full', 'SaveDir', 'D:\out')
%     oct_enface_demo('Devessel', {'Coverage', 0.15, 'Dilate', 1})
%
%   参见 oct_enface, oct_frangi2d, oct_devessel, oct_layer_seg。

opt.Dir      = '';         % 空 = 用 oct_find_data('bscan') 自动找
opt.Slab     = 'deep';
opt.Show     = true;
opt.SaveDir  = '';
opt.Devessel = {};
opt = oct_parseopt(opt, varargin);

if isempty(opt.Dir), opt.Dir = oct_find_data('bscan'); end
if ~exist(opt.Dir, 'dir')
    error('oct_enface_demo:noDir', '找不到 B-scan 目录: %s', opt.Dir);
end
d = dir(fullfile(opt.Dir, '*.png'));
if isempty(d), error('oct_enface_demo:noPng', '%s 下没有 png', opt.Dir); end
files = sort({d.name});
n = numel(files);

% ---- 读体数据 + 分层 -------------------------------------------------
fprintf('读 %d 幅 B-scan 并分层...\n', n);
t0 = tic;
first = oct_layer_gt(fullfile(opt.Dir, files{1}));
[H, W] = size(first);
vol = zeros(H, W, n);
bd  = cell(1, n);
for i = 1:n
    img = oct_layer_gt(fullfile(opt.Dir, files{i}));
    vol(:, :, i) = img;
    bd{i} = oct_layer_seg(img);
end
fprintf('  %.1f s。体数据 %d x %d x %d\n', toc(t0), H, W, n);

% ---- en-face ---------------------------------------------------------
[ef, efi] = oct_enface(vol, bd, 'Slab', opt.Slab);
fprintf('en-face %s（%s -> %s）%d x %d\n', efi.slab, efi.top, efi.bot, ...
        size(ef, 1), size(ef, 2));

% ---- 血管检测 + 去血管 ------------------------------------------------
t1 = tic;
[out, mask, V] = oct_devessel(ef, opt.Devessel{:});
fprintf('去血管 %.2f s，掩膜覆盖 %.1f%%\n', toc(t1), 100*mean(mask(:)));

% 效果：血管处的亮度应该被填到接近背景
d0 = mean(ef(~mask)) - mean(ef(mask));
d1 = mean(out(~mask)) - mean(out(mask));
V1 = oct_frangi2d(out);
fprintf('  血管处 vs 背景的亮度差: %.2f -> %.2f\n', d0, d1);
fprintf('  血管性总量: %.4f -> %.4f（降 %.0f%%）\n', ...
        mean(V(:)), mean(V1(:)), 100*(1 - mean(V1(:))/max(mean(V(:)), eps)));

% ---- 显示 ------------------------------------------------------------
if opt.Show
    fig = figure('Name', 'en-face 血管处理', 'NumberTitle', 'off', 'Color', 'k');
    set(fig, 'Position', [80, 120, 1000, 760]);
    ttl = {sprintf('en-face (%s)', efi.slab), 'Frangi 血管性响应', ...
           '血管掩膜', '去血管后'};
    dat = {ef, V, double(mask), out};
    for k = 1:4
        ax = axes('Parent', fig, 'Position', [0.04, 1-0.245*k, 0.92, 0.20]);
        im = dat{k};
        if k == 2
            % Frangi 响应高度偏斜，按分位数拉伸才看得见
            sv = sort(im(:)); hi = sv(max(1, round(0.995*numel(sv))));
            imagesc(ax, im, [0, max(hi, eps)]);
        else
            imagesc(ax, im);
        end
        colormap(ax, gray(256));
        set(ax, 'XTick', [], 'YTick', []);
        title(ax, ttl{k}, 'Color', 'w');
    end
end

% ---- 存图 ------------------------------------------------------------
if ~isempty(opt.SaveDir)
    if ~exist(opt.SaveDir, 'dir'), mkdir(opt.SaveDir); end
    imwrite(local_n8(ef),  fullfile(opt.SaveDir, ['enface_' efi.slab '.png']));
    imwrite(local_n8(out), fullfile(opt.SaveDir, ['enface_' efi.slab '_devessel.png']));
    imwrite(uint8(mask)*255, fullfile(opt.SaveDir, 'vessel_mask.png'));
    sv = sort(V(:)); q = sv(max(1, round(0.995*numel(sv))));
    imwrite(uint8(min(V/max(q, eps), 1)*255), ...
            fullfile(opt.SaveDir, 'vessel_frangi.png'));
    % 血管掩膜叠红
    A = local_n8(ef); rgb = repmat(A, 1, 1, 3);
    r = rgb(:,:,1); g = rgb(:,:,2); b = rgb(:,:,3);
    r(mask) = 255;
    g(mask) = uint8(double(g(mask))*0.25);
    b(mask) = uint8(double(b(mask))*0.25);
    rgb(:,:,1) = r; rgb(:,:,2) = g; rgb(:,:,3) = b;
    imwrite(rgb, fullfile(opt.SaveDir, 'vessel_overlay.png'));
    fprintf('PNG 已存到 %s\n', opt.SaveDir);
end
end

function u = local_n8(v)
lo = min(v(:)); hi = max(v(:));
if hi <= lo, u = zeros(size(v), 'uint8'); return; end
u = uint8((v - lo) / (hi - lo) * 255);
end
