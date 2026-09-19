function [ef, info] = oct_enface(vol, bdList, varargin)
%OCT_ENFACE  按分层结果把体数据投影成 en-face（C-scan）。
%
%   ef = OCT_ENFACE(vol, bdList)
%   [ef, info] = OCT_ENFACE(vol, bdList, 'Name', value, ...)
%
%   vol    : [H x W x nBscan] 体数据（每页一幅 B-scan）
%   bdList : 1 x nBscan 的分层结果（oct_layer_seg 的输出，struct 数组或 cell）
%   ef     : [nBscan x W] en-face 投影
%
%   投影的上下界由两条分层边界（加偏移）夹出来，这样投影会跟着视网膜的
%   起伏走，而不是切一个平面 —— 中心凹下沉近百像素，切平面会把不同的
%   组织层混到一起。
%
%   选项：
%     'Slab'    预设板层（默认 'deep'）：
%                 'full'   ILM -> RPE，整个视网膜
%                 'rnfl'   ILM -> RNFL，神经纤维层
%                 'deep'   IS/OS -> RPE，外层亮带 —— 血管投影阴影在这层
%                          最清楚（实测平均梯度 11.8，比 full 的 5.2 高一倍）
%                 'subrpe' RPE -> RPE+30，RPE 下方
%                 'custom' 用 'Top'/'Bot'/'TopOff'/'BotOff' 自己指定
%     'Top'     'custom' 时的上界层名（默认 'isos'）
%     'Bot'     'custom' 时的下界层名（默认 'rpe'）
%     'TopOff'  上界的像素偏移（默认 0）
%     'BotOff'  下界的像素偏移（默认 0）
%     'Stat'    投影方式：'mean'（默认）/'max'/'sum'
%
%   info : .slab .top .bot .nBscan .width
%
%   参见 oct_layer_seg, oct_frangi2d, oct_devessel。

opt.Slab   = 'deep';
opt.Top    = 'isos';
opt.Bot    = 'rpe';
opt.TopOff = 0;
opt.BotOff = 0;
opt.Stat   = 'mean';
opt = oct_parseopt(opt, varargin);

switch lower(opt.Slab)
    case 'full',   top = 'ilm';  bot = 'rpe';  to = 0;  bo = 0;
    case 'rnfl',   top = 'ilm';  bot = 'rnfl'; to = 0;  bo = 0;
    case 'deep',   top = 'isos'; bot = 'rpe';  to = 0;  bo = 0;
    case 'subrpe', top = 'rpe';  bot = 'rpe';  to = 0;  bo = 30;
    case 'custom', top = opt.Top; bot = opt.Bot; to = opt.TopOff; bo = opt.BotOff;
    otherwise
        error('oct_enface:slab', '未知 Slab ''%s''', opt.Slab);
end

if isstruct(bdList), bdList = num2cell(bdList); end
n = numel(bdList);
[H, W, nv] = size(vol);
if nv ~= n
    error('oct_enface:size', 'vol 有 %d 页，bdList 有 %d 个', nv, n);
end

ef = zeros(n, W);
for i = 1:n
    im = vol(:, :, i);
    b  = bdList{i};
    t  = b.(top) + to;
    d  = b.(bot) + bo;
    for x = 1:W
        a1 = min(max(round(t(x)), 1), H);
        a2 = min(max(round(d(x)), 1), H);
        if a2 < a1, tmp = a1; a1 = a2; a2 = tmp; end
        if a2 == a1, a2 = min(a1 + 1, H); end
        seg = im(a1:a2, x);
        switch lower(opt.Stat)
            case 'mean', ef(i, x) = mean(seg);
            case 'max',  ef(i, x) = max(seg);
            case 'sum',  ef(i, x) = sum(seg);
            otherwise
                error('oct_enface:stat', '未知 Stat ''%s''', opt.Stat);
        end
    end
end

if nargout > 1
    info.slab   = lower(opt.Slab);
    info.top    = top;  info.topOff = to;
    info.bot    = bot;  info.botOff = bo;
    info.nBscan = n;
    info.width  = W;
end
end
