function ok = oct_setup(varargin)
%OCT_SETUP  把工具箱加进路径，并检查示例数据齐不齐。
%
%   oct_setup
%   ok = oct_setup('Name', value, ...)
%
%   解压之后第一件事就是在 MATLAB 里 cd 到这个目录，然后跑
%       oct_setup
%   它会把当前目录和 test\ 加进搜索路径，再列一下哪些示例数据在、哪些缺。
%
%   选项：
%     'Save'   true 时把路径存进 MATLAB 的 pathdef（下次启动还在）。
%              默认 false —— 只对本次会话生效，不动别人的配置。
%     'Quiet'  true 时不打印（默认 false）
%
%   ok : 必需的数据都在就是 true
%
%   参见 oct_demo_all, oct_datadir, oct_find_data。

opt.Save  = false;
opt.Quiet = false;
opt = local_parse(opt, varargin);

here = fileparts(mfilename('fullpath'));
addpath(here);
if exist(fullfile(here, 'test'), 'dir')
    addpath(fullfile(here, 'test'));
end
if opt.Save
    try
        savepath;
    catch e
        fprintf('savepath 失败（可能没权限）: %s\n', e.message);
    end
end

% ---- MATLAB 版本 -----------------------------------------------------
v = version('-release');
if ~opt.Quiet
    fprintf('\n=== Matlab_OCT ===\n');
    fprintf('目录   %s\n', here);
    fprintf('MATLAB %s\n', v);
end

% ---- 工具箱依赖：一个都不需要 ---------------------------------------
if ~opt.Quiet
    fprintf('依赖   只用基础 MATLAB，不需要任何工具箱\n');
end

% ---- 数据 ------------------------------------------------------------
[dd, where] = oct_datadir();
kinds = {'volume',  '原始体数据',       true
         'analy',   '原 exe 的分层',    true
         'bscan',   'B-scan PNG',       false
         'spectrum','原始光谱 CSV',     false
         'rawbin',  '12bit 碎片',       false
         'strawberry','草莓测试集',     false};

if ~opt.Quiet
    fprintf('数据   %s  (来源: %s)\n', dd, where);
    fprintf('--------------------------------------------------\n');
end
ok = true;
for i = 1:size(kinds, 1)
    [f, got] = oct_find_data(kinds{i,1}, 'Quiet', true);
    must = kinds{i,3};
    if ~got && must, ok = false; end
    if ~opt.Quiet
        if got
            if exist(f, 'dir')
                d = dir(fullfile(f, '*.png'));
                extra = sprintf('%d 张 png', numel(d));
            else
                d = dir(f);
                extra = sprintf('%.1f MB', d(1).bytes/1048576);
            end
            fprintf('  [有] %-10s %-14s %s\n', kinds{i,1}, kinds{i,2}, extra);
        elseif must
            fprintf('  [缺] %-10s %-14s <- 必需！\n', kinds{i,1}, kinds{i,2});
        else
            fprintf('  [ - ] %-10s %-14s 可选，缺了相关 demo 会跳过\n', ...
                    kinds{i,1}, kinds{i,2});
        end
    end
end

if ~opt.Quiet
    fprintf('--------------------------------------------------\n');
    if ok
        fprintf('可以开始了。试试：\n');
        fprintf('  oct_report       一张 OCT 黄斑分析报告图\n');
        fprintf('  oct_demo_all     依次跑一遍所有 demo\n');
        fprintf('  oct_selftest     跑自测\n');
        fprintf('  help oct_report  看某个函数的说明\n');
    else
        fprintf('必需的数据缺了，把数据放到 %s\n', dd);
        fprintf('或者设环境变量指过去： setenv(''OCT_DATA'', ''D:\\你的目录'')\n');
    end
    fprintf('\n');
end
end

% ======================================================================
function opt = local_parse(opt, args)
% 这里不能用 oct_parseopt —— 路径还没加进去呢
if mod(numel(args), 2) ~= 0
    error('oct_setup:args', '选项必须成对出现');
end
f = fieldnames(opt);
for k = 1:2:numel(args)
    idx = find(strcmpi(char(args{k}), f), 1);
    if isempty(idx), error('oct_setup:badOpt', '未知选项 ''%s''', char(args{k})); end
    opt.(f{idx}) = args{k+1};
end
end
