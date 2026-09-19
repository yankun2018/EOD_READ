function [data, info] = oct_load_spectrum(path, varargin)
%OCT_LOAD_SPECTRUM  读取 OCT 原始光谱数据，统一返回 [nLine x nPoint] 矩阵。
%
%   data = OCT_LOAD_SPECTRUM(path)
%   data = OCT_LOAD_SPECTRUM(path, 'Name', value, ...)
%
%   支持的格式（'Format' 选项，默认 'auto' 按扩展名猜）：
%     'csv'    每行一条 A-line 的纯数字 CSV（行尾可以有多余逗号）。
%              例：Desktop\Desktop\octifft\oct_origin_spectrum.csv
%              5951 x 2048，12 bit (0~4095)。
%     'raw16'  连续的 uint16 小端流，按 'AlineLength' 切条。
%              例：faster_3dim_scan_vulkan\test2_16bit.raw
%              872415232 B = 262144 条 x 1664 点 = 512 幅 B-scan x 512 线。
%     'raw12'  连续的 12 bit 打包流：每 3 字节 = 2 个采样，
%              位序与 Spectrum_read\read_all_bin.cpp 完全一致：
%                  n1 = (b0 << 4) | (b1 & 0x0F)
%                  n2 = (b2 << 4) | (b1 >> 4)
%     'eodbin' EOD 采集板的 socket 块格式：每 8932 字节一块，
%              块首 8 字节是计数头，其余 8924 字节是连续的 12 bit 流
%              （跨块拼接）。test_data\bin 正好是一整块 ~2.9 条 A-line。
%              注意：read_all_bin.cpp 里每 88 块还有一次 60+8 字节的 epoch 头，
%              这里没有处理——只有块数很多时才需要补上。
%
%   其它选项：
%     'AlineLength'  每条 A-line 的点数。csv 用第一行自动判断，其余格式必填
%                    （默认 1664，对应 vulkan 工程那份草莓数据）。
%     'MaxLines'     最多读多少条 A-line，Inf 表示全读（默认 Inf）。
%     'SkipLines'    先跳过多少条 A-line（默认 0）。
%     'Range'        [首行 末行]，1-based 闭区间，比 SkipLines/MaxLines 直观。
%                    等价于 SkipLines = 首行-1, MaxLines = 末行-首行+1。
%                    给了 Range 就以它为准（会覆盖 SkipLines/MaxLines）。
%                    末行给 Inf 表示"从首行读到文件尾"。
%
%   info 返回 .format .nLine .nPoint .bytes 供检查。
%
%   参见 oct_show_spectrum, oct_recon_demo。

opt.Format      = 'auto';
opt.AlineLength = 1664;
opt.MaxLines    = Inf;
opt.SkipLines   = 0;
opt.Range       = [];
opt = local_parseopt(opt, varargin);
opt = local_applyRange(opt);

if ~exist(path, 'file')
    error('oct_load_spectrum:noFile', '文件不存在: %s', path);
end

fmt = lower(opt.Format);
if strcmp(fmt, 'auto')
    [~, base, ext] = fileparts(path);
    switch lower(ext)
        case '.csv'
            fmt = 'csv';
        case '.raw'
            fmt = 'raw16';
        otherwise
            % 没有扩展名的 test_data\bin 走 socket 块格式
            if strcmpi(base, 'bin')
                fmt = 'eodbin';
            else
                fmt = 'raw16';
            end
    end
end

