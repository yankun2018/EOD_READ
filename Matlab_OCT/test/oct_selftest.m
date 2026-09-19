function oct_selftest(matlabDir, goldenFile)
%OCT_SELFTEST  Matlab_OCT 自测：loader / prep / pipeline / 参数 / 显示函数。
%
%   oct_selftest                      % 路径按本文件位置自动推
%   oct_selftest(matlabDir, goldenFile)
%
%   golden.txt 里是「C++ 逐行直译」实现算出的金标准（由同目录 golden.py 生成），
%   pipeline 的输出要和它对到 1e-11 以内。改了 oct_recon_pipeline.m 之后跑这个，
%   就能确认没把算法改跑偏。
%
%   命令行跑法：
%     matlab -batch "cd Matlab_OCT/test; oct_selftest"
%
%   需要 test_data/bin（仓库里有）。octifft 的 CSV 不在时相关用例会自动 SKIP。

here = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(matlabDir),  matlabDir  = fullfile(here, '..'); end
if nargin < 2 || isempty(goldenFile), goldenFile = fullfile(here, 'golden.txt'); end
addpath(matlabDir);
nfail = 0;
fprintf('=== Matlab_OCT self test ===\n\n');

% ---------------------------------------------------------------- 1 loader
fprintf('[1] oct_load_spectrum\n');
binPath = oct_find_data('rawbin', 'Quiet', true);
try
    [d, info] = oct_load_spectrum(binPath, 'AlineLength', 2048);
    want = [8 11 2 0 13 0 5 9 4 1 0 4 0 5 3 1 8 8 0 4 8 0 0 0];
    got  = d(1, 1:24);
    nfail = nfail + chk('eodbin format', strcmp(info.format, 'eodbin'));
    nfail = nfail + chk('eodbin shape [2 2048]', isequal(size(d), [2 2048]));
    nfail = nfail + chk('eodbin first 24 samples', isequal(got, want));
    nfail = nfail + chk('eodbin 12bit range', min(d(:)) >= 0 && max(d(:)) <= 4095);
    fprintf('      -> %d x %d, %d..%d\n', size(d,1), size(d,2), min(d(:)), max(d(:)));
catch e
    nfail = nfail + 1; fprintf('  FAIL eodbin: %s\n', e.message);
end

csvPath = oct_find_data('spectrum', 'Quiet', true);
if ~isempty(csvPath) && exist(csvPath, 'file')
    try
        t0 = tic;
        [d2, info2] = oct_load_spectrum(csvPath, 'MaxLines', 120);
        nfail = nfail + chk('csv format',  strcmp(info2.format, 'csv'));
        nfail = nfail + chk('csv shape [120 2048]', isequal(size(d2), [120 2048]));
        nfail = nfail + chk('csv row1 head', isequal(d2(1,1:10), [0 0 9 0 3 10 8 2 13 5]));
        nfail = nfail + chk('csv 12bit range', min(d2(:)) >= 0 && max(d2(:)) <= 4095);
        % SkipLines 要和不跳时的对应行一致
        d3 = oct_load_spectrum(csvPath, 'MaxLines', 5, 'SkipLines', 100);
        nfail = nfail + chk('csv SkipLines', isequal(d3, d2(101:105, :)));
        % Range [首行 末行] 闭区间，应等价于 SkipLines=首-1, MaxLines=末-首+1
        d3b = oct_load_spectrum(csvPath, 'Range', [101 105]);
        nfail = nfail + chk('csv Range 等价 SkipLines/MaxLines', isequal(d3b, d3));
        nfail = nfail + chk('csv Range 行数 = 末-首+1', size(d3b, 1) == 5);
        d3c = oct_load_spectrum(csvPath, 'Range', [7 7]);
        nfail = nfail + chk('csv Range 单行 [7 7]', isequal(d3c, d2(7, :)));
        % 末行给 Inf 应该读到文件尾。行数不写死 —— 打包时 CSV 被截过
        % （完整 5951 条，包里只放 600 条），按实际总数算
        dAllRows = size(oct_load_spectrum(csvPath), 1);
        tailN = min(12, dAllRows);
        d3d = oct_load_spectrum(csvPath, 'Range', [dAllRows-tailN+1 Inf]);
        nfail = nfail + chk(sprintf('csv Range 末行 Inf 读到尾（%d 行）', tailN), ...
                            size(d3d, 1) == tailN);
        % Range 覆盖同时给的 SkipLines/MaxLines
        d3e = oct_load_spectrum(csvPath, 'SkipLines', 3000, 'MaxLines', 99, ...
                                'Range', [101 105]);
        nfail = nfail + chk('Range 覆盖 SkipLines/MaxLines', isequal(d3e, d3));
        % 非法 Range 要报错
        for bad = {[5 3], [0 10], [1 2 3]}
            try
                oct_load_spectrum(csvPath, 'Range', bad{1});
                nfail = nfail + chk(sprintf('非法 Range %s 应报错', mat2str(bad{1})), false);
            catch
                nfail = nfail + chk(sprintf('非法 Range %s 应报错', mat2str(bad{1})), true);
            end
        end
        fprintf('      -> 120 行耗时 %.2f s\n', toc(t0));
    catch e
        nfail = nfail + 1; fprintf('  FAIL csv: %s\n', e.message);
    end
else
    fprintf('  SKIP csv (%s 不存在)\n', csvPath);
end

% raw16：自己造一个临时文件，顺带验 MaxLines 是否真的限制了读盘
try
    tmp = [tempname '.raw'];
    ref = uint16(mod((0:(1664*50-1)) * 37, 65536));
    fid = fopen(tmp, 'w'); fwrite(fid, ref, 'uint16'); fclose(fid);
    d4 = oct_load_spectrum(tmp, 'AlineLength', 1664, 'MaxLines', 3);
    nfail = nfail + chk('raw16 shape [3 1664]', isequal(size(d4), [3 1664]));
    nfail = nfail + chk('raw16 values', isequal(d4(2,:), double(ref(1665:3328))));
    % fseek 版 SkipLines：跳过的行要和全读时的对应行一致
    d5 = oct_load_spectrum(tmp, 'AlineLength', 1664, 'MaxLines', 4, 'SkipLines', 30);
    dAll = oct_load_spectrum(tmp, 'AlineLength', 1664);
    nfail = nfail + chk('raw16 SkipLines 形状', isequal(size(d5), [4 1664]));
    nfail = nfail + chk('raw16 SkipLines 内容', isequal(d5, dAll(31:34, :)));
    nfail = nfail + chk('raw16 全读 50 行', isequal(size(dAll), [50 1664]));
    % SkipLines 跳到文件尾之外要返回空而不是报错
    d6 = oct_load_spectrum(tmp, 'AlineLength', 1664, 'MaxLines', 2, 'SkipLines', 999);
    nfail = nfail + chk('raw16 跳过头返回空', isempty(d6));
    % raw12 也验一遍 SkipLines
    tmp12 = [tempname '.r12'];
    bytes = uint8(mod(0:(3*1200-1), 256));
    fid = fopen(tmp12, 'w'); fwrite(fid, bytes, 'uint8'); fclose(fid);
    a12 = oct_load_spectrum(tmp12, 'Format', 'raw12', 'AlineLength', 100);
    b12 = oct_load_spectrum(tmp12, 'Format', 'raw12', 'AlineLength', 100, ...
                            'MaxLines', 3, 'SkipLines', 5);
    nfail = nfail + chk('raw12 SkipLines 内容', isequal(b12, a12(6:8, :)));
    % 奇数个采样的偏移（AlineLength 为奇数时会落在 3 字节组中间）
    c12 = oct_load_spectrum(tmp12, 'Format', 'raw12', 'AlineLength', 101);
    d12 = oct_load_spectrum(tmp12, 'Format', 'raw12', 'AlineLength', 101, ...
                            'MaxLines', 3, 'SkipLines', 5);
    nfail = nfail + chk('raw12 半组偏移', isequal(d12, c12(6:8, :)));
    delete(tmp); delete(tmp12);
