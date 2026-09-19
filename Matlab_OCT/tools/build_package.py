#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Matlab_OCT 打成一个解压即用的分发包。

只用 Python 标准库，不需要 numpy / PIL / MATLAB。

用法
----
    python tools/build_package.py                     # 默认输出到仓库根
    python tools/build_package.py -o D:\\out           # 指定输出目录
    python tools/build_package.py --spectrum-rows 1200
    python tools/build_package.py --bscan-step 5      # B-scan 样例密一点
    python tools/build_package.py --no-bscan          # 不放 B-scan

数据从哪来
----------
volume / analy
    仓库的 test_data\\ 下，随仓库一起提交的，必需。

bscan（带 7 条分层线的 B-scan PNG）
    优先用 --bscan-dir 指的现成目录；没有就**从 volume + analy 现场生成**。
    生成出来的和原来那批 PNG 逐像素一致（验证过），所以不必额外保存
    那 42 MB 图片。

spectrum（原始光谱 CSV）
    仓库里没有，需要 --spectrum 指一份。不给就跳过，包里不带光谱，
    对应的 demo 会自动跳过。data\\README.txt 里会写明这一点。
"""

import argparse
import io
import os
import shutil
import struct
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PKG  = os.path.dirname(HERE)             # Matlab_OCT/
ROOT = os.path.dirname(PKG)              # 仓库根

# _analy.dat 的槽位 -> 由浅到深的层（1-based 槽位号）。
# 顺序不是由浅到深，深度方向也是反的，判据见 oct_layer_import 的说明。
CHMAP  = [3, 4, 5, 6, 7, 2, 1]
LAYER_COLORS = [
    (255, 0, 0),      # ILM
    (255, 255, 0),    # RNFL/GCL
    (255, 0, 255),    # IPL/INL
    (255, 125, 0),    # INL/OPL
    (255, 0, 125),    # OPL/ONL
    (0, 255, 0),      # IS/OS
    (0, 0, 255),      # RPE/BM
]

DEPTH   = 700
NALINE  = 432
VOLHDR  = 1024
ANAHDR  = 16
NPOINT  = 1024


def log(msg):
    print(msg, flush=True)


# ---------------------------------------------------------------- PNG
def write_png(path, rgb_rows, width, height):
    """写一个 8 位 RGB 的 PNG。rgb_rows 是每行的 bytearray（长 width*3）。"""
    raw = bytearray()
    for row in rgb_rows:
        raw.append(0)            # filter type 0 (None)
        raw += row

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', zlib.compress(bytes(raw), 9)))
        f.write(chunk(b'IEND', b''))


def make_bscan_pngs(volpath, analypath, outdir, step):
    """从体数据 + 分层结果生成带 7 条线的 B-scan PNG。

    和原来那批 pic_bscan 的 PNG 逐像素一致：
      * 体数据每幅是 NALINE x DEPTH 行优先，转置后再翻转深度
      * 分层值要做 DEPTH - v 才是 0-based 行号
    """
    with open(volpath, 'rb') as f:
        f.seek(VOLHDR)
        volraw = f.read()
    frame = DEPTH * NALINE
    nb = len(volraw) // frame

    with open(analypath, 'rb') as f:
        f.seek(ANAHDR)
        anaraw = f.read()
    per = 7 * NPOINT * 4
    nba = len(anaraw) // per

    n = min(nb, nba)
    made = 0
    for i in range(0, n, step):
        base = i * frame
        # 第 i 幅：NALINE 条 A-line，每条 DEPTH 个采样（行优先）
        # 目标图是 DEPTH 行 x NALINE 列，且深度翻转
        rows = []
        for y in range(DEPTH):
            src_depth = DEPTH - 1 - y          # 翻转
            row = bytearray(NALINE * 3)
            for x in range(NALINE):
                v = volraw[base + x * DEPTH + src_depth]
                j = x * 3
                row[j] = v
                row[j + 1] = v
                row[j + 2] = v
            rows.append(row)

        # 画 7 条线
        ab = i * per
        for k, slot in enumerate(CHMAP):
            off = ab + (slot - 1) * NPOINT * 4
            vals = struct.unpack_from('<%dI' % NPOINT, anaraw, off)
            r, g, b = LAYER_COLORS[k]
            for x in range(NALINE):
                v = vals[x]
                if v == 0:
                    continue
                yy = DEPTH - v                 # 0-based 行号
                if 0 <= yy < DEPTH:
                    j = x * 3
                    rows[yy][j] = r
                    rows[yy][j + 1] = g
                    rows[yy][j + 2] = b

        write_png(os.path.join(outdir, 'img_%04d.png' % (i + 1)),
                  rows, NALINE, DEPTH)
        made += 1
    return made


# ---------------------------------------------------------------- 数据说明
DATA_README = """Matlab_OCT 示例数据
===================

