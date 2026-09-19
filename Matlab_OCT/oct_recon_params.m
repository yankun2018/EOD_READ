function p = oct_recon_params(preset, varargin)
%OCT_RECON_PARAMS  OCT 重建参数，字段和 faster_3dim_scan_vulkan 的 CPU 流水线一一对应。
%
%   p = OCT_RECON_PARAMS                      % 默认 'strawberry1664'
%   p = OCT_RECON_PARAMS(preset)
%   p = OCT_RECON_PARAMS(preset, 'Name', value, ...)   % 覆盖个别字段
%
%   预设：
%     'strawberry1664'  原样照抄 cpu_pipline.cpp / main.cpp:RunDemo0 的常数，
%                       配 test2_16bit.raw（1664 点 / 线，512 线 / B-scan）。
%     'cuda1664'        同上，但色散系数用 cuda_pipline.cu 里的
%                       c = [0 20.24 0 0]（GPU 版和 CPU 版这里本来就不一样）。
%     'eod2048'         配 octifft\oct_origin_spectrum.csv（2048 点 12 bit）。
%                       k 域重采样是恒等的（d = [0 N 0 0]）、不做色散补偿（c 全 0）
%                       —— 这不是"先凑一个"，是实测标定过的最优值：拿 806 条强反射
%                       A-line 扫 d2 和 c1，亚 bin FWHM 的最小值就落在这组默认值上
%                       （d2 偏到 ±600 会从 6.0 劣化到 16~21）。说明这套采集出来的
%                       光谱已经是 k 域线性的，也没有明显的未补偿色散。
%                       换了硬件/光路就要重新标，方法见 Matlab_OCT\README.md。
%
%   字段说明（步骤编号同 C++ 注释）：
%     alineLength      每条 A-line 的点数
%     bscanWidth       每幅 B-scan 的 A-line 条数
%     bgLines          步骤1：背景滑动平均的条数（C++ 固定 20），0 = 不减背景
%     d                步骤2：k 域线性化的三次多项式系数 [d0 d1 d2 d3]
%                      t(i) = d0 + (d1/N)i + (d2/N^2)i^2 + (d3/N^3)i^3, N = len-1
%     klinInplace      true  复刻 C++ 的原地插值（input_arr == output_arr）。
%                      当 t(i) < i 时会读到已被覆写的值，和 CUDA 版结果不同；
%                      留 false 走正确的异地插值（默认）。
%     c                步骤3：色散补偿系数 [c0 c1 c2 c3]，同样的三次多项式
%     direction        步骤3：虚部符号，+1 / -1
%     fillFactor       步骤4：汉宁窗占空比（C++ 0.95）
%     centerPosition   步骤4：窗中心位置（C++ 0.5）
%     logOffset        步骤6：取对数前加的偏置（C++ 1000）
%     halfOnly         true  只保留 IDFT 结果的前一半（去镜像），默认 true
%     flipAlternate    true  偶数幅 B-scan 左右翻转（双向扫描），默认 true
%
%   参见 oct_recon_pipeline, oct_recon_demo。

if nargin < 1 || isempty(preset)
    preset = 'strawberry1664';
end

switch lower(preset)
    case {'strawberry1664', 'cpu', 'strawberry'}
        p.alineLength = 1664;
        p.bscanWidth  = 512;
        p.bgLines     = 20;
        p.d           = [0, 2016, -994, 624];
        p.c           = [0, 10.5, 1.5, 0];

    case {'cuda1664', 'cuda'}
        p.alineLength = 1664;
        p.bscanWidth  = 512;
        p.bgLines     = 20;
        p.d           = [0, 2016, -994, 624];
        p.c           = [0, 20.24, 0, 0];

    case {'eod2048', 'eod'}
        p.alineLength = 2048;
        p.bscanWidth  = 500;
        p.bgLines     = 32;              % read_all_bin.cpp 用的是 32
        p.d           = [0, 2047, 0, 0]; % N = 2047，等价于不做重采样（实测最优）
        p.c           = [0, 0, 0, 0];    % 不做色散补偿（实测 c1 扫 0~30 都是平的）

    otherwise
        error('oct_recon_params:preset', '未知预设 ''%s''', preset);
end

p.preset        = lower(preset);
p.klinInplace   = false;
p.direction     = 1;
p.fillFactor    = 0.95;
p.centerPosition = 0.5;
p.logOffset     = 1000;
p.halfOnly      = true;
p.flipAlternate = true;

p = oct_parseopt(p, varargin);
end