catch e
    nfail = nfail + 1; fprintf('  FAIL raw16: %s\n', e.message);
end

% ------------------------------------------------------------------ 2 prep
fprintf('\n[2] oct_recon_prep\n');
p = oct_recon_params('eod2048');
k = oct_recon_prep(p);
nfail = nfail + chk('idx 不越界', min(k.idx) >= 1 && max(k.idx + 1) <= p.alineLength);
nfail = nfail + chk('frac in [0,1]', all(k.frac >= 0 & k.frac <= 1));
nfail = nfail + chk('末点 frac=1 (取到端点)', abs(k.frac(end) - 1) < 1e-9);
nz = find(k.win > 0);
% C++ 是 0-based 的 [53,1994]，MATLAB 1-based 就是 [54,1995]
nfail = nfail + chk('汉宁窗非零区间 (0-based [53,1994])', nz(1) == 54 && nz(end) == 1995);
nfail = nfail + chk('窗峰值 1', abs(max(k.win) - 1) < 1e-6);

p1 = oct_recon_params('strawberry1664');
k1 = oct_recon_prep(p1);
nfail = nfail + chk('1664 idx 不越界', min(k1.idx) >= 1 && max(k1.idx + 1) <= 1664);
nfail = nfail + chk('1664 恒等色散 cos(0)=1', abs(k1.cosT(1) - 1) < 1e-12);

% -------------------------------------------------------------- 3 pipeline
fprintf('\n[3] oct_recon_pipeline vs C++ 逐行直译金标准\n');
g = readGolden(goldenFile);
for n = 1:numel(g)
    c = g(n);
    switch c.name
        case 'strawberry1664_offplace'
            pp = oct_recon_params('strawberry1664', 'klinInplace', false);
        case 'strawberry1664_inplace'
            pp = oct_recon_params('strawberry1664', 'klinInplace', true);
        case 'eod2048_offplace'
            pp = oct_recon_params('eod2048', 'klinInplace', false);
        otherwise
            fprintf('  SKIP 未知用例 %s\n', c.name); continue;
    end
    spec = synth(40, c.ln);
    out  = oct_recon_pipeline(spec, pp);
    eSum = abs(sum(out(:)) - c.sum) / abs(c.sum);
    eMin = abs(min(out(:)) - c.mn);
    eMax = abs(max(out(:)) - c.mx);
    eHead = max(abs(out(end, 1:8) - c.head));
    ok = eSum < 1e-11 && eMin < 1e-9 && eMax < 1e-9 && eHead < 1e-9;
    nfail = nfail + chk(sprintf('%-24s (sum rel %.1e, head %.1e)', c.name, eSum, eHead), ok);
    if ~ok
        fprintf('        sum  %.10f vs %.10f\n', sum(out(:)), c.sum);
        fprintf('        min  %.10f vs %.10f\n', min(out(:)), c.mn);
        fprintf('        max  %.10f vs %.10f\n', max(out(:)), c.mx);
    end
end

% 形状 / halfOnly
pp = oct_recon_params('strawberry1664');
nfail = nfail + chk('halfOnly=true  -> 832 列', size(oct_recon_pipeline(synth(25,1664), pp), 2) == 832);
pp.halfOnly = false;
nfail = nfail + chk('halfOnly=false -> 1664 列', size(oct_recon_pipeline(synth(25,1664), pp), 2) == 1664);
% bgLines=0 时应完全跳过背景相减
pp = oct_recon_params('strawberry1664', 'bgLines', 0);
a = oct_recon_pipeline(synth(25,1664), pp);
b = oct_recon_pipeline(synth(25,1664), oct_recon_params('strawberry1664'));
nfail = nfail + chk('bgLines=0 与默认不同', max(abs(a(:)-b(:))) > 1e-6);
nfail = nfail + chk('bgLines=0 前20行与默认一致', max(max(abs(a(1:20,:)-b(1:20,:)))) < 1e-9);
% 列数不匹配要报错
try
    oct_recon_pipeline(zeros(4, 100), oct_recon_params('strawberry1664'));
    nfail = nfail + chk('列数不匹配应报错', false);
catch
    nfail = nfail + chk('列数不匹配应报错', true);
end

% --------------------------------------------------------- 4 参数 / 选项
fprintf('\n[4] oct_recon_params / oct_parseopt\n');
nfail = nfail + chk('cpu 色散 [0 10.5 1.5 0]', isequal(oct_recon_params('strawberry1664').c, [0 10.5 1.5 0]));
nfail = nfail + chk('cuda 色散 [0 20.24 0 0]', isequal(oct_recon_params('cuda1664').c, [0 20.24 0 0]));
nfail = nfail + chk('覆盖字段', oct_recon_params('eod2048', 'bgLines', 7).bgLines == 7);
try
    oct_recon_params('eod2048', 'noSuchField', 1);
    nfail = nfail + chk('未知选项应报错', false);
catch
    nfail = nfail + chk('未知选项应报错', true);
end
try
    oct_recon_params('noSuchPreset');
    nfail = nfail + chk('未知预设应报错', false);
catch
    nfail = nfail + chk('未知预设应报错', true);
end

% ------------------------------------------------------------ 5 显示函数
fprintf('\n[5] 显示函数（无头跑，画完就关）\n');
try
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 2, ...
                      'Pause', 0, 'BgWindow', 2, 'ShowKlin', true);
    close all;
    nfail = nfail + chk('oct_show_spectrum gif 风格', true);
catch e
    nfail = nfail + 1; fprintf('  FAIL oct_show_spectrum: %s\n', e.message);
end
try
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 2, ...
                      'Pause', 0, 'Style', 'plot');
    close all;
    nfail = nfail + chk('oct_show_spectrum plot 风格', true);
