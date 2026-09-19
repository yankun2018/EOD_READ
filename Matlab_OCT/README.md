# Matlab_OCT

原始光谱显示 + SD-OCT 重建的 MATLAB 版。

- **光谱显示**：等价于 `Spectrum_read/read_all_bin.cpp` 里那几个 OpenCV 窗口
  （仓库根目录的 `image.gif` 就是其中"光谱"窗口的录屏）。
- **重建显示**：照 `faster_3dim_scan_vulkan` 工程 **CPU 部分** 的算法翻的
  （`cpu_pipline.cpp` + `main.cpp:RunDemo0/RunDemo1`），不依赖 CUDA / Vulkan / OpenCV。

只用到基础 MATLAB，不需要任何工具箱。R2016b 及以上（用到了隐式扩展）。

各算法的出处见 [REFERENCES.md](REFERENCES.md)。

## 文件

| 文件 | 作用 |
|---|---|
| `oct_load_spectrum.m` | 读原始数据，统一成 `[nLine x nPoint]`。支持 CSV / uint16 raw / 12 bit 打包 / EOD socket 块 |
| `oct_show_spectrum.m` | 逐条滚动显示光谱（原始 / 减背景 / k 域插值 / 重建后的 A-line），可同时开一个滚动 B-scan 窗口，可导出 gif |
| `oct_recon_params.m` | 重建参数，字段和 C++ 的常数一一对应；带三个预设 |
| `oct_recon_prep.m` | 预计算查找表：k 域插值下标、色散相位、汉宁窗 |
| `oct_recon_pipeline.m` | 重建六步，按 A-line 向量化 |
| `oct_recon_demo.m` | 读数据 → 重建 → 滚动显示 B-scan + en-face C-scan |
| `oct_parseopt.m` | 名值对选项解析（内部用） |
| `oct_layer_seg.m` | **视网膜 7 层分割**（图论最短路），复刻 `EOD_read_seg.exe` 里 `DIJK_SEG.m` 的思路 |
| `oct_layer_gt.m` | 从原 exe 输出的彩色叠加图里取回灰度 B-scan + 7 条边界（ground truth）|
| `oct_layer_demo.m` | 在 pic_md 那 120 张上跑分层、画对比图、报误差 |
| `oct_layer_export.m` / `oct_layer_import.m` | 读写 EOD 的 `_analy.dat` 分层格式 |
| `oct_layer_batch.m` | 批量跑一个目录，导出干净灰度图 / 叠加图 / 对比图 / dat / csv / 报告 |
| `oct_enface.m` | 按分层结果把体数据投影成 en-face（C-scan）|
| `oct_frangi2d.m` | **Frangi 血管增强**，复刻 `FrangiFilter2D.m` + `Hessian2D.m` + `eig2image.m` |
| `oct_devessel.m` | **en-face 去血管**，复刻 `enface_deVessel.m` + `graphcut_BW.m` 那一步 |
| `oct_enface_demo.m` | 体数据 → 分层 → en-face → 血管检测 → 去血管，一条链跑完 |
| `oct_volume_read.m` | 读原始三维扫描 `.dat`（120 × 432 × 700）|
| `oct_thickness_map.m` | **层厚图**（任意两层，微米），对应 `oct_thickness.py` |
| `oct_deviation_map.m` | **偏差图**（池化 + 分级），对应 `oct_DeviationMap.py` |
| `oct_analy_demo.m` | C-scan + 层厚图 + 偏差图，对应 `Analy_and_image_show` 那三个脚本 |
| `oct_fovea_find.m` | 自动定位中心凹（全层厚度最小处）|
| `oct_etdrs_grid.m` | **ETDRS 九分区**厚度分析（1/3/6 mm 同心圆）|
| `oct_etdrs_rgb.m` | 把九分区画成报告上那个靶心图（自带 5x7 点阵字体）|
| `oct_thickness_rgb.m` | 厚度地形图上色（冷色薄暖色厚）|
| `oct_significance_rgb.m` | 显著性图（白/绿/黄/红四带）|
| `oct_report.m` | **一张综合报告图**：地形图 + 靶心图 + 显著性图 + C-scan + B-scan + 厚度剖面 |
| `test/oct_selftest.m` | 自测，163 项断言，含与 C++ 逐行直译结果的数值比对 |
| `REFERENCES.md` | 所有算法的原始论文（19 条 DOI 全部核对过）|

## 快速开始

```matlab
cd Matlab_OCT

% 1) 看原始光谱，复刻 image.gif 的观感
oct_show_spectrum

% 2) 带坐标轴 + 减背景那一路，方便读数
oct_show_spectrum('Style', 'plot', 'MaxLines', 200)

% 3) 一边看光谱一边看 B-scan 长出来（= C++ 那个循环里的一堆窗口）
oct_show_spectrum('ShowAline', true, 'ShowBscan', true, 'MaxLines', 1200)

% 4) 重建并滚动显示 B-scan + en-face（自动找数据，见下面"数据"一节）
oct_recon_demo

% 5) RunDemo0 那种一条一条刷新的模式，只跑一幅
oct_recon_demo('Mode', 'aline', 'MaxBscans', 1)

% 6) 拿回数据自己后处理
[bscans, cscan] = oct_recon_demo('MaxBscans', 64);
```

