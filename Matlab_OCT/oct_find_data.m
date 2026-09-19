function [f, ok] = oct_find_data(kind, varargin)
%OCT_FIND_DATA  找某类示例数据的具体路径。
%
%   f = OCT_FIND_DATA(kind)
%   [f, ok] = OCT_FIND_DATA(kind, 'Quiet', true)
%
%   kind 可以是：
%     'volume'    原始三维体数据 .dat
%     'analy'     分层结果 _analy.dat
%     'bscan'     B-scan PNG 所在的目录
%     'spectrum'  原始光谱 CSV
%     'rawbin'    12 bit socket 块的碎片（test_data\bin）
%     'strawberry' vulkan 工程那份 test2_16bit.raw（一般不在包里）
%
%   会在几个候选位置里挨个找（见 oct_datadir），找不到就报错，
%   并把找过的地方和下载地址一起打出来 —— 数据太大的那几份没放进包里。
%
%   选项：
%     'Quiet'  true 时找不到只返回 ok=false，不报错（默认 false）
%
%   参见 oct_datadir, oct_setup。

opt.Quiet = false;
opt = oct_parseopt(opt, varargin);

base = oct_datadir();
here = fileparts(mfilename('fullpath'));
dev  = fullfile(here, '..', '..', 'Desktop');    % 开发机上那几个散落目录

% 每一类：{相对 base 的候选, 开发机候选, 是不是目录, 说明}
switch lower(kind)
    case 'volume'
        pats = {fullfile(base, 'volume', '*.dat'), ...
                fullfile(base, '*-001.dat'), ...
                fullfile(here, '..', 'test_data', '*-001.dat')};
        isDir = false;
        note = '原始三维体数据（120 x 432 x 700）';
        excl = '_analy';
    case 'analy'
        pats = {fullfile(base, 'volume', '*_analy.dat'), ...
                fullfile(base, '*_analy.dat'), ...
                fullfile(here, '..', 'test_data', '*_analy.dat')};
        isDir = false; note = '原 exe 的分层结果'; excl = '';
    case 'bscan'
        pats = {fullfile(base, 'bscan'), ...
                fullfile(dev, 'pic_md_origin', 'pic_bscan'), ...
                fullfile(dev, 'pic_md')};
        isDir = true; note = 'B-scan 的 PNG（带 7 条分层线）'; excl = '';
    case 'spectrum'
        pats = {fullfile(base, 'spectrum', '*spectrum*.csv'), ...
                fullfile(base, 'spectrum', '*.csv'), ...
                fullfile(dev, 'octifft', 'oct_origin_spectrum.csv')};
        isDir = false; note = '原始光谱 CSV'; excl = '';
    case 'rawbin'
        pats = {fullfile(base, 'spectrum', 'bin'), ...
                fullfile(base, 'bin'), ...
                fullfile(here, '..', 'test_data', 'bin')};
        isDir = false; note = '12 bit socket 块碎片'; excl = '';
    case 'strawberry'
        pats = {fullfile(base, 'volume', 'test2_16bit.raw'), ...
                fullfile(dev, 'faster_3dim_scan_vulkan', 'test2_16bit.raw')};
        isDir = false;
        note = ['草莓测试集（872 MB，没放进包里）。下载: ' ...
                'https://figshare.com/articles/dataset/' ...
                'SSOCT_test_dataset_for_OCTproZ/12356705'];
        excl = '';
    otherwise
        error('oct_find_data:kind', '未知数据类型 ''%s''', kind);
end

f = ''; ok = false;
for i = 1:numel(pats)
    if isDir
        if exist(pats{i}, 'dir')
            d = dir(fullfile(pats{i}, '*.png'));
            if ~isempty(d), f = pats{i}; ok = true; break; end
        end
    else
        d = dir(pats{i});
        d = d(~[d.isdir]);
        if ~isempty(excl)
            d = d(cellfun(@(n) isempty(strfind(n, excl)), {d.name}));  %#ok<STREMP>
        end
        if ~isempty(d)
            f = fullfile(fileparts(pats{i}), d(1).name);
            ok = true; break;
        end
    end
end

if ~ok && ~opt.Quiet
    msg = sprintf('找不到 %s（%s）。找过这些地方:\n', kind, note);
    for i = 1:numel(pats)
        msg = [msg sprintf('  %s\n', pats{i})];  %#ok<AGROW>
    end
    msg = [msg sprintf(['也可以设环境变量指过去:\n' ...
           '  setenv(''OCT_DATA'', ''D:\\你的数据目录'')\n'])];
    error('oct_find_data:notFound', '%s', msg);
end
end