catch e
    nfail = nfail + 1; fprintf('  FAIL oct_show_spectrum plot: %s\n', e.message);
end
% 新增的 A-line / B-scan 面板：4 个面板时曾因 subplot 互相删除而崩过
try
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 3, ...
                      'Pause', 0, 'ShowKlin', true, 'ShowAline', true);
    nfail = nfail + chk('oct_show_spectrum 4 面板 (gif)', numel(findall(gcf,'Type','axes')) == 4);
    close all;
catch e
    nfail = nfail + 1; fprintf('  FAIL 4 面板 gif: %s\n', e.message);
end
try
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 3, ...
                      'Pause', 0, 'ShowKlin', true, 'ShowAline', true, 'Style', 'plot');
    nfail = nfail + chk('oct_show_spectrum 4 面板 (plot)', numel(findall(gcf,'Type','axes')) == 4);
    close all;
catch e
    nfail = nfail + 1; fprintf('  FAIL 4 面板 plot: %s\n', e.message);
end
try
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 3, ...
                      'Pause', 0, 'ShowBscan', true, 'BscanCols', 8);
    figs = findall(0, 'Type', 'figure');
    nms = get(figs, 'Name'); if ~iscell(nms), nms = {nms}; end
    nfail = nfail + chk('ShowBscan 开了独立窗口', any(contains(nms, 'BSCAN')));
    % B-scan 窗口里的图像应该是 depth x BscanCols，且写进去的列非零
    im = findall(0, 'Type', 'image');
    cd_ = get(im(1), 'CData');
    % test_data/bin 只有 2 条完整 A-line。BscanCols 给 8，但画布会收窄到
    % min(BscanCols, 条数)，免得右边留一大片空白 —— 所以是 2 列而不是 8 列
    nL = size(oct_load_spectrum(binPath, 'AlineLength', 2048), 1);
    nfail = nfail + chk(sprintf('B-scan 尺寸收窄到 [1024 %d]', nL), ...
                        isequal(size(cd_), [1024 nL]));
    nfail = nfail + chk('B-scan 每列都填了', all(any(diff(cd_,1,1) ~= 0, 1)));
    % 默认 BscanNorm='range'，存的是原始 log 值（靠 CLim 定灰度），不是 [0,1]
    nfail = nfail + chk('B-scan 默认存 log 值', min(cd_(:)) > 5);
    cl = get(get(im(1), 'Parent'), 'CLim');
    nfail = nfail + chk('B-scan 默认 CLim = 全区间 min/max', ...
                        abs(cl(1)-min(cd_(:))) < 1e-6 && abs(cl(2)-max(cd_(:))) < 1e-6);
    close all;
catch e
    nfail = nfail + 1; fprintf('  FAIL ShowBscan: %s\n', e.message);
end
% BscanNorm 三种模式
if ~isempty(csvPath) && exist(csvPath, 'file')
    try
        % 'range': 存的是原始 log 值，CLim = 全区间 min/max
        oct_show_spectrum('File', csvPath, 'Range', [201 260], 'ShowBscan', true, ...
                          'Pause', 0, 'BscanNorm', 'range');
        im = findall(0, 'Type', 'image'); cd_ = get(im(1), 'CData');
        cl = get(get(im(1), 'Parent'), 'CLim');
        nfail = nfail + chk('range: 60 条 -> 60 列（不留空白）', size(cd_, 2) == 60);
        nfail = nfail + chk('range: CLim == 数据 min/max', ...
                            abs(cl(1)-min(cd_(:))) < 1e-6 && abs(cl(2)-max(cd_(:))) < 1e-6);
        nfail = nfail + chk('range: 存的是 log 值不是 [0,1]', min(cd_(:)) > 5);
        % 和直接批量重建的结果应逐元素一致
        p0 = oct_recon_params('eod2048');
        nb = p0.bgLines;
        rawAll = oct_load_spectrum(csvPath, 'Range', [201-nb 260]);
        rr = oct_recon_pipeline(rawAll, p0);
        ref = rr(nb+1:end, :).';
        nfail = nfail + chk(sprintf('range: 与批量重建一致 (max %.1e)', ...
                            max(abs(cd_(:)-ref(:)))), max(abs(cd_(:)-ref(:))) < 1e-4);
        close all;
    catch e
        nfail = nfail + 1; fprintf('  FAIL BscanNorm range: %s\n', e.message);
    end
    try
        % 'aline': 每列各自拉满到 [0,1]，所以每列的 min/max 就是 0/1
        oct_show_spectrum('File', csvPath, 'Range', [201 260], 'ShowBscan', true, ...
                          'Pause', 0, 'BscanNorm', 'aline');
        im = findall(0, 'Type', 'image'); cd_ = get(im(1), 'CData');
        nfail = nfail + chk('aline: 每列都归一化到 [0,1]', ...
                            all(abs(min(cd_,[],1)) < 1e-9) && all(abs(max(cd_,[],1)-1) < 1e-9));
        close all;
    catch e
        nfail = nfail + 1; fprintf('  FAIL BscanNorm aline: %s\n', e.message);
    end
    try
        oct_show_spectrum('File', csvPath, 'Range', [201 260], 'ShowBscan', true, ...
                          'Pause', 0, 'BscanNorm', 'running');
        close all;
        nfail = nfail + chk('running 模式能跑', true);
    catch e
        nfail = nfail + 1; fprintf('  FAIL BscanNorm running: %s\n', e.message);
    end
    try
        oct_show_spectrum('File', csvPath, 'Range', [201 210], 'ShowBscan', true, ...
                          'Pause', 0, 'BscanNorm', 'nosuch');
        close all;
        nfail = nfail + chk('非法 BscanNorm 应报错', false);
    catch
        nfail = nfail + chk('非法 BscanNorm 应报错', true);
    end
    try
        % 区间头部要有背景上下文：第 201 行起的结果不该受"从哪开始读"影响
        a = oct_show_spectrum_probe(csvPath, [201 260]);
        b = oct_show_spectrum_probe(csvPath, [201 400]);
        nfail = nfail + chk(sprintf('区间头部有背景上下文 (max %.1e)', ...
                            max(abs(a(:)-b(:)))), max(abs(a(:)-b(:))) < 1e-4);
    catch e
        nfail = nfail + 1; fprintf('  FAIL 背景上下文: %s\n', e.message);
    end
end

try
    % YLim 显式给的时候不该去探测
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 2, ...
                      'Pause', 0, 'ShowAline', true, 'YLim', [0 4100]);
    close all;
    nfail = nfail + chk('显式 YLim + ShowAline', true);
catch e
    nfail = nfail + 1; fprintf('  FAIL 显式 YLim: %s\n', e.message);
end
try
    gifOut = [tempname '.gif'];
    oct_show_spectrum('File', binPath, 'AlineLength', 2048, 'MaxLines', 2, ...
                      'Pause', 0, 'BgWindow', 0, 'SaveGif', gifOut);
    close all;
    nfail = nfail + chk('SaveGif 产出文件', exist(gifOut, 'file') == 2);
    if exist(gifOut, 'file'), delete(gifOut); end
