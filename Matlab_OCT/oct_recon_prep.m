function k = oct_recon_prep(p)
%OCT_RECON_PREP  预计算重建用的查找表（k 域索引、色散相位、汉宁窗）。
%
%   k = OCT_RECON_PREP(p)，p 来自 oct_recon_params。
%   返回：
%     k.idx   步骤2 插值的左侧整数下标（1-based，已钳到合法范围）
%     k.frac  步骤2 的插值小数部分
%     k.cosT  步骤3 的 cos(t)
%     k.sinT  步骤3 的 direction*sin(t)
%     k.win   步骤4 的汉宁窗
%   都是 1 x alineLength 的行向量。

len = p.alineLength;
N   = len - 1;
i   = 0:N;                                  % C++ 里是 0-based，这里保持一致

% ---- 步骤2：k 域线性化 ---------------------------------------------
d = p.d;
t = d(1) + (d(2)/N)*i + (d(3)/N^2)*i.^2 + (d(4)/N^3)*i.^3;
tt = floor(t);                              % C++ 是 (int)t，t >= 0 时等价
tt = min(max(tt, 0), len - 2);              % C++ 没做边界检查，这里钳一下防越界
k.frac = t - tt;
k.idx  = tt + 1;                            % 转成 MATLAB 的 1-based

% ---- 步骤3：色散补偿相位 -------------------------------------------
c = p.c;
tc = c(1) + (c(2)/N)*i + (c(3)/N^2)*i.^2 + (c(4)/N^3)*i.^3;
k.cosT = cos(tc);
k.sinT = p.direction * sin(tc);

% ---- 步骤4：汉宁窗 --------------------------------------------------
% 完全照搬 initPipline() 里的整数运算，包括那两个奇怪的阈值
width  = floor(p.fillFactor * len);
center = floor(p.centerPosition * len);
minPos = center - floor(width / 2);
maxPos = minPos + width;
if maxPos < minPos
    tmp = minPos; minPos = maxPos; maxPos = tmp;   %#ok<NASGU>
end
xi     = i - minPos;
xiNorm = xi / (width - 1);
k.win  = 0.5 * (1 - cos(2*pi*xiNorm));
k.win(xiNorm > 0.999 | xiNorm < 0.0001) = 0;
end
