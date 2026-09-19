function out = oct_recon_pipeline(spec, p, k)
%OCT_RECON_PIPELINE  SD-OCT 重建流水线，MATLAB 版。
%
%   out = OCT_RECON_PIPELINE(spec, p)
%   out = OCT_RECON_PIPELINE(spec, p, k)      % k 由 oct_recon_prep 预先算好
%
%   spec : [nLine x alineLength] 原始光谱，一行一条 A-line
%   p    : oct_recon_params 返回的参数
%   out  : [nLine x M] 深度剖面的 log 幅度。p.halfOnly 为 true 时
%          M = alineLength/2（去掉 IDFT 的镜像一半），否则 M = alineLength
%
%   六个步骤逐条对应 faster_3dim_scan_vulkan\cpu_pipline.cpp：
%     1 background_subtraction  减去最近 bgLines 条的滑动平均
%     2 klinearization          波长域 -> 波数域的三次多项式重采样 + 线性插值
%     3 calibration_method      实信号 -> 复信号，同时乘上色散补偿相位
%     4 window_hanning          汉宁窗
%     5 cv::idft                未归一化的逆 DFT，等价于 MATLAB 的 ifft(...)*len
%     6 log(|.| + logOffset)    取模、加偏置、取对数
%
%   注意两处和 C++ 的差别，都是有意为之：
%     * 第 2 步 C++ 是原地插值（klinearization(input_t, input_t, ...)），
%       在 t(i) < i 的区间会读到本轮已经被覆写的值；CUDA 版是异地的。
%       这里默认走异地（和 CUDA 一致），p.klinInplace = true 可复刻 CPU 的行为。
%     * cv::idft 不带 DFT_SCALE，所以是未归一化的；这里乘回 len 保证
%       第 6 步的 logOffset = 1000 仍然是同一个量级，不然对比度会完全不同。
%
%   参见 oct_recon_params, oct_recon_prep, oct_recon_demo。

if nargin < 3 || isempty(k)
    k = oct_recon_prep(p);
end

len = p.alineLength;
if size(spec, 2) ~= len
    error('oct_recon_pipeline:size', ...
          'spec 的列数是 %d，但 p.alineLength = %d', size(spec, 2), len);
end
x = double(spec);
nLine = size(x, 1);

% ---- 步骤1：背景相减 -------------------------------------------------
% C++: 前 bgLines 条原样透传，之后减去"含当前条在内的最近 bgLines 条"的均值。
% filter 沿第 1 维做的就是这个拖尾滑动平均；前 bgLines-1 行是不完整窗口，
% 但那几行本来就要透传，正好被下面覆盖掉。
if p.bgLines > 0 && nLine > 0
    nb = p.bgLines;
    bg = filter(ones(1, nb) / nb, 1, x, [], 1);
    x(nb+1:end, :) = x(nb+1:end, :) - bg(nb+1:end, :);
end

% ---- 步骤2：k 域线性化 -----------------------------------------------
if p.klinInplace
    % 逐点顺序覆写，复刻 C++ 的原地行为（对 A-line 之间仍然是向量化的）
    for i = 1:len
        a = x(:, k.idx(i));
        b = x(:, k.idx(i) + 1);
        x(:, i) = a + k.frac(i) * (b - a);
    end
else
    a = x(:, k.idx);
    b = x(:, k.idx + 1);
    x = a + k.frac .* (b - a);
end

% ---- 步骤3：色散补偿，实 -> 复 ---------------------------------------
z = complex(x .* k.cosT, x .* k.sinT);

% ---- 步骤4：加窗 -----------------------------------------------------
z = z .* k.win;

% ---- 步骤5：逆 DFT（未归一化，对齐 cv::idft）-------------------------
z = ifft(z, [], 2) * len;

% ---- 步骤6：取模 -> 加偏置 -> 取对数 ---------------------------------
out = log(abs(z) + p.logOffset);

% ---- 去掉镜像的那一半 ------------------------------------------------
if p.halfOnly
    out = out(:, 1:floor(len/2));
end
end