catch e
    nfail = nfail + 1; fprintf('  FAIL SaveGif: %s\n', e.message);
end

fprintf('\n[6] oct_recon_demo\n');
% Range: 只重建指定的 A-line 区间，且真的从那里开始
if ~isempty(csvPath) && exist(csvPath, 'file')
    try
        ref = oct_recon_demo('File', csvPath, 'Preset', 'eod2048', 'BscanWidth', 40, ...
            'MaxBscans', 2, 'SkipLines', 200, 'Pause', 0, 'ShowEnface', false);
        close all;
        got = oct_recon_demo('File', csvPath, 'Preset', 'eod2048', 'BscanWidth', 40, ...
            'Range', [201 280], 'Pause', 0, 'ShowEnface', false);
        close all;
        nfail = nfail + chk('demo Range 等价 SkipLines+MaxBscans', isequal(got, ref));
        nfail = nfail + chk('demo Range 幅数 = floor(80/40) = 2', size(got, 3) == 2);
        % 区间凑不满一整幅时给出明确报错
        try
            oct_recon_demo('File', csvPath, 'Preset', 'eod2048', 'BscanWidth', 40, ...
                'Range', [201 230], 'Pause', 0, 'ShowEnface', false);
            close all;
            nfail = nfail + chk('demo Range 不足一幅应报错', false);
        catch
            nfail = nfail + chk('demo Range 不足一幅应报错', true);
        end
    catch e
        nfail = nfail + 1; fprintf('  FAIL demo Range: %s\n', e.message);
    end
end
if ~isempty(csvPath) && exist(csvPath, 'file')
    for mode = {'batch', 'aline'}
        try
            [bs, cs] = oct_recon_demo('File', csvPath, 'Preset', 'eod2048', ...
                'BscanWidth', 40, 'MaxBscans', 2, 'Mode', mode{1}, ...
                'Pause', 0, 'EnfaceMargin', 50);
            close all;
            okShape = isequal(size(bs), [1024 40 2]) && isequal(size(cs), [2 40]);
            nfail = nfail + chk(sprintf('demo Mode=%s 形状', mode{1}), okShape);
            nfail = nfail + chk(sprintf('demo Mode=%s 输出有限', mode{1}), all(isfinite(bs(:))));
            if strcmp(mode{1}, 'batch')
                bsBatch = bs;
            else
                % aline 模式逐条算，结果应该和 batch 几乎一致
                dmax = max(abs(bs(:) - bsBatch(:)));
                nfail = nfail + chk(sprintf('aline 与 batch 一致 (max %.1e)', dmax), dmax < 1e-9);
            end
        catch e
            nfail = nfail + 1; fprintf('  FAIL demo %s: %s\n', mode{1}, e.message);
        end
    end
else
    fprintf('  SKIP (没有 CSV 数据)\n');
end


% ---------------------------------------------------- 7 分层
fprintf('\n[7] 视网膜分层 oct_layer_*\n');
picDir = oct_find_data('bscan', 'Quiet', true);
if ~isempty(picDir) && exist(picDir, 'dir')
    try
        % 用目录里实际存在的图，别写死文件名 —— 包里只放了 12 张样例
        pngs = dir(fullfile(picDir, '*.png'));
        pngs = sort({pngs.name});
        pick1 = pngs{min(6, numel(pngs))};
        f = fullfile(picDir, pick1);
        [im, g, gi] = oct_layer_gt(f);
        nfail = nfail + chk('gt 图尺寸 700x432', isequal(gi.size, [700 432]));
        nfail = nfail + chk('gt 7 层每层 432 点', all(gi.nFound == 432));
        nfail = nfail + chk('gt 灰度无 NaN', ~any(isnan(im(:))));
        nfail = nfail + chk('gt 层序 ILM<...<RPE', ...
            mean(g.ilm)<mean(g.rnfl) && mean(g.rnfl)<mean(g.ipl) && ...
            mean(g.ipl)<mean(g.inl) && mean(g.inl)<mean(g.opl) && ...
            mean(g.opl)<mean(g.isos) && mean(g.isos)<mean(g.rpe));

        bd = oct_layer_seg(im);
        fn = {'ilm','rnfl','ipl','inl','opl','isos','rpe'};
        okAll = true;
        for k = 1:7
            v = bd.(fn{k});
            okAll = okAll && numel(v)==432 && all(isfinite(v)) && all(v>=1 & v<=700);
        end
        nfail = nfail + chk('seg 输出 7 x 432 且都在图内', okAll);

        % 误差取几张的平均：单张会波动（img_0060 是中心凹那张，偏难），
        % 全集 120 张的验证集成绩是 2.02 px，这里给 3.0 的余量
        % 同理：从目录里挑三张，而不是写死文件名
        idx3 = unique(min(numel(pngs), max(1, round([0.2 0.5 0.8]*numel(pngs)))));
        picks = pngs(idx3);
        e = [];
        for pi = 1:numel(picks)
            pf = fullfile(picDir, picks{pi});
            if ~exist(pf, 'file'), continue; end
            [im2, g2] = oct_layer_gt(pf);
            b2 = oct_layer_seg(im2);
            for k = 1:7
                gg = g2.(fn{k}); mm = ~isnan(gg);
                e(end+1) = mean(abs(b2.(fn{k})(mm) - gg(mm))); %#ok<AGROW>
            end
        end
        nfail = nfail + chk(sprintf('seg %d 张平均误差 %.2f px < 3.0', ...
                            numel(picks), mean(e)), mean(e) < 3.0);
        nfail = nfail + chk('seg 结果层序单调', ...
            all(bd.ilm<=bd.rnfl+1) && all(bd.rnfl<=bd.ipl+1) && all(bd.ipl<=bd.inl+1) && ...
            all(bd.inl<=bd.opl+1) && all(bd.opl<=bd.isos+1) && all(bd.isos<=bd.rpe+1));
        % 关掉偏移应当把结果整体抬上去
        bd0 = oct_layer_seg(im, 'Offsets', zeros(1,7));
        nfail = nfail + chk('Offsets=0 时结果更浅', mean(bd0.ilm) < mean(bd.ilm));
    catch e2
        nfail = nfail + 1; fprintf('  FAIL 分层: %s\n', e2.message);
    end
else
    fprintf('  SKIP pic_md 不存在\n');
end

