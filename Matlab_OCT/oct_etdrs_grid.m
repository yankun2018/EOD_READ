function [res, labelMap] = oct_etdrs_grid(T, varargin)
%OCT_ETDRS_GRID  ETDRS 九分区厚度分析（OCT 报告上那个靶心图）。
%
%   res = OCT_ETDRS_GRID(T)
%   [res, labelMap] = OCT_ETDRS_GRID(T, 'Name', value, ...)
%
%   T        : 厚度图（oct_thickness_map 的输出，[nBscan x nAline]）
%   res      : 结构体，见下面"返回"
%   labelMap : 和 T 同尺寸的分区编号图（1..9，区外是 0）
%
%   ETDRS 网格（Early Treatment Diabetic Retinopathy Study）是三个同心圆：
%   直径 1 mm（中心区）、3 mm（内环）、6 mm（外环），内外环各按对角线分成
%   上/鼻/下/颞四个象限，一共 9 个分区。商用 OCT（Cirrus / Spectralis /
%   Topcon）报告上的九宫格靶心图就是这个。
%
%   分区编号（1=中心，2~5=内环，6~9=外环）：
%       1  中心区 central (直径 1 mm)
%       2  内上 inner superior      6  外上 outer superior
%       3  内鼻 inner nasal         7  外鼻 outer nasal
%       4  内下 inner inferior      8  外下 outer inferior
%       5  内颞 inner temporal      9  外颞 outer temporal
%
%   方位按标准报告的画法：上=superior、下=inferior，
%   **OD（右眼）左=颞侧、右=鼻侧；OS（左眼）左右互换**。
%
%   选项：
%     'PixY'    纵向（B-scan 方向）的像素间距，mm（默认 6/120 = 0.05）
%     'PixX'    横向（A-line 方向）的像素间距，mm（默认 6/432）
%     'Center'  中心凹位置 [cy cx]，[] = 用 oct_fovea_find 自动找（默认 []）
%     'Eye'     'OD'（默认）或 'OS'，决定鼻/颞在哪一侧
%     'Diam'    三个圆的直径，mm（默认 [1 3 6]）
%
%   返回 res：
%     .mean(1..9)    各区平均厚度（单位同 T）
%     .std / .n      各区标准差、有效像素数
%     .names         各区名字（cell）
%     .centerPoint   中心凹那一点的厚度（单张 A-line，不是平均）
%     .volume(1..3)  1/3/6 mm 三个圆内的体积（mm^3，T 单位是 µm 时才有意义）
%     .avgAll        6 mm 圆内的平均厚度
%     .center        实际用的 [cy cx]
%     .eye / .pix / .diam
%
%   参见 oct_fovea_find, oct_thickness_map, oct_report。

opt.PixY   = 6/120;
opt.PixX   = 6/432;
opt.Center = [];
opt.Eye    = 'OD';
opt.Diam   = [1 3 6];
opt = oct_parseopt(opt, varargin);

T = double(T);
[H, W] = size(T);

eye = upper(opt.Eye);
if ~any(strcmp(eye, {'OD', 'OS'}))
    error('oct_etdrs_grid:eye', '''Eye'' 只能是 ''OD'' 或 ''OS''');
end

% ---- 中心凹 ----------------------------------------------------------
if isempty(opt.Center)
    [cy, cx] = oct_fovea_find(T);
else
    if numel(opt.Center) ~= 2
        error('oct_etdrs_grid:center', '''Center'' 要给 [cy cx]');
    end
    cy = opt.Center(1); cx = opt.Center(2);
end

% ---- 每个像素到中心凹的物理距离和方位 --------------------------------
[XX, YY] = meshgrid(1:W, 1:H);
dx = (XX - cx) * opt.PixX;          % mm，向右为正
dy = (YY - cy) * opt.PixY;          % mm，向下为正
rr = sqrt(dx.^2 + dy.^2);

rad = sort(opt.Diam(:).') / 2;      % 半径
if numel(rad) ~= 3
    error('oct_etdrs_grid:diam', '''Diam'' 要给三个直径');
end

% 象限：按对角线分。atan2 的角度以"向右"为 0、向下为正
ang = atan2(dy, dx);
isRight = abs(ang) <= pi/4;                     % 右
isLeft  = abs(ang) >= 3*pi/4;                   % 左
isDown  = ang >  pi/4 & ang <  3*pi/4;          % 下
isUp    = ang < -pi/4 & ang > -3*pi/4;          % 上

% OD：左=颞、右=鼻；OS：反过来
if strcmp(eye, 'OD')
    isNasal = isRight;  isTemp = isLeft;
else
    isNasal = isLeft;   isTemp = isRight;
end

inner = rr > rad(1) & rr <= rad(2);
outer = rr > rad(2) & rr <= rad(3);

labelMap = zeros(H, W);
labelMap(rr <= rad(1)) = 1;
labelMap(inner & isUp)      = 2;
labelMap(inner & isNasal)   = 3;
labelMap(inner & isDown)    = 4;
labelMap(inner & isTemp)    = 5;
labelMap(outer & isUp)      = 6;
labelMap(outer & isNasal)   = 7;
labelMap(outer & isDown)    = 8;
labelMap(outer & isTemp)    = 9;

% ---- 逐区统计 --------------------------------------------------------
names = {'中心区', '内上', '内鼻', '内下', '内颞', ...
         '外上', '外鼻', '外下', '外颞'};
abbr  = {'C', 'IS', 'IN', 'II', 'IT', 'OS', 'ON', 'OI', 'OT'};
res.mean = nan(1, 9);
res.std  = nan(1, 9);
res.n    = zeros(1, 9);
for k = 1:9
    v = T(labelMap == k);
    v = v(isfinite(v));
    res.n(k) = numel(v);
    if ~isempty(v)
        res.mean(k) = mean(v);
        res.std(k)  = std(v);
    end
end
res.names = names;
res.abbr  = abbr;

% ---- 中心点厚度（就取中心凹那一个点，报告上会单列）------------------
iy = min(max(round(cy), 1), H);
ix = min(max(round(cx), 1), W);
res.centerPoint = T(iy, ix);

% ---- 体积：厚度(µm) x 面积(mm²) -> mm³ -------------------------------
% 每个像素的面积是 PixX*PixY mm²，厚度按 µm 算，所以要 /1000
pixArea = opt.PixX * opt.PixY;
res.volume = nan(1, 3);
for k = 1:3
    m = rr <= rad(k) & isfinite(T);
    if any(m(:))
        res.volume(k) = sum(T(m)) / 1000 * pixArea;
    end
end

m6 = rr <= rad(3) & isfinite(T);
res.avgAll = mean(T(m6));
res.center = [cy cx];
res.eye    = eye;
res.pix    = [opt.PixY opt.PixX];
res.diam   = sort(opt.Diam(:).');

% 网格有没有被图像边界截掉 —— 截掉了外环的统计就不完整，得提醒
res.covered = all(rr(:) <= rad(3)) || ...
              (cy - rad(3)/opt.PixY >= 1 && cy + rad(3)/opt.PixY <= H && ...
               cx - rad(3)/opt.PixX >= 1 && cx + rad(3)/opt.PixX <= W);
end
