function oct_demo_all(varargin)
%OCT_DEMO_ALL  依次跑一遍所有 demo，数据缺了就跳过。
%
%   oct_demo_all
%   oct_demo_all('Name', value, ...)
%
%   选项：
%     'SaveDir'  非空时把所有出图存到该目录（默认 ''，只显示不存）
%     'Show'     开窗显示（默认 true）。跑批量或无头环境时设 false。
%     'Only'     只跑其中几个，cell，可选
%                'spectrum' 'recon' 'layer' 'enface' 'analy' 'report'
%                默认全跑
%
%   例：
%     oct_demo_all
%     oct_demo_all('SaveDir', 'out', 'Show', false)
%     oct_demo_all('Only', {'report'})
%
%   参见 oct_setup。

opt.SaveDir = '';
opt.Show    = true;
opt.Only    = {};
opt = oct_parseopt(opt, varargin);

if ischar(opt.Only), opt.Only = {opt.Only}; end
want = @(n) isempty(opt.Only) || any(strcmpi(n, opt.Only));

sd = opt.SaveDir;
if ~isempty(sd) && ~exist(sd, 'dir'), mkdir(sd); end

fprintf('\n');
n = 0; skipped = {};

% ---- 1 原始光谱 ------------------------------------------------------
if want('spectrum')
    [~, got] = oct_find_data('spectrum', 'Quiet', true);
    if got
        local_head('1/6  原始光谱滚动显示  oct_show_spectrum');
        % 取中间 400 条。不写死区间 —— 打包时 CSV 被截过（完整 5951 条，
        % 包里只放 600 条），写死 [2000 2400] 在精简数据上会读不到东西
        nAll = size(oct_load_spectrum(oct_find_data('spectrum')), 1);
        k0 = max(1, round(nAll/2) - 200);
        k1 = min(nAll, k0 + 399);
        args = {'Range', [k0 k1], 'Pause', 0};
        if ~isempty(sd), args = [args {'SaveGif', fullfile(sd, 'spectrum.gif')}]; end
        oct_show_spectrum(args{:});
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'spectrum（缺光谱 CSV）';
    end
end

% ---- 2 光谱重建成 B-scan --------------------------------------------
if want('recon')
    [~, g1] = oct_find_data('spectrum', 'Quiet', true);
    [~, g2] = oct_find_data('strawberry', 'Quiet', true);
    if g1 || g2
        local_head('2/6  光谱重建 B-scan  oct_recon_demo');
        oct_recon_demo('MaxBscans', 2, 'Pause', 0, 'ShowEnface', false);
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'recon（缺光谱数据）';
    end
end

% ---- 3 视网膜分层 ----------------------------------------------------
if want('layer')
    [~, got] = oct_find_data('bscan', 'Quiet', true);
    if got
        local_head('3/6  视网膜 7 层分割  oct_layer_demo');
        if opt.Show
            oct_layer_demo('Files', 1:3, 'Pause', 0.4);
        else
            oct_layer_demo('Files', 1:6, 'Show', 'none');
        end
        if ~isempty(sd)
            oct_layer_demo('Files', 1:3, 'Pause', 0, 'SaveDir', sd);
        end
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'layer（缺 B-scan PNG）';
    end
end

% ---- 4 en-face + 血管 ------------------------------------------------
if want('enface')
    [~, got] = oct_find_data('bscan', 'Quiet', true);
    if got
        local_head('4/6  en-face + Frangi 血管 + 去血管  oct_enface_demo');
        args = {'Show', opt.Show};
        if ~isempty(sd), args = [args {'SaveDir', sd}]; end
        oct_enface_demo(args{:});
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'enface（缺 B-scan PNG）';
    end
end

% ---- 5 C-scan / 厚度 / 偏差 ------------------------------------------
if want('analy')
    [~, got] = oct_find_data('volume', 'Quiet', true);
    if got
        local_head('5/6  C-scan + 层厚图 + 偏差图  oct_analy_demo');
        args = {'Show', opt.Show};
        if ~isempty(sd), args = [args {'SaveDir', sd}]; end
        oct_analy_demo(args{:});
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'analy（缺原始体数据）';
    end
end

% ---- 6 报告图 --------------------------------------------------------
if want('report')
    [~, got] = oct_find_data('volume', 'Quiet', true);
    if got
        local_head('6/6  OCT 黄斑分析报告  oct_report');
        args = {'Show', opt.Show};
        if ~isempty(sd), args = [args {'Save', fullfile(sd, 'oct_report.png')}]; end
        oct_report(args{:});
        if ~opt.Show, close all; end
        n = n + 1;
    else
        skipped{end+1} = 'report（缺原始体数据）';
    end
end

fprintf('\n==================================================\n');
fprintf('跑完 %d 个 demo\n', n);
if ~isempty(skipped)
    fprintf('跳过了:\n');
    for i = 1:numel(skipped), fprintf('  - %s\n', skipped{i}); end
end
if ~isempty(sd)
    fprintf('出图在 %s\n', sd);
end
fprintf('==================================================\n\n');
end

function local_head(s)
fprintf('\n--------------------------------------------------\n');
fprintf('%s\n', s);
fprintf('--------------------------------------------------\n');
end