volume/
  od-3dscan-macular-...-001.dat
      原始三维扫描，120 幅 x 432 A-line x 700 深度，uint8。
      1024 字节头，之后每幅是 432x700 行优先。
  od-3dscan-macular-...-001_analy.dat
      原 EOD_read_seg.exe 的 7 层分割结果。
      16 字节头 + 120 x 7 x 1024 uint32。
      通道顺序和深度方向都要转换，细节见 oct_layer_import 的说明。

  这两份是完整的，分层 / 厚度图 / ETDRS / 报告图全靠它们。

bscan/
{BSCAN_NOTE}

spectrum/
{SPECTRUM_NOTE}
  bin                    12 bit socket 块的碎片，8932 字节
                         用来验证解包，不够重建出图。

没放进包里的
------------
草莓测试集 test2_16bit.raw（872 MB），OCTproZ 的公开数据：
  https://figshare.com/articles/dataset/SSOCT_test_dataset_for_OCTproZ/12356705
放到 volume/ 下就能被 oct_recon_demo 用上。

换数据目录
----------
默认找工具箱目录下的 data\\。想放别处就设环境变量：
    setenv('OCT_DATA', 'D:\\我的数据目录')
目录结构保持 volume\\ bscan\\ spectrum\\ 就行。

重新打包
--------
包里带了 tools\\build_package.py，在仓库根执行：
    python tools/build_package.py --spectrum 你的光谱.csv
只用 Python 标准库，不需要 numpy / PIL / MATLAB。
"""

START_HERE = """Matlab_OCT —— OCT 数据处理与分析工具箱
======================================

怎么用
------
1. 把这个 Matlab_OCT 文件夹解压到任意位置（路径别有中文最稳妥）。
2. 打开 MATLAB，cd 到这个文件夹：

       cd('D:\\你解压的位置\\Matlab_OCT')

3. 跑一次初始化（加路径 + 检查数据）：

       oct_setup

4. 然后就能直接用了：

       oct_report        一张 OCT 黄斑分析报告图（最直观，先跑这个）
       oct_demo_all      依次跑一遍所有 demo
       oct_selftest      跑自测（163 项断言）

环境要求
--------
MATLAB R2016b 或更新（用到了隐式扩展）。
**不需要任何工具箱** —— 图像处理、信号、统计那些都没用到，
所有滤波、形态学、连通域、分位数、正态分位都是自己实现的。
在 R2026b 上验证过。

主要功能
--------
光谱侧
  oct_load_spectrum    读原始光谱（CSV / uint16 raw / 12bit 打包 / socket 块）
  oct_show_spectrum    逐条滚动显示光谱，可同时看重建的 A-line 和 B-scan
  oct_recon_pipeline   SD-OCT 重建六步（背景相减/k域线性化/色散/加窗/IDFT/log）
  oct_recon_demo       光谱 -> B-scan + en-face

分层
  oct_layer_seg        视网膜 7 层分割（图论最短路）
  oct_layer_demo       在带标注的 B-scan 上跑并报误差
  oct_layer_batch      批量处理一个目录
  oct_layer_import/export   读写原系统的 _analy.dat

