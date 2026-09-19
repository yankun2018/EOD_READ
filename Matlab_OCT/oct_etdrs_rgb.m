function rgb = oct_etdrs_rgb(res, varargin)
%OCT_ETDRS_RGB  把 ETDRS 九分区画成报告上那个靶心图。
%
%   rgb = OCT_ETDRS_RGB(res)
%   rgb = OCT_ETDRS_RGB(res, 'Name', value, ...)
%
%   res : oct_etdrs_grid 的输出
%   rgb : uint8 RGB 图，九个扇区按厚度上色，每区中间写数值
%
%   选项：
%     'Size'     输出边长（默认 420）
%     'Range'    上色的厚度区间，[] = 按这九个值自动取（默认 []）
%     'Style'    色表，透传给 oct_thickness_rgb（默认 'oct'）
%     'Digits'   数值保留几位小数（默认 0）
%     'Labels'   true 时在四个方向标 S/N/I/T（默认 true）
%     'Bands'    给一个 1x9 的 band（1红 2黄 3绿 4白）就按显著性配色，
%                而不是按厚度渐变（默认 []）
%
%   参见 oct_etdrs_grid, oct_thickness_rgb, oct_report。

opt.Size   = 420;
opt.Range  = [];
opt.Style  = 'oct';
opt.Digits = 0;
opt.Labels = true;
opt.Bands  = [];
opt = oct_parseopt(opt, varargin);

S = round(opt.Size);
half = S / 2;
rad = res.diam / 2;                  % mm
rmax = rad(3);
pxPerMm = half / rmax;               % 让 6mm 圆刚好占满

[XX, YY] = meshgrid(1:S, 1:S);
dx = (XX - half - 0.5) / pxPerMm;    % mm
dy = (YY - half - 0.5) / pxPerMm;
rr = sqrt(dx.^2 + dy.^2);
ang = atan2(dy, dx);

isRight = abs(ang) <= pi/4;
isLeft  = abs(ang) >= 3*pi/4;
isDown  = ang >  pi/4 & ang <  3*pi/4;
isUp    = ang < -pi/4 & ang > -3*pi/4;
if strcmp(res.eye, 'OD')
    isNasal = isRight; isTemp = isLeft;
else
    isNasal = isLeft;  isTemp = isRight;
end

inner = rr > rad(1) & rr <= rad(2);
outer = rr > rad(2) & rr <= rad(3);
lab = zeros(S, S);
lab(rr <= rad(1)) = 1;
lab(inner & isUp) = 2;  lab(inner & isNasal) = 3;
lab(inner & isDown) = 4; lab(inner & isTemp) = 5;
lab(outer & isUp) = 6;  lab(outer & isNasal) = 7;
lab(outer & isDown) = 8; lab(outer & isTemp) = 9;

