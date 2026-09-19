function bytes = oct_layer_export(path, bdList, varargin)
%OCT_LAYER_EXPORT  把分层结果写成 EOD 的 _analy.dat 格式。
%
%   bytes = OCT_LAYER_EXPORT(path, bdList)
%   bytes = OCT_LAYER_EXPORT(path, bdList, 'Name', value, ...)
%
%   bdList : 1 x nBscan 的 struct 数组（或 cell），每个是 oct_layer_seg 的输出。
%   path   : 输出文件
%   bytes  : 写了多少字节
%
%   格式是从 EOD_read_seg_data\show_analy_data_line.py 反推的：
%       16 字节头（全 0）
%       然后 nBscan x 7 x nPoint 个 uint32（小端），按 C 序：
%           for 每幅 B-scan
%               for 7 个槽位（顺序见下面 CHMAP，不是由浅到深）
%                   for 每条 A-line 的行号
%   校验：120 x 7 x 1024 x 4 + 16 = 3440656 字节，和仓库里那份
%   test_data\od-3dscan-macular-20210104-150822-001_analy.dat 的大小一模一样。
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
%     'NPoint'  每条边界重采样到多少点（默认 1024，原系统用的就是这个）。
%               分层是在 432 列的图上做的，这里线性插值上去。
%     'Header'  16 字节头的内容（默认全 0）
%     'Depth'   B-scan 的深度像素数，用来做深度翻转（默认 700）
%     'Flip'    是否做深度翻转（默认 true，和 oct_layer_import 对称）
%
%   反过来读用 oct_layer_import。
%
%   参见 oct_layer_seg, oct_layer_import。

opt.NPoint = 1024;
opt.Header = zeros(1, 16, 'uint8');
opt.Depth  = 700;
opt.Flip   = true;
opt = oct_parseopt(opt, varargin);

if isstruct(bdList), bdList = num2cell(bdList); end
if ~iscell(bdList), error('oct_layer_export:arg', 'bdList 要是 struct 数组或 cell'); end
n = numel(bdList);
if n == 0, error('oct_layer_export:empty', 'bdList 是空的'); end

% 由浅到深的层名 -> 文件里的槽位号（实测，见上面的说明）
names = {'ilm', 'rnfl', 'ipl', 'inl', 'opl', 'isos', 'rpe'};
CHMAP = [3, 4, 5, 6, 7, 2, 1];     % 见上面的说明
N = opt.NPoint;

buf = zeros(N, 7, n, 'uint32');
for i = 1:n
    bd = bdList{i};
    for k = 1:7
        y = bd.(names{k});
        y = y(:).';
        if numel(y) ~= N
            % 线性重采样到 N 点（分层在 432 列上做，原系统存 1024 点）
            y = interp1(linspace(0, 1, numel(y)), y, linspace(0, 1, N), 'linear');
        end
        bad = ~isfinite(y);
        if opt.Flip
            y = opt.Depth + 1 - y;              % 回到文件的深度方向
        end
        y(bad) = 0;                             % 无效点在文件里记 0
        buf(:, CHMAP(k), i) = uint32(max(round(y), 0));
    end
end

fid = fopen(path, 'w');
if fid < 0, error('oct_layer_export:open', '写不了: %s', path); end
c = onCleanup(@() fclose(fid));   %#ok<NASGU>
h = uint8(opt.Header); h(end+1:16) = 0;
fwrite(fid, h(1:16), 'uint8');
fwrite(fid, buf, 'uint32');       % 列优先展开正好是 point->line->bscan
bytes = 16 + numel(buf)*4;
end
