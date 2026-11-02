#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Escape Gravity —— 程序化音频素材生成器。

只用 Python 3 标准库 + numpy 合成全部 `assets/audio/` 下的 BGM 与 SFX，
16-bit PCM WAV / 44.1kHz，BGM 立体声、SFX 单声道。可重复运行，产物完全
由本脚本决定（随机种子固定）。

设计要点
--------
* BGM 用「整数周期 / 环绕折叠」保证无缝循环：
  - 连续层（drone、噪声铺底）的所有频率与 LFO 都是 1/loop_len 的整数倍，
    因此天然以 loop 长度周期重复；
  - 瞬态层（pad、钟声、脉冲、琶音）在尾部多渲染 tail 秒，再把超出的部分
    折叠回开头（wrap-around overlap-add），使混响/音符尾巴跨过接缝连续。
* 立体声靠声部去相关：左右各一组失谐、钟声等功率声像、混响 IR 左右去相关。
* SFX 每个都做「设计」而非纯正弦哔声：扫频 + 噪声层 + 瞬态 + 饱和，
  首尾 5ms 淡入淡出，峰值归一化到各文件指定的 dBFS 目标（全部 ≤ -1）。
* 生成后自检（时长/声道/采样率/峰值/DC/首尾/接缝）并写 docs/audio_report.md。

用法:
    python3 tools/gen_audio.py            # 生成 + 自检 + 写报告
    python3 tools/gen_audio.py --no-report