% oct_layer_batch：写到临时目录，检查产物齐不齐
if ~isempty(picDir) && exist(picDir, 'dir')
    try
        od = fullfile(tempdir, ['octbatch_' num2str(feature('getpid'))]);
        st = oct_layer_batch(picDir, od, 'Files', 1:3);
        nfail = nfail + chk('batch 3 张都认出带 GT', st.nGT == 3);
        nfail = nfail + chk('batch gray_clean 3 张', ...
            numel(dir(fullfile(od,'gray_clean','*.png'))) == 3);
        nfail = nfail + chk('batch seg_overlay 3 张', ...
            numel(dir(fullfile(od,'seg_overlay','*.png'))) == 3);
        nfail = nfail + chk('batch seg_compare 3 张', ...
            numel(dir(fullfile(od,'seg_compare','*.png'))) == 3);
        dd = dir(fullfile(od,'layers.dat'));
        nfail = nfail + chk('batch layers.dat = 16+3x7x1024x4', ...
            ~isempty(dd) && dd.bytes == 16 + 3*7*1024*4);
        nfail = nfail + chk('batch report.txt 有了', ...
            exist(fullfile(od,'report.txt'), 'file') == 2);
        % gray_clean 里不该再有那 7 种纯色
        gi2 = imread(fullfile(od,'gray_clean','img_0001.png'));
        nfail = nfail + chk('gray_clean 是单通道灰度', size(gi2,3) == 1);
        % 写出的 dat 能读回来，且和 batch 的结果一致
        bl3 = oct_layer_import(fullfile(od,'layers.dat'), 'NBscan', 3);
        nfail = nfail + chk('batch 的 dat 能读回 3 幅', numel(bl3) == 3);
        nfail = nfail + chk('batch dat 层序单调', ...
            all(bl3(1).ilm <= bl3(1).rnfl + 1));
        rmdir(od, 's');
    catch e4
        nfail = nfail + 1; fprintf('  FAIL batch: %s\n', e4.message);
    end
end

% analy.dat 的读写
analy = oct_find_data('analy', 'Quiet', true);
if ~isempty(analy) && exist(analy, 'file')
    try
        [bl, bi] = oct_layer_import(analy);
        nfail = nfail + chk('analy 120 幅 x 1024 点', bi.nBscan==120 && bi.nPoint==1024);
        nfail = nfail + chk('analy 文件大小 3440656 且无余数', ...
                            bi.bytes==3440656 && bi.extra==0);
        % CHMAP 对的话，有效列必然层序单调
        fn = {'ilm','rnfl','ipl','inl','opl','isos','rpe'};
        tot = 0; cols = 0;
        for i = 1:120
            M = zeros(7, 1024);
            for k = 1:7, M(k,:) = bl(i).(fn{k}); end
            o = all(M>0, 1); Mo = M(:, o);
            tot = tot + sum(all(diff(Mo,1,1)>=0, 1)); cols = cols + sum(o);
        end
        % 只要求"所有 7 层都有效的列"全部层序单调。列数不写死 —— 翻转后
        % 无效点是 NaN，各层缺失的位置不完全重合，交集会略少于 120x432。
        nfail = nfail + chk(sprintf('analy 通道映射正确（%d/%d 列层序单调）', tot, cols), ...
                            tot == cols && cols > 0.99*120*432);
        % 单调只说明顺序自洽，不说明哪端是 ILM。语义用生理值验：
        % 全视网膜厚度应落在正常黄斑的 200~350 um
        [Tf, tif] = oct_thickness_map(bl, 'Top','ilm', 'Bot','rpe');
        nfail = nfail + chk(sprintf('analy 全层厚度 %.0f um 在 200~350', tif.median), ...
                            tif.median > 200 && tif.median < 350);
        % RNFL 紧贴 ILM，厚度变化幅度应远大于 RPE-ISOS（后者基本恒定）
        [~, tiR] = oct_thickness_map(bl, 'Top','ilm',  'Bot','rnfl');
        [~, tiP] = oct_thickness_map(bl, 'Top','isos', 'Bot','rpe');
        spanR = tiR.p95 - tiR.p5;  spanP = tiP.p95 - tiP.p5;
        nfail = nfail + chk(sprintf('analy 层语义（RNFL 变幅 %.0f > RPE-ISOS %.0f）', ...
                            spanR, spanP), spanR > 2*spanP);
        % 和 pic_md 的彩线交叉验证：那批 PNG 就是这份 analy.dat 的可视化
        if ~isempty(picDir) && exist(picDir, 'dir')
            % 交叉验证：从 PNG 文件名解析出它是第几幅，再和 analy 的对应幅比
            pngs2 = dir(fullfile(picDir, '*.png'));
            pngs2 = sort({pngs2.name});
            pf = ''; idxB = 0;
            for t2 = 1:numel(pngs2)
                num = sscanf(pngs2{t2}, 'img_%d');
                if ~isempty(num) && num >= 1 && num <= numel(bl)
                    pf = fullfile(picDir, pngs2{t2}); idxB = num; break;
                end
            end
            if ~isempty(pf) && exist(pf, 'file')
                [~, gg60] = oct_layer_gt(pf);
                fn2 = {'ilm','rnfl','ipl','inl','opl','isos','rpe'};
                dm = [];
                for k = 1:7
                    aa = bl(idxB).(fn2{k})(1:432);
                    bb = gg60.(fn2{k});
                    mm2 = isfinite(aa) & isfinite(bb);
                    dm = [dm, abs(aa(mm2) - bb(mm2))]; %#ok<AGROW>
                end
                nfail = nfail + chk(sprintf('analy 与 pic_md 彩线一致（%.1f%% 点差<1px）', ...
                                    100*mean(dm < 1)), mean(dm < 1) > 0.99);
            end
        end
        % 往返
        tmpd = [tempname '.dat'];
        nb = oct_layer_export(tmpd, bl);
        bl2 = oct_layer_import(tmpd);
        mx = 0;
        for i = 1:120
            for k = 1:7, mx = max(mx, max(abs(bl(i).(fn{k})-bl2(i).(fn{k})))); end
        end
        nfail = nfail + chk('analy 往返字节数一致', nb == bi.bytes);
        nfail = nfail + chk('analy 往返逐元素一致', mx == 0);
        delete(tmpd);
    catch e3
        nfail = nfail + 1; fprintf('  FAIL analy: %s\n', e3.message);
    end
else
    fprintf('  SKIP analy.dat 不存在\n');
end


