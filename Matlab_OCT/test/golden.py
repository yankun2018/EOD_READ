# 用「C++ 逐行直译」的实现生成金标准，给 MATLAB 侧对比。
# 输入是确定性公式，MATLAB 能一模一样地复现，不依赖随机数。
import numpy as np, io

def cpp_ref(spec, D, C, BG, DIR=1, FILL=.95, CEN=.5, LOGOFF=1000., inplace=False):
    nl, ln = spec.shape; N = float(ln - 1)
    sub = np.empty_like(spec)
    for i in range(nl):
        for j in range(ln):
            if i < BG: sub[i, j] = spec[i, j]
            else:
                s = sum(spec[i-k, j] for k in range(BG))
                sub[i, j] = spec[i, j] - s/BG
    width = int(FILL*ln); center = int(CEN*ln); minPos = center - width//2
    win = np.empty(ln)
    for i in range(ln):
        xn = (i - minPos)/(width - 1.0)
        win[i] = 0.0 if (xn > .999 or xn < .0001) else .5*(1-np.cos(2*np.pi*xn))
    out = np.empty((nl, ln))
    for li in range(nl):
        a = sub[li].copy()
        dst = a if inplace else np.empty(ln)
        for i in range(ln):
            t = D[0] + (D[1]/N)*i + (D[2]/N**2)*i*i + (D[3]/N**3)*i*i*i
            tt = int(t)
            tt = min(max(tt, 0), ln-2)          # 和 MATLAB 侧一样钳一下
            dst[i] = a[tt] + (t-tt)*(a[tt+1]-a[tt])
        a = dst
        re = np.empty(ln); im = np.empty(ln)
        for i in range(ln):
            t = C[0] + (C[1]/N)*i + (C[2]/N**2)*i*i + (C[3]/N**3)*i*i*i
            re[i] = a[i]*np.cos(t); im[i] = a[i]*DIR*np.sin(t)
        re *= win; im *= win
        z = np.fft.ifft(re + 1j*im)*ln
        out[li] = np.log(np.abs(z) + LOGOFF)
    return out

def synth(nl, ln):
    i = np.arange(nl)[:, None]; j = np.arange(ln)[None, :]
    return ((i+1)*7919.0 + (j+1)*104729.0) % 4096.0

cases = [
    ('strawberry1664_offplace', 1664, (0,2016,-994,624), (0,10.5,1.5,0), 20, False),
    ('strawberry1664_inplace',  1664, (0,2016,-994,624), (0,10.5,1.5,0), 20, True),
    ('eod2048_offplace',        2048, (0,2047,0,0),      (0,0,0,0),      32, False),
]
with io.open('golden.txt','w') as f:
    for name, ln, D, C, BG, ip in cases:
        spec = synth(40, ln)
        out = cpp_ref(spec, D, C, BG, inplace=ip)
        half = out[:, :ln//2]
        # 写下若干可校验的统计量 + 最后一条 A-line 的前 8 个点
        f.write('%s %d %d %.17g %.17g %.17g %s\n' % (
            name, ln, BG, half.sum(), half.min(), half.max(),
            ' '.join('%.17g' % v for v in half[-1, :8])))
        print(f'{name:26} half{half.shape} sum={half.sum():.6f} '
              f'min={half.min():.6f} max={half.max():.6f}')
print('\ngolden.txt 已生成')