en-face 与血管
  oct_enface           按分层投影成 en-face
  oct_frangi2d         Frangi 血管增强
  oct_devessel         检测并抹掉血管投影阴影

分析与报告
  oct_volume_read      读原始三维 .dat
  oct_thickness_map    层厚图（任意两层，微米）
  oct_fovea_find       中心凹定位
  oct_etdrs_grid       ETDRS 九分区（1/3/6 mm）
  oct_report           综合报告图（地形图+靶心图+显著性图+C-scan+B-scan+剖面）

每个函数都有详细的中文帮助，用 help 看：

    help oct_report
    help oct_layer_seg

更多细节看 README.md（算法、精度、和原系统的对照、踩过的坑）。
各算法的原始论文见 REFERENCES.md（19 条 DOI 都核对过）。

数据
----
示例数据在 data\\ 下，data\\README.txt 说明了各是什么、
哪些因为太大没放进来、以及怎么补。

重新打包
--------
tools\\build_package.py 能重新生成这个 zip，只用 Python 标准库：
    python tools/build_package.py

一个提醒
--------
显著性图（oct_significance_rgb）默认是"相对本次扫描自身的分位"，
因为没有正常人群数据库。那种图只能看这只眼内部哪里相对薄/厚，
**不能当诊断依据**。有正常库的话传 'Norm' 参数进去。
"""


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description='把 Matlab_OCT 打成解压即用的分发包')
    ap.add_argument('-o', '--out', default=ROOT, help='zip 输出目录')
    ap.add_argument('--stage', default=None, help='暂存目录（默认用临时目录）')
    ap.add_argument('--spectrum', default=None,
                    help='原始光谱 CSV。不给就不带光谱数据')
    ap.add_argument('--spectrum-rows', type=int, default=600,
                    help='光谱截取多少条 A-line（默认 600）')
    ap.add_argument('--bscan-dir', default=None,
                    help='现成的 B-scan PNG 目录。不给就从体数据生成')
    ap.add_argument('--bscan-step', type=int, default=10,
                    help='每隔几幅取一张 B-scan（默认 10，即 12 张）')
    ap.add_argument('--no-bscan', action='store_true', help='不放 B-scan')
    args = ap.parse_args()

    test_data = os.path.join(ROOT, 'test_data')
    if not os.path.isdir(test_data):
        log('找不到 %s —— 这个脚本要在仓库里跑' % test_data)
        return 1

    stage_root = args.stage or os.path.join(ROOT, '.build_pkg')
    stage = os.path.join(stage_root, 'Matlab_OCT')
    if os.path.isdir(stage_root):
        shutil.rmtree(stage_root)
    os.makedirs(stage)

    # ---- 1 脚本 ----
    n = 0
    for f in sorted(os.listdir(PKG)):
        p = os.path.join(PKG, f)
        if os.path.isfile(p) and (f.endswith('.m') or f.endswith('.md')):
            shutil.copy2(p, stage)
            n += 1
    log('脚本 %d 个' % n)

    for sub in ('test', 'tools'):
        src = os.path.join(PKG, sub)
        if not os.path.isdir(src):
            continue
        dst = os.path.join(stage, sub)
        os.makedirs(dst)
        c = 0
        for f in sorted(os.listdir(src)):
            p = os.path.join(src, f)
            if os.path.isfile(p):
                shutil.copy2(p, dst)
                c += 1
        log('%s/ %d 个' % (sub, c))

    # ---- 2 数据 ----
    D = os.path.join(stage, 'data')
    for sub in ('volume', 'bscan', 'spectrum'):
        os.makedirs(os.path.join(D, sub))

    volpath = analypath = None
    for f in sorted(os.listdir(test_data)):
        if not f.endswith('.dat'):
            continue
        src = os.path.join(test_data, f)
        shutil.copy2(src, os.path.join(D, 'volume', f))
        log('  volume/%s  %.1f MB' % (f, os.path.getsize(src) / 1048576))
        if f.endswith('_analy.dat'):
            analypath = src
        else:
            volpath = src

    binsrc = os.path.join(test_data, 'bin')
    if os.path.exists(binsrc):
        shutil.copy2(binsrc, os.path.join(D, 'spectrum', 'bin'))

    # ---- B-scan ----
    bscan_note = '  （这次没放）'
    if not args.no_bscan:
        bdir = os.path.join(D, 'bscan')
        if args.bscan_dir and os.path.isdir(args.bscan_dir):
            cnt = 0
            names = sorted(f for f in os.listdir(args.bscan_dir)
                           if f.lower().endswith('.png'))
            for i, f in enumerate(names):
                if i % args.bscan_step:
                    continue
                shutil.copy2(os.path.join(args.bscan_dir, f), bdir)
                cnt += 1
            log('  bscan/ %d 张（从 %s 取）' % (cnt, args.bscan_dir))
        elif volpath and analypath:
            log('  bscan/ 从体数据现场生成中...')
            cnt = make_bscan_pngs(volpath, analypath, bdir, args.bscan_step)
            log('  bscan/ %d 张（生成的，与原图逐像素一致）' % cnt)
        else:
            cnt = 0
            log('  bscan/ 跳过（没有体数据）')
        if cnt:
            bscan_note = (
                '  img_XXXX.png   %d 张样例（每 %d 幅取 1）\n'
                '      B-scan 灰度图上画好了 7 条分层线，当 ground truth 用。\n'
                '      完整的 120 张没放（42 MB），可以用 tools\\build_package.py\n'
                '      重新生成，或在 MATLAB 里从 volume/ 那两份自己画。'
                % (cnt, args.bscan_step))

    # ---- 光谱 ----
    spectrum_note = ('  （这次没带光谱 CSV。oct_show_spectrum / oct_recon_demo\n'
                     '   会自动跳过，别的功能不受影响。）')
    if args.spectrum and os.path.exists(args.spectrum):
        outcsv = os.path.join(D, 'spectrum',
                              'oct_spectrum_%d.csv' % args.spectrum_rows)
        with io.open(args.spectrum, encoding='utf-8') as fi, \
             io.open(outcsv, 'w', encoding='utf-8', newline='\n') as fo:
            for k, line in enumerate(fi):
                if k >= args.spectrum_rows:
                    break
                fo.write(line)
        sz = os.path.getsize(outcsv)
        log('  spectrum/%s  %.1f MB' % (os.path.basename(outcsv), sz / 1048576))
        spectrum_note = (
            '  oct_spectrum_%d.csv   原始光谱前 %d 条 A-line\n'
            '      每行一条 A-line，2048 个点，12 bit（0~4095）。'
            % (args.spectrum_rows, args.spectrum_rows))
    elif args.spectrum:
        log('  光谱文件不存在，跳过: %s' % args.spectrum)

    # ---- 3 说明文件 ----
    io.open(os.path.join(D, 'README.txt'), 'w',
            encoding='utf-8', newline='\n').write(
        DATA_README.replace('{BSCAN_NOTE}', bscan_note)
                   .replace('{SPECTRUM_NOTE}', spectrum_note))
    io.open(os.path.join(stage, 'START_HERE.txt'), 'w',
            encoding='utf-8', newline='\n').write(START_HERE)

    # ---- 4 打 zip ----
    if not os.path.isdir(args.out):
        os.makedirs(args.out)
    zp = os.path.join(args.out, 'Matlab_OCT.zip')
    base = os.path.dirname(stage)
    tot = 0
    with zipfile.ZipFile(zp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, _dirs, files in os.walk(stage):
            for f in sorted(files):
                full = os.path.join(root, f)
                z.write(full, os.path.relpath(full, base))
                tot += os.path.getsize(full)

    shutil.rmtree(stage_root)
    log('')
    log('包内原始大小 %.1f MB' % (tot / 1048576))
    log('ZIP %s  %.1f MB' % (zp, os.path.getsize(zp) / 1048576))
    return 0


if __name__ == '__main__':
    sys.exit(main())
