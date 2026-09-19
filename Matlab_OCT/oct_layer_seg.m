function [bd, aux] = oct_layer_seg(img, varargin)
%OCT_LAYER_SEG  OCT B-scan 视网膜 7 层边界分割（图论最短路）。
%
%   bd = OCT_LAYER_SEG(img)
%   bd = OCT_LAYER_SEG(img, 'Name', value, ...)
%   [bd, aux] = OCT_LAYER_SEG(...)
%
%   img : [H x W] 灰度 B-scan，深度沿行（第 1 行最浅）、A-line 沿列。
%   bd  : 结构体，7 个字段各是 1 x W 的行向量（亚像素行号，1-based）：
%           ilm   内界膜 ILM                （暗->亮，最上）
%           rnfl  RNFL/GCL                  （亮->暗）
%           ipl   IPL/INL                   （亮->暗）
%           inl   INL/OPL                   （暗->亮）
%           opl   OPL/ONL                   （亮->暗）
%           isos  IS/OS 椭圆体带            （暗->亮，强）
%           rpe   RPE/BM                    （亮->暗，强，最下）
%   aux : 中间量（粗定位的 top/bot、两种梯度图），调参时看
%
%   方法是 Chiu et al. 2010 那一套（Optics Express 18(18):19413）：
%   把每一列的每个像素当成图的节点，边权 w = 2 - (g_a + g_b) + eps，
%   g 是归一化到 [0,1] 的垂直梯度；梯度越强权重越小，于是"沿着边界走"
%   就是从最左列到最右列的最短路。逐层做，每定出一层就用它限制下一层的
%   搜索范围。这也是被封进 EOD_read_seg.exe 里那个 DIJK_SEG.m 的思路。
%
%   与教科书版本的两处出入，都是这批数据逼出来的：
%   * **软先验**。中心凹处内层被压扁（实测内层相对 ILM 的偏移从周边的
%     40/55/64 px 压到 15/25/31），单靠硬区间会让 IPL/INL/OPL 在过渡区
%     跑飞。所以按 ILM->ISOS 的归一化比例给一个期望深度，偏离越远权重
%     越大（二次惩罚，截断在 alpha）。
%   * **RNFL 算两轮**。RNFL 要 IPL 定上界、IPL 又要 RNFL 定下界，
%     循环依赖。先用宽约束粗算一次 RNFL 把 IPL 框出来，最后再回头精修。
%
%   选项：
%     'Offsets'   1x7 逐层偏移（像素），加到结果上。默认是拿
%                 Desktop\pic_md 那 120 张标定出来的值，见下面 DEFOFF。
%                 传 zeros(1,7) 可以看未校正的原始输出。
%     'Smooth'    路径平滑的高斯 sigma（默认 5，RNFL 用 6）
%     'Alpha'     内层软先验强度（默认 0.20，0 = 关掉）
%     'RnflAlpha' RNFL 的先验强度（默认 0.10，比内层弱）
%     'RnflFrac'/'IplFrac'/'InlFrac'/'OplFrac'  各层期望深度比例
%     'RpePrior'  RPE 是否也用比例先验（默认 1）
%     'PreSigma'  预平滑 sigma（默认 3）
%
%   只用基础 MATLAB，不需要图像处理工具箱。
%
%   参见 oct_layer_gt, oct_layer_demo。

% 逐层偏移的默认值：算法定在灰度跃变的中心，而这批 GT 标得略深，每层稳定
% 偏 1.3~3.6 px（ILM/ISOS/RPE 这三条强边界的标准差只有 0.8~1.0，非常一致）。
% 这是标注习惯的差异，不是算法误差 —— 换一套数据/另一个标注者就该重标，
% 别当成物理常数。传 zeros(1,7) 看未校正的原始输出。
% 标定方式：pic_md 全部 120 张的有符号偏差取反。
% 诚实的数字：拿奇数 60 张标定、偶数 60 张验证，3.42 -> 2.02 px。
DEFOFF = [2.55, 2.41, 3.22, 3.13, 2.23, 2.57, 3.39];

opt.Offsets   = DEFOFF;
opt.Smooth    = 5;
% 内层先验强度。实测越弱越好（0.30->0.08 让总体从 2.40 降到 2.28）——
% 先验只该在中心凹那种"没有梯度可循"的地方兜底，别跟图像证据抢方向。
opt.Alpha     = 0.08;
% 预平滑不能太强：RNFL/GCL 那条边界本来就弱，sigma=3 会把它糊掉。
% 实测 3 -> 2 让 RNFL 从 3.70 降到 2.76，最难的那张（img_0062）4.06 -> 3.01。
opt.PreSigma  = 2;
% 内层的期望深度，按 (层 - ILM)/(ISOS - ILM) 给。默认值是拿 pic_md 那
% 120 张的 GT 逐列统计出来的中位数，不是拍的：
%   RNFL 0.168(σ.103) | IPL 0.430(σ.074) | INL 0.567(σ.066) | OPL 0.653(σ.063)
% RNFL 的方差最大 —— 中心凹处厚度趋近 0、周边厚，所以它最难定。
opt.RnflFrac  = 0.168;
opt.IplFrac   = 0.430;
opt.InlFrac   = 0.567;
opt.OplFrac   = 0.653;
opt.RnflAlpha = 0.10;    % RNFL 单独一档：它的厚度方差最大（σ=0.103），
                         % 先验给太强反而把它按死，实测 0.10 比 0.30 好
