function [vol, info] = oct_volume_read(path, varargin)
%OCT_VOLUME_READ  读 EOD 的原始三维扫描 .dat。
%
%   vol = OCT_VOLUME_READ(path)
%   [vol, info] = OCT_VOLUME_READ(path, 'Name', value, ...)
%
%   vol : [depth x nAline x nBscan] uint8 转 double，深度沿第 1 维
%         （第 1 行最浅），和 oct_layer_seg 要的方向一致。
%
%   格式是从 Analy_and_image_show\oct_cscan.py 反推的：
%       1024 字节头
%       然后每幅 B-scan 是 nAline x depth 个 uint8（行优先，即先走完一条
%       A-line 的 depth 个采样再换下一条），读进来要转置成 depth x nAline。
%   校验：仓库里 test_data\od-3dscan-macular-20210104-150822-001.dat
%   是 36289144 字节 = 1024 + 120 x 432 x 700 + 120 字节尾巴。
%
%   选项：
%     'Depth'    每条 A-line 的采样数（默认 700）
%     'NAline'   每幅 B-scan 的 A-line 条数（默认 432）
%     'NBscan'   读几幅，Inf = 按文件大小推（默认 Inf）
%     'Skip'     先跳过几幅（默认 0）
%     'Header'   头部字节数（默认 1024）
%     'Flip'     深度翻转（默认 true）。.dat 里每条 A-line 的采样是"从
%                脉络膜侧数"的，翻过来才符合本工具箱"第 1 行最浅（ILM 侧）"
%                的约定，oct_layer_seg 也是按这个约定写的。
%                判据：翻转后 ILM 之上是暗的玻璃体（亮度 38.9）、RPE 之下
%                是较亮的脉络膜（86.9）；不翻的话正好相反。
%                oct_cscan.py 里那句 ROTATE_90 干的是同一件事。
%
%   info : .nBscan .depth .nAline .bytes .tail（尾巴多出来的字节数）
%
%   参见 oct_layer_seg, oct_enface, oct_analy_demo。

opt.Depth  = 700;
opt.NAline = 432;
opt.NBscan = Inf;
opt.Skip   = 0;
opt.Header = 1024;
opt.Flip   = true;
opt = oct_parseopt(opt, varargin);

d = dir(path);
if isempty(d), error('oct_volume_read:noFile', '找不到: %s', path); end

per = opt.Depth * opt.NAline;            % 一幅 B-scan 的字节数
avail = floor((d.bytes - opt.Header) / per);
if avail < 1
    error('oct_volume_read:tooSmall', ...
          '%s 只有 %d 字节，不够一幅（头 %d + %d x %d = %d）', ...
          path, d.bytes, opt.Header, opt.Depth, opt.NAline, opt.Header + per);
end
n = avail - opt.Skip;
if isfinite(opt.NBscan), n = min(n, opt.NBscan); end
if n < 1
    error('oct_volume_read:skipTooBig', ...
          '跳过 %d 幅之后只剩 %d 幅', opt.Skip, avail - opt.Skip);
end

fid = fopen(path, 'r');
if fid < 0, error('oct_volume_read:open', '打不开: %s', path); end
c = onCleanup(@() fclose(fid));   %#ok<NASGU>
if fseek(fid, opt.Header + opt.Skip * per, 'bof') ~= 0
    error('oct_volume_read:seek', 'seek 失败');
end
raw = fread(fid, per * n, '*uint8');
got = floor(numel(raw) / per);
if got < n
    n = got;
    if n < 1, error('oct_volume_read:short', '读到的数据不够一幅'); end
end

% 每幅是 nAline x depth（行优先）；MATLAB 按列优先 reshape，
% 所以 reshape 成 [depth, nAline] 就已经是转置好的
vol = double(reshape(raw(1:per*n), opt.Depth, opt.NAline, n));
if opt.Flip
    vol = vol(end:-1:1, :, :);
end

if nargout > 1
    info.nBscan = n;
    info.depth  = opt.Depth;
    info.nAline = opt.NAline;
    info.bytes  = d.bytes;
    info.tail   = d.bytes - opt.Header - avail * per;
end
end