% -------------------------------------------- 8 en-face / 血管
fprintf('\n[8] en-face + Frangi + 去血管\n');
if ~isempty(picDir) && exist(picDir, 'dir')
    try
        % 用 6 幅拼个小体数据，够验接口和数值性质
        fs = dir(fullfile(picDir, '*.png')); fs = sort({fs.name});
        pick = fs(1:6);
        [i1, ~] = oct_layer_gt(fullfile(picDir, pick{1}));
        [Hh, Ww] = size(i1);
        vv = zeros(Hh, Ww, numel(pick)); bb = cell(1, numel(pick));
        for t = 1:numel(pick)
            im3 = oct_layer_gt(fullfile(picDir, pick{t}));
            vv(:,:,t) = im3; bb{t} = oct_layer_seg(im3);
        end

        % --- oct_enface ---
        [e1, ei] = oct_enface(vv, bb, 'Slab', 'deep');
        nfail = nfail + chk('enface 形状 [nBscan x W]', isequal(size(e1), [numel(pick) Ww]));
        nfail = nfail + chk('enface deep = isos->rpe', ...
                            strcmp(ei.top,'isos') && strcmp(ei.bot,'rpe'));
        nfail = nfail + chk('enface 值有限且非负', all(isfinite(e1(:))) && all(e1(:) >= 0));
        e2 = oct_enface(vv, bb, 'Slab', 'full');
        nfail = nfail + chk('enface full 与 deep 不同', max(abs(e1(:)-e2(:))) > 1);
        % max 投影必然 >= mean 投影
        e3 = oct_enface(vv, bb, 'Slab', 'deep', 'Stat', 'max');
        nfail = nfail + chk('enface max >= mean', all(e3(:) >= e1(:) - 1e-9));
        try
            oct_enface(vv, bb, 'Slab', 'nosuch');
            nfail = nfail + chk('enface 未知 Slab 应报错', false);
        catch
            nfail = nfail + chk('enface 未知 Slab 应报错', true);
        end

        % --- oct_frangi2d：合成一张有暗管的图来验 ---
        [xx, yy] = meshgrid(1:120, 1:60);
        tube = 200 - 120*exp(-((yy-30).^2)/(2*2.5^2));   % 一条水平暗管
        Vs = oct_frangi2d(tube, 'ScaleRange', [1 4]);
        nfail = nfail + chk('frangi 输出同尺寸', isequal(size(Vs), size(tube)));
        nfail = nfail + chk('frangi 归一化到 [0,1]', min(Vs(:)) >= 0 && max(Vs(:)) <= 1+1e-9);
        % 管中心的响应应该显著高于远处背景
        onLine = mean(mean(Vs(29:31, 20:100)));
        offLine = mean(mean(Vs([5:10, 51:56], 20:100)));
        nfail = nfail + chk(sprintf('frangi 检出暗管（管上 %.3f >> 背景 %.3f）', onLine, offLine), ...
                            onLine > 10*offLine + 0.05);
        % 极性：同一张暗管图，找亮管时"管中心"应该没响应。
        % 注意要比管中心而不是全图均值 —— 暗管两侧相对更亮，会被当成亮脊，
        % 所以找亮管的全图均值反而更大（实测 0.170 > 0.096），比均值会误判。
        Vb = oct_frangi2d(tube, 'ScaleRange', [1 4], 'BlackWhite', false, 'Normalize', false);
        Vd = oct_frangi2d(tube, 'ScaleRange', [1 4], 'BlackWhite', true,  'Normalize', false);
        cD = mean(mean(Vd(29:31, 20:100)));
        cB = mean(mean(Vb(29:31, 20:100)));
        nfail = nfail + chk(sprintf('frangi 极性开关有效（管心 暗 %.3f / 亮 %.3f）', cD, cB), ...
                            cD > 0.5 && cB < 0.01);
        % 亮管的图反过来
        Vs2 = oct_frangi2d(255-tube, 'ScaleRange', [1 4], 'BlackWhite', false);
        nfail = nfail + chk('frangi 亮管也能检出', ...
                            mean(mean(Vs2(29:31, 20:100))) > 0.2);

        % --- oct_devessel ---
        [o1, m1, V1] = oct_devessel(e1, 'Frangi', {'ScaleRange',[1 6]});
        nfail = nfail + chk('devessel 输出同尺寸', isequal(size(o1), size(e1)));
        nfail = nfail + chk('devessel 掩膜覆盖 2%~25%', ...
                            mean(m1(:)) > 0.02 && mean(m1(:)) < 0.25);
        nfail = nfail + chk('devessel 掩膜外一点没动', ...
                            max(abs(o1(~m1) - e1(~m1))) < 1e-9);
        nfail = nfail + chk('devessel 输出无 NaN', ~any(isnan(o1(:))));
        % 填补能力在合成图上测 —— 自测只拼了 6 幅，en-face 才 6 行高，
        % 真血管在这么少的行里不成形，拿真数据测这条会假失败。
        bgv = 180;
        syn = bgv * ones(60, 200);
        syn(28:32, :) = 90;                      % 一条水平暗管
        syn(:, 100:104) = 90;                    % 一条垂直暗管
        syn = syn + 2*sin((1:200)/7);            % 一点缓变背景
        mk = false(size(syn)); mk(28:32, :) = true; mk(:, 100:104) = true;
        [os, ~] = oct_devessel(syn, 'Mask', mk, 'Dilate', 0);
        gap0 = mean(syn(~mk)) - mean(syn(mk));
        gap1 = mean(os(~mk))  - mean(os(mk));
        nfail = nfail + chk(sprintf('devessel 抹平暗管（差 %.1f -> %.1f）', gap0, gap1), ...
                            abs(gap1) < 0.1*abs(gap0));
        nfail = nfail + chk('devessel 填补值落在背景附近', ...
                            all(abs(os(mk) - bgv) < 8));
        % 自带掩膜时应当直接用
        mm = false(size(e1)); mm(3:5, 10:40) = true;
        [o2, m2] = oct_devessel(e1, 'Mask', mm);
        nfail = nfail + chk('devessel 接受外部掩膜', isequal(m2, mm));
        nfail = nfail + chk('devessel 外部掩膜外不动', ...
                            max(abs(o2(~mm) - e1(~mm))) < 1e-9);
    catch e8
        nfail = nfail + 1; fprintf('  FAIL en-face/血管: %s\n', e8.message);
    end
else
    fprintf('  SKIP pic_md_origin 不存在\n');
end