% RNFL 厚度的绝对上界（px）。GT 统计：中位 13、95% 36、最大 63，跨度极大，
% 中心凹及其颞侧几乎贴着 ILM（1~3 px），用比例先验按不住 —— 见 README。
% [] = 不用这个上界，只靠 IPL 兜。
opt.RnflMaxThick = [];
% RNFL 先验的来源：
%   'frac'  固定比例 RnflFrac*span（老做法，表达不了"一侧薄一侧厚"）
%   'band'  从图像本身估 RNFL 亮带的下缘。想法是 RNFL 在中心凹及其颞侧会
%           整段消失（GT 实测厚度 1~3 px），固定比例会把线硬拉走 20 多 px。
%           但实测反而更差（RNFL 3.70 -> 6.73）—— 亮带下缘在薄区本身就没有
%           明确的亮度台阶可找。代码留着，默认不用。
opt.RnflPrior = 'frac';
% 先验尺度（psig）是否随 span 缩放。动机是 img_0119/0120 的 span 只有 79 px
% （正常 ~98），内层系统偏深 7~9 px。但实测没用（2.278 -> 2.342），默认关。
opt.PriorScaleSpan = 0;
opt.RpePrior  = 1;       % 1 = RPE 也用比例先验（GT 统计 1.299），0 = 只用硬区间
opt = oct_parseopt(opt, varargin);

img = double(img);
if ndims(img) ~= 2 %#ok<ISMAT>
    error('oct_layer_seg:dims', 'img 要是二维灰度图，给的是 %s', mat2str(size(img)));
end
[H, W] = size(img);
if H < 40 || W < 8
    error('oct_layer_seg:tooSmall', '图太小: %d x %d', H, W);
end

% ---- 预处理：平滑 + 归一化 ------------------------------------------
im = local_gauss2(img, opt.PreSigma, opt.PreSigma);
im = (im - min(im(:))) / (max(im(:)) - min(im(:)) + 1e-12);

gUp = local_vgrad(im, +1);    % 暗->亮（向下变亮）
gDn = local_vgrad(im, -1);    % 亮->暗

% ---- 粗定位视网膜带 --------------------------------------------------
[top, bot] = local_locate(im, opt.Smooth);

sm = opt.Smooth;
a  = opt.Alpha;
aR = opt.RnflAlpha; if isempty(aR), aR = a; end
cl = @(v) min(max(v, 1), H);          % 钳到合法行号

% ---- 1) ILM：视网膜带上缘最强的 暗->亮 -------------------------------
ilm = local_sp(gUp, cl(top-25), cl(top+25), [], 0, H);
ilm = local_smooth(ilm, sm);

% ---- 2) IS/OS：ILM 下方最强的 暗->亮（外层亮带的上缘）---------------
isos = local_sp(gUp, cl(ilm+55), cl(bot+10), [], 0, H);
isos = local_smooth(isos, sm);

% ILM->ISOS 的跨度，内层期望深度都按它折算
span = max(isos - ilm, 20);

% 先验尺度的缩放系数：1 = 固定尺度；开了就按 span 相对 100 px 缩放
if opt.PriorScaleSpan
    psScale = mean(span) / 100;
else
    psScale = 1;
end

% RNFL 的先验中心：固定比例还是从图像估亮带下缘
if strcmpi(opt.RnflPrior, 'band')
    muR = local_rnfl_band(im, ilm, span, sm);
else
    muR = ilm + opt.RnflFrac*span;
end

% ---- 3) RPE/BM：IS/OS 下方最强的 亮->暗 ------------------------------
if opt.RpePrior
    rpe = local_sp(gDn, cl(isos+12), cl(isos+60), ilm + 1.299*span, a, H, 20*psScale);
else
    rpe = local_sp(gDn, cl(isos+12), cl(isos+60), [], 0, H);
end
rpe = local_smooth(rpe, sm);

% ---- 4) OPL/ONL ------------------------------------------------------
opl = local_sp(gDn, cl(ilm+14), cl(isos-14), ilm + opt.OplFrac*span, a, H, 22*psScale);
opl = local_smooth(opl, sm);

