# 参考文献

`Matlab_OCT` 里各个算法的出处。每一条的作者、卷期页码、DOI 都通过 CrossRef API
核对过，不是凭印象写的。

标注说明：
- **★ 直接实现** —— 代码就是照这篇做的
- ○ 背景/依据 —— 用来定参数、定判据或解释结果
- ◇ 数据来源

---

## 一、视网膜分层

### ★ Chiu et al. 2010 —— 图论最短路分层

> Chiu SJ, Li XT, Nicholas P, Toth CA, Izatt JA, Farsiu S.
> **Automatic segmentation of seven retinal layers in SDOCT images congruent with
> expert manual segmentation.**
> *Optics Express* 2010;18(18):19413–19428.
> DOI [10.1364/OE.18.019413](https://doi.org/10.1364/OE.18.019413)
> · [全文](https://opg.optica.org/oe/fulltext.cfm?uri=oe-18-18-19413)

`oct_layer_seg.m` 的算法本体。把每列每个像素当图的节点，边权
`w = 2 − (g_a + g_b) + ε`（g 是归一化垂直梯度），沿边界走就是最短路；
逐层做，每定出一层就用它限制下一层的搜索范围。

被封在 `EOD_read_seg.exe` 里的 `DIJK_SEG.m` 走的也是这个思路 —— 文件名里的
"DIJK" 就是 Dijkstra。不过因为图是无环的（只能往右），我按列做 DP 即可，
不用真跑 Dijkstra 的堆。

**我加的两处与原文不同的东西**，都是这批数据逼出来的，见 `README.md` 的
"和 C++ 不一致的两处"和"调参过程中站住和没站住的想法"：
1. 软先验（中心凹处内层被压扁，硬区间跟不上）
2. RNFL 算两轮（RNFL 与 IPL 互为约束，循环依赖）

### ○ Chiu et al. 2012 —— 闭合轮廓的同类方法

> Chiu SJ, Toth CA, Bowes Rickman C, Izatt JA, Farsiu S.
> **Automatic segmentation of closed-contour features in ophthalmic images using
> graph theory and dynamic programming.**
> *Biomedical Optics Express* 2012;3(5):1127–1140.
> DOI [10.1364/BOE.3.001127](https://doi.org/10.1364/BOE.3.001127)

同一组人把方法推广到闭合轮廓。没实现，列在这儿是因为它把图构造讲得更清楚。

### ○ LaRocca et al. 2011 —— 角膜层的同类方法

> LaRocca F, Chiu SJ, McNabb RP, Kuo AN, Izatt JA, Farsiu S.
> **Robust automatic segmentation of corneal layer boundaries in SDOCT images
> using graph theory and dynamic programming.**
> *Biomedical Optics Express* 2011;2(6):1524–1538.
> DOI [10.1364/BOE.2.001524](https://doi.org/10.1364/BOE.2.001524)

---

## 二、血管增强

### ★ Frangi et al. 1998 —— Frangi vesselness

> Frangi AF, Niessen WJ, Vincken KL, Viergever MA.
> **Multiscale vessel enhancement filtering.**
> In: *MICCAI 1998*, Lecture Notes in Computer Science, vol. 1496, pp. 130–137.
> DOI [10.1007/BFb0056195](https://doi.org/10.1007/BFb0056195)

`oct_frangi2d.m` 的算法本体。多尺度算 Hessian，取特征值 |λ₁| ≤ |λ₂|，

```
Rb = λ₁/λ₂                 管状程度（血管 ≈ 0，斑点 ≈ 1）
S  = √(λ₁² + λ₂²)          结构强度
V  = exp(−Rb²/2β²) · (1 − exp(−S²/2c²))
```

逐尺度取最大响应。对应 exe 里的 `FrangiFilter2D.m` + `Hessian2D.m` +
`eig2image.m` 三个文件，我合成了一个。

**实现时栽的两处**（细节见 `README.md`）：`Rb` 的分子分母写反过、
极性判据误用了 λ₁（应该用 λ₂）。这两个错误都会让血管**完全检测不到**。

### ○ Sato et al. 1998 —— 同期的多尺度线状滤波

> Sato Y, Nakajima S, Shiraga N, Atsumi H, Yoshida S, Koller T, Gerig G, Kikinis R.
> **Three-dimensional multi-scale line filter for segmentation and visualization
> of curvilinear structures in medical images.**
> *Medical Image Analysis* 1998;2(2):143–168.
> DOI [10.1016/S1361-8415(98)80009-1](https://doi.org/10.1016/S1361-8415\(98\)80009-1)

和 Frangi 同年、思路平行的另一套 Hessian 线状滤波。没实现，但讨论
特征值判据时值得对照。

### ◇ Kroon 的 MATLAB 实现

> Dirk-Jan Kroon. **Hessian based Frangi Vesselness filter.**
> MATLAB Central File Exchange.
> <https://www.mathworks.com/matlabcentral/fileexchange/24409>

`EOD_read_seg.exe` 依赖图里那三个文件（`FrangiFilter2D.m` / `Hessian2D.m` /
`eig2image.m`）就是这个包 —— 文件名和大小都对得上。算法本身是上面 Frangi
那篇的，这个包只是实现。**我没有拆 exe 里的加密源码**，`oct_frangi2d.m` 是
照论文重写的，选项名沿用了这个包的叫法（`FrangiScaleRange` 之类）方便对照。

原包用了 `imfilter`（图像处理工具箱），我换成了自己写的对称边界卷积。

---

## 三、OCT 成像与重建

### ○ Huang et al. 1991 —— OCT 的原始论文

> Huang D, Swanson EA, Lin CP, Schuman JS, Stinson WG, Chang W, Hee MR,
> Flotte T, Gregory K, Puliafito CA, Fujimoto JG.
> **Optical Coherence Tomography.**
> *Science* 1991;254(5035):1178–1181.
> DOI [10.1126/science.1957169](https://doi.org/10.1126/science.1957169)

### ○ Leitgeb et al. 2003 / Choma et al. 2003 —— 频域 OCT 的灵敏度优势

> Leitgeb R, Hitzenberger CK, Fercher AF.
> **Performance of Fourier domain vs. time domain optical coherence tomography.**
> *Optics Express* 2003;11(8):889–894.
> DOI [10.1364/OE.11.000889](https://doi.org/10.1364/OE.11.000889)

> Choma MA, Sarunic MV, Yang C, Izatt JA.
> **Sensitivity advantage of swept source and Fourier domain optical coherence
> tomography.**
> *Optics Express* 2003;11(18):2183–2189.
> DOI [10.1364/OE.11.002183](https://doi.org/10.1364/OE.11.002183)

解释了为什么 `oct_recon_pipeline.m` 那条链是"采光谱 → IDFT 出深度剖面"
而不是逐点扫描。

### ○ Wojtkowski et al. 2004 —— 数值色散补偿

> Wojtkowski M, Srinivasan VJ, Ko TH, Fujimoto JG, Kowalczyk A, Duker JS.
> **Ultrahigh-resolution, high-speed, Fourier domain optical coherence tomography
> and methods for dispersion compensation.**
> *Optics Express* 2004;12(11):2404–2422.
> DOI [10.1364/OPEX.12.002404](https://doi.org/10.1364/OPEX.12.002404)

`oct_recon_pipeline.m` 第 2、3 步（k 域线性化 + 色散补偿相位）的依据。
代码里那两组三次多项式系数 `d` 和 `c` 就是干这个的。

> **注意**：我们这套 `eod2048` 预设实测 `d = [0 2047 0 0]`（恒等重采样）、
> `c = [0 0 0 0]`（不补色散）就是最优 —— 拿 806 条强反射 A-line 扫过，
> 亚 bin FWHM 的最小值就落在这组默认值上。说明这套采集出来的光谱本来就是
> k 域线性的。换硬件要重标，方法见 `README.md`。

### ○ Dorrer et al. 2000 —— 光谱干涉的采样问题

> Dorrer C, Belabas N, Likforman JM, Joffre M.
> **Spectral resolution and sampling issues in Fourier-transform spectral
> interferometry.**
> *Journal of the Optical Society of America B* 2000;17(10):1795–1802.
> DOI [10.1364/JOSAB.17.001795](https://doi.org/10.1364/JOSAB.17.001795)

波长域到波数域重采样为什么必要的理论背景。

---

## 四、ETDRS 网格与黄斑厚度

### ○ ETDRS Report 1 (1985) —— 网格的出处

> Early Treatment Diabetic Retinopathy Study Research Group.
> **Photocoagulation for Diabetic Macular Edema. ETDRS report number 1.**
> *Archives of Ophthalmology* 1985;103(12):1796–1806.
> DOI [10.1001/archopht.1985.01050120030015](https://doi.org/10.1001/archopht.1985.01050120030015)

### ○ ETDRS Report 7 (1991) —— 研究设计

> Early Treatment Diabetic Retinopathy Study Research Group.
> **Early Photocoagulation for Diabetic Retinopathy. ETDRS report number 9.**
> *Ophthalmology* 1991;98(5 Suppl):766–785.
> DOI [10.1016/S0161-6420(13)38011-7](https://doi.org/10.1016/S0161-6420\(13\)38011-7)

`oct_etdrs_grid.m` 的三个同心圆（直径 1/3/6 mm）+ 内外环各四象限 = 9 区，
这个划分法出自 ETDRS 研究，后来被所有商用 OCT 沿用。

> **说明**：ETDRS 原始报告是给眼底照相/激光治疗定分区的，不是为 OCT 写的。
> OCT 厂商把这个网格搬到厚度图上是后来的惯例。所以这两篇是"分区定义的
> 出处"，不是"OCT 厚度分析的方法学论文"。

### ○ Grover et al. 2009 —— Spectralis 的正常值

> Grover S, Murthy RK, Brar VS, Chalam KV.
> **Normative Data for Macular Thickness by High-Definition Spectral-Domain
> Optical Coherence Tomography (Spectralis).**
> *American Journal of Ophthalmology* 2009;148(2):266–271.
> DOI [10.1016/j.ajo.2009.03.006](https://doi.org/10.1016/j.ajo.2009.03.006)

中心点厚度正常值约 227.3 µm。我们这份数据算出来 **231.9 µm**，很接近。

### ○ Invernizzi et al. 2018 —— 分层厚度图的正常值

> Invernizzi A, Pellegrini M, Acquistapace A, Benatti E, Erba S, Cozzi M,
> Cigada M, Viola F, Gillies M, Staurenghi G.
> **Normative Data for Retinal-Layer Thickness Maps Generated by Spectral-Domain
> OCT in a White Population.**
> *Ophthalmology Retina* 2018;2(8):808–815.e1.
> DOI [10.1016/j.oret.2017.12.012](https://doi.org/10.1016/j.oret.2017.12.012)

逐层（不只是全层）的正常值，`oct_thickness_map.m` 换 `Top`/`Bot` 做分层
分析时的对照。

### ○ Jammal et al. 2022 —— SD-OCT 黄斑厚度正常值

> Jammal HM, Al-Omari R, Khader Y.
> **Normative Data of Macular Thickness Using Spectral Domain Optical Coherence
> Tomography for Healthy Jordanian Children.**
> *Clinical Ophthalmology* 2022;16:3571–3580.
> DOI [10.2147/OPTH.S386946](https://doi.org/10.2147/OPTH.S386946)

这篇明确指出**厚度依赖设备和扫描协议**，正常库要针对设备单独建 ——
这是为什么 `oct_significance_rgb.m` 默认走"相对自身分位"而不是硬编一套
正常值的原因。

---

## 五、厚度图与显著性图的临床用法

### ○ Ahn 2025 —— 厚度分析综述

> Ahn SJ.
> **Retinal Thickness Analysis Using Optical Coherence Tomography: Diagnostic
> and Monitoring Applications in Retinal Diseases.**
> *Diagnostics* 2025;15(7):833.
> DOI [10.3390/diagnostics15070833](https://doi.org/10.3390/diagnostics15070833)
> · [全文](https://pmc.ncbi.nlm.nih.gov/articles/PMC11988421/)

厚度地形图的色标惯例（冷色薄、暖色厚）就是照这个来的。

### ○ Kim et al. 2021 —— 偏差图的临床应用

> Kim KE, Ahn SJ, Woo SJ, Park KH, Lee BR, Lee YK, Sung YJ.
> **Use of OCT Retinal Thickness Deviation Map for Hydroxychloroquine
> Retinopathy Screening.**
> *Ophthalmology* 2021;128(1):110–119.
> DOI [10.1016/j.ophtha.2020.06.021](https://doi.org/10.1016/j.ophtha.2020.06.021)

`oct_significance_rgb.m` 那种"偏差图"在临床上怎么用的实例。

### ○ Nemet et al. 2025 —— 四色分带的陷阱（"绿病"）

> Nemet M, Lankry P, Waisbourd M.
> **Overlooking early glaucoma with an apparently normal OCT RNFL: beware of
> "Green Disease".**
> *Eye* 2025;39:1217–1219.
> DOI [10.1038/s41433-025-03661-0](https://doi.org/10.1038/s41433-025-03661-0)

红/黄/绿/白四带的百分位定义（红 <1%、黄 1–5%、绿 5–95%、白 >95%）就是
这类文章里说的那套。

> **这篇更重要的是它的警告**："绿色 = 正常"是个陷阱 —— 落在绿带只说明
> 还在正常库的 5–95% 区间里，不等于没有病变（早期青光眼可能全绿）。
> 反过来也有"红病"（正常变异被标成红色）。
> 所以 `oct_significance_rgb.m` 在没有正常库时会把 `info.mode` 标成
> `'self'`，`oct_report` 也会打提醒 —— 那种图**不能当诊断依据**。

---

## 六、数据来源

### ◇ OCTproZ —— 草莓测试集

> Zabic M, Matthias B, Heisterkamp A, Ripken T.
> **Open Source Optical Coherence Tomography Software.**
> *Journal of Open Source Software* 2020;5(54):2580.
> DOI [10.21105/joss.02580](https://doi.org/10.21105/joss.02580)

`oct_recon_demo` 里 `strawberry1664` 预设配的那份 `test2_16bit.raw`
（872 MB，没放进包里）就是这个项目的公开测试集：
<https://figshare.com/articles/dataset/SSOCT_test_dataset_for_OCTproZ/12356705>

`faster_3dim_scan_vulkan` 工程的 `main.cpp` 里也注明了这个出处。

### ◇ 包内的示例数据

`data/` 下的体数据、分层结果、B-scan、光谱都来自本项目自己的设备，
不是公开数据集。详见 `data/README.txt`。

---

## 关于引用准确性

上面每条的作者、期刊、卷期、页码、DOI 都通过 CrossRef API 查过。

过程中确实查错过一次：我一开始凭 PII 猜 Grover 2009 的 DOI 是
`10.1016/j.ajo.2009.02.002`，查出来是一篇早产儿视网膜病变远程医疗的论文，
完全不相干。正确的是 `10.1016/j.ajo.2009.03.006`。**DOI 不要猜。**

两条 ETDRS 报告的 CrossRef 记录没有作者字段（团体作者），这是正常的。
报告编号我按通行的引法标注，但 Report 7 那条 CrossRef 返回的标题是
"Early Photocoagulation for Diabetic Retinopathy"，通常被引作 report
number 9 —— 如果你要在正式文稿里引，建议再核一次报告编号。