switch fmt
    case 'csv'
        data = local_read_csv(path, opt);
    case 'raw16'
        % 每个采样 2 字节，SkipLines 直接 fseek 过去，不从头读
        [skipSamp, needSamp, opt] = local_budget(opt);
        raw  = local_read_bytes(path, needSamp * 2, skipSamp * 2);
        s    = double(typecast(raw(1:2*floor(numel(raw)/2)), 'uint16'));
        data = local_fold(s, opt);
    case 'raw12'
        % 每 3 字节 2 个采样：只能 seek 到整组，余下的半组当采样丢掉
        [skipSamp, needSamp, opt] = local_budget(opt);
        grp  = floor(skipSamp / 2);          % 完整跳过的 3 字节组数
        rem_ = skipSamp - grp * 2;           % 组内还要丢几个采样
        raw  = local_read_bytes(path, ceil((needSamp + rem_) / 2) * 3, grp * 3);
        s    = local_unpack12(raw);
        data = local_fold(s(rem_+1:end), opt);
    case 'eodbin'
        blk  = 8932;      % 一个 socket 块的总长
        hdr  = 8;         % 块首计数头
        % 先算 payload 要多少字节，再按整块向上取整加回块头
        needPayload = ceil(local_need_samples(opt) / 2) * 3;
        if isfinite(needPayload)
            needBytes = ceil((needPayload + 1) / (blk - hdr)) * blk;
        else
            needBytes = Inf;
        end
        raw  = local_read_bytes(path, needBytes);
        nblk = floor(numel(raw) / blk);
        if nblk == 0
            % 不足一块也照样把去掉头的部分拆出来
            payload = raw(hdr+1:end);
        else
            m = reshape(raw(1:nblk*blk), blk, nblk);
            payload = reshape(m(hdr+1:end, :), [], 1);
            tail = raw(nblk*blk+1:end);
            if numel(tail) > hdr
                payload = [payload; tail(hdr+1:end)];
            end
        end
        data = local_fold(local_unpack12(payload), opt);
    otherwise
        error('oct_load_spectrum:badFormat', '未知格式: %s', fmt);
end

info.format = fmt;
info.nLine  = size(data, 1);
info.nPoint = size(data, 2);
d = dir(path);
info.bytes  = d.bytes;
end

% ------------------------------------------------------------------
function raw = local_read_bytes(path, nbytes, skipBytes)
% 从 skipBytes 处开始读 nbytes 个字节（nbytes = Inf 表示读到文件尾）。
% 这一步很关键：test2_16bit.raw 有 872 MB，整份读进来再 double() 会撑到 3.5 GB，
% 所以 MaxLines 要直接限制读盘量，SkipLines 要用 fseek 跳过去而不是读了再丢。
if nargin < 2 || isempty(nbytes) || ~isfinite(nbytes)
    nbytes = Inf;
else
    nbytes = max(ceil(nbytes), 0);
end
if nargin < 3 || isempty(skipBytes)
    skipBytes = 0;
end
fid = fopen(path, 'r');
if fid < 0, error('oct_load_spectrum:open', '打不开: %s', path); end
c = onCleanup(@() fclose(fid));   %#ok<NASGU>
if skipBytes > 0 && fseek(fid, skipBytes, 'bof') ~= 0
    raw = zeros(0, 1, 'uint8');   % 跳过了文件尾，直接空
    return;
end
raw = fread(fid, nbytes, '*uint8');
end

% ------------------------------------------------------------------
function [skipSamp, needSamp, opt] = local_budget(opt)
% 把 SkipLines / MaxLines 换算成"跳多少个采样、读多少个采样"。
% 跳的部分交给 fseek，所以要把 opt.SkipLines 清零，免得 local_fold 再跳一次。
if isempty(opt.AlineLength)
    skipSamp = 0; needSamp = Inf; return;
end
skipSamp = opt.SkipLines * opt.AlineLength;
if isfinite(opt.MaxLines)
    needSamp = opt.MaxLines * opt.AlineLength;
else
    needSamp = Inf;
end
opt.SkipLines = 0;
end

% ------------------------------------------------------------------
function n = local_need_samples(opt)
% 按 SkipLines + MaxLines 算出最少需要多少个采样，Inf = 全要。
% eodbin 有块头夹在中间，不好直接 seek，所以还是从头读。
if ~isfinite(opt.MaxLines) || isempty(opt.AlineLength)
    n = Inf;