% ---- 5) RNFL/GCL 粗定位（为了把 IPL 框出来）-------------------------
hiR0 = cl(opl-16);
if ~isempty(opt.RnflMaxThick)
    hiR0 = min(hiR0, cl(ilm + opt.RnflMaxThick));
end
rnfl0 = local_sp(gDn, cl(ilm+2), hiR0, muR, aR, H, 16*psScale);
rnfl0 = local_smooth(rnfl0, sm + 1);

% ---- 6) IPL/INL ------------------------------------------------------
ipl = local_sp(gDn, cl(rnfl0+3), cl(opl-8), ilm + opt.IplFrac*span, a, H, 18*psScale);
ipl = local_smooth(ipl, sm);

% ---- 7) INL/OPL ------------------------------------------------------
inl = local_sp(gUp, cl(ipl+3), cl(opl-3), ilm + opt.InlFrac*span, a, H, 16*psScale);
inl = local_smooth(inl, sm);

% ---- 8) RNFL/GCL 精修：夹在 ILM 和 IPL 之间 --------------------------
% 中心凹处 RNFL 厚度趋近 0，会紧贴 ILM（实测只差 3 px），所以下界给 ilm+1
hiR = cl(ipl-2);
if ~isempty(opt.RnflMaxThick)
    hiR = min(hiR, cl(ilm + opt.RnflMaxThick));
end
rnfl = local_sp(gDn, cl(ilm+1), hiR, muR, aR, H, 16*psScale);
rnfl = local_smooth(rnfl, sm + 1);