% --------------------------------- 9 原始体数据 / C-scan / 厚度 / 偏差
fprintf('\n[9] oct_volume_read / thickness / deviation\n');
volf = oct_find_data('volume', 'Quiet', true);
if ~isempty(volf) && exist(volf, 'file')
    try
        [vv9, vi9] = oct_volume_read(volf, 'NBscan', 4);
        nfail = nfail + chk('vol 形状 700x432x4', isequal(size(vv9), [700 432 4]));
        nfail = nfail + chk('vol 值域 0~255', min(vv9(:)) >= 0 && max(vv9(:)) <= 255);
        nfail = nfail + chk('vol 尾巴 120 字节', vi9.tail == 120);
        % Skip 应当等价于全读后切片
        va = oct_volume_read(volf, 'NBscan', 6);
        vb = oct_volume_read(volf, 'Skip', 2, 'NBscan', 3);
        nfail = nfail + chk('vol Skip 等价切片', isequal(vb, va(:,:,3:5)));
        % Flip 就是深度翻转
        vnf = oct_volume_read(volf, 'NBscan', 2, 'Flip', false);
        nfail = nfail + chk('vol Flip 是深度翻转', ...
                            isequal(vv9(:,:,1), vnf(end:-1:1,:,1)));
        % 方向判据：ILM 之上（玻璃体）应比 RPE 之下（脉络膜）暗
        bl9 = oct_layer_import(oct_find_data('analy'), 'NBscan', 4);
        b9 = vv9(:,:,1);
        yi = round(median(bl9(1).ilm(1:432)));
        yr = round(median(bl9(1).rpe(1:432)));
        up9 = max(1,yi-40):max(1,yi-5);
        dn9 = min(700,yr+5):min(700,yr+40);
        nfail = nfail + chk(sprintf('vol 方向（ILM 上 %.0f < RPE 下 %.0f）', ...
                            mean(mean(b9(up9,:))), mean(mean(b9(dn9,:)))), ...
                            mean(mean(b9(up9,:))) < mean(mean(b9(dn9,:))));

        % --- 厚度图 ---
        blA = oct_layer_import(oct_find_data('analy'));
        [T9, ti9] = oct_thickness_map(blA);
        nfail = nfail + chk(sprintf('thickness 形状 %dx%d', size(T9,1), size(T9,2)), ...
                            isequal(size(T9), [120 432]));
        nfail = nfail + chk('thickness 默认 ilm->rpe', ...
                            strcmp(ti9.top,'ilm') && strcmp(ti9.bot,'rpe'));
        nfail = nfail + chk('thickness 全为正', all(T9(isfinite(T9)) > 0));
        % px 和 um 差一个固定倍数
        Tpx = oct_thickness_map(blA, 'Unit', 'px');
        nfail = nfail + chk('thickness um/px 比 = pixZ', ...
                            abs(median(T9(isfinite(T9))) / median(Tpx(isfinite(Tpx))) - 2.44141) < 1e-6);
        try
            oct_thickness_map(blA, 'Top', 'nosuch');
            nfail = nfail + chk('thickness 未知层应报错', false);
        catch
            nfail = nfail + chk('thickness 未知层应报错', true);
        end

        % --- 偏差图 ---
        [gr9, po9, di9] = oct_deviation_map(T9, 'Grid', 24);
        nfail = nfail + chk('deviation 网格 24x24', isequal(size(gr9), [24 24]));
        % 120/24=5, 432/24=18 —— 和 oct_DeviationMap.py 里那两个
        % range(5) / range(18) 正好一致
        nfail = nfail + chk('deviation 块大小 5x18（同原脚本）', ...
                            isequal(di9.blockSize, [5 18]));
        nfail = nfail + chk('deviation 参考=池化中位', ...
                            abs(di9.ref - median(po9(isfinite(po9)))) < 1e-9);
        nfail = nfail + chk('deviation 分级在 1..5', ...
                            all(gr9(isfinite(gr9)) >= 1 & gr9(isfinite(gr9)) <= 5));
        nfail = nfail + chk('deviation 各级占比和为 1', ...
                            abs(sum(di9.fracByLevel) - 1) < 1e-9);
        % 给定参考值时，完全均匀的厚度图应当全是 1 级
        flat = 300 * ones(120, 432);
        gf = oct_deviation_map(flat, 'Ref', 300);
        nfail = nfail + chk('deviation 均匀图全 1 级', all(gf(:) == 1));
        gf2 = oct_deviation_map(flat, 'Ref', 100);
        nfail = nfail + chk('deviation 偏离 200% 全顶级', all(gf2(:) == 5));
    catch e9
        nfail = nfail + 1; fprintf('  FAIL 体数据/厚度/偏差: %s\n', e9.message);
    end
else
    fprintf('  SKIP 原始 .dat 不存在\n');
end