else
    n = (opt.SkipLines + opt.MaxLines) * opt.AlineLength;
end
end

% ------------------------------------------------------------------
function s = local_unpack12(raw)
% 3 字节 -> 2 个 12 bit 采样，位序同 read_all_bin.cpp
n = 3 * floor(numel(raw) / 3);
b = reshape(double(raw(1:n)), 3, []);
n1 = b(1,:) * 16 + mod(b(2,:), 16);
n2 = b(3,:) * 16 + floor(b(2,:) / 16);
s  = reshape([n1; n2], 1, []);
end

% ------------------------------------------------------------------
function data = local_fold(s, opt)
% 一维采样流 -> [nLine x nPoint]
N = opt.AlineLength;
if isempty(N) || N < 2
    error('oct_load_spectrum:alineLength', '这种格式必须给 AlineLength');
end
s = s(:).';
skip = opt.SkipLines * N;
if skip >= numel(s)
    data = zeros(0, N);
    return;
end
s = s(skip+1:end);
nLine = floor(numel(s) / N);
if isfinite(opt.MaxLines)
    nLine = min(nLine, opt.MaxLines);
end
if nLine == 0
    % 不够一整条时，补零凑一条，方便看 test_data\bin 这种碎片
    nLine = 1;
    s(end+1:N) = 0;
end
data = reshape(s(1:nLine*N), N, nLine).';
end

% ------------------------------------------------------------------
function data = local_read_csv(path, opt)
fid = fopen(path, 'r');
if fid < 0, error('oct_load_spectrum:open', '打不开: %s', path); end
c = onCleanup(@() fclose(fid));

% 先看第一行定宽度
first = fgetl(fid);
if ~ischar(first)
    error('oct_load_spectrum:emptyCsv', '空文件: %s', path);
end
v0 = sscanf(strtrim(first), '%f,');
N  = numel(v0);

frewind(fid);
for k = 1:opt.SkipLines
    if ~ischar(fgetl(fid)), break; end
end

chunk = 4096;
data  = zeros(chunk, N);
nLine = 0;
while nLine < opt.MaxLines
    ln = fgetl(fid);
    if ~ischar(ln), break; end
    ln = strtrim(ln);
    if isempty(ln), continue; end
    v = sscanf(ln, '%f,');
    if numel(v) < N
        v(end+1:N) = 0;      %#ok<AGROW>
    end
    nLine = nLine + 1;
    if nLine > size(data, 1)
        data(end+chunk, N) = 0;   % 成倍扩容
    end
    data(nLine, :) = v(1:N).';
end
data = data(1:nLine, :);
end

% ------------------------------------------------------------------
function opt = local_applyRange(opt)
% 'Range' [首行 末行] -> SkipLines / MaxLines
if isempty(opt.Range)
    return;
end
r = opt.Range;
if numel(r) ~= 2
    error('oct_load_spectrum:range', '''Range'' 要给 [首行 末行] 两个数');
end
first = r(1); last = r(2);
if ~isfinite(first) || first < 1 || first ~= fix(first)
    error('oct_load_spectrum:range', '首行要是 >= 1 的整数，给的是 %g', first);
end
if last < first
    error('oct_load_spectrum:range', '末行 %g 小于首行 %g', last, first);
end
opt.SkipLines = first - 1;
if isfinite(last)
    opt.MaxLines = last - first + 1;
else
    opt.MaxLines = Inf;      % [首行 Inf] = 读到文件尾
end
end

% ------------------------------------------------------------------
function opt = local_parseopt(opt, args)
if mod(numel(args), 2) ~= 0
    error('oct_load_spectrum:args', '选项必须成对出现');
end
f = fieldnames(opt);
for k = 1:2:numel(args)
    idx = find(strcmpi(args{k}, f), 1);
    if isempty(idx)
        error('oct_load_spectrum:badOpt', '未知选项: %s', args{k});
    end
    opt.(f{idx}) = args{k+1};
end
end