% ---- 每个扇区的颜色 --------------------------------------------------
if ~isempty(opt.Bands)
    if numel(opt.Bands) ~= 9
        error('oct_etdrs_rgb:bands', '''Bands'' 要给 9 个数');
    end
    BCOL = [0.85 0.10 0.10; 0.95 0.85 0.15; 0.15 0.70 0.25; 1 1 1];
    cols = zeros(9, 3);
    for k = 1:9
        b = opt.Bands(k);
        if isfinite(b) && b >= 1 && b <= 4
            cols(k, :) = BCOL(round(b), :);
        else
            cols(k, :) = 0.5;
        end
    end
else
    v = res.mean(isfinite(res.mean));
    if isempty(opt.Range)
        if isempty(v), lo = 0; hi = 1;
        else, lo = min(v); hi = max(v);
        end
    else
        lo = opt.Range(1); hi = opt.Range(2);
    end
    if hi <= lo, hi = lo + 1; end
    % 借 oct_thickness_rgb 的色表，保证和地形图同一套配色
    [~, cmap] = oct_thickness_rgb([lo hi], 'Style', opt.Style, 'Range', [lo hi]);
    cols = zeros(9, 3);
    for k = 1:9
        if ~isfinite(res.mean(k))
            cols(k, :) = 0.5;
        else
            t = (res.mean(k) - lo) / (hi - lo);
            ci = min(max(round(t*(size(cmap,1)-1)) + 1, 1), size(cmap,1));
            cols(k, :) = cmap(ci, :);
        end
    end
end

R = zeros(S, S); G = R; B = R;
for k = 1:9
    m = (lab == k);
    R(m) = cols(k,1); G(m) = cols(k,2); B(m) = cols(k,3);
end
rgb = uint8(round(cat(3, R, G, B) * 255));

% ---- 分界线 ----------------------------------------------------------
edge = false(S, S);
for k = 1:3
    edge = edge | (abs(rr - rad(k)) < 1.1/pxPerMm);
end
diag1 = abs(abs(dx) - abs(dy)) < 1.1/pxPerMm;
edge = edge | (diag1 & rr > rad(1) & rr <= rad(3));
edge = edge & (rr <= rad(3) + 1/pxPerMm);
for ch = 1:3
    t = rgb(:,:,ch); t(edge) = 40; rgb(:,:,ch) = t;
end
% 圆外涂黑
out = rr > rad(3);
for ch = 1:3
    t = rgb(:,:,ch); t(out) = 0; rgb(:,:,ch) = t;
end

% ---- 写数值 ----------------------------------------------------------
% 九个扇区的标注位置（中心 + 内环四个 + 外环四个）
rIn  = (rad(1) + rad(2)) / 2;
rOut = (rad(2) + rad(3)) / 2;
posR = [0, rIn, rIn, rIn, rIn, rOut, rOut, rOut, rOut];
% 方位角：上、鼻、下、颞
if strcmp(res.eye, 'OD'), nasalAng = 0; tempAng = pi; else, nasalAng = pi; tempAng = 0; end
posA = [0, -pi/2, nasalAng, pi/2, tempAng, -pi/2, nasalAng, pi/2, tempAng];

for k = 1:9
    if ~isfinite(res.mean(k)), continue; end
    px = half + 0.5 + posR(k)*pxPerMm*cos(posA(k));
    py = half + 0.5 + posR(k)*pxPerMm*sin(posA(k));
    txt = local_fmt(res.mean(k), opt.Digits);
    rgb = local_text(rgb, txt, round(py), round(px), local_ink(cols(k,:)));
end

if opt.Labels
    ink = [255 255 255];
    if strcmp(res.eye, 'OD'), lt = 'T'; rt = 'N'; else, lt = 'N'; rt = 'T'; end
    rgb = local_text(rgb, 'S',  10,     round(half), ink);
    rgb = local_text(rgb, 'I',  S-10,   round(half), ink);
    rgb = local_text(rgb, lt,   round(half), 10,     ink);
    rgb = local_text(rgb, rt,   round(half), S-10,   ink);
end
end

% ======================================================================
function s = local_fmt(v, d)
if d <= 0, s = sprintf('%d', round(v));
else,      s = sprintf(['%.' num2str(d) 'f'], v);
end
end

function ink = local_ink(bg)
% 背景亮就用黑字，暗就用白字
if 0.299*bg(1) + 0.587*bg(2) + 0.114*bg(3) > 0.6
    ink = [0 0 0];
else
    ink = [255 255 255];
end
end

% ======================================================================
function img = local_text(img, str, cy, cx, ink)
%LOCAL_TEXT  把字符串画到图上（自带 5x7 点阵，不依赖 insertText）。
F = local_font();
str = upper(str);
gw = 6; gh = 7; sc = 2;                    % 字距、字高、放大倍数
n = numel(str);
w = n*gw*sc;
y0 = round(cy - gh*sc/2);
x0 = round(cx - w/2);
[H, W, ~] = size(img);
for i = 1:n
    ch = str(i);
    if ~isKey(F, ch), continue; end
    g = F(ch);                             % 7 x 5 逻辑
    for r = 1:gh
        for c = 1:5
            if ~g(r, c), continue; end
            yy = y0 + (r-1)*sc + (0:sc-1);
            xx = x0 + (i-1)*gw*sc + (c-1)*sc + (0:sc-1);
            yy = yy(yy >= 1 & yy <= H);
            xx = xx(xx >= 1 & xx <= W);
            if isempty(yy) || isempty(xx), continue; end
            for ci = 1:3
                t = img(yy, xx, ci);
                t(:) = ink(ci);
                img(yy, xx, ci) = t;
            end
        end
    end
end
end

% ======================================================================
function F = local_font()
%LOCAL_FONT  5x7 点阵，只要数字、小数点和 S/N/I/T 这几个字母。
persistent P
if ~isempty(P), F = P; return; end
d = containers.Map('KeyType', 'char', 'ValueType', 'any');
d('0') = [0 1 1 1 0;1 0 0 0 1;1 0 0 1 1;1 0 1 0 1;1 1 0 0 1;1 0 0 0 1;0 1 1 1 0];
d('1') = [0 0 1 0 0;0 1 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 1 1 1 0];
d('2') = [0 1 1 1 0;1 0 0 0 1;0 0 0 0 1;0 0 0 1 0;0 0 1 0 0;0 1 0 0 0;1 1 1 1 1];
d('3') = [1 1 1 1 1;0 0 0 1 0;0 0 1 0 0;0 0 0 1 0;0 0 0 0 1;1 0 0 0 1;0 1 1 1 0];
d('4') = [0 0 0 1 0;0 0 1 1 0;0 1 0 1 0;1 0 0 1 0;1 1 1 1 1;0 0 0 1 0;0 0 0 1 0];
d('5') = [1 1 1 1 1;1 0 0 0 0;1 1 1 1 0;0 0 0 0 1;0 0 0 0 1;1 0 0 0 1;0 1 1 1 0];
d('6') = [0 0 1 1 0;0 1 0 0 0;1 0 0 0 0;1 1 1 1 0;1 0 0 0 1;1 0 0 0 1;0 1 1 1 0];
d('7') = [1 1 1 1 1;0 0 0 0 1;0 0 0 1 0;0 0 1 0 0;0 1 0 0 0;0 1 0 0 0;0 1 0 0 0];
d('8') = [0 1 1 1 0;1 0 0 0 1;1 0 0 0 1;0 1 1 1 0;1 0 0 0 1;1 0 0 0 1;0 1 1 1 0];
d('9') = [0 1 1 1 0;1 0 0 0 1;1 0 0 0 1;0 1 1 1 1;0 0 0 0 1;0 0 0 1 0;0 1 1 0 0];
d('.') = [0 0 0 0 0;0 0 0 0 0;0 0 0 0 0;0 0 0 0 0;0 0 0 0 0;0 1 1 0 0;0 1 1 0 0];
d('-') = [0 0 0 0 0;0 0 0 0 0;0 0 0 0 0;1 1 1 1 1;0 0 0 0 0;0 0 0 0 0;0 0 0 0 0];
d('S') = [0 1 1 1 1;1 0 0 0 0;1 0 0 0 0;0 1 1 1 0;0 0 0 0 1;0 0 0 0 1;1 1 1 1 0];
d('N') = [1 0 0 0 1;1 1 0 0 1;1 1 0 0 1;1 0 1 0 1;1 0 0 1 1;1 0 0 1 1;1 0 0 0 1];
d('I') = [1 1 1 1 1;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;1 1 1 1 1];
d('T') = [1 1 1 1 1;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0;0 0 1 0 0];
k = d.keys;
for i = 1:numel(k), d(k{i}) = logical(d(k{i})); end
P = d; F = d;
end