## oct_show_spectrum 的 B-scan 归一化

`'BscanNorm'` 三种：

| 值 | 做法 | 用处 |
|---|---|---|
| `'range'`（默认）| 先把整个显示区间批量重建好，用这一整块的 min/max 统一归一化 | 和 `oct_recon_demo`/"草莓"那版一个路子，结构清楚、噪声不被拉起来 |
| `'aline'` | 每条 A-line 按自己的 min/max 拉满 | C++ `BSCAN_ALINE_TIME` 的原始行为；无信号的列噪声会被放大成白色竖条 |
| `'running'` | 随着列填进来，用"已填部分"的 min/max 动态调 | 想看对比度怎么随数据变 |

不管哪种，B-scan 都还是**逐列生长**的，只是灰度怎么定不一样。

两个相关的实现细节：

- **整块预重建。** 以前每帧调一次 `oct_recon_pipeline`（一次只算 1 条），既慢又拿不到
  全区间的灰度范围。现在开头一次批量算完（分块只为控峰值内存，结果和整块算一致），
  循环里只是查表。重建本身从 107 A-line/s 提到 **7000~9000 A-line/s**。
- **推屏节流。** 列照旧每条都填，但 `CData` 和 `drawnow` 按 ~30 Hz 推。801 条每帧
  都推一次 1024×801 的数组是几 GB 的内存拷贝，而屏幕刷不了那么快。
  `Pause > 0`（说明想一帧一帧看）或要存 gif 时仍然每帧都推。
- **区间头部的背景上下文。** 读数据时往前多读 `bgLines` 条算完丢掉，
  不然区间头部那几条没减背景，B-scan 左边会有一条明显偏亮的竖带。
  所以 `Range [201 260]` 和 `Range [201 400]` 的前 60 列结果完全一致。

## 视网膜分层（复刻 EOD_read_seg.exe）

`EOD_read_seg.exe` 是 MATLAB R2019b 打包的，源码在 CTF 里是加密的（拆不出来，也不该拆）。
但 `Desktop\pic_md` 下那 120 张 PNG 是它的**输出** —— B-scan 上画好了 7 条分层线，
每张 432 列、每条线每列恰好一个纯色像素，等于一套完整的 ground truth。
`oct_layer_gt` 把灰度和线都取回来，`oct_layer_seg` 用灰度重新分一遍，再拿原来的线对分。

```matlab
cd Matlab_OCT
oct_layer_demo                         % 逐张对比 我的结果 / 原 exe 的线
oct_layer_demo('Files', 60)            % 只看第 60 张
s = oct_layer_demo('Show', 'none');    % 全部 120 张，只要数字

% 单张用
[img, gt] = oct_layer_gt('.../pic_md/img_0060.png');
bd = oct_layer_seg(img);               % bd.ilm / .rnfl / .ipl / .inl / .opl / .isos / .rpe

% 批量处理一个目录，产物全套导出
oct_layer_batch('.../pic_bscan', '.../输出目录')
```