% ---- 逐层偏移校正 ----------------------------------------------------
o = opt.Offsets;
if numel(o) ~= 7
    error('oct_layer_seg:offsets', '''Offsets'' 要给 7 个数，给的是 %d 个', numel(o));
end
bd.ilm  = ilm  + o(1);
bd.rnfl = rnfl + o(2);
bd.ipl  = ipl  + o(3);
bd.inl  = inl  + o(4);
bd.opl  = opl  + o(5);
bd.isos = isos + o(6);
bd.rpe  = rpe  + o(7);

if nargout > 1
    aux.top = top; aux.bot = bot;
    aux.gUp = gUp; aux.gDn = gDn;
    aux.im  = im;  aux.rnfl0 = rnfl0;
end
end

% ======================================================================
function p = local_sp(gn, lo, hi, mu, alpha, H, psig)
%LOCAL_SP  按梯度图构权重再找最短路。
% gn        [H x W] 归一化梯度
% lo/hi     1 x W 硬区间（含端点），区间外加大权重
% mu/alpha  软先验：期望行号 mu(x)，偏离的二次惩罚，截断在 alpha
% psig      软先验的尺度（像素）
if nargin < 7 || isempty(psig), psig = 25; end
[Hg, W] = size(gn);
w = 2 - 2*gn + 1e-5;                      % Chiu 的权重，梯度越强越小
rows = (1:Hg).';

if alpha > 0 && ~isempty(mu)
    d = (rows - mu(:).') / psig;          % 隐式扩展成 [H x W]
    w = w + alpha * min(d.^2, 4);         % 截断，免得远处权重爆掉
end

bad = (rows < lo(:).') | (rows > hi(:).');
w(bad) = w(bad) + 1e4;

p = local_dag(w);
p = min(max(p, 1), H);
end

% ======================================================================
function path = local_dag(w)
%LOCAL_DAG  每列取一个节点、向右推进的 DAG 最短路（8 邻接的右上/右/右下）。
% 图是无环的（只能往右），所以按列做 DP 就行，不用真的跑 Dijkstra 的堆。
[H, W] = size(w);
dist = inf(H, W);
prev = zeros(H, W, 'int32');
dist(:, 1) = w(:, 1);

for x = 2:W
    d0 = dist(:, x-1);
    up = [inf; d0(1:end-1)];              % 来自上一列的上一行
    dn = [d0(2:end); inf];                % 来自上一列的下一行
    [best, k] = min([up, d0, dn], [], 2); % k: 1=up 2=same 3=down
    dist(:, x) = best + w(:, x);
    src = (1:H).' + double(k) - 2;        % k=1 -> -1, k=2 -> 0, k=3 -> +1
    prev(:, x) = int32(min(max(src, 1), H));
end

path = zeros(1, W);
[~, r] = min(dist(:, W));
path(W) = r;
for x = W:-1:2
    r = double(prev(r, x));
    path(x-1) = r;
end
end

% ======================================================================
function g = local_vgrad(im, direction)
%LOCAL_VGRAD  垂直梯度，归一化到 [0,1]。
% 核 [1;1;0;-1;-1] 作卷积（会翻转），于是
%   g(i) = (im(i+1)+im(i+2)) - (im(i-1)+im(i-2))
% direction=+1 时向下变亮为正 -> 暗->亮；-1 反过来。
k = direction * [1; 1; 0; -1; -1];
g = local_conv2sym(im, k);
g = (g - min(g(:))) / (max(g(:)) - min(g(:)) + 1e-12);
end

% ======================================================================
function mu = local_rnfl_band(im, ilm, span, sm)
%LOCAL_RNFL_BAND  逐列估 RNFL 亮带的下缘，给 RNFL/GCL 边界当先验中心。
% RNFL 在 B-scan 上是紧贴 ILM 的一条亮带，它的下缘就是 RNFL/GCL 界面。
% 做法：在 ILM 下方半个 span 内找亮度峰，再往下走到亮度掉回"峰与谷的中点"
% 的位置。RNFL 消失的地方（中心凹一带）峰会紧贴 ILM，估出来的厚度自然就小，
% 这一点是固定比例先验做不到的。
[H, W] = size(im);
mu = zeros(1, W);
for x = 1:W
    a = max(1, round(ilm(x)));
    b = min(H, round(ilm(x) + 0.5*span(x)));
    if b - a < 4
        mu(x) = min(H, a + 6);
        continue;
    end
    seg = im(a:b, x);
    [pk, ip] = max(seg);
    lo = min(seg(ip:end));
    half = lo + 0.5*(pk - lo);
    j = ip;
    while j < numel(seg) && seg(j) > half
        j = j + 1;
    end
    mu(x) = a + j - 1;
end
mu = local_smooth(mu, sm + 3);      % 逐列估计会抖，平掉
end

% ======================================================================
function [top, bot] = local_locate(im, sm)
%LOCAL_LOCATE  粗定位视网膜带：每列亮度剖面里超过阈值的最上/最下行。
[H, W] = size(im);
s = local_gauss2(im, 9, 15);              % 纵向 9、横向 15
thr = max(s, [], 1) * 0.30;               % 每列各自的阈值
top = zeros(1, W); bot = zeros(1, W);
for x = 1:W
    idx = find(s(:, x) > thr(x));
    if isempty(idx)
        top(x) = round(H*0.3); bot(x) = round(H*0.6);
    else
        top(x) = idx(1); bot(x) = idx(end);
    end
end
top = local_smooth(top, sm + 7);
bot = local_smooth(bot, sm + 7);
end

% ======================================================================
function y = local_smooth(p, sigma)
%LOCAL_SMOOTH  一维高斯平滑，边界按端点延拓。
p = double(p(:)).';
if sigma <= 0, y = p; return; end
r = max(1, ceil(4*sigma));
t = -r:r;
k = exp(-t.^2 / (2*sigma^2)); k = k / sum(k);
pad = [repmat(p(1), 1, r), p, repmat(p(end), 1, r)];
y = conv(pad, k, 'valid');
end

% ======================================================================
function out = local_gauss2(im, sy, sx)
%LOCAL_GAUSS2  可分离二维高斯，边界对称延拓。不依赖工具箱。
out = im;
if sy > 0
    r = max(1, ceil(4*sy)); t = -r:r;
    k = exp(-t.^2/(2*sy^2)).'; k = k/sum(k);
    out = local_conv2sym(out, k);
end
if sx > 0
    r = max(1, ceil(4*sx)); t = -r:r;
    k = exp(-t.^2/(2*sx^2)); k = k/sum(k);
    out = local_conv2sym(out, k);
end
end

% ======================================================================
function out = local_conv2sym(im, k)
%LOCAL_CONV2SYM  conv2 'same'，但边界用对称延拓而不是补零。
% 补零会在图像上下缘造出假的强梯度，ILM 会被吸到第 1 行去。
[kh, kw] = size(k);
ph = floor(kh/2); pw = floor(kw/2);
[H, W] = size(im);
% 延拓索引用周期性反射算。早先是拼一段再把非法值滤掉，核比图大时
% 会塌掉（滤完宽度不够，后面切片越界）；这里 sigma 最大 15、图 700 行，
% 碰不到，但 oct_frangi2d 里同样的函数被 6 行的小图撞出来过，一起改。
ri = local_reflect((1:H+2*ph) - ph, H);
ci = local_reflect((1:W+2*pw) - pw, W);
out = conv2(im(ri, ci), k, 'same');
out = out(ph+1:ph+H, pw+1:pw+W);
end

% ======================================================================
function idx = local_reflect(i, N)
%LOCAL_REFLECT  把任意整数索引折回 [1,N]（symmetric：边界像素重复）。
if N == 1, idx = ones(size(i)); return; end
p = 2*N;
j = mod(i-1, p);
j(j < 0) = j(j < 0) + p;
big = j >= N;
j(big) = p - 1 - j(big);
idx = j + 1;
end
