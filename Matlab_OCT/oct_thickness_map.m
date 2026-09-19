function [T, info] = oct_thickness_map(bdList, varargin)
%OCT_THICKNESS_MAP  从分层结果算层厚图，对应 Analy_and_image_show\oct_thickness.py。
%
%   T = OCT_THICKNESS_MAP(bdList)
%   [T, info] = OCT_THICKNESS_MAP(bdList, 'Name', value, ...)
%
%   bdList : 1 x nBscan 的分层结果（oct_layer_seg / oct_layer_import 的输出）
%   T      : [nBscan x nAline] 厚度图。默认单位是微米。
%
%   选项：
%     'Top'    上界层名（默认 'ilm'）
%     'Bot'    下界层名（默认 'rpe'）—— 默认算全视网膜厚度
%     'Unit'   'um'（默认）/ 'px'
%     'PixZ'   深度方向的像素间距，微米（默认 2.44141，来自
%              oct_thickness.py 里的 pix_z = 0.00244141 mm）
%     'NAline' 输出宽度，[] = 用分层结果里非零的列数（默认 []）
%
%   info : .top .bot .unit .pixZ .median .p5 .p95 .valid（有效像素比例）
%
%   常用的几对：
%     ilm  -> rpe    全视网膜厚度（正常黄斑 200~350 um）
%     ilm  -> rnfl   RNFL 厚度（中心凹趋 0，周边 20~50 um）
%     isos -> rpe    RPE 复合体
%
%   注意 oct_thickness.py 里算的是 oct_pos[1]-oct_pos[2]，按文件里的原始
%   槽位号取的，实际是 RNFL 到 RPE（跨了大半个视网膜，225 um），
%   不是哪一层的厚度。脚本里那句空注释 "#整理分层的正确顺序" 就是这个意思，
%   槽位到层的映射见 oct_layer_import 的说明。
%
%   参见 oct_layer_import, oct_deviation_map, oct_analy_demo。

opt.Top    = 'ilm';
opt.Bot    = 'rpe';
opt.Unit   = 'um';
opt.PixZ   = 2.44141;
opt.NAline = [];
opt = oct_parseopt(opt, varargin);

if isstruct(bdList), bdList = num2cell(bdList); end
n = numel(bdList);
if n == 0, error('oct_thickness_map:empty', 'bdList 是空的'); end

names = fieldnames(bdList{1});
for nm = {opt.Top, opt.Bot}
    if ~any(strcmp(nm{1}, names))
        error('oct_thickness_map:layer', ...
              '没有 ''%s'' 这一层，可用的是: %s', nm{1}, strjoin(names.', ', '));
    end
end

% 输出宽度：取各幅里"最后一个有效列"的最大值。
% 早先取的是最小值（要求所有幅都有效），但这份数据有 9 幅末尾几列缺失，
% 那样会把另外 111 幅完整的 432 列一起砍到 403。缺的地方留 NaN 就行，
% 下游（oct_deviation_map）本来就忽略 NaN。
W = opt.NAline;
if isempty(W)
    W = 0;
    for i = 1:n
        v = bdList{i}.(opt.Top);
        good = find(isfinite(v) & v > 0);
        if ~isempty(good), W = max(W, good(end)); end
    end
    if W == 0, W = numel(bdList{1}.(opt.Top)); end
end

T = nan(n, W);
for i = 1:n
    a = bdList{i}.(opt.Top);
    b = bdList{i}.(opt.Bot);
    m = min(W, min(numel(a), numel(b)));
    d = b(1:m) - a(1:m);
    d(~isfinite(a(1:m)) | ~isfinite(b(1:m))) = NaN;
    d(a(1:m) <= 0 | b(1:m) <= 0) = NaN;       % 0 是"无效"
    T(i, 1:m) = d;
end

if strcmpi(opt.Unit, 'um')
    T = T * opt.PixZ;
elseif ~strcmpi(opt.Unit, 'px')
    error('oct_thickness_map:unit', '''Unit'' 只能是 ''um'' 或 ''px''');
end

if nargout > 1
    v = sort(T(isfinite(T)));
    info.top   = opt.Top;
    info.bot   = opt.Bot;
    info.unit  = lower(opt.Unit);
    info.pixZ  = opt.PixZ;
    info.valid = numel(v) / numel(T);
    if isempty(v)
        info.median = NaN; info.p5 = NaN; info.p95 = NaN;
    else
        info.median = median(v);
        info.p5  = v(max(1, ceil(0.05*numel(v))));
        info.p95 = v(max(1, ceil(0.95*numel(v))));
    end
end
end
