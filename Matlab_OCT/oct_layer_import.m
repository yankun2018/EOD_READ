function [bdList, info] = oct_layer_import(path, varargin)
%OCT_LAYER_IMPORT  读 EOD 的 _analy.dat 分层结果。
%
%   bdList = OCT_LAYER_IMPORT(path)
%   [bdList, info] = OCT_LAYER_IMPORT(path, 'Name', value, ...)
%
%   格式见 oct_layer_export：16 字节头 + nBscan x 7 x nPoint 个 uint32。
%   仓库里的 test_data\od-3dscan-macular-20210104-150822-001_analy.dat
%   就是原 exe 对同目录那份 .dat 跑出来的结果（120 幅 x 7 线 x 1024 点，
%   其中每幅只有前 432 列非 0 —— 那次扫描就是 432 条 A-line）。
%
%   两件事要同时处理，否则层的语义会整体反过来：
%
%   1) **深度方向**。文件里存的深度值是"从脉络膜侧数"的，和本工具箱
%      "第 1 行最浅（ILM 侧）"的约定相反，要做 y -> Depth+1-y。
%      Analy_and_image_show 那三个 Python 脚本里的 `700 - m` 就是这件事。
%   2) **槽位顺序**。文件里 7 个槽位不是按深度排的。翻转之后实测
%      （120 幅 x 432 有效列）由浅到深是
%          ch3 < ch4 < ch5 < ch6 < ch7 < ch2 < ch1
%      即 ch3=ILM ch4=RNFL ch5=IPL ch6=INL ch7=OPL ch2=IS/OS ch1=RPE。
%
%   语义是拿三个生理判据定下来的，不是猜的：
%     * 玻璃体腔应当最暗：ILM 之上亮度 38.9，RPE 之下 86.9（脉络膜）
%     * RNFL 紧贴 ILM，厚度在中心凹趋 0、周边厚，变化幅度应远大于
%       RPE-IS/OS（后者厚度基本恒定）：实测 30 px vs 6 px
%     * 全层 ILM->RPE 厚度 118 px = 288 um，落在正常黄斑 200~350 um 内
%   反过来取（ch1=ILM）这三条全都不成立。
%
%   选项：
%     'NPoint'   每条边界多少点（默认 1024）
%     'NBscan'   读几幅，Inf = 按文件大小推（默认 Inf）
%     'Depth'    B-scan 的深度像素数，用来做深度翻转（默认 700）
%     'Flip'     是否做深度翻转（默认 true）。设 false 就拿文件里的原始值，
%                此时层的语义是反的（ch1 那一侧变成最浅），只在对照原始
%                字节时才用。
%
%   bdList : 1 x nBscan 的 struct 数组，字段同 oct_layer_seg
%   info   : .nBscan .nPoint .bytes
%
%   参见 oct_layer_export, oct_layer_seg。

opt.NPoint = 1024;
opt.NBscan = Inf;
opt.Depth  = 700;
opt.Flip   = true;
opt = oct_parseopt(opt, varargin);

d = dir(path);
if isempty(d), error('oct_layer_import:noFile', '找不到: %s', path); end

N = opt.NPoint;
per = 7 * N * 4;                       % 一幅占多少字节
avail = floor((d.bytes - 16) / per);
if avail < 1
    error('oct_layer_import:tooSmall', ...
          '%s 只有 %d 字节，不够一幅（头 16 + 7x%d x4 = %d）', ...
          path, d.bytes, N, 16 + per);
end
n = avail;
if isfinite(opt.NBscan), n = min(n, opt.NBscan); end

fid = fopen(path, 'r');
if fid < 0, error('oct_layer_import:open', '打不开: %s', path); end
c = onCleanup(@() fclose(fid));   %#ok<NASGU>
fread(fid, 16, 'uint8');               % 跳过头
raw = fread(fid, N*7*n, 'uint32=>double');
raw = reshape(raw, N, 7, n);

names = {'ilm', 'rnfl', 'ipl', 'inl', 'opl', 'isos', 'rpe'};
CHMAP = [3, 4, 5, 6, 7, 2, 1];     % 由浅到深 -> 文件槽位，见上面的说明
bdList = repmat(struct(), 1, n);
for i = 1:n
    for k = 1:7
        y = raw(:, CHMAP(k), i).';
        if opt.Flip
            z = (y == 0);                       % 0 是"无效"，别把它翻成 Depth+1
            y = opt.Depth + 1 - y;
            y(z) = NaN;
        end
        bdList(i).(names{k}) = y;
    end
end

info.nBscan = n;
info.nPoint = N;
info.bytes  = d.bytes;
info.extra  = d.bytes - 16 - n*per;
end
