function [p, where] = oct_datadir(sub)
%OCT_DATADIR  解析示例数据所在的目录。
%
%   p = OCT_DATADIR
%   p = OCT_DATADIR(sub)
%   [p, where] = OCT_DATADIR(...)
%
%   所有 demo 的默认数据路径都走这个函数，这样整包换个地方解压也能跑。
%   按顺序找，用第一个存在的：
%     1. 环境变量 OCT_DATA 指的目录
%     2. 本工具箱目录下的 data\        <- 打包分发时数据放这儿
%     3. 上一级的 test_data\           <- 在 EOD_READ 仓库里直接用时
%     4. 开发机上那几个散落的目录（Desktop\octifft 等）
%
%   sub 给了就再往下拼一层，并且**不检查是否存在**（调用方自己判断）：
%     oct_datadir('volume')    体数据和分层结果
%     oct_datadir('bscan')     B-scan 的 PNG
%     oct_datadir('spectrum')  原始光谱
%
%   where 返回命中的是哪一条（'env' / 'pkg' / 'repo' / 'dev' / 'none'）。
%
%   参见 oct_setup, oct_demo_all。

here = fileparts(mfilename('fullpath'));

cand = {};
ev = getenv('OCT_DATA');
if ~isempty(ev), cand{end+1} = {ev, 'env'}; end
cand{end+1} = {fullfile(here, 'data'),           'pkg'};
cand{end+1} = {fullfile(here, '..', 'test_data'), 'repo'};

p = ''; where = 'none';
for i = 1:numel(cand)
    if exist(cand{i}{1}, 'dir')
        p = cand{i}{1};
        where = cand{i}{2};
        break;
    end
end
if isempty(p)
    p = fullfile(here, 'data');       % 不存在也返回它，报错信息里好看
    where = 'none';
end

if nargin > 0 && ~isempty(sub)
    p = fullfile(p, sub);
end
end