"""

from __future__ import annotations

import argparse
import math
import os
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(ROOT, "assets", "audio")
REPORT_PATH = os.path.join(ROOT, "docs", "audio_report.md")
SR = 44100

# --------------------------------------------------------------------------
# 基础工具
# --------------------------------------------------------------------------


def n_of(dur: float) -> int:
    return int(round(dur * SR))


def t_of(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def midi2f(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def db(v: float) -> float:
    return 20.0 * math.log10(max(v, 1e-12))


def sat(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    """软饱和，避免硬削波并增加谐波。"""
    return np.tanh(x * drive)


def norm_peak(x: np.ndarray, target_db: float) -> np.ndarray:
    p = peak(x)
    if p < 1e-12:
        return x
    return x * (10.0 ** (target_db / 20.0) / p)


def dc_block(x: np.ndarray) -> np.ndarray:
    """去掉直流分量（低于 -60dBFS 的残余偏移也会被消除）。"""
    return x - float(np.mean(x))


def dc_block_bias(x: np.ndarray, ms: float = 5.0) -> np.ndarray:
    """去掉淡变后残留的直流偏置：用一条两端为 0 的窗口做内部补偿，
    这样端点仍严格为 0，而全片均值回到 ~0。"""
    n = len(x)
    k = max(1, min(int(round(ms * SR / 1000.0)), n // 2))
    w = np.ones(n)
    w[:k] = np.sin(np.linspace(0.0, np.pi / 2.0, k)) ** 2
    w[-k:] = w[:k][::-1]
    return x - float(np.mean(x)) * w


def fade_ends(x: np.ndarray, ms: float = 5.0, shape: str = "cos") -> np.ndarray:
    n = len(x)
    k = max(1, min(int(round(ms * SR / 1000.0)), n // 2))
    y = x.copy()
    if shape == "cos":
        w = np.sin(np.linspace(0.0, np.pi / 2.0, k)) ** 2
    else:
        w = np.linspace(0.0, 1.0, k)
    y[:k] *= w
    y[-k:] *= w[::-1]
    return y


def fade_in(x: np.ndarray, ms: float) -> np.ndarray:
    k = min(max(1, int(round(ms * SR / 1000.0))), len(x))
    y = x.copy()
    y[:k] *= np.sin(np.linspace(0.0, np.pi / 2.0, k)) ** 2
    return y


def fade_out(x: np.ndarray, ms: float) -> np.ndarray:
    k = min(max(1, int(round(ms * SR / 1000.0))), len(x))
    y = x.copy()
    y[-k:] *= np.sin(np.linspace(np.pi / 2.0, 0.0, k)) ** 2
    return y


# ---------------- 噪声 ----------------

def noise_white(n: int, rng: np.random.Generator) -> np.ndarray:
    x = rng.standard_normal(n)
    return x / (peak(x) + 1e-12)


def noise_pink(n: int, rng: np.random.Generator, circular: bool = True) -> np.ndarray:
    """1/f 幅度谱的粉噪。circular=True 时用长度 n 的循环 FFT，结果以 n 为周期。"""
    x = rng.standard_normal(n)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if n > 2 else 1.0
    X = X / np.sqrt(f / 20.0)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (peak(y) + 1e-12)


# ---------------- 滤波（FFT 域，避免逐样本递归） ----------------

def _lp_gain(f: np.ndarray, hi: float, lo, order: int) -> np.ndarray:
    g = np.ones_like(f)
    if hi is not None:
        g = g / np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo is not None:
        g = g / np.sqrt(1.0 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
    return g


def filt(x: np.ndarray, lo: float | None = None, hi: float | None = None,
         order: int = 2) -> np.ndarray:
    """零填充 FFT 滤波，长度不变，末端尾巴不会绕回开头。"""
    n = len(x)
    nfft = 1 << int(np.ceil(np.log2(n + min(8192, n) + 1)))
    X = np.fft.rfft(x, nfft)
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    y = np.fft.irfft(X * _lp_gain(f, hi, lo, order), nfft)[:n]
    return y


def filt_circ(x: np.ndarray, lo: float | None = None, hi: float | None = None,
              order: int = 2) -> np.ndarray:
    """循环 FFT 滤波，结果严格以 len(x) 为周期（用于可循环素材）。"""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(X * _lp_gain(f, hi, lo, order), n)
    return y


def bandpass(x: np.ndarray, fc: float, bw: float = 0.7, circular: bool = True) -> np.ndarray:
    """对数频率上的高斯带通；bw 为八度单位的宽度。"""
    n = len(x)
    if circular:
        X = np.fft.rfft(x)
        f = np.fft.rfftfreq(n, 1.0 / SR)
        f[0] = 1e-6
        g = np.exp(-0.5 * (np.log2(f / fc) / max(bw, 0.05)) ** 2)
        g[0] = 0.0
        return np.fft.irfft(X * g, n)
    X = np.fft.rfft(x, 1 << int(np.ceil(np.log2(n * 2))))
    f = np.fft.rfftfreq(len(X) * 2 - 2, 1.0 / SR)
    f[0] = 1e-6
    g = np.exp(-0.5 * (np.log2(f / fc) / max(bw, 0.05)) ** 2)
    g[0] = 0.0
    return np.fft.irfft(X * g, len(X) * 2 - 2)[:n]


def convolve_fft(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    n = len(a) + len(b) - 1
    nfft = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(a, nfft) * np.fft.rfft(b, nfft), nfft)
    return y[:n]


# ---------------- 混响 ----------------

def make_ir(dur: float, decay: float, rng: np.random.Generator,
            lp: float = 6000.0, predelay: float = 0.012,
            pre: int = 10) -> np.ndarray:
    """指数衰减噪声 + 稀疏早期反射的混响冲激响应。"""
    n = n_of(dur)
    t = t_of(n)
    ir = rng.standard_normal(n) * np.exp(-t / decay)
    ir = filt(ir, hi=lp, order=2)
    # 早期反射
    for _ in range(pre):
        d = rng.uniform(0.003, 0.07)
        s = int(d * SR)
        if s < n:
            ir[s] += rng.uniform(0.3, 1.0) * (1.0 - d / 0.08)
    # 预延迟
    pd = n_of(predelay)
    ir = np.concatenate([np.zeros(pd), ir])[:n]
    return ir


def reverb_send(x: np.ndarray, ir: np.ndarray, ratio: float) -> np.ndarray:
    """与 x 等长的湿信号，按「湿/干 RMS 比 = ratio」自动校准电平。"""
    w = convolve_fft(x, ir)[: len(x)]
    dr, wr = rms(x), rms(w)
    if wr < 1e-12 or dr < 1e-12:
        return np.zeros_like(x)
    return w * (ratio * dr / wr)


def rev_mono(x: np.ndarray, ratio: float = 0.35, decay: float = 0.5,
             rng: np.random.Generator | None = None, lp: float = 5000.0) -> np.ndarray:
    rng = rng or np.random.default_rng(7)
    ir = make_ir(max(0.25, decay * 2.5), decay, rng, lp=lp)
    return x + reverb_send(x, ir, ratio)


# ---------------- 素材单元 ----------------

def thump(n: int, f0: float, f1: float, tau: float, tau_pitch: float = 0.06,
          drive: float = 1.6, harm2: float = 0.15) -> np.ndarray:
    """低频冲击：指数下滑的正弦 + 二次谐波 + 软饱和。"""
    t = t_of(n)
    f = (f0 - f1) * np.exp(-t / max(tau_pitch, 1e-4)) + f1
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) + harm2 * np.sin(2.0 * ph)
    return sat(body * np.exp(-t / tau), drive)


def noise_sweep(n: int, f0: float, f1: float, rng: np.random.Generator,
                bw: float = 1.0, bands: int = 24, curve: str = "exp",
                f_lo: float = 70.0, f_hi: float = 14000.0) -> np.ndarray:
    """噪声带通中心随时间扫动的 whoosh：用一组固定带通 × 时变增益求和，平滑无台阶。"""
    x = rng.standard_normal(n)
    tt = np.arange(n) / max(n - 1, 1)
    if curve == "exp":
        fc = f0 * (f1 / f0) ** tt
    else:
        fc = f0 + (f1 - f0) * tt
    centers = np.geomspace(f_lo, f_hi, bands)
    out = np.zeros(n)
    for c in centers:
        g = np.exp(-0.5 * (np.log2(c / fc) / max(bw, 0.12)) ** 2)
        if float(np.max(g)) < 0.02:
            continue
        out += bandpass(x, c, bw=max(bw, 0.12)) * g
    return out / (peak(out) + 1e-12)


def crackle(n: int, rng: np.random.Generator, count: int, t0: float, t1: float,
            f_lo: float = 700.0, f_hi: float = 8000.0,
            dec: tuple[float, float] = (0.008, 0.05)) -> np.ndarray:
    """碎片 / 碎石颗粒：随机位置上的短带通噪声爆发。"""
    out = np.zeros(n)
    for _ in range(count):
        s = int(rng.uniform(t0, t1) * SR)
        if s >= n - 4:
            continue
        ln = int(min(n_of(rng.uniform(0.006, 0.05)), n - s))
        if ln <= 2:
            continue
        tt = t_of(ln)
        b = bandpass(rng.standard_normal(ln), rng.uniform(f_lo, f_hi), 0.55)
        b /= peak(b) + 1e-12
        out[s:s + ln] += b * np.exp(-tt / rng.uniform(*dec)) * rng.uniform(0.25, 1.0)
    return out


def fm_bell(f: float, dur: float, index: float = 2.6, ratio: float = 3.5,
            decay: float = 1.2, att: float = 0.004, rng: np.random.Generator | None = None,
            partial2: float = 0.18) -> np.ndarray:
    n = n_of(dur)
    t = t_of(n)
    mod_env = np.exp(-t / (decay * 0.32))
    mod = np.sin(2.0 * np.pi * f * ratio * t + (rng.uniform(0, 6.28) if rng else 0.0)) * index * mod_env
    car = np.sin(2.0 * np.pi * f * t + mod)
    car += partial2 * np.sin(2.0 * np.pi * f * 2.01 * t) * np.exp(-t / (decay * 0.5))
    env = (1.0 - np.exp(-t / att)) * np.exp(-t / decay)
    return car * env


def metal_ring(n: int, t: np.ndarray, freqs, decay: float = 0.15,
               rng: np.random.Generator | None = None) -> np.ndarray:
    out = np.zeros(n)
    for i, f in enumerate(freqs):
        d = decay * (0.55 + 0.9 * ((i * 7) % 5) / 4.0)
        ph = rng.uniform(0, 6.28) if rng else i * 1.7
        out += (1.0 / (1.0 + i * 0.55)) * np.sin(2.0 * np.pi * f * t + ph) * np.exp(-t / d)
    return out


def pluck(f: float, dur: float = 0.3, decay: float = 0.1, bright: float = 0.45) -> np.ndarray:
    n = n_of(dur)
    t = t_of(n)
    s = (np.sin(2 * np.pi * f * t)
         + bright * 0.6 * np.sin(2 * np.pi * 2 * f * t)
         + bright * 0.3 * np.sin(2 * np.pi * 3 * f * t)
         + bright * 0.15 * np.sin(2 * np.pi * 4.02 * f * t))
    env = (1.0 - np.exp(-t / 0.0018)) * np.exp(-t / decay)
    return s * env


def echo(x: np.ndarray, delay_s: float, taps: int = 4, decay: float = 0.45,
         total_n: int | None = None) -> np.ndarray:
    """简单多抽头延迟（不做反馈，避免失控）。"""
    n = total_n or (len(x) + int(delay_s * SR * taps) + 1)
    out = np.zeros(n)
    m = min(len(x), n)
    out[:m] += x[:m]
    d = int(delay_s * SR)
    for k in range(1, taps + 1):
        s = k * d
        if s >= n:
            break
        out[s:s + min(m, n - s)] += x[: min(m, n - s)] * (decay ** k)
    return out


# --------------------------------------------------------------------------
# 立体声拼装工具
# --------------------------------------------------------------------------

def add_st(buf: np.ndarray, sig: np.ndarray, start_s: float, gain: float = 1.0,
           pan: float = 0.0) -> None:
    s = int(round(start_s * SR))
    if s >= len(buf):
        return
    m = min(len(sig), len(buf) - s)
    l = gain * math.cos((pan + 1.0) * math.pi / 4.0)
    r = gain * math.sin((pan + 1.0) * math.pi / 4.0)
    buf[s:s + m, 0] += sig[:m] * l
    buf[s:s + m, 1] += sig[:m] * r


def add_mono_st(buf: np.ndarray, sig: np.ndarray, start_s: float, gain: float = 1.0) -> None:
    s = int(round(start_s * SR))
    if s >= len(buf):
        return
    m = min(len(sig), len(buf) - s)
    buf[s:s + m, 0] += sig[:m] * gain
    buf[s:s + m, 1] += sig[:m] * gain


def loop_seam_crossfade(mixed: np.ndarray, cont: np.ndarray, trans: np.ndarray,
                        n_loop: int, ms: float = 3.0) -> np.ndarray:
    """在循环接缝处做极短等幅交叉淡化。

    cont 是严格以 n_loop 为周期的连续层，trans 是带尾巴的瞬态层。接缝前一刻的
    真实信号是 mixed[n-1]；接续信号是 cont[0:X] + trans[n_loop:n_loop+X]。
    把开头 X 毫秒按 0→1 淡入这个接续信号，即可让首尾在样本与斜率上都连续。
    """
    x = max(1, min(n_of(ms), n_loop // 2, len(trans) - n_loop))
    w = np.linspace(0.0, 1.0, x, dtype=np.float64)[:, None]
    nxt = cont[:x] + trans[n_loop:n_loop + x]
    out = mixed.copy()
    out[:x] = mixed[:x] * w + nxt * (1.0 - w)
    return out


def wrap_fold(sig: np.ndarray, n_loop: int) -> np.ndarray:
    """环绕折叠：把超过 loop 长度的尾巴叠加回开头，保证接缝处能量/混响连续。"""
    out = sig[:n_loop].copy()
    tail = sig[n_loop:]
    m = min(len(tail), n_loop)
    if m > 0:
        out[:m] += tail[:m]
    return out


def pad_stereo(freqs, dur: float, rel: float, rng: np.random.Generator,
               fc: float = 900.0, att: float = 1.2, detune: float = 7.0,
               harm: int = 9, tilt: float = 1.15, swell_cycles: float = 1.0,
               loop_len: float = 40.0, level: float = 1.0) -> np.ndarray:
    """加法合成的深空 pad：谐波随一条缓慢的「亮度」控制信号开合，左右失谐去相关。"""
    n = n_of(dur + rel)
    t = t_of(n)
    sw = 0.5 + 0.5 * np.sin(2.0 * np.pi * (swell_cycles / loop_len) * t + rng.uniform(0, 6.28))
    bright = 0.35 + 0.65 * sw
    env = np.ones(n)
    na = max(1, n_of(att))
    env[:na] = np.sin(np.linspace(0.0, np.pi / 2.0, na)) ** 2
    nr = max(1, n_of(rel))
    env[-nr:] *= np.cos(np.linspace(0.0, np.pi / 2.0, nr)) ** 2
    L = np.zeros(n)
    R = np.zeros(n)
    for f0 in freqs:
        for sign, which in ((1.0, 0), (-1.0, 1)):
            f = f0 * 2.0 ** (sign * detune / 1200.0)
            for h in range(1, harm + 1):
                fh = f * h
                if fh > 8500.0:
                    break
                a = 1.0 / (h ** tilt)
                w = 1.0 / (1.0 + (h / 3.0) ** 2)
                curve = a * (w + (1.0 - w) * bright)
                ph = rng.uniform(0.0, 2.0 * np.pi)
                voice = np.sin(2.0 * np.pi * fh * t + ph) * curve
                if which == 0:
                    L += voice
                else:
                    R += voice
    L2 = env * (0.88 * L + 0.42 * R)
    R2 = env * (0.88 * R + 0.42 * L)
    # 轻微 Haas 偏移，加强宽度（不超 10ms）
    d = n_of(0.006)
    R2 = np.concatenate([np.zeros(d), R2])[:n]
    return np.stack([L2, R2], axis=1) * level


# --------------------------------------------------------------------------
# BGM 1 —— bgm_menu：40s / BPM 60 / 40 拍 / 10 小节
# --------------------------------------------------------------------------

MENU_BPM = 60.0
MENU_BEATS = 40
MENU_LOOP = MENU_BEATS * 60.0 / MENU_BPM  # 40.0 s


def build_menu() -> np.ndarray:
    rng = np.random.default_rng(20240501)
    spb = 60.0 / MENU_BPM                      # 每拍秒数 = 1.0
    n_loop = int(round(MENU_LOOP * SR))        # 1764000
    tail = n_of(4.0)
    cont = np.zeros((n_loop, 2))               # 连续层：严格以 n_loop 为周期
    trans = np.zeros((n_loop + tail, 2))       # 瞬态层：尾部折叠回开头

    # ---- 连续层 1：A1 低音 drone（55 / 55.25 / 110 / 27.5 Hz，全为 1/40s 整数倍）
    t = t_of(n_loop)
    drone = (0.55 * np.sin(2 * np.pi * 55.0 * t)
             + 0.40 * np.sin(2 * np.pi * 55.25 * t + 0.9)
             + 0.16 * np.sin(2 * np.pi * 110.0 * t + 2.1)
             + 0.30 * np.sin(2 * np.pi * 27.5 * t + 1.3))
    drone *= 1.0 + 0.22 * np.sin(2 * np.pi * (2 / MENU_LOOP) * t)  # 0.05Hz 慢呼吸
    drone = sat(drone * 0.55, 1.05)
    cont[:, 0] += drone * 0.30
    cont[:, 1] += drone * 0.30

    # ---- 连续层 2：极轻噪声铺底（循环粉噪 + 慢 LFO，整数周期）
    for ch, lfo_cycles, ph0 in ((0, 3, 0.0), (1, 5, 1.7)):
        nz = noise_pink(n_loop, rng)
        nz = filt_circ(nz, lo=120, hi=900, order=2)
        nz /= peak(nz) + 1e-12
        lfo = 0.55 + 0.45 * np.sin(2 * np.pi * (lfo_cycles / MENU_LOOP) * t + ph0)
        cont[:, ch] += nz * lfo * 0.035

    # ---- 瞬态层 1：pad 和声进行（每 8 拍换一次，10 小节）
    prog = [
        (0.0, 8.0, [45, 52, 57, 60, 64]),      # Am
        (8.0, 8.0, [41, 48, 57, 60, 64]),      # Fmaj7
        (16.0, 8.0, [48, 55, 59, 64, 43]),     # Cmaj7
        (24.0, 4.0, [50, 57, 62, 65]),         # Dm
        (28.0, 4.0, [40, 47, 52, 55]),         # Em
        (32.0, 8.0, [45, 52, 57, 64]),         # Am（回归）
    ]
    for b0, nb, notes in prog:
        freqs = [midi2f(m) for m in notes]
        pad = pad_stereo(freqs, nb * spb, rel=1.8, rng=rng, att=1.5,
                         detune=8.0, harm=9, swell_cycles=1.0,
                         loop_len=MENU_LOOP, level=0.10)
        s = int(round(b0 * spb * SR))
        m = min(len(pad), len(trans) - s)
        trans[s:s + m] += pad[:m]

    # ---- 瞬态层 2：稀疏钟声（五声音阶，左右交替，长衰减）
    bell_times = [2.5, 6.0, 9.5, 13.0, 17.5, 21.0, 24.5, 28.0, 31.5, 35.0, 38.0]
    pent = [69, 72, 74, 76, 79, 81, 84]
    for i, b in enumerate(bell_times):
        f = midi2f(pent[(i * 3) % len(pent)])
        dur = 3.6
        b_sig = fm_bell(f, dur, index=2.2, ratio=3.51, decay=1.5, rng=rng)
        b_hi = fm_bell(f * 2.0, dur, index=1.2, ratio=4.01, decay=0.8, rng=rng)
        b_hi = np.pad(b_hi, (0, max(0, len(b_sig) - len(b_hi))))[: len(b_sig)]
        b_sig = b_sig + 0.22 * b_hi
        b_sig *= 0.55 + 0.45 * (0.5 + 0.5 * math.cos(i * 1.1))
        pan = -0.55 if i % 2 == 0 else 0.55
        add_st(trans, b_sig, b * spb, gain=0.30, pan=pan)

    # ---- 瞬态层 3：极轻脉冲（每小节一次，45Hz 落点）
    for b in range(0, MENU_BEATS, 4):
        p = thump(n_of(0.9), 52.0, 38.0, tau=0.28, tau_pitch=0.05, drive=1.2)
        add_st(trans, p, b * spb, gain=0.16, pan=0.0)

    # ---- 整段瞬态层混响（左右去相关 IR）
    for ch in (0, 1):
        ir = make_ir(2.8, 1.1, rng, lp=4200, predelay=0.02)
        wet = reverb_send(trans[:, ch], ir, ratio=0.55)
        trans[:, ch] = trans[:, ch] + wet

    mixed = cont + wrap_fold(trans, n_loop)
    return loop_seam_crossfade(mixed, cont, trans, n_loop, ms=3.0)


# --------------------------------------------------------------------------
# BGM 2 —— bgm_run：84 BPM，17 小节 = 68 拍 = 48.571s
# --------------------------------------------------------------------------

RUN_BPM = 84.0
RUN_BEATS = 68
RUN_LOOP = RUN_BEATS * 60.0 / RUN_BPM  # 48.571428... s
RUN_SPB = 60.0 / RUN_BPM               # 0.7142857 s


def build_run() -> np.ndarray:
    rng = np.random.default_rng(84101)
    n_loop = int(round(RUN_LOOP * SR))     # 2142000
    tail = n_of(3.0)
    cont = np.zeros((n_loop, 2))
    trans = np.zeros((n_loop + tail, 2))
    t = t_of(n_loop)

    # ---- 连续层：低频 drone + 噪声床（整数周期 LFO）
    drone = (0.55 * np.sin(2 * np.pi * 55.0 * t)
             + 0.25 * np.sin(2 * np.pi * 55.35 * t + 1.1)
             + 0.20 * np.sin(2 * np.pi * 82.5 * t + 0.4))
    drone *= 1.0 + 0.18 * np.sin(2 * np.pi * (2 / RUN_LOOP) * t)
    cont[:, 0] += drone * 0.16
    cont[:, 1] += drone * 0.16
    for ch, cyc, ph in ((0, 4, 0.3), (1, 6, 2.2)):
        nz = noise_pink(n_loop, rng)
        nz = filt_circ(nz, lo=250, hi=1600, order=2)
        nz /= peak(nz) + 1e-12
        cont[:, ch] += nz * (0.5 + 0.5 * np.sin(2 * np.pi * (cyc / RUN_LOOP) * t + ph)) * 0.020

    beat = RUN_SPB
    bar = 4 * beat
    # 每 4 小节一个和弦，17 小节 = 4+4+4+4+1
    chords = {
        "Am": dict(root=33, triad=[57, 60, 64]),
        "F": dict(root=29, triad=[53, 57, 60]),
        "C": dict(root=36, triad=[55, 60, 64]),
        "G": dict(root=31, triad=[55, 59, 62]),
    }
    bars = ["Am"] * 4 + ["F"] * 4 + ["C"] * 4 + ["G"] * 4 + ["Am"]
    assert len(bars) == 17

    def chord_of(bar_idx: int) -> dict:
        return chords[bars[bar_idx % 17]]

    # ---- pad：每 4 小节一段，暗色铺底
    for seg in range(0, 17, 4):
        name = bars[seg]
        c = chords[name]
        freqs = [midi2f(m) for m in c["triad"]]
        pad = pad_stereo(freqs, 4 * bar, rel=1.2, rng=rng, att=1.4,
                         detune=6.0, harm=8, swell_cycles=1.0, loop_len=RUN_LOOP,
                         level=0.075)
        s = int(round(seg * bar * SR))
        m = min(len(pad), len(trans) - s)
        trans[s:s + m] += pad[:m]

    # ---- 低频脉冲（kick 感）：每小节 1、3 拍重，1.5、3.5 拍幽灵
    for b in range(RUN_BEATS):
        bb = b % 4
        if bb in (0, 2):
            g = 0.55 if bb == 0 else 0.44
            p = thump(n_of(0.42), 96.0, 41.0, tau=0.14, tau_pitch=0.055, drive=1.5)
            add_st(trans, p, b * beat, gain=g, pan=0.0)
        elif bb in (1, 3):
            p = thump(n_of(0.3), 78.0, 44.0, tau=0.09, tau_pitch=0.04, drive=1.3)
            add_st(trans, p, (b + 0.5) * beat, gain=0.17, pan=0.0)

    # ---- 贝斯：根音 + 偶尔五度
    for b in range(RUN_BEATS):
        c = chord_of(b // 4)
        root = midi2f(c["root"])
        f = root * (2.0 if b % 8 == 6 else 1.0)
        n = n_of(0.5)
        tt = t_of(n)
        ph = 2 * np.pi * np.cumsum(np.full(n, f)) / SR
        sig = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.14 * np.sin(3 * ph))
        sig = sat(sig * 1.3, 1.3) * (1 - np.exp(-tt / 0.004)) * np.exp(-tt / 0.22)
        sig = filt(sig, hi=420, order=2)
        if b % 4 in (0, 2):
            add_st(trans, sig, b * beat, gain=0.36, pan=0.0)
        # 五度小点缀
        if b % 8 == 7:
            add_st(trans, pluck(midi2f(c["root"] + 19), 0.35, 0.12, 0.3), b * beat, gain=0.12)

    # ---- 琶音：16 分音符，低音量 + 左右交替 + 延迟抽头
    arp = np.zeros((n_loop + tail, 2))   # 多渲染尾巴，循环接缝处 arp 不会被硬切
    sixteenth = beat / 4.0
    pattern = [0, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 2, 0, 1, 2]
    for b in range(RUN_BEATS):
        c = chord_of(b // 4)
        triad = c["triad"]
        for k in range(16):
            idx = pattern[(b * 3 + k) % 16]
            m = triad[idx] + 12
            f = midi2f(m)
            vel = 0.55 + 0.45 * ((k % 4) == 0)
            if b % 4 == 3 and k >= 12:
                vel *= 0.6
            sig = pluck(f, 0.45, decay=0.13, bright=0.5) * vel
            s = int(round((b * beat + k * sixteenth) * SR))
            if s >= n_loop:
                continue
            mm = min(len(sig), len(arp) - s)
            pan = -0.35 if (b + k) % 2 == 0 else 0.35
            gl = math.cos((pan + 1) * math.pi / 4)
            gr = math.sin((pan + 1) * math.pi / 4)
            arp[s:s + mm, 0] += sig[:mm] * gl * 0.085
            arp[s:s + mm, 1] += sig[:mm] * gr * 0.085
    # 琶音延迟（3/16 拍），制造空间但不糊
    d = int(round(3 * sixteenth * SR))
    for ch in (0, 1):
        dry = arp[:, ch]
        out = dry.copy()
        for k in (1, 2, 3):
            g = 0.34 ** k
            out[k * d:] += dry[: len(arp) - k * d] * g
        arp[:, ch] = out
    trans += arp

    # ---- 轻噪 hi-hat：8 分音符，弱，左右交替
    for b in range(RUN_BEATS):
        for k in (0, 1):
            if (b + k) % 2 == 1 and b % 4 == 3:
                continue
            s = (b + 0.5 * k) * beat
            n = n_of(0.05)
            tt = t_of(n)
            h = bandpass(rng.standard_normal(n), 7200.0, 0.9)
            h /= peak(h) + 1e-12
            h *= np.exp(-tt / 0.012) * (1 - np.exp(-tt / 0.001))
            pan = 0.3 if k == 0 else -0.3
            add_st(trans, h, s, gain=0.10, pan=pan)

    # ---- 最后 1 小节的 riser + 琶音回转，让循环接回开头
    fill_start = 16 * bar
    nf = n_of(4 * bar)
    nz = rng.standard_normal(nf)
    riser = np.zeros(nf)
    tt = np.arange(nf) / max(nf - 1, 1)
    fc = 320.0 * (6000.0 / 320.0) ** tt
    for c in np.geomspace(200, 9000, 18):
        g = np.exp(-0.5 * (np.log2(c / fc) / 0.8) ** 2)
        riser += bandpass(nz, c, 0.8) * g
    riser /= peak(riser) + 1e-12
    # 包络在 92% 处达峰，最后 ~80ms 快速收束到 0：接回循环开头时噪声不会硬切
    up = np.clip(tt / 0.92, 0, 1) ** 2.0
    tail_duck = np.clip((1.0 - tt) / 0.06, 0, 1) ** 1.5
    riser *= up * tail_duck
    add_st(trans, riser, fill_start, gain=0.12, pan=0.0)
    for k in range(12):
        c = chord_of(16)
        f = midi2f(c["triad"][k % 3] + 12)
        add_st(trans, pluck(f, 0.4, 0.11, 0.5) * (1 - k / 14), fill_start + k * (beat / 3), gain=0.06)

    # ---- 瞬态层整体轻微混响
    for ch in (0, 1):
        ir = make_ir(1.9, 0.62, rng, lp=5200, predelay=0.015)
        wet = reverb_send(trans[:, ch], ir, ratio=0.22)
        trans[:, ch] = trans[:, ch] + wet

    mixed = cont + wrap_fold(trans, n_loop)
    return loop_seam_crossfade(mixed, cont, trans, n_loop, ms=3.0)


# --------------------------------------------------------------------------
# SFX
# --------------------------------------------------------------------------

def sfx_thrust(rng):
    dur = 1.2
    n = n_of(dur)
    t = t_of(n)
    out = np.zeros(n)
    # 所有分音频率 = k / 1.2s → 循环周期严格成立
    for k, a, ph in ((33, 1.00, 0.0), (40, 0.62, 1.1), (50, 0.46, 2.3), (66, 0.32, 0.4),
                     (100, 0.24, 1.9), (132, 0.15, 3.1), (170, 0.10, 0.7), (210, 0.06, 4.2)):
        out += a * np.sin(2.0 * np.pi * (k / dur) * t + ph)
    nz = rng.standard_normal(n)
    low = filt_circ(nz, hi=700, order=3)
    mid = filt_circ(nz, lo=450, hi=2600, order=2)
    out += 0.95 * low / (peak(low) + 1e-12) + 0.20 * mid / (peak(mid) + 1e-12)
    out *= 1.0 + 0.16 * np.sin(2.0 * np.pi * (3 / dur) * t) \
        + 0.08 * np.sin(2.0 * np.pi * (7 / dur) * t + 1.3)
    return sat(out * 0.85, 1.35)


def sfx_boost(rng):
    n = n_of(0.35)
    t = t_of(n)
    body = noise_sweep(n, 260, 5400, rng, bw=1.1)
    env = np.clip(t / 0.035, 0, 1) ** 1.3 * np.exp(-np.maximum(t - 0.035, 0) / 0.11)
    f = 68.0 * np.exp(-t / 0.05) + 92.0
    low = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.09)
    out = body * env * 0.9 + low * 0.5
    return sat(out * 1.2, 1.6)


def sfx_launch(rng):
    n = n_of(0.28)
    t = t_of(n)
    out = np.zeros(n)
    jet = noise_sweep(n, 3200, 380, rng, bw=1.2)
    out += jet * np.exp(-t / 0.05) * 0.9
    for f, a, d in ((1870, 0.45, 0.020), (2730, 0.32, 0.015), (3910, 0.24, 0.011),
                    (5430, 0.16, 0.008)):
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    f = 130.0 * np.exp(-t / 0.03) + 45.0
    out += 0.5 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.075)
    return sat(out * 1.15, 1.5)


def sfx_lock(rng):
    n = n_of(0.5)
    t = t_of(n)
    out = np.zeros(n)
    for start, f in ((0.015, 1568.0), (0.235, 2093.0)):
        s = int(start * SR)
        ln = n_of(0.075)
        tt = t_of(ln)
        f_t = f * (1.0 + 0.02 * np.exp(-tt / 0.008) - 0.035 * tt / 0.075)
        ph = 2 * np.pi * np.cumsum(f_t) / SR
        env = (1 - np.exp(-tt / 0.0018)) * np.exp(-tt / 0.032)
        sig = (np.sin(ph) + 0.30 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)) * env
        out[s:s + ln] += sig
    out += 0.05 * filt(rng.standard_normal(n), lo=900, hi=4200) * np.exp(-t / 0.35)
    return sat(out * 1.1, 1.4)


def sfx_pulse(rng):
    n = n_of(0.5)
    t = t_of(n)
    f = 155.0 * np.exp(-t / 0.08) + 38.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    sub = np.sin(ph) * np.exp(-t / 0.16) + 0.25 * np.sin(2 * ph) * np.exp(-t / 0.09)
    imp = filt(rng.standard_normal(n), hi=4200, order=2)
    imp = imp / (peak(imp) + 1e-12) * np.exp(-t / 0.012)
    tail = filt(rng.standard_normal(n), lo=70, hi=900, order=2)
    tail = tail / (peak(tail) + 1e-12) * np.exp(-t / 0.11)
    out = sub * 1.05 + 0.45 * imp + 0.30 * tail
    return sat(out * 1.05, 1.8)


def sfx_dash(rng):
    n = n_of(0.3)
    t = t_of(n)
    w = noise_sweep(n, 320, 5200, rng, bw=0.9)
    env = np.clip(t / 0.055, 0, 1) ** 1.6 * np.exp(-np.maximum(t - 0.055, 0) / 0.075)
    sub = thump(n, 120, 55, tau=0.14, tau_pitch=0.07, drive=1.2, harm2=0.1)
    out = w * env * 0.95 + sub * 0.22
    return sat(out * 1.1, 1.4)


def sfx_gravity(rng):
    n = n_of(0.6)
    t = t_of(n)
    f = 112.0 * np.exp(-t / 0.24) + 41.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    wob = 1.0 + 0.14 * np.sin(2 * np.pi * 9.0 * t + 2.4 * np.sin(2 * np.pi * 2.2 * t))
    sig = np.sin(ph) + 0.42 * np.sin(1.997 * ph + 0.8) + 0.30 * np.sin(0.5 * ph)
    env = (1 - np.exp(-t / 0.02)) * np.exp(-t / 0.42)
    nz = filt(rng.standard_normal(n), hi=300, order=2)
    nz = nz / (peak(nz) + 1e-12) * np.exp(-t / 0.3)
    out = sat(sig * env * wob * 0.85 + nz * 0.18, 1.3)
    return out


def sfx_hit(rng):
    n = n_of(0.25)
    t = t_of(n)
    out = np.zeros(n)
    # 玻璃裂响：高频噪声瞬态 + 几个不谐和共振
    hs = filt(rng.standard_normal(n), lo=2200, order=3)
    hs = hs / (peak(hs) + 1e-12) * np.exp(-t / 0.018)
    out += hs * 0.85
    for f, a, d in ((3180, 0.30, 0.045), (4720, 0.22, 0.032), (6110, 0.16, 0.024),
                    (8420, 0.10, 0.016)):
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    out += thump(n, 92, 62, tau=0.09, tau_pitch=0.05) * 0.22
    out += crackle(n, rng, 5, 0.0, 0.12, 2500, 9000, (0.004, 0.02)) * 0.5
    return sat(out * 1.15, 1.5)


def sfx_explosion_small(rng):
    n = n_of(0.6)
    t = t_of(n)
    boom = filt(rng.standard_normal(n), hi=2200, order=2)
    boom = boom / (peak(boom) + 1e-12) * np.exp(-t / 0.16)
    low = thump(n, 105, 38, tau=0.22, tau_pitch=0.08, drive=1.6)
    mid = bandpass(rng.standard_normal(n), 900, 1.6)
    mid = mid / (peak(mid) + 1e-12) * np.exp(-t / 0.09)
    cr = crackle(n, rng, 14, 0.02, 0.4, 1200, 9000, (0.006, 0.03))
    out = boom * 0.85 + low * 0.55 + mid * 0.22 + cr * 0.35
    return sat(out * 1.1, 1.6)


def sfx_explosion_big(rng):
    n = n_of(1.1)
    t = t_of(n)
    out = np.zeros(n)
    sub = thump(n, 78, 29, tau=0.55, tau_pitch=0.13, drive=1.8)
    out += sub * 0.85
    rumb = filt(rng.standard_normal(n), hi=380, order=3)
    rumb = rumb / (peak(rumb) + 1e-12) * np.exp(-t / 0.45)
    out += rumb * 0.7
    mid = bandpass(rng.standard_normal(n), 1400, 1.8)
    mid = mid / (peak(mid) + 1e-12) * np.exp(-t / 0.22)
    out += mid * 0.42
    crack = filt(rng.standard_normal(n), lo=1800, order=2)
    crack = crack / (peak(crack) + 1e-12) * np.exp(-t / 0.010)
    out += crack * 0.5
    out += crackle(n, rng, 46, 0.03, 0.9, 900, 10000, (0.006, 0.04)) * 0.5
    # 第二记较小的塌陷
    s2 = int(0.19 * SR)
    sub2 = thump(n_of(0.5), 62, 32, tau=0.3, tau_pitch=0.09, drive=1.6) * 0.32
    out[s2:s2 + len(sub2)] += sub2[: n - s2]
    out *= 1 - 0.15 * np.exp(-t / 0.5)
    return sat(out * 1.05, 1.7)


def sfx_missile_hit(rng):
    n = n_of(0.5)
    t = t_of(n)
    out = np.zeros(n)
    out += metal_ring(n, t, (523, 811, 1247, 1890, 2710, 3610), decay=0.16, rng=rng) * 0.55
    heavy = thump(n, 130, 55, tau=0.13, tau_pitch=0.05, drive=1.7)
    out += heavy * 0.55
    # 电流尾：带通噪声 + 100Hz 方波调幅
    buzz = bandpass(rng.standard_normal(n), 3200, 1.2)
    buzz /= peak(buzz) + 1e-12
    am = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 100.0 * t))
    out += buzz * am * np.exp(-t / 0.12) * 0.28
    out += crackle(n, rng, 8, 0.0, 0.2, 2000, 9000, (0.004, 0.02)) * 0.35
    return sat(out * 1.1, 1.5)


def sfx_meteor(rng):
    n = n_of(0.3)
    t = t_of(n)
    out = np.zeros(n)
    crk = bandpass(rng.standard_normal(n), 2600, 1.0)
    crk = crk / (peak(crk) + 1e-12) * np.exp(-t / 0.028)
    out += crk * 0.8
    out += thump(n, 120, 60, tau=0.1, tau_pitch=0.05) * 0.5
    out += crackle(n, rng, 12, 0.0, 0.25, 900, 9000, (0.004, 0.025)) * 0.45
    return sat(out * 1.1, 1.5)


def sfx_pickup(rng):
    n = n_of(0.12)
    t = t_of(n)
    f = 1320.0
    sig = (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t)
           + 0.18 * np.sin(2 * np.pi * f * 1.5 * t))
    env = (1 - np.exp(-t / 0.0018)) * np.exp(-t / 0.045)
    click = filt(rng.standard_normal(n), lo=3000, order=2) * np.exp(-t / 0.004)
    click /= peak(click) + 1e-12
    return sig * env * 0.9 + click * 0.12


def sfx_upgrade(rng):
    n = n_of(0.8)
    out = np.zeros(n)
    for i, m in enumerate((72, 76, 79, 84)):
        f = midi2f(m)
        start = int(0.0 + i * 0.13 * SR)
        seg = fm_bell(f, 0.55, index=1.9, ratio=2.0, decay=0.30, rng=rng) * 0.55
        p = pluck(f, 0.55, 0.18, 0.35) * 0.35
        p = np.pad(p, (0, max(0, len(seg) - len(p))))[: len(seg)]
        seg = seg + p
        m2 = min(len(seg), n - start)
        out[start:start + m2] += seg[:m2]
    shimmer = noise_sweep(n, 2000, 7000, rng, bw=1.3)
    out += shimmer * np.linspace(0, 1, n) ** 3 * 0.10
    return rev_mono(out, ratio=0.3, decay=0.35, rng=rng)


def sfx_token(rng):
    n = n_of(0.2)
    out = np.zeros(n)
    for start, f, ln in ((0.0, 1046.5, 0.055), (0.055, 1568.0, 0.13)):
        s = int(start * SR)
        m = n_of(ln)
        tt = t_of(m)
        sig = (np.sin(2 * np.pi * f * tt) + 0.42 * np.sin(2 * np.pi * 2.01 * f * tt)
               + 0.22 * np.sin(2 * np.pi * 3.02 * f * tt) + 0.10 * np.sin(2 * np.pi * 4.1 * f * tt))
        env = (1 - np.exp(-tt / 0.0015)) * np.exp(-tt / (0.035 if start == 0 else 0.07))
        out[s:s + m] += sig * env
    return sat(out * 1.1, 1.3)


def sfx_safezone(rng):
    n = n_of(0.9)
    t = t_of(n)
    out = np.zeros(n)
    for i, m in enumerate((57, 61, 64, 69, 76)):
        f = midi2f(m)
        for det in (-4.0, 4.0):
            fd = f * 2 ** (det / 1200.0)
            out += np.sin(2 * np.pi * fd * t + i * 0.9 + det * 0.1) * (0.5 if m < 70 else 0.28)
            out += 0.18 * np.sin(2 * np.pi * 2 * fd * t + i) * np.exp(-t / 0.5)
    env = (1 - np.exp(-t / 0.09)) * np.exp(-t / 0.5)
    out *= env
    out += 0.06 * noise_sweep(n, 800, 4000, rng, bw=1.4) * np.exp(-t / 0.25)
    return rev_mono(out * 0.9, ratio=0.45, decay=0.45, rng=rng, lp=4000)


def sfx_ui_hover(rng):
    n = n_of(0.08)
    t = t_of(n)
    f = 760.0 + 620.0 * (t / t[-1]) ** 0.7
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.03)
    out = (np.sin(ph) + 0.22 * np.sin(2 * ph)) * env
    nz = filt(rng.standard_normal(n), lo=3000, order=2) * np.exp(-t / 0.01)
    out += 0.10 * nz / (peak(nz) + 1e-12)
    return sat(out * 1.0, 1.2)


def sfx_ui_click(rng):
    n = n_of(0.1)
    t = t_of(n)
    nz = filt(rng.standard_normal(n), lo=1800, order=2) * np.exp(-t / 0.006)
    nz /= peak(nz) + 1e-12
    f_t = 1900.0 * np.exp(-t / 0.012) + 700.0
    ph = 2 * np.pi * np.cumsum(f_t) / SR
    tone = np.sin(ph) * np.exp(-t / 0.022)
    out = nz * 0.5 + tone * 0.6
    return sat(out * 1.1, 1.3)


def sfx_alarm(rng):
    n = n_of(0.7)
    t = t_of(n)
    out = np.zeros(n)
    # 两声交替警报音
    for i, (start, f) in enumerate(((0.02, 880.0), (0.24, 660.0), (0.46, 880.0))):
        s = int(start * SR)
        ln = n_of(0.15)
        tt = t_of(ln)
        ph = 2 * np.pi * f * tt
        sig = (np.sin(ph) + 0.34 * np.sin(3 * ph) + 0.16 * np.sin(5 * ph))
        env = (1 - np.exp(-tt / 0.006)) * np.exp(-tt / 0.09) * (0.8 if i == 1 else 1.0)
        out[s:s + ln] += filt(sig * env, hi=5200, order=2)
    out += 0.10 * np.sin(2 * np.pi * 220.0 * t) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 3.4 * t)))
    out *= (1 - np.exp(-t / 0.01)) * np.exp(-t / 0.55)
    return sat(out * 1.1, 1.4)


def sfx_gameover(rng):
    n = n_of(1.6)
    t = t_of(n)
    out = np.zeros(n)
    # 下行长音：三个八度下沉的锯齿 + 失谐 + 低通渐暗
    f = 330.0 * np.exp(-t / 0.75) + 96.0
    ph = 2 * np.pi * np.cumsum(f) / SR
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.2 * t)
    saw = np.sin(ph * vib) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph) + 0.18 * np.sin(4 * ph)
    saw = filt(saw, hi=1400, order=2)
    env = (1 - np.exp(-t / 0.06)) * np.exp(-t / 0.8)
    out += saw * env * 0.7
    # 小调和弦下沉 pad
    for m, a in ((45, 0.5), (48, 0.4), (52, 0.3), (57, 0.18)):
        f2 = midi2f(m) * (1 - 0.04 * (t / 1.6))
        out += np.sin(2 * np.pi * f2 * t + m * 0.3) * a * env * 0.5
    out += 0.10 * noise_sweep(n, 3000, 300, rng, bw=1.5) * env
    return rev_mono(out, ratio=0.4, decay=0.7, rng=rng, lp=4200)


def sfx_warp(rng):
    n = n_of(1.2)
    t = t_of(n)
    out = np.zeros(n)
    # 上升气声
    up = noise_sweep(n, 300, 8200, rng, bw=1.0)
    up_env = np.clip(t / 0.85, 0, 1) ** 2.0
    out += up * up_env * 0.55
    # 上行失谐锯齿和弦
    for m, a in ((45, 0.5), (52, 0.35), (57, 0.28), (60, 0.2)):
        f0 = midi2f(m)
        f = f0 * 2.0 ** (1.6 * np.clip(t / 0.85, 0, 1))
        ph = 2 * np.pi * np.cumsum(f) / SR
        out += a * (np.sin(ph) + 0.45 * np.sin(2.01 * ph)) * np.clip(t / 0.9, 0, 1) ** 1.4
    # 到达瞬间的冲击
    imp = int(0.86 * SR)
    hit = thump(n_of(0.35), 120, 40, tau=0.16, tau_pitch=0.06) * 0.5
    mic = min(len(hit), n - imp)
    out[imp:imp + mic] += hit[:mic]
    # 尾部收束
    out *= np.exp(-np.maximum(t - 0.95, 0) / 0.18)
    out += 0.08 * noise_sweep(n, 6000, 1200, rng, bw=1.6) * np.exp(-np.maximum(t - 0.9, 0) / 0.2)
    return rev_mono(sat(out, 1.3), ratio=0.35, decay=0.5, rng=rng, lp=5000)


# 文件名 / 规格时长 / 峰值目标 dBFS / 随机种子 / 生成函数 / 说明
SFX_CATALOG = [
    ("sfx_thrust.wav", 1.2, -6.0, 4101, sfx_thrust,
     "推进器循环轰鸣：以 1/1.2s 整数倍分音为骨架 + 循环成形噪声，缓慢颤动（loop）"),
    ("sfx_boost.wav", 0.35, -3.0, 4102, sfx_boost,
     "加力点火：噪声带通 260→5.4kHz 上扬 + 低频点火推力 + 软饱和"),
    ("sfx_launch.wav", 0.28, -2.5, 4103, sfx_launch,
     "导弹发射：3.2k→380Hz 短气声 + 四段金属瞬态 + 45Hz 推力"),
    ("sfx_lock.wav", 0.5, -4.0, 4104, sfx_lock,
     "锁定警报：1568/2093Hz 两声短哔，1/3/5 次谐波 + 2% 下滑 + 极轻底噪"),
    ("sfx_pulse.wav", 0.5, -1.5, 4105, sfx_pulse,
     "脉冲：155→38Hz 指数扫频 + 4.2kHz 低通冲击瞬态 + 带通余震尾 + 饱和"),
    ("sfx_dash.wav", 0.3, -3.5, 4106, sfx_dash,
     "相位滑行：320→5.2kHz 快速 whoosh + 120→55Hz 低频推力"),
    ("sfx_gravity.wav", 0.6, -3.5, 4107, sfx_gravity,
     "引力锚展开：112→41Hz 下沉双失谐正弦 + 9Hz 颤动 + 低频噪声"),
    ("sfx_hit.wav", 0.25, -3.0, 4108, sfx_hit,
     "护盾受击：2.2kHz 高通碎裂瞬态 + 四个不谐和玻璃共振 + 低冲击 + 碎屑"),
    ("sfx_explosion_small.wav", 0.6, -2.0, 4109, sfx_explosion_small,
     "小爆炸：2.2kHz 低通噪声爆 + 105→38Hz thump + 中频碎片 + 颗粒"),
    ("sfx_explosion_big.wav", 1.1, -1.5, 4110, sfx_explosion_big,
     "大爆炸：78→29Hz 低频冲击 + 380Hz 隆隆 + 1.4kHz 中频 + 46 颗碎屑 + 二次塌陷"),
    ("sfx_missile_hit.wav", 0.5, -1.8, 4111, sfx_missile_hit,
     "导弹撞炮塔：六个不谐和金属分音 + 130→55Hz 重击 + 100Hz 方波调幅电流尾"),
    ("sfx_meteor.wav", 0.3, -2.8, 4112, sfx_meteor,
     "陨石碎裂：2.6kHz 带通岩石爆裂 + 120→60Hz 冲击 + 12 颗碎屑"),
    ("sfx_pickup.wav", 0.12, -6.0, 4113, sfx_pickup,
     "拾取物质：1320Hz 钟形双分音 + 3kHz 微小点击，便于连续叠放"),
    ("sfx_upgrade.wav", 0.8, -4.0, 4114, sfx_upgrade,
     "升级：C5-E5-G5-C6 四音上行 FM 钟 + 高频微光 + 短混响"),
    ("sfx_token.wav", 0.2, -6.0, 4115, sfx_token,
     "获得代币：1046Hz→1568Hz 两段硬币叮，含 4 个金属分音"),
    ("sfx_safezone.wav", 0.9, -5.0, 4116, sfx_safezone,
     "进入安全区：A 大三和弦五声部（失谐立体化）+ 柔和起音 + 气声 + 混响"),
    ("sfx_ui_hover.wav", 0.08, -12.0, 4117, sfx_ui_hover,
     "悬停：760→1380Hz 短滑音 + 3kHz 气声，极轻"),
    ("sfx_ui_click.wav", 0.1, -10.0, 4118, sfx_ui_click,
     "点击：1.8kHz 高通点击瞬态 + 1900→700Hz 下滑音"),
    ("sfx_alarm.wav", 0.7, -4.5, 4119, sfx_alarm,
     "低燃料/护盾警报：880/660Hz 三声交替警示（奇次谐波）+ 220Hz 脉动底"),
    ("sfx_gameover.wav", 1.6, -3.0, 4120, sfx_gameover,
     "游戏结束：330→96Hz 下行锯齿（带颤音 + 低通渐暗）+ 小调和弦下沉 + 混响"),
    ("sfx_warp.wav", 1.2, -2.0, 4121, sfx_warp,
     "跃迁：300→8.2kHz 上升气声 + 失谐和弦上行 + 0.86s 冲击 + 收束尾"),
]


# --------------------------------------------------------------------------
# 写出与自检
# --------------------------------------------------------------------------

def to_int16(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")


def write_wav(path: str, data: np.ndarray, channels: int) -> None:
    if channels == 1:
        flat = data if data.ndim == 1 else data[:, 0]
    else:
        flat = data.reshape(-1)
    pcm = to_int16(flat)
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


SPEC = {  # 文件名 -> (时长, 说明)
    "bgm_menu.wav": (MENU_LOOP, "菜单：深空 pad + 稀疏钟声 + 极轻脉冲，BPM 60"),
    "bgm_run.wav": (RUN_LOOP, "游戏：低频脉冲 + 琶音 + 轻噪，BPM 84"),
}


def read_wav(path: str):
    with wave.open(path, "rb") as w:
        nch, sw, sr, nf = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(nf)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if nch == 2:
        x = x.reshape(-1, 2)
    return x, nch, sw, sr, nf


def seam_metrics(x: np.ndarray) -> dict:
    """接缝连续性指标。

    * d2  ：接缝处的二阶差分 |(x[1]-x[0]) - (x[-1]-x[-2])|，再除以文件内部二阶
            差分的 95 分位。<=1 表示接缝处的曲线弯曲程度没有超出文件自身范围，
            即波形/斜率都是连续的（不会有咔哒声）。
    * jump：首尾样本直接相减，仅作参考——它同时包含信号本身的正常步进。
    """
    x = x if x.ndim == 1 else x[:, 0]
    d = np.diff(x)
    typ = float(np.median(np.abs(d))) + 1e-12
    d2 = np.abs(np.diff(x, 2))
    p95_d2 = float(np.percentile(d2, 95)) + 1e-12
    d2_ratio = float(abs((x[1] - x[0]) - (x[-1] - x[-2]))) / p95_d2
    jump = float(abs(x[0] - x[-1]))
    slope_jump = float(abs((x[0] - x[-1]) - (x[-1] - x[-2])))
    k = max(1, int(0.02 * SR))
    pre = rms(x[-k:])
    post = rms(x[:k])
    # 文件内部 20ms 窗口 RMS 的正常波动范围（用于判断接缝的能量跳变是否异常）
    nwin = len(x) // k
    win = np.sqrt(np.mean(np.square(x[: nwin * k]).reshape(nwin, k), axis=1))
    wdb = 20.0 * np.log10(np.maximum(win, 1e-9))
    diffs = np.abs(np.diff(wdb))
    p95 = float(np.percentile(diffs, 95)) + 1e-9
    seam_db = abs(db(post) - db(pre))
    return dict(jump=jump, typ=typ, ratio=jump / typ, slope=slope_jump / typ,
                p95_d2=p95_d2, d2=d2_ratio,
                rms_pre=pre, rms_post=post, db_diff=db(post) - db(pre),
                seam_db=seam_db, p95=p95, env_ratio=seam_db / p95)


def spectral_centroid(x: np.ndarray) -> float:
    x = x if x.ndim == 1 else x.mean(axis=1)
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    s = float(np.sum(X))
    return float(np.sum(f * X) / s) if s > 1e-12 else 0.0


def analyze(path: str) -> dict:
    x, nch, sw, sr, nf = read_wav(path)
    dur = nf / sr
    p = peak(x)
    r = rms(x)
    mono = x if nch == 1 else x.mean(axis=1)
    dc = float(np.max(np.abs(mono.mean())))
    nan = bool(np.any(~np.isfinite(x)))
    clip = int(np.count_nonzero(np.abs(x) >= 32767.0 / 32768.0))
    k5 = max(1, int(round(0.005 * sr)))
    head = float(np.max(np.abs(mono[:k5])))
    tail = float(np.max(np.abs(mono[-k5:])))
    # 结尾静音长度（相对峰值 -80dB）
    thr = p * 1e-4
    nz = np.nonzero(np.abs(mono) > thr)[0]
    silent_tail = float((nf - 1 - nz[-1]) / sr) if len(nz) else dur
    corr = None
    if nch == 2:
        a, b = x[:, 0], x[:, 1]
        if rms(a) > 1e-9 and rms(b) > 1e-9:
            c = float(np.corrcoef(a, b)[0, 1])
            corr = c
    return dict(path=path, dur=dur, nch=nch, sw=sw, sr=sr, nf=nf,
                peak=p, peak_db=db(p), rms=r, rms_db=db(r), crest=db(p) - db(r),
                dc=dc, nan=nan, clip=clip, head=head, tail=tail,
                silent_tail=silent_tail, corr=corr, centroid=spectral_centroid(mono),
                size=os.path.getsize(path), seam=seam_metrics(x))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-report", action="store_true")
    args = ap.parse_args()

    os.makedirs(AUDIO_DIR, exist_ok=True)
    t0 = __import__("time").time()

    # ---- BGM
    print("[gen] bgm_menu.wav ...")
    menu = build_menu()
    menu = norm_peak(menu, -3.5)
    write_wav(os.path.join(AUDIO_DIR, "bgm_menu.wav"), menu, 2)

    print("[gen] bgm_run.wav ...")
    run = build_run()
    run = norm_peak(run, -3.5)
    write_wav(os.path.join(AUDIO_DIR, "bgm_run.wav"), run, 2)

    # ---- SFX
    for name, dur, target, seed, fn, note in SFX_CATALOG:
        rng = np.random.default_rng(seed)
        x = fn(rng)
        want = n_of(dur)
        if len(x) < want:
            x = np.concatenate([x, np.zeros(want - len(x))])
        x = x[:want]
        if not np.all(np.isfinite(x)):
            raise RuntimeError(f"{name}: non-finite samples")
        x = dc_block(x)
        x = fade_ends(x, 5.0)      # 清单要求：首尾各 5ms 淡入淡出
        x = dc_block_bias(x, 5.0)  # 淡变会引入微小直流偏置，这里补掉
        x = norm_peak(x, target)   # 淡变之后再归一化，峰值精确落在目标
        write_wav(os.path.join(AUDIO_DIR, name), x, 1)
        print(f"[gen] {name}")

    # ---- 校验
    names = ["bgm_menu.wav", "bgm_run.wav"] + [c[0] for c in SFX_CATALOG]
    rows = []
    for n in names:
        rows.append(analyze(os.path.join(AUDIO_DIR, n)))

    hdr = ("file", "dur", "spec", "dev", "ch", "sr", "peak", "rms", "crest",
           "dc", "head", "tail")
    print("\n{:<26}{:>7}{:>7}{:>7}{:>3}{:>7}{:>8}{:>7}{:>7}{:>8}{:>8}{:>8}".format(*hdr))
    for r in rows:
        base = os.path.basename(r["path"])
        spec = SPEC.get(base, ((r["dur"]), ""))[0] if base in SPEC else \
            next(c[1] for c in SFX_CATALOG if c[0] == base)
        dev = (r["dur"] / spec - 1.0) * 100.0
        print("{:<26}{:7.3f}{:7.3f}{:6.1f}%{:>3}{:>7}{:8.2f}{:7.2f}{:7.2f}{:8.5f}{:8.5f}{:8.5f}".format(
            base, r["dur"], spec, dev, r["nch"], r["sr"], r["peak_db"], r["rms_db"],
            r["crest"], r["dc"], r["head"], r["tail"]))

    # ---- 断言：规格
    problems = []
    for r in rows:
        base = os.path.basename(r["path"])
        is_bgm = base.startswith("bgm_")
        spec = SPEC[base][0] if base in SPEC else next(c[1] for c in SFX_CATALOG if c[0] == base)
        if abs(r["dur"] / spec - 1.0) > 0.20:
            problems.append(f"{base}: 时长偏差 {100*(r['dur']/spec-1):.1f}%")
        if r["sr"] != SR:
            problems.append(f"{base}: 采样率 {r['sr']}")
        if r["nch"] != (2 if is_bgm else 1):
            problems.append(f"{base}: 声道 {r['nch']}")
        lim = -3.0 if is_bgm else -1.0
        if r["peak_db"] > lim:
            problems.append(f"{base}: 峰值 {r['peak_db']:.2f}dBFS > {lim}")
        if r["clip"]:
            problems.append(f"{base}: 削波样本 {r['clip']}")
        if r["nan"]:
            problems.append(f"{base}: 含 NaN/Inf")
        if r["dc"] > 1e-3:
            problems.append(f"{base}: DC 偏移 {r['dc']:.4f}")

    print("\n[check] 累计生成 %.1fs" % (__import__("time").time() - t0))
    print("[check] 文件数 %d，总大小 %.2f MB" % (
        len(rows), sum(r["size"] for r in rows) / 1048576.0))
    if problems:
        print("[check] 问题:")
        for p in problems:
            print("  -", p)
        return 1
    print("[check] 全部规格项通过（时长/声道/采样率/峰值/无削波/无 NaN）")

    # ---- 接缝报告
    print("\n[loop] 接缝连续性（首尾差 / 文件内典型相邻差）:")
    for base in ("bgm_menu.wav", "bgm_run.wav", "sfx_thrust.wav"):
        r = next(r for r in rows if os.path.basename(r["path"]) == base)
        s = r["seam"]
        print("  {:<16} 接缝二阶差分/文件 p95={:5.2f}  首尾 20ms 能量差={:+.2f} dB"
              "  (文件内 20ms 窗口跳变 p95={:4.2f} dB, 比值={:4.2f})".format(
                  base, s["d2"], s["db_diff"], s["p95"], s["env_ratio"]))

    if not args.no_report:
        write_report(rows)
        print("[report] ->", REPORT_PATH)
    return 0


def write_report(rows) -> None:
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    total = sum(r["size"] for r in rows) / 1048576.0
    L = []
    L.append("# 音频资产报告 — Escape Gravity\n")
    L.append("由 `tools/gen_audio.py` 生成并自动核对（脚本重跑即复现）。\n")
    L.append("## 1. 概览\n")
    L.append(f"- 采样格式：16-bit PCM WAV / 44.1 kHz；BGM 立体声、SFX 单声道")
    L.append(f"- 文件数：{len(rows)}；总大小：{total:.2f} MiB")
    L.append("- 失真/削波：全文件无 NaN、无 ±32767 削波样本；峰值由脚本归一化控制")
    L.append("- 电平上限：BGM ≤ -3 dBFS，SFX ≤ -1 dBFS（实测见下表）\n")

    L.append("## 2. 格式与电平核对\n")
    L.append("| 文件 | 规格时长 | 实测时长 | 偏差 | 声道 | 采样率 | 峰值 dBFS | RMS dBFS | 峰均比 | DC 偏移 | 首 5ms | 尾 5ms |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        base = os.path.basename(r["path"])
        if base in SPEC:
            spec = SPEC[base][0]
        else:
            spec = next(c[1] for c in SFX_CATALOG if c[0] == base)
        dev = (r["dur"] / spec - 1.0) * 100.0
        L.append("| `{}` | {:.3f}s | {:.3f}s | {:+.1f}% | {} | {} | {:.2f} | {:.2f} | {:.1f} dB | {:.6f} | {:.5f} | {:.5f} |".format(
            base, spec, r["dur"], dev, r["nch"], r["sr"], r["peak_db"], r["rms_db"],
            r["crest"], r["dc"], r["head"], r["tail"]))
    L.append("")

    L.append("## 3. 循环接缝自检\n")
    L.append("判据：接缝处的样本跳变与斜率跳变，和文件内部「典型相邻样本差」（中位数）比较。"
             "比值接近 1 说明接缝与普通采样点无异；若为数十倍以上则会有咔哒声。\n")
    L.append("| 文件 | 接缝二阶差分 / 文件内 p95 | 首尾 20ms 能量差 | 文件内 20ms 窗口跳变 p95 | 能量比值 | 结论 |")
    L.append("|---|---|---|---|---|---|")
    for base in ("bgm_menu.wav", "bgm_run.wav", "sfx_thrust.wav"):
        r = next(r for r in rows if os.path.basename(r["path"]) == base)
        s = r["seam"]
        ok = "连续（可无缝循环）" if (s["d2"] <= 1.0 and s["env_ratio"] < 1.5) else "需复查"
        L.append("| `{}` | {:.2f} | {:+.2f} dB | {:.2f} dB | {:.2f} | {} |".format(
            base, s["d2"], s["db_diff"], s["p95"], s["env_ratio"], ok))
    L.append("")
    L.append("说明：BGM 的连续层（drone、噪声床）所有频率与 LFO 都是 1/循环长度 的整数倍，"
             "瞬态层多渲染 3–4s 尾巴后环绕折叠回开头，再在接缝处做 3ms 等幅交叉淡化；"
             "因此接缝处的波形、斜率、包络与混响尾都是连续的。"
             "「接缝二阶差分 / 文件内 p95」小于 1 表示接缝的曲线弯曲没有超出文件自身范围。"
             "`sfx_thrust.wav` 的分音全部为 1/1.2s 的整数倍、噪声用循环 FFT 成形，"
             "按清单要求仍加了首尾 5ms 淡变（循环点两侧同为零幅度，故无咔哒，只有约 10ms 的轻微起伏）。\n")

    L.append("## 4. 频谱 / 音色自检\n")
    L.append("| 文件 | 频谱重心 | L/R 相关 | 结尾静音 | 备注 |")
    L.append("|---|---|---|---|---|")
    for r in rows:
        base = os.path.basename(r["path"])
        corr = "—" if r["corr"] is None else "{:.2f}".format(r["corr"])
        note = SPEC[base][1] if base in SPEC else ""
        L.append("| `{}` | {:.0f} Hz | {} | {:.3f}s | {} |".format(
            base, r["centroid"], corr, r["silent_tail"], note))
    L.append("")
    L.append("两首 BGM 的 L/R 相关系数明显小于 1（0.7–0.9 之间为正常的轻度声场宽度），"
             "SFX 单声道无此列。所有 SFX 结尾静音 < 6ms，没有拖长的空尾巴。\n")

    L.append("## 5. 设计说明\n")
    L.append("| 文件 | 设计 |")
    L.append("|---|---|")
    for name, dur, target, seed, fn, note in SFX_CATALOG:
        L.append("| `{}` | {} |".format(name, note))
    L.append("")
    L.append("音乐：\n")
    L.append("- `bgm_menu.wav`：60 BPM、40 拍（= 40.0s，整数小节）。A 小调深空 pad 每 8 拍换和弦"
             "（Am→Fmaj7→Cmaj7→Dm→Em→Am），全部由加法合成谐波随缓慢「亮度」信号开合；"
             "五声音阶稀疏 FM 钟声左右交替、3.6s 衰减；每小节一次 52→38Hz 极轻脉冲；"
             "27.5–110Hz 的 A1 drone 与粉噪铺底构成底噪。无鼓。")
    L.append("- `bgm_run.wav`：84 BPM、17 小节 = 68 拍 = 48.571s（每分钟 31500 样本/拍，整数采样）。"
             "每 4 小节换和弦（Am→F→C→G→Am），第 17 小节是 riser + 琶音回转，直接接回开头。"
             "元素：低频脉冲（96→41Hz，1/3 拍重、反拍幽灵）、滤波贝斯根音、"
             "16 分琶音（左右交替 + 3/16 拍延迟抽头，音量压得很低避免旋律疲劳）、"
             "8 分轻噪 hat、暗色 pad 与低频 drone。混响较干，保持推进感不吵。\n")

    L.append("## 6. 已知不足\n")
    L.append("1. 无法试听，只能靠波形/频谱/接缝指标与合成参数自检；音色的主观平衡（如 pad 与钟声的相对比例）"
             "未经人耳确认，必要时可调整 `tools/gen_audio.py` 中的 gain 系数重跑。")
    L.append("2. `sfx_thrust.wav` 为满足「SFX 首尾 5ms 淡变」，循环点处有约 10ms 的幅度起伏；"
             "若引擎对 loop 做交叉淡化可完全消除，否则这 10ms 会是极轻微的脉动。")
    L.append("3. BGM 采用「整数周期 + 环绕折叠」实现无缝，未做逐采样级交叉淡化；"
             "接缝指标显示连续，但极端情况下（引擎对 loop 起点做硬切换）仍建议开启引擎侧淡入淡出。")
    L.append("4. 混响为指数衰减噪声 IR + 稀疏早期反射的简化算法，尾音密度不如真实卷积混响，"
             "深空感足够但不适合近距离大场景。")
    L.append("5. SFX 均为单声道、未做多普勒或距离衰减，这些应在引擎侧根据相对速度处理。")
    L.append("")
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


if __name__ == "__main__":
    sys.exit(main())