`oct_layer_batch` 的产物：`gray_clean\`（抹掉叠加线、插值补回的干净灰度图）、
`seg_overlay\`（我的线画在灰度图上）、`seg_compare\`（我的 / 原线 并排）、
`layers.dat`（`_analy.dat` 格式，下游工具能直接读）、`layers.csv`、`report.txt`。
输入带不带分层线都行 —— 带线就顺便抹掉当 GT 并报误差，不带就直接分层。

> **注意** `Desktop\pic_md_origin\pic_bscan` 和 `Desktop\pic_md` 是同一批文件
> （120 个的总 MD5 一致，zip 里也一样），都还带着原 exe 画的 7 条线，
> 没有真正的"无线原图"。`gray_clean\` 里补出来的才最接近原图。

### 算法

Chiu et al. 2010（Optics Express 18(18):19413）那一套图论最短路，也就是
`DIJK_SEG.m` 名字的由来：每列每个像素是图的节点，边权 `w = 2 - (g_a+g_b) + eps`，
`g` 是归一化的垂直梯度；梯度越强权重越小，于是"沿边界走"就是从最左列到最右列的
最短路。图是无环的（只能往右），按列做 DP 就行，不用真跑 Dijkstra 的堆。
逐层做，每定出一层就用它限制下一层的搜索范围。

顺序：ILM → IS/OS → RPE（三条最强的先定）→ OPL → RNFL 粗 → IPL → INL → RNFL 精修。

两处和教科书版本不同，都是这批数据逼出来的：

1. **软先验。** 中心凹处内层被压扁 —— 实测内层相对 ILM 的偏移从周边的 40/55/64 px
   压到 15/25/31，单靠硬区间会让 IPL/INL/OPL 在过渡区跑飞。所以按 ILM→ISOS 的
   归一化比例给期望深度，偏离越远权重越大。比例不是拍的，是 120 张 GT 逐列统计的：

   | 层 | (层−ILM)/(ISOS−ILM) 均值 | 标准差 |
   |---|---|---|
   | RNFL/GCL | 0.168 | 0.103 |
   | IPL/INL | 0.430 | 0.074 |
   | INL/OPL | 0.567 | 0.066 |
   | OPL/ONL | 0.653 | 0.063 |
   | RPE/BM | 1.299 | 0.048 |

   RNFL 的方差最大（中心凹处厚度趋近 0、周边厚），所以它的先验强度单独给 0.10，
   比内层的 0.20 弱 —— 按太死反而更差（实测 2.25 vs 2.36）。

2. **RNFL 算两轮。** RNFL 要 IPL 定上界、IPL 又要 RNFL 定下界，循环依赖。
   先用宽约束粗算一次把 IPL 框出来，最后再回头精修。

### 精度

```
cd Matlab_OCT/test
matlab -batch "oct_selftest"
```

拿奇数 60 张标定偏移、偶数 60 张验证（严格的 train/test 分离）：

| 层 | 未校正 | 校正后 |
|---|---|---|
| ILM | 2.99 | **1.32** |
| RNFL/GCL | 3.94 | 2.90 |
| IPL/INL | 3.86 | 2.89 |
| INL/OPL | 3.57 | 2.20 |
| OPL/ONL | 2.90 | 2.12 |
| IS/OS | 2.83 | **1.06** |
| RPE/BM | 3.80 | **1.57** |
| **总体** | 3.41 | **2.01 px** |

逐列误差（全部 120 张 × 432 列 = 51840 条）：中位 **1.08 px**，
47% 的列 <1px、74% <2px、93% <5px。速度 **0.12 s/张**（432×700，纯 MATLAB 单线程）。

`'Offsets'` 那 7 个数是**标定量不是算法的一部分**：算法定位在灰度跃变的中心，
而这批 GT 标得略深，每层稳定偏 1.3~3.6 px（ILM/ISOS/RPE 三条强边界的标准差只有
0.8~1.0，非常一致）。这是标注习惯的差异。换一套数据或另一个标注者就该重标 ——
传 `zeros(1,7)` 看未校正的原始输出。

### 调参过程中站住和没站住的想法

一开始是 2.25 px。有人指出某些图（img_0062）的线"不平滑、很多弯曲"，量化之后发现
**不是抖动问题** —— 我的线曲率 0.016，原版 0.543，我比它平滑 34 倍。真正的毛病是
过度平滑导致线不贴合组织、自己划出一道弧。顺着这个线索：

| 改动 | 结果 |
|---|---|
| **预平滑 sigma 3 → 2** | ✅ 总体 2.12→2.04，img_0062 从 4.06→3.10。RNFL 那条边界本来就弱，sigma=3 会把它糊掉 |
| **内层先验强度 0.20 → 0.08** | ✅ 总体 → 2.02。先验只该在中心凹那种"没梯度可循"的地方兜底，别跟图像证据抢方向 |
| 路径平滑 sigma 调小 | ❌ 5 就是最优，再小反而变差 |
| RNFL 先验改成"从图像估亮带下缘" | ❌ RNFL 3.70→6.73。薄区本身就没有明确的亮度台阶可找（代码留在 `RnflPrior='band'`，默认不用）|
| 去掉 RNFL 先验 | ❌ 3.41→5.71，先验整体是有用的 |
| 先验尺度随 span 缩放 | ❌ 2.28→2.34（`PriorScaleSpan`，默认关）|
| 内层比例整体缩小 5~10% | ❌ 明显变差 |

img_0062 最终 4.06 → **2.67 px**。

RNFL/IPL 仍是最难的两层（约 2.9 px）。最差的是 img_0119/0120（约 7 px）：
那两张视网膜特别薄（span 只有 79 px，正常 ~98），内层会系统偏深 7~9 px，
误差集中在右侧 1/3。比例先验在这种尺度上按不住 —— 已知问题，没解决。

## en-face 与血管处理（exe 里剩下那几个文件）

`EOD_read_seg.exe` 的依赖图里有 9 个 `.m`，分层只用到 `DIJK_SEG.m` 一个。剩下的：

| 原文件 | 这边的对应 | 状态 |
|---|---|---|
| `DIJK_SEG.m` | `oct_layer_seg.m` | ✅ 分层 |
| `FrangiFilter2D.m` + `Hessian2D.m` + `eig2image.m` | `oct_frangi2d.m` | ✅ 血管增强 |
| `enface_deVessel.m` + `graphcut_BW.m` | `oct_devessel.m` | ✅ 去血管 |
| `OCT_SEG.m` / `OCT_SEG_method.m` / `EOD_read_seg.m` | — | ❌ 主流程和 socket 服务外壳，没做 |

```matlab
cd Matlab_OCT
oct_enface_demo                        % 整条链跑一遍并显示
oct_enface_demo('SaveDir', 'D:\out')   % 顺便存图
```

### en-face 投影

分层结果给出的上下界是**跟着视网膜起伏走**的，不是切平面 —— 中心凹下沉近百像素，
切平面会把不同组织层混在一起。`oct_enface` 提供四个预设板层：

| Slab | 范围 | 平均梯度（结构强弱）|
|---|---|---|
| `full` | ILM → RPE | 5.2 |
| `rnfl` | ILM → RNFL | 15.1 |
| `deep`（默认）| IS/OS → RPE | **11.8** |
| `subrpe` | RPE → RPE+30 | 11.4 |

默认选 `deep`：血管的投影阴影在这层最清楚（比 `full` 高一倍）。

### Frangi 血管增强

Frangi et al. 1998 那一套：多尺度算 Hessian，取特征值 |λ1| ≤ |λ2|，
`Rb = λ1/λ2` 衡量管状程度、`S = ‖λ‖` 衡量结构强度，
`V = exp(-Rb²/2β²)·(1-exp(-S²/2c²))`，逐尺度取最大。
`Hessian2D` 和 `eig2image` 作为局部函数放在同一个文件里。

原包用的 `imfilter` 是图像处理工具箱的，这里换成自己写的对称边界卷积。

**写这个的时候栽了两次**，都在实现细节上：

1. `Rb` 的分子分母写反了（写成 `λ2/λ1`）。血管处 λ1≈0，反过来算会让 `Rb` 爆掉、
   `exp(-Rb/β)` 归零 —— 血管**完全检测不到**，响应图几乎全黑。
2. 极性判据用了 λ1，应该用 **λ2**。暗管横切面是"亮-暗-亮"，二阶导为正，
   所以判据是 λ2 > 0。λ1 是沿管方向的曲率，符号没意义。

修完之后合成的暗管上，管心响应 0.964、背景 0.000；同一张图找亮管时管心 0.000。

### 去血管

流程：Frangi 找暗管 → 二值化 + 去小连通块（这一步对应 `graphcut_BW.m`）→
可选膨胀 → 扩散填充补回来。

两个实现上的选择：

- **阈值用分位数，不用"相对最大值"。** Frangi 响应高度偏斜（实测中位 0、
  均值 0.053、最大 1.0），`0.15*max` 只圈到 0.85% 的像素，而血管典型占 5~15%。
  `'Coverage'` 直接指定目标覆盖率更稳。
- **填补用扩散，不用逐列插值。** 逐列线性插值快，但有方向性 —— 填出来的补丁在
  en-face 上留下一道道横条纹，比血管还显眼。扩散（反复用 8 邻域有效像素的均值
  填空洞）各向同性，没这个毛病。

实测（120 幅拼的 en-face，`deep` 板层）：掩膜覆盖 7.9%，
血管处与背景的亮度差 **39.2 → -0.60**，血管性总量降 39%，非血管区一个像素没动。

`'Dilate'` 默认 0，因为两个指标会打架：`Dilate=2` 时"残余血管性"降得最多
（48% vs 38%），但掩膜涨到 16.8%，把血管旁的正常组织也圈进去，填补后血管处比
背景亮 6.5（过补偿）。去血管是为了让后续定量不受干扰，亮度不失真比"抹得干净"
更重要，所以默认不膨胀。

### 关于 graphcut_BW.m

那个文件只有 1214 字节（约 30~40 行），装不下一个完整的 max-flow/min-cut。
从名字和体量看更像是"拿到血管性响应之后做二值化 + 形态学清理"的一层包装，
`oct_devessel` 就按这个实现。**真正的图割（能量最小化）没做** —— 名字对得上，
内部实现不保证一致。

`OCT_SEG.m`（3794 B）和 `OCT_SEG_method.m`（8744 B）是主流程编排，
`EOD_read_seg.m`（1319 B）是那个 TCP 服务外壳（监听 127.0.0.1:30012）。
这两块只有文件名和大小，没有别的线索，没做。

### _analy.dat 格式

原系统的分层结果存成 16 字节头 + `nBscan × 7 × nPoint` 个 uint32（小端）。
仓库里 `test_data\od-3dscan-macular-20210104-150822-001_analy.dat` 正好
`16 + 120×7×1024×4 = 3440656` 字节。

**通道顺序不是由浅到深**，实测（51840 个有效列逐列 100% 满足）是

```
ch1 < ch2 < ch7 < ch6 < ch5 < ch4 < ch3
```

即 `ch1=ILM  ch2=RNFL  ch3=RPE  ch4=IS/OS  ch5=OPL  ch6=INL  ch7=IPL` ——
前两个按深度排，后五个倒着放。`oct_layer_import`/`oct_layer_export` 里的 `CHMAP`
就是这个映射，往返逐元素一致。另外那份文件每幅只有前 432 列非 0，那次扫描就是
432 条 A-line（和 pic_md 的宽度一致）。

## 眼科报告上那套分析可视化

商用 OCT（Cirrus / Spectralis / Topcon）报告上的标准内容都做了：

```matlab
cd Matlab_OCT
oct_report                                  % 一张综合报告图
oct_report('Eye','OS')                      % 左眼（鼻/颞方向互换）
oct_report('Top','ilm','Bot','rnfl')        % 换成 RNFL 厚度分析
oct_report('Save','D:
ep.png')

% 单独用
[cy,cx] = oct_fovea_find(T);                % 中心凹定位
res = oct_etdrs_grid(T, 'Eye','OD');        % 九分区数值
imwrite(oct_thickness_rgb(T), 'topo.png');  % 地形图
imwrite(oct_significance_rgb(T), 'sig.png');% 显著性图
imwrite(oct_etdrs_rgb(res), 'bull.png');    % 靶心图
```

### ETDRS 九分区

[ETDRS](https://www.researchgate.net/figure/Early-Treatment-Diabetic-Retinopathy-Study-ETDRS-grid-a-Delineation-of-the-nine_fig1_326338215)
网格是三个同心圆（直径 **1 / 3 / 6 mm**），内外环各按对角线分成上/鼻/下/颞
四象限，一共 9 区。方位按标准报告的画法：上=superior、下=inferior，
**OD 左=颞、右=鼻，OS 左右互换**。我们这份扫描是 6×6 mm，正好覆盖外环。

实测（`test_data` 那份，OD）：

```
        上      鼻      下      颞
内环   343.2   351.9   341.0   334.5
外环   278.8   303.2   290.1   274.3
中心点 231.9   中心区(1mm) 289.7   6mm 平均 299.5
体积   1mm 0.228 / 3mm 2.380 / 6mm 8.297 mm³
```

和文献对照：

| 指标 | 我算的 | 文献 |
|---|---|---|
| 中心点厚度 | 231.9 µm | Spectralis 正常 [227.3 µm](https://www.ajo.com/article/S0002-9394(09)00161-5/pdf) |
| 6mm 圆体积 | 8.297 mm³ | 正常约 7.5~8.5 |
| 内环 vs 外环 | 334~352 > 274~303 | 内环最厚 ✓ |
| 鼻侧 vs 颞侧 | 鼻 352/303 > 颞 335/274 | 鼻侧更厚 ✓ |

中心区（1mm 圆平均）289.7 比[文献的 235~270 µm](https://www.dovepress.com/normative-data-of-macular-thickness-using-spectral-domain-optical-cohe-peer-reviewed-fulltext-article-OPTH)
偏高 20 µm 左右。原因之一是这份数据的中心凹凹陷很窄 —— 剖面图上 1 mm 内
就从 232 升到 340，1mm 圆的平均被边缘拉高了。文献也明确说厚度依赖设备和
扫描协议，所以这个差值不一定是错，但拿去和别的设备比要当心。

### 厚度地形图与显著性图

两套配色都按报告的惯例来：

- **地形图**：深蓝 → 青 → 绿 → 黄 → 红 → 白，**冷色薄、暖色厚**。
- **显著性图**：固定四色 —— 红 = 最薄的 1%、黄 = 1~5%、绿 = 5~95%（正常那
  90%）、白 = 最厚的 5%。这是
  [Cirrus/Spectralis 的标准分带](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11978987/)。

**显著性图有个前提要说清楚。** 那四档本来是相对**正常人群数据库**的百分位。
没有正常库时 `oct_significance_rgb` 退化成"相对本次扫描自身的分位"，
`info.mode` 会标成 `'self'`，`oct_report` 也会在输出里打一行提醒。
这种图只能看"这只眼内部哪里相对薄/厚"，**不能当诊断依据**。
有正常库就传进去，这时走 z 分数 + 正态分位，才是真正的临床显著性图：

```matlab
oct_significance_rgb(T, 'Norm', [290 15])                  % 全图统一 mu/sigma
oct_significance_rgb(T, 'Norm', struct('mu',M,'sigma',S))   % 逐像素的正常库
```

### 中心凹定位

ETDRS 网格必须对准中心凹，所以这一步不能错。`oct_fovea_find` 在全层厚度图上
找最小值，三个细节：

- **先平滑**（默认 sigma 纵 3 / 横 8）。逐点最小值会被噪声和分层小毛刺带跑。
  纵向只有 120 幅、横向 432 条，所以两个方向的 sigma 不一样。
- **只在中间一半里找**（`'Margin'` 默认 0.25）。图像边缘常因分层失败而异常薄，
  不限制范围很容易定位到角上。
- **亚像素**：在最小值附近按"越薄权重越大"做质心。

实测定位到 (B-scan 64.2, A-line 201.2)，那一点厚度 232 µm（全图中位 288），
合成的凹陷测试也能定到 ±4 像素内。

### 报告图的六块

`oct_report` 出的那张图：厚度地形图（带色条）、ETDRS 靶心图（九个数值 +
S/N/I/T 方位）、显著性图（带图例）、en-face C-scan（红十字标中心凹）、
过中心凹的 B-scan（叠 7 条分层线）、过中心凹的水平/垂直厚度剖面曲线。
剖面那条是经典的"双峰夹中心凹"形状：谷底 232 µm，两侧升到 340~366。

靶心图里的数字是自己画的 5×7 点阵（`insertText` 要 Computer Vision 工具箱，
这台机器没装），所以只有数字、小数点和 S/N/I/T 这几个字形。

## Analy_and_image_show 那三个脚本

`oct_cscan.py` / `oct_thickness.py` / `oct_DeviationMap.py` 也一并做了，
直接吃 `test_data` 下那两份真实数据：

```matlab
cd Matlab_OCT
oct_analy_demo                              % C-scan + 层厚图 + 偏差图
oct_analy_demo('Top','ilm', 'Bot','rnfl')   % 换成 RNFL 厚度
oct_analy_demo('Analy','seg')               % 不读 analy.dat，现场分层
oct_analy_demo('SaveDir', 'D:\out')
```

实测层厚（用原 exe 的分层，`test_data` 那份扫描）：

| 层对 | 中位厚度 | 5%~95% |
|---|---|---|
| ILM → RNFL | 29.3 µm | 14.6~75.7 |
| RNFL → IPL | 56.2 | 36.6~95.2 |
| IPL → INL | 31.7 | 19.5~43.9 |
| INL → OPL | 19.5 | 12.2~26.9 |
| OPL → IS/OS | 75.7 | 56.2~109.9 |
| IS/OS → RPE | 65.9 | 58.6~73.2 |
| **ILM → RPE（全层）** | **288 µm** | 244~349 |

全层 288 µm 落在正常黄斑的 200~350 µm 内，厚度图上中心凹（最薄的黑点）和
环形增厚都很清楚 —— 这是判断整条链对不对的关键证据。

### 原脚本里三个值得一提的地方

**1. 通道顺序**（原脚本留了句空注释 `#整理分层的正确顺序`，没做）。
`_analy.dat` 的 7 个槽位不是按深度排的，深度方向也和显示方向相反。
两件事一起处理之后，由浅到深是 `ch3 < ch4 < ch5 < ch6 < ch7 < ch2 < ch1`。
原脚本按槽位号直接取，所以：

| 脚本写的 | 以为在算 | 实际在算 |
|---|---|---|
| `oct_pos[0] - oct_pos[6]` | 全视网膜厚度 | ILM → IPL/INL，只有 144 µm |
| `oct_pos[1] - oct_pos[2]` | 某一层厚度 | RNFL → RPE，225 µm，跨了大半个视网膜 |

映射是拿三个生理判据定下来的，不是猜的：玻璃体腔应最暗（ILM 之上 38.9 vs
RPE 之下 86.9）、RNFL 厚度变化幅度应远大于 RPE-IS/OS（73 px vs 15 px）、
全层厚度应在 200~350 µm。反过来取这三条全都不成立。

**2. `oct_DeviationMap.py` 跑不起来。** 第 137 行 `new_img2np.zeros(...)`
少了个 `=`，是个语法错误。而且分级判据有个死分支：

```python
if   abs(dev) > 0.99: x = 99
elif abs(dev) > 0.95: x = 95
elif abs(dev) > 0.5 : x = 10
elif abs(dev) > 1   : x = 5      # 永远走不到：>1 的早被第一条抓走了
else                : x = 1
```

`oct_deviation_map` 换成一组从小到大、可配置的阈值（默认 5%/10%/25%/50%）。
参考厚度默认用数据自己的中位数 —— 原脚本写死 `nom_thickness = 28`，
那个值配它自己算出的厚度（144 µm，即 59 px）差一倍多，整张图会被判成
"偏差 > 99%"。

**3. 深度翻转。** 原脚本的 `700 - m` 是**对的**，只是原因绕：
`oct_cscan.py` 里 `ROTATE_90` 会把深度方向翻过来，`700 - m` 正好补回去。
`oct_volume_read` 用 `'Flip'`（默认 true）直接把体数据摆成"第 1 行最浅"，
`oct_layer_import` 也做对称的翻转，两边约定一致。

### 闭环验证

`Desktop\pic_md_origin\pic_bscan` 那 120 张 PNG 就是这份 `.dat` 的可视化：

- `vol[59]` 转置 + 深度翻转与 `img_0060.png` 的灰度**逐像素 100% 相同**
  （平均差 0.00；换任何别的幅号都不匹配）
- 那些彩线与 `analy.dat` 按上述映射翻转后的值，**99.83% 的点完全一致**
  （RPE 100.00%、平均差 0.032 px；剩下 0.17% 是两条线重叠时被覆盖）

所以 B-scan 读取、深度方向、通道映射三件事都对得上。

## 数据

脚本会自动去找这两份（都不在本仓库里，太大）：

| 数据 | 路径 | 形状 | 对应预设 |
|---|---|---|---|
| 草莓（vulkan 工程那份） | `Desktop\Desktop\faster_3dim_scan_vulkan\test2_16bit.raw` | 262144 × 1664 uint16 = 512 幅 × 512 线 | `strawberry1664` |
| EOD 实测光谱 | `Desktop\Desktop\octifft\oct_origin_spectrum.csv` | 5951 × 2048，12 bit | `eod2048` |

这两份都能重建出正常的 B-scan（见下面"验证"一节）。EOD 那份是单反射面的标定数据，
不是组织样本，细节见"octifft 那份 EOD 数据是什么"。

仓库里的 `test_data/bin` 只有 8932 字节（约 2.9 条 A-line），是 README 说的"缓存里只剩的片段"，
只够验证解包，重建不出图：

```matlab
d = oct_load_spectrum('../test_data/bin', 'AlineLength', 2048);   % 自动按 socket 块解 12 bit
plot(d(1, :));
```

草莓那份数据的原始出处（OCTproZ 的测试集）：
<https://figshare.com/articles/dataset/SSOCT_test_dataset_for_OCTproZ/12356705>

## 重建的六步

`oct_recon_pipeline.m` 里逐步对应 `cpu_pipline.cpp`：

| 步 | C++ 函数 | MATLAB 做法 |
|---|---|---|
| 1 | `background_subtraction` | `filter(ones(1,bgLines)/bgLines, 1, x, [], 1)` 做拖尾滑动平均再相减；前 `bgLines` 条原样透传 |
| 2 | `klinearization` | 三次多项式 `t(i)=d0+(d1/N)i+(d2/N²)i²+(d3/N³)i³` 重采样 + 线性插值，下标查找表预先算好 |
| 3 | `calibration_method` | `complex(x.*cos(tc), x.*direction.*sin(tc))`，实信号变复信号顺带做色散补偿 |
| 4 | `window_hanning` | 乘 `fillFactor=0.95` / `centerPosition=0.5` 的汉宁窗（整数运算照抄，包括那两个 0.999 / 0.0001 阈值）|
| 5 | `cv::idft` | `ifft(z, [], 2) * len`，**乘 len** 是因为 OpenCV 的 `idft` 没带 `DFT_SCALE`，是未归一化的 |
| 6 | 取模 + log | `log(abs(z) + logOffset)`，`logOffset = 1000` |

然后 `oct_recon_demo.m` 负责显示侧：转置取前一半（去 IDFT 镜像）填进 B-scan 的列、
偶数幅左右翻转（双向扫描，对应 C++ 的 `lr_swap`）、按帧 min/max 拉满对比度
（对应 `minMaxIdx` + `convertTo`）、深度方向求和得 en-face。

`batch` 模式每幅会往前多喂 `bgLines` 条再丢掉，让背景滑动平均跨过 B-scan 边界。
C++ 的 `RunDemo1`/`RunDemo2` 是一个 batch 喂一次，背景窗口在每个 batch 头部重置
（`background_subtraction` 里的 `if (i < 20)` 是相对 batch 的）；因为它 `batch_size=64`，
一次喂 32768 条，重置的代价被摊薄了。这里按幅处理，要是也重置，第 2 幅往后整幅偏亮，
而且和 `aline` 模式对不上。垫一下之后两种模式的输出**位级一致**。

### 和 C++ 不一致的两处，都是故意的

1. **第 2 步的原地插值。** C++ 是 `klinearization(input_t, input_t, 1664)`，输入输出同一块内存。
   在 `t(i) < i` 的区间（草莓那套系数下 x∈[0.534, 1.0]，即后半条 A-line）会读到本轮**已经被覆写**的值。
   CUDA 版 (`cuda_pipline.cu`) 写的是独立的 `output`，所以 GPU 和 CPU 结果本来就不一样。
   这里默认走异地（和 CUDA 一致）；想复刻 CPU 的原地行为：

   ```matlab
   p = oct_recon_params('strawberry1664', 'klinInplace', true);
   oct_recon_demo('Params', p);
   ```

   差异不小：草莓数据第 120 幅实测两者最大差 **2.893**，而整幅的动态范围只有 3.058 ——
   也就是说这不是个可以忽略的细节，图会明显不一样（原地版竖条纹更重）。

2. **色散系数 `c`。** CPU 版是 `c = [0 10.5 1.5 0]`，CUDA 版是 `c = [0 20.24 0 0]`。
   预设 `strawberry1664` 用 CPU 的，`cuda1664` 用 GPU 的。

## octifft 那份 EOD 数据是什么

重建出来是**一个反射面在深度上来回扫**的轨迹（斜坡 + 回扫的锯齿/V 形），
不是组织样本 —— 看着像镜面或玻片的对光/标定数据。5951 条 A-line 里：

- 26% 的峰落在 DC 附近（`loc < 30`），也就是量程内没有反射面
- 14%（806 条）是量程中间的强反射面，适合用来标定

`eod2048` 预设的 `d = [0 2047 0 0]`（恒等重采样）和 `c = [0 0 0 0]`（不补色散）
**已经是这份数据的最优值**，不用再调。拿那 806 条扫过：

| 参数 | 扫描范围 | 最优 | 亚 bin FWHM |
|---|---|---|---|
| `c1`（色散一次项） | 0 ~ 30 | 1.0 | 5.998（基线 6.068，只好 1.2%，基本是平的）|
| `d2`（k 域二次项） | −600 ~ +600 | **0** | 6.0；偏到 ±600 劣化到 16~21 |

`d2` 扫出来是个清晰的 V 形最小值，且最小值就在 0 —— 说明这套采集出来的光谱本来
就是 k 域线性的，也没有明显的未补偿色散。

### 但这份数据的光谱是削顶的

`oct_show_spectrum('ShowAline', true)` 一眼能看出来：原始光谱峰顶是一条平的直线，
减背景之后那一段完全没有条纹。实测：

- **5951 条 A-line 全部（100%）有饱和点**（`== 4095`）
- 每条中位 **216 个点饱和**（占 2048 点带宽的 10.5%），最多 265 个
- 饱和集中在采样点 **1131 ~ 1441**，而汉宁窗的有效区是 115 ~ 1935
  —— 也就是说饱和区**完全落在窗内**，全都参与了 IDFT

这一段带宽的干涉条纹被 ADC 削掉了，直接损失轴向分辨率和 SNR，也是峰值只比底噪
高 0.96（log 域）、FWHM 停在 6 bin 的原因之一。这是采集端的曝光/增益问题，
调 `d`/`c` 救不回来 —— 要把相机积分时间或参考臂光强降下来重采一份。

## 换了硬件/光路怎么重新标 d / c

判据就一条：**同一个反射面的点扩散函数越窄越好**。别用整数 bin 量半高宽（太粗，
量不出区别），要在**线性幅度域**上做两侧线性插值到亚 bin；也要先把量程内没有
反射面的 A-line 剔掉，否则峰落在 DC 上会把中位数污染掉：

```matlab
d  = oct_load_spectrum('.../oct_origin_spectrum.csv');
p0 = oct_recon_params('eod2048');
r0 = oct_recon_pipeline(d, p0);

% 只留"量程中间有强反射面"的 A-line
[pk, loc] = max(r0, [], 2);
good = loc >= 30 & loc <= size(r0,2)-30 & (pk - median(r0,2)) > 1.5;
sub  = d(good, :);

for c1 = 0:2:30
    r = oct_recon_pipeline(sub, oct_recon_params('eod2048', 'c', [0 c1 0 0]));
    % 在 exp(r) - logOffset 上量亚 bin FWHM，取中位数
    fprintf('c1=%5.1f  FWHM %.3f\n', c1, subbinFWHM(r, p0));
end
```

`test/oct_selftest.m` 旁边的分析脚本思路就是这个，`subbinFWHM` 的写法见
上面表格那次实测（先找峰、取半高、两侧线性插值求交点）。

`p.bgLines` 也值得试：`read_all_bin.cpp` 用 32 条，vulkan 工程用 20 条，改这个对
固定图样噪声（FPN）的压制效果影响很直接。

## 验证

在 MATLAB R2026b Prerelease 上跑过（无 Image Processing / Signal 工具箱）：

```
cd Matlab_OCT/test
matlab -batch "oct_selftest"      % 163 项断言全过
```

- **算法正确性**：`oct_recon_pipeline` 的输出与「C++ 逐行直译」实现（`test/golden.py`，
  含原地插值的副作用）对比，`klinInplace` 两种模式下相对误差 **~1e-15**。
- **解包**：`test_data/bin` 的 12 bit socket 块解出 2 条 A-line，前 24 个采样逐一核对；
  `raw16`/`raw12` 的 `SkipLines` 用 `fseek` 实现，与全读后切片的结果逐元素一致。
- **两种模式一致**：`aline` 与 `batch` 输出最大差 **0.0**。
- **真数据出图**：草莓数据 256 幅 × 512 线 × 1664 点，**9.0 s**（≈14600 A-line/s，
  单线程纯 MATLAB），B-scan 能看清表面和籽（achene）、en-face 能看出果肉纹理。
- **光谱显示**：EOD 第 1500 条光谱渲染成 2344×480 黑底白线，和仓库根目录 `image.gif`
  的帧形状一致（双峰肩台、饱和平顶、锯齿条纹）。
- **滚动 B-scan**：`'range'` 归一化的结果与直接批量 `oct_recon_pipeline` 逐元素一致
  （最大差 4.8e-07，single 存储的舍入）；`Range [2250 3050]` 801 条端到端
  **1.57 s（510 A-line/s）**，全部 5951 条 4.34 s（1370 A-line/s）。

`oct_selftest` 需要 `test_data/bin`；octifft 的 CSV 不在时相关用例自动 SKIP。