% ------------------------------- 10 报告类可视化（ETDRS / 地形图 / 显著性）
fprintf('\n[10] ETDRS 与报告可视化\n');
volfR = oct_find_data('volume', 'Quiet', true);
anfR = oct_find_data('analy', 'Quiet', true);
if ~isempty(anfR) && exist(anfR, 'file')
    try
        blR = oct_layer_import(anfR);
        TR = oct_thickness_map(blR);

        % --- 中心凹定位 ---
        [fy, fx, fiR] = oct_fovea_find(TR);
        nfail = nfail + chk('fovea 落在图内', fy >= 1 && fy <= size(TR,1) && ...
                                              fx >= 1 && fx <= size(TR,2));
        nfail = nfail + chk('fovea 在中央区域（Margin 内）', ...
                            fy > 0.25*size(TR,1) && fy < 0.75*size(TR,1) && ...
                            fx > 0.25*size(TR,2) && fx < 0.75*size(TR,2));
        % 中心凹应当是最薄处：那一点的厚度要低于全图中位数
        nfail = nfail + chk(sprintf('fovea 处最薄（%.0f < 中位 %.0f）', ...
                            TR(round(fy),round(fx)), median(TR(isfinite(TR)))), ...
                            TR(round(fy),round(fx)) < median(TR(isfinite(TR))));
        % 合成一个"中间有凹陷"的厚度图，定位应当落在凹陷中心
        [gx2, gy2] = meshgrid(1:200, 1:100);
        bowl = 300 - 80*exp(-(((gx2-120).^2)/(2*25^2) + ((gy2-40).^2)/(2*12^2)));
        [by, bx] = oct_fovea_find(bowl);
        nfail = nfail + chk(sprintf('fovea 合成凹陷定位 (%.0f,%.0f) 应近 (40,120)', by, bx), ...
                            abs(by-40) < 4 && abs(bx-120) < 6);

        % --- ETDRS ---
        rR = oct_etdrs_grid(TR, 'Eye', 'OD');
        nfail = nfail + chk('etdrs 9 区都有值', all(isfinite(rR.mean)));
        nfail = nfail + chk('etdrs 圆直径 1/3/6', isequal(rR.diam, [1 3 6]));
        % 生理形态。注意"中心区平均"不一定低于外环 —— 这份数据的中心凹
        % 凹陷很窄（1mm 内就从 232 升到 340），1mm 圆的平均被边缘拉到 290，
        % 略高于外环 287。所以只断言真正稳的三条：
        %   内环 > 外环、中心点 < 中心区平均、中心点 < 内环
        inner = mean(rR.mean(2:5)); outer = mean(rR.mean(6:9));
        nfail = nfail + chk(sprintf('etdrs 内环 > 外环（%.0f > %.0f）', inner, outer), ...
                            inner > outer);
        nfail = nfail + chk(sprintf('etdrs 中心点 < 中心区平均（%.0f < %.0f）', ...
                            rR.centerPoint, rR.mean(1)), ...
                            rR.centerPoint < rR.mean(1));
        nfail = nfail + chk(sprintf('etdrs 中心点 < 内环（%.0f < %.0f）', ...
                            rR.centerPoint, inner), rR.centerPoint < inner);
        % 鼻侧比颞侧厚（正常解剖）
        nfail = nfail + chk(sprintf('etdrs 鼻侧>颞侧（内 %.0f>%.0f，外 %.0f>%.0f）', ...
                            rR.mean(3), rR.mean(5), rR.mean(7), rR.mean(9)), ...
                            rR.mean(3) > rR.mean(5) && rR.mean(7) > rR.mean(9));
        % 中心点厚度落在文献范围（Spectralis 正常约 227 um）
        nfail = nfail + chk(sprintf('etdrs 中心点 %.0f um 在 180~320', rR.centerPoint), ...
                            rR.centerPoint > 180 && rR.centerPoint < 320);
        nfail = nfail + chk(sprintf('etdrs 6mm 体积 %.2f mm^3 在 5~12', rR.volume(3)), ...
                            rR.volume(3) > 5 && rR.volume(3) < 12);
        % 体积应随圆增大而单调增
        nfail = nfail + chk('etdrs 体积随圆增大', ...
                            rR.volume(1) < rR.volume(2) && rR.volume(2) < rR.volume(3));
        % OD / OS 的鼻颞应当互换
        rS = oct_etdrs_grid(TR, 'Eye', 'OS', 'Center', rR.center);
        nfail = nfail + chk('etdrs OD/OS 鼻颞互换', ...
                            abs(rS.mean(3) - rR.mean(5)) < 1e-9 && ...
                            abs(rS.mean(5) - rR.mean(3)) < 1e-9);
        try
            oct_etdrs_grid(TR, 'Eye', 'XX');
            nfail = nfail + chk('etdrs 非法 Eye 应报错', false);
        catch
            nfail = nfail + chk('etdrs 非法 Eye 应报错', true);
        end

        % --- 地形图上色 ---
        [tg, cm] = oct_thickness_rgb(TR);
        nfail = nfail + chk('topo RGB 尺寸', isequal(size(tg), [size(TR) 3]));
        nfail = nfail + chk('topo 色表 256x3 在 [0,1]', ...
                            isequal(size(cm), [256 3]) && min(cm(:)) >= 0 && max(cm(:)) <= 1);
        % 冷色薄暖色厚：薄处的蓝分量应高于厚处，厚处红分量应更高
        thin = TR < median(TR(isfinite(TR)));
        Rc = double(tg(:,:,1)); Bc = double(tg(:,:,3));
        nfail = nfail + chk('topo 薄处偏蓝、厚处偏红', ...
                            mean(Bc(thin)) > mean(Bc(~thin & isfinite(TR))) && ...
                            mean(Rc(~thin & isfinite(TR))) > mean(Rc(thin)));

        % --- 显著性图 ---
        [sg, bnd, siR] = oct_significance_rgb(TR);
        nfail = nfail + chk('sig 模式 self', strcmp(siR.mode, 'self'));
        % 自身分位模式下，四带占比应当就是 1/4/90/5
        want = [0.01 0.04 0.90 0.05];
        nfail = nfail + chk(sprintf('sig 四带占比 %.0f/%.0f/%.0f/%.0f%%', ...
                            100*siR.fracByBand), ...
                            max(abs(siR.fracByBand - want)) < 0.01);
        nfail = nfail + chk('sig band 取值 1..4', ...
                            all(ismember(bnd(isfinite(bnd)), 1:4)));
        % 给正常库时走 norm 模式，且薄的地方该落到红带
        [~, bnd2, si2] = oct_significance_rgb(TR, 'Norm', [300 10]);
        nfail = nfail + chk('sig 正常库模式', strcmp(si2.mode, 'norm'));
        nfail = nfail + chk('sig 正常库下中心凹落红带', ...
                            bnd2(round(fy), round(fx)) == 1);

        % --- 靶心图渲染 ---
        bl2 = oct_etdrs_rgb(rR, 'Size', 240);
        nfail = nfail + chk('bullseye 尺寸 240x240x3', isequal(size(bl2), [240 240 3]));
        nfail = nfail + chk('bullseye 四角为黑（圆外）', ...
                            all(bl2(1,1,:) == 0) && all(bl2(1,end,:) == 0) && ...
                            all(bl2(end,1,:) == 0) && all(bl2(end,end,:) == 0));
        nfail = nfail + chk('bullseye 中心非黑', any(bl2(120,120,:) > 0));
        bl3 = oct_etdrs_rgb(rR, 'Size', 240, 'Bands', [1 2 3 4 3 2 1 3 4]);
        nfail = nfail + chk('bullseye Bands 模式能跑', isequal(size(bl3), [240 240 3]));

        % --- 整份报告 ---
        if ~isempty(volfR) && exist(volfR, 'file')
            tmpr = [tempname '.png'];
            oR = oct_report('Show', false, 'Save', tmpr);
            nfail = nfail + chk('report 出图', exist(tmpr, 'file') == 2);
            nfail = nfail + chk('report 返回 etdrs', isfield(oR, 'etdrs') && ...
                                all(isfinite(oR.etdrs.mean)));
            if exist(tmpr, 'file'), delete(tmpr); end
            close all;
        end
    catch e10
        nfail = nfail + 1; fprintf('  FAIL ETDRS/报告: %s\n', e10.message);
    end
else
    fprintf('  SKIP analy.dat 不存在\n');
end

fprintf('\n=== %s ===\n', ternary(nfail == 0, '全部通过', sprintf('%d 项失败', nfail)));
if nfail > 0, exit(1); end
end

% ------------------------------------------------------------------
function n = chk(name, ok)
if ok
    fprintf('  ok   %s\n', name); n = 0;
else
    fprintf('  FAIL %s\n', name); n = 1;
end
end

function cols = oct_show_spectrum_probe(f, range)
% 跑一遍 ShowBscan，取回 B-scan 的前 60 列
oct_show_spectrum('File', f, 'Range', range, 'ShowBscan', true, 'Pause', 0);
im = findall(0, 'Type', 'image');
cd_ = get(im(1), 'CData');
cols = cd_(:, 1:60);
close all;
end

function s = synth(nl, ln)
i = (0:nl-1).'; j = 0:ln-1;
s = mod((i+1)*7919 + (j+1)*104729, 4096);
end

function g = readGolden(f)
fid = fopen(f, 'r'); txt = textscan(fid, '%s', 'Delimiter', '\n'); fclose(fid);
txt = txt{1};
g = struct('name', {}, 'ln', {}, 'bg', {}, 'sum', {}, 'mn', {}, 'mx', {}, 'head', {});
for i = 1:numel(txt)
    parts = strsplit(strtrim(txt{i}), ' ');
    if numel(parts) < 14, continue; end
    g(end+1).name = parts{1};                     %#ok<AGROW>
    g(end).ln   = str2double(parts{2});
    g(end).bg   = str2double(parts{3});
    g(end).sum  = str2double(parts{4});
    g(end).mn   = str2double(parts{5});
    g(end).mx   = str2double(parts{6});
    g(end).head = cellfun(@str2double, parts(7:14));
end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
