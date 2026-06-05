%% optimized_single_pixel_polarization_reconstruction.m
% =========================================================================
% 功能：
%   1) 从 TDC 二进制时间戳文件中读取 DMD 触发与 SPAD 光子事件；
%   2) 根据相邻 DMD 触发之间的 SPAD 事件数，得到每张掩膜对应的光子计数序列 y；
%   3) 对 6 个偏振测量通道分别重建强度图：I0, I45, I90, I135, IR, IL；
%   4) 由重建后的强度图计算 Stokes 图像：S0, S1, S2, S3；
%   5) 计算并保存 DOP, DOLP, DOCP, AOP 图像；
%   6) 可选：对原始测量序列先计算 DOP/AOP/DOCP 序列再直接重建，用于对照分析。
%
% 推荐路线：
%   原始光子计数序列 -> 分别重建 I0/I45/I90/I135/IR/IL -> 计算 Stokes 图 -> 计算 DOP/AOP/DOCP 图。
%
% 注意：
%   AOP/DOP/DOCP 是非线性量，默认不建议直接用原始测量序列先计算再重建。
%   直接序列法只适合做对照，不建议作为最终论文主结果。
%
% 依赖：
%   1) TVAL3 函数及其路径；
%   2) MATLAB Image Processing Toolbox，主要用于 imwrite、mat2gray、padarray 等；
%   3) TDC 数据格式应与原代码一致：uint64 中高位存通道号，低位存时间戳。
%
% 作者建议：
%   使用前请重点修改“用户参数区”。
% =========================================================================

clear; clc; close all;

%% ========================= 0. 添加 TVAL3 算法路径：必须根据电脑位置修改 =========================
% 【必须修改】这里填写“包含 TVAL3.m 的文件夹路径”，不是 TVAL3.m 文件本身。
% 例如，如果 TVAL3.m 位于：
%   C:\Users\pc\Desktop\Stocks_code\TVAL3\TVAL3.m
% 那么这里就写：
%   "C:\Users\pc\Desktop\Stocks_code\TVAL3"

cfg.TVAL3_path = "F:\code\stocks_two\TVAL3_v1.0";   % 【必须修改】TVAL3 文件夹路径

% 将 TVAL3 主文件夹及其所有子文件夹加入 MATLAB 搜索路径。
addpath(genpath(cfg.TVAL3_path));

% 检查 MATLAB 是否已经能够找到 TVAL3.m。
% 如果这里报错，说明 cfg.TVAL3_path 填错了，或者该文件夹里没有 TVAL3.m。
if exist('TVAL3', 'file') ~= 2
    error("没有找到 TVAL3.m，请检查 cfg.TVAL3_path 是否正确：%s", cfg.TVAL3_path);
else
    fprintf("TVAL3 路径加载成功：%s\n", which('TVAL3'));
end

%% ========================= 0. 用户参数区：必须根据实验修改 =========================

% ---------- 0.1 TDC 通道设置 ----------
% 与你原代码一致：DMD 触发通道为 5，SPAD 光子通道为 6。
cfg.DMD_CH  = 5;       % 【需要确认】DMD 触发信号所在 TDC 通道
cfg.SPAD_CH = 6;       % 【需要确认】SPAD 光子事件所在 TDC 通道

% ---------- 0.2 单像素重建尺寸与掩膜数 ----------
cfg.imgH = 256;        % 【需要修改】重建图像高度
cfg.imgW = 256;        % 【需要修改】重建图像宽度
cfg.masksPerFrame = 2621;  % 【需要修改】每张图使用的掩膜数量 m

% ---------- 0.3 起始帧/无效掩膜设置 ----------
% 如果 DMD 播放前有黑场、白场、预热帧、同步帧，需要跳过。
% 例如：正式 Hadamard 掩膜前有 2 张无效帧，则设为 2。
cfg.skipMasks = 0;     % 【强烈建议检查】跳过正式重建前的 DMD 周期数量

% 如果每个 DMD 周期中存在多余的固定事件，或者 diff(DMD_mark)-1 后仍偏大，可在这里修正。
% 一般情况下保持为 0。
cfg.countOffset = 0;   % 【通常不用改】每个掩膜计数的额外修正量

% ---------- 0.4 是否进行暗计数/背景扣除 ----------
% 如果有暗场数据或黑场数据，建议设置为 true 并提供 darkCounts。
% 这里默认 false。
cfg.enableDarkCorrection = false;
cfg.darkCountPerMask = 0;   % 每张掩膜平均暗计数；没有就保持 0

% ---------- 0.5 测量矩阵路径 ----------
% A 的尺寸应为：masksPerFrame × (imgH*imgW)
% 例如：2621 × 65536。
cfg.A_path = "F:\code\stocks_two\rate_0p0400\A_01.csv";  % 【必须修改】测量矩阵 CSV 路径

% ---------- 0.6 输出文件夹 ----------
cfg.outDir = "F:\code\stocks_two\result\019_FUTONG";  % 【必须修改】输出目录
if ~exist(cfg.outDir, 'dir')
    mkdir(cfg.outDir);
end

% ---------- 0.7 六个偏振态数据文件路径 ----------
% 每个偏振态可以对应 1 个或多个 bin 文件。
% 如果某个偏振态由两个 bin 文件拼接而来，就写成 ["file1.bin", "file2.bin"]。
%
% 线偏振：
%   I0   : 0° 分析器下的强度
%   I45  : 45° 分析器下的强度
%   I90  : 90° 分析器下的强度
%   I135 : 135° 分析器下的强度
%
% 圆偏振：
%   IR   : 右旋圆偏振分析得到的强度
%   IL   : 左旋圆偏振分析得到的强度
%
% 重要：六组数据必须使用完全相同的 DMD 掩膜顺序，且必须与 A_path 的行顺序一致。
dataFiles.I0   = "F:\code\stocks_two\PET_futongege\I0_002.bin";      % 【必须修改】0° 数据
dataFiles.I45  = "F:\code\stocks_two\PET_futongege\I45_002.bin";     % 【必须修改】45° 数据
dataFiles.I90  = "F:\code\stocks_two\PET_futongege\I90_002.bin";     % 【必须修改】90° 数据
dataFiles.I135 = "F:\code\stocks_two\PET_futongege\I135_002.bin";    % 【必须修改】135° 数据
dataFiles.IR   = "F:\code\stocks_two\PET_futongege\IR_002.bin";      % 【必须修改】右旋圆偏振数据
dataFiles.IL   = "F:\code\stocks_two\PET_futongege\IL_002.bin";      % 【必须修改】左旋圆偏振数据

% ---------- 0.8 S3 符号约定 ----------
% 常见定义之一：S3 = IR - IL。
% 有些仪器或论文使用相反定义：S3 = IL - IR。
% 如果你发现 DOCP 正负号与理论相反，修改此参数即可。
cfg.S3Convention = "IR_minus_IL";  % 可选："IR_minus_IL" 或 "IL_minus_IR"

% ---------- 0.9 AOP 输出角度范围 ----------
% AOP = 0.5 * atan2(S2, S1)
% 原始范围通常为 [-90°, 90°)。为了显示方便，可映射到 [0°, 180°)。
cfg.AOPRange = "0_to_180";         % 可选："minus90_to_90" 或 "0_to_180"

% ---------- 0.10 是否重建“直接由序列计算的偏振参数” ----------
% 默认 false。
% true 时会计算：
%   yDOP  = sqrt(yS1.^2+yS2.^2+yS3.^2)./yS0
%   yDOCP = yS3./yS0 或 abs(yS3)./yS0
%   yAOP  = 0.5*atan2(yS2,yS1)
% 并直接用这些序列重建 DOP/AOP/DOCP 图。
% 注意：这是非线性先算再反演，通常只作对照，不建议作为最终结果。
cfg.enableDirectParamRecon = false;

% ---------- 0.11 DOCP 是否取绝对值 ----------
% signed DOCP = S3/S0，可表示左右旋符号；
% absolute DOCP = abs(S3)/S0，只表示圆偏振成分比例。
cfg.DOCPMode = "signed";           % 可选："signed" 或 "absolute"

% ---------- 0.12 保存格式 ----------
cfg.saveMat = true;                 % 保存 .mat 原始矩阵，推荐 true
cfg.saveTif = true;                 % 保存 32-bit tif，推荐 true
cfg.savePngForView = true;          % 保存便于观察的 png，推荐 true

% ---------- 0.12.1 大文件分块读取设置 ----------
% 【需要改的地方】
% 这个参数决定每次从 .bin 文件中读取多少个 uint64 时间戳。
% 作用：
%   1) 数值越大：读取速度可能更快，但瞬时内存占用更高；
%   2) 数值越小：更省内存，但读取速度变慢。
% 推荐：
%   你的电脑 31.7 GB 内存，可以先用 2e6；
%   如果仍然内存不足，改成 5e5；
%   如果运行稳定但太慢，可以改成 5e6。
cfg.readBlockSize = 2e6;             % 【可修改】分块读取大小，单位：uint64 个数

% ---------- 0.14 偏振参数清晰轮廓增强显示设置 ----------
% 这部分不改变原始 Stokes/强度重建数据，主要用于生成“轮廓更清晰”的 AOP/DOLP/DOP/DOCP 展示图。
% 核心思想：
%   1) 用 S0 强度图提取目标区域；
%   2) 对目标区域 mask 做形态学清理，让轮廓连续；
%   3) 只在目标区域显示 DOP/DOLP/DOCP；
%   4) AOP 默认使用 S0 目标区域显示，这样轮廓更完整；
%   5) 同时保存严格 AOP mask，便于判断哪些地方 AOP 物理可信度更高。
cfg.enablePaperStylePolFigure = true;     % 【推荐 true】输出类似论文风格的伪彩色偏振参数图
cfg.paperFigDir = fullfile(cfg.outDir, "paper_style_figures");
if ~exist(cfg.paperFigDir, 'dir')
    mkdir(cfg.paperFigDir);
end

% ----- S0 目标区域提取参数 -----
% S0 是总强度图，通常目标轮廓在 S0 中最稳定。因此先用 S0 生成目标 mask。
% 阈值由两个条件共同决定：
%   S0 > max(maskS0Ratio * max(S0), prctile(S0, maskS0Percentile))
% 调参建议：
%   背景残留太多：增大 maskS0Ratio 或 maskS0Percentile；
%   目标被删掉太多：减小 maskS0Ratio 或 maskS0Percentile。
cfg.maskS0Ratio = 0.05;              % 【重要可调】S0 最大值比例阈值，常用 0.03~0.12
cfg.maskS0Percentile = 15;           % 【重要可调】S0 百分位阈值，常用 10~30

% ----- mask 平滑和形态学参数 -----
% 这些参数决定目标轮廓是否连续、噪声点是否被去掉。
cfg.maskMedianKernel = [5 5];        % 【可调】生成 mask 前对 S0 做中值滤波，[3 3] 保细节，[5 5] 更稳
cfg.maskOpenRadius = 1;              % 【可调】开运算半径，去小噪点；噪点多可设 2
cfg.maskCloseRadius = 4;             % 【重要可调】闭运算半径，连接断裂轮廓；轮廓断裂设 4~6
cfg.maskDilateRadius = 0;            % 【可调】膨胀半径，目标边缘太细可设 1
cfg.maskMinArea = 120;               % 【重要可调】删除小连通域；噪点多设 200~500，细节丢失则降到 50
cfg.maskFillHoles = true;            % 【推荐 true】填充目标内部孔洞
cfg.useLargestMaskComponent = false; % 【谨慎】单个完整目标可 true；字母/多笔画目标建议 false

% ----- AOP 有效区设置 -----
% 严格物理意义：AOP 只有在 DOLP 足够高的位置才稳定。
% 但为了展示轮廓，可以让 AOP 使用 S0 目标 mask，这样能明显看到目标边界。
cfg.AOP_DOLP_min = 0.05;             % 【可调】严格 AOP 有效阈值，常用 0.02~0.10
cfg.AOP_useS0MaskOnly = true;        % 【展示推荐 true】true：AOP 轮廓更完整；false：AOP 更严格但可能碎

% ----- 偏振参数显示平滑 -----
% 只用于展示图和保存的增强参数图，不改变原始 Stokes 图。
cfg.enableParamMedianFilter = true;  % 【推荐 true】对 DOP/DOLP/DOCP/AOP 做中值滤波
cfg.paramMedianKernel = [3 3];       % 【可调】[3 3] 温和，[5 5] 更平滑但会模糊边缘
cfg.enableParamGaussianFilter = true;% 【推荐 true】对展示参数图做轻微高斯平滑
cfg.paramGaussianSigma = 0.8;        % 【可调】0.5~1.2 常用，越大越平滑

% ----- 伪彩色显示范围 -----
% 这些只影响论文风格 PNG 的颜色显示，不影响 .mat 原始数据。
cfg.AOPDisplayRange  = [0 180];      % AOP 单位为度，通常显示 0~180
cfg.DOLPDisplayRange = [0 1];        % DOLP 显示范围
cfg.DOPDisplayRange  = [0 1];        % DOP 显示范围
cfg.DOCPDisplayRange = [-1 1];       % signed DOCP 显示 -1~1；absolute DOCP 可改成 [0 1]
cfg.paperColormap = "turbo";         % 【可调】"turbo" 颜色层次清楚；老 MATLAB 不支持时自动用 jet


% ---------- 0.13 偏振参数图质量控制：解决 DOP/AOP 随机噪声、轮廓差问题 ----------
% 重要原因：DOP/AOP/DOCP 都是比值或反正切量。
% 如果某些像素 S0 很低，或者 S1/S2 很弱，则 DOP 会被噪声放大，AOP 会变成随机角度，
% 视觉上表现为满屏雪花点、没有目标轮廓。
cfg.enableParamQualityControl = true;   % 【推荐 true】启用 S0/DOLP 有效区域掩膜
cfg.enableStokesMedianFilter = true;    % 【推荐 true】计算偏振参数前，对 S0/S1/S2/S3 做中值滤波降噪
cfg.stokesMedianKernel = [3 3];         % 【可修改】中值滤波窗口，[3 3] 温和；[5 5] 更强但会模糊边缘

% S0 有效区域阈值。用于去掉背景和弱光区域，避免除以很小的 S0。
% 两个条件同时使用：S0 > max(S0MinRatio*max(S0), prctile(S0, S0Percentile))。
cfg.S0MinRatioForParam = 0.05;          % 【可修改】弱光剔除阈值，0.03~0.10 常用
cfg.S0PercentileForParam = 15;          % 【可修改】低亮度百分位剔除，10~30 常用

% AOP 只有在线偏振分量足够强时才有物理意义。
% 当 DOLP 太低时，atan2(S2,S1) 对噪声极其敏感，AOP 会像随机噪声。
cfg.DOLPMinForAOP = 0.03;               % 【可修改】AOP 有效阈值，0.02~0.10 常用

% DOP/DOLP 物理上通常应在 [0,1]。重建噪声会导致局部 >1，显示时建议截断。
cfg.clipDOPTo01 = true;                 % 【推荐 true】把 DOP/DOLP 显示与保存参数限制在 [0,1]

% 是否额外保存有效掩膜图。白色表示该像素的偏振参数可信度较高。
cfg.saveValidityMask = true;            % 【推荐 true】保存 ParamValidMask 和 AOPValidMask


%% ========================= 1. TVAL3 参数区：一般可先保持默认 =========================

opts.mu = 2^12;
opts.beta = 2^8;
opts.mu0 = 2^4;
opts.beta0 = 2^-5;
opts.maxcnt = 10;
opts.tol_inn = 1e-16;
opts.tol = 1e-4;
opts.maxit = 50;


%% ========================= 2. 读取测量矩阵 A，并做尺寸检查 =========================

fprintf("\n[1/7] 正在读取测量矩阵 A...\n");
Phi = readmatrix(cfg.A_path);

expectedRows = cfg.masksPerFrame;
expectedCols = cfg.imgH * cfg.imgW;

assert(size(Phi,1) == expectedRows, ...
    "测量矩阵 A 的行数错误：当前为 %d，期望为 %d。请检查 masksPerFrame 或 A_path。", ...
    size(Phi,1), expectedRows);

assert(size(Phi,2) == expectedCols, ...
    "测量矩阵 A 的列数错误：当前为 %d，期望为 %d = imgH*imgW。请检查图像尺寸或 A 文件。", ...
    size(Phi,2), expectedCols);

fprintf("测量矩阵尺寸正确：%d × %d\n", size(Phi,1), size(Phi,2));


%% ========================= 3. 从六组偏振数据中提取光子计数序列 =========================

fprintf("\n[2/7] 正在从 TDC 文件中提取六个偏振态的光子计数序列...\n");

polNames = {"I0", "I45", "I90", "I135", "IR", "IL"};
y = struct();
numFramesEachPol = zeros(numel(polNames),1);

for k = 1:numel(polNames)
    name = polNames{k};
    files = dataFiles.(name);

    fprintf("\n--- 正在处理偏振态 %s ---\n", name);
    fprintf("文件数量：%d\n", numel(files));

    counts = readPhotonCountsFromTDC(files, cfg);

    if cfg.enableDarkCorrection
        counts = counts - cfg.darkCountPerMask;
        counts(counts < 0) = 0;
    end

    y.(name) = counts(:);
    numFramesEachPol(k) = floor(length(y.(name)) / cfg.masksPerFrame);

    fprintf("偏振态 %s：有效掩膜计数数量 = %d，可重建帧数 = %d\n", ...
        name, length(y.(name)), numFramesEachPol(k));
end

% 六个偏振态必须至少都有一帧。
minFrames = min(numFramesEachPol);
assert(minFrames >= 1, "六个偏振态中至少有一个不足以组成一帧，请检查数据或 masksPerFrame。");

fprintf("\n六个偏振态共同可重建帧数 = %d\n", minFrames);

% 如果某些偏振态数据更多，只取共同帧数，避免长度不一致。
for k = 1:numel(polNames)
    name = polNames{k};
    keepLen = minFrames * cfg.masksPerFrame;
    y.(name) = y.(name)(1:keepLen);
end


%% ========================= 4. 对六个偏振强度通道分别重建 =========================

fprintf("\n[3/7] 正在分别重建 I0/I45/I90/I135/IR/IL 强度图...\n");

I = struct();
for k = 1:numel(polNames)
    name = polNames{k};
    I.(name) = zeros(cfg.imgH, cfg.imgW, minFrames);
end

for frameIdx = 1:minFrames
    fprintf("\n===== 正在重建第 %d / %d 帧 =====\n", frameIdx, minFrames);

    idx1 = (frameIdx - 1) * cfg.masksPerFrame + 1;
    idx2 = frameIdx * cfg.masksPerFrame;

    for k = 1:numel(polNames)
        name = polNames{k};
        y_frame = y.(name)(idx1:idx2);

        % 建议做列向量化，并转 double，避免 TVAL3 输入类型问题。
        y_frame = double(y_frame(:));

        % 可选：测量向量归一化。默认这里不做，因为光子计数绝对强度对 S0 有意义。
        % 如果不同偏振态曝光时间或激光功率不同，应在进入 Stokes 计算前做标定校正。

        fprintf("  TVAL3 重建 %s...\n", name);
        U = reconstructByTVAL3(Phi, y_frame, cfg, opts);
        I.(name)(:,:,frameIdx) = U;
    end
end


%% ========================= 5. 由强度图计算 Stokes、DOP、AOP、DOCP =========================

fprintf("\n[4/7] 正在由重建强度图计算 Stokes/DOP/AOP/DOCP 图像...\n");

Stokes = struct();
Param = struct();

for frameIdx = 1:minFrames
    I0   = I.I0(:,:,frameIdx);
    I45  = I.I45(:,:,frameIdx);
    I90  = I.I90(:,:,frameIdx);
    I135 = I.I135(:,:,frameIdx);
    IR   = I.IR(:,:,frameIdx);
    IL   = I.IL(:,:,frameIdx);

    % ---------- 5.1 Stokes 计算 ----------
    % 常用六强度法：
    %   S0 = I0 + I90
    %   S1 = I0 - I90
    %   S2 = I45 - I135
    %   S3 = IR - IL  或 IL - IR，取决于你的圆偏振定义。
    S0 = I0 + I90;
    S1 = I0 - I90;
    S2 = I45 - I135;

    switch cfg.S3Convention
        case "IR_minus_IL"
            S3 = IR - IL;
        case "IL_minus_IR"
            S3 = IL - IR;
        otherwise
            error("cfg.S3Convention 只能为 'IR_minus_IL' 或 'IL_minus_IR'。");
    end

    % ---------- 5.2 保存原始 Stokes 图 ----------
    % 注意：这里保存的是未做质量掩膜的原始 Stokes 结果，用于后续定量检查。
    Stokes.S0(:,:,frameIdx) = S0;
    Stokes.S1(:,:,frameIdx) = S1;
    Stokes.S2(:,:,frameIdx) = S2;
    Stokes.S3(:,:,frameIdx) = S3;

    % ---------- 5.3 计算偏振参数图：带质量控制版本 ----------
    % DOP/AOP/DOCP 是非线性参数，对噪声非常敏感。
    % 尤其 AOP = 0.5*atan2(S2,S1)，当 S1、S2 很小时，角度会随机跳变。
    % 因此这里先对 Stokes 做轻微中值滤波，然后用 S0 和 DOLP 建立有效掩膜。
    [DOP, DOLP, DOCP, AOP_deg, validMask, aopValidMask] = ...
        computePolarizationParamsWithMask(S0, S1, S2, S3, cfg);

    % ---------- 5.4 保存到结构体 ----------
    Param.DOP(:,:,frameIdx)  = DOP;
    Param.DOLP(:,:,frameIdx) = DOLP;
    Param.DOCP(:,:,frameIdx) = DOCP;
    Param.AOP_deg(:,:,frameIdx) = AOP_deg;
    Param.ValidMask(:,:,frameIdx) = validMask;
    Param.AOPValidMask(:,:,frameIdx) = aopValidMask;
end


%% ========================= 6. 可选：直接由测量序列计算 DOP/AOP/DOCP 再重建 =========================

DirectRecon = struct();

if cfg.enableDirectParamRecon
    fprintf("\n[5/7] 正在执行直接序列法重建 DOP/AOP/DOCP，仅建议用于对照...\n");

    DirectRecon.DOP = zeros(cfg.imgH, cfg.imgW, minFrames);
    DirectRecon.DOCP = zeros(cfg.imgH, cfg.imgW, minFrames);
    DirectRecon.AOP_deg = zeros(cfg.imgH, cfg.imgW, minFrames);

    for frameIdx = 1:minFrames
        idx1 = (frameIdx - 1) * cfg.masksPerFrame + 1;
        idx2 = frameIdx * cfg.masksPerFrame;

        yI0   = double(y.I0(idx1:idx2));
        yI45  = double(y.I45(idx1:idx2));
        yI90  = double(y.I90(idx1:idx2));
        yI135 = double(y.I135(idx1:idx2));
        yIR   = double(y.IR(idx1:idx2));
        yIL   = double(y.IL(idx1:idx2));

        yS0 = yI0 + yI90;
        yS1 = yI0 - yI90;
        yS2 = yI45 - yI135;

        switch cfg.S3Convention
            case "IR_minus_IL"
                yS3 = yIR - yIL;
            case "IL_minus_IR"
                yS3 = yIL - yIR;
        end

        epsY = max(abs(yS0(:))) * 1e-12 + eps;
        yS0_safe = yS0;
        yS0_safe(abs(yS0_safe) < epsY) = epsY;

        yDOP = sqrt(yS1.^2 + yS2.^2 + yS3.^2) ./ yS0_safe;

        switch cfg.DOCPMode
            case "signed"
                yDOCP = yS3 ./ yS0_safe;
            case "absolute"
                yDOCP = abs(yS3) ./ yS0_safe;
        end

        yAOP_deg = rad2deg(0.5 * atan2(yS2, yS1));
        if cfg.AOPRange == "0_to_180"
            yAOP_deg = mod(yAOP_deg, 180);
        end

        fprintf("  直接序列法重建第 %d 帧 DOP...\n", frameIdx);
        DirectRecon.DOP(:,:,frameIdx) = reconstructByTVAL3(Phi, yDOP(:), cfg, opts);

        fprintf("  直接序列法重建第 %d 帧 DOCP...\n", frameIdx);
        DirectRecon.DOCP(:,:,frameIdx) = reconstructByTVAL3(Phi, yDOCP(:), cfg, opts);

        fprintf("  直接序列法重建第 %d 帧 AOP...\n", frameIdx);
        DirectRecon.AOP_deg(:,:,frameIdx) = reconstructByTVAL3(Phi, yAOP_deg(:), cfg, opts);
    end
else
    fprintf("\n[5/7] 已跳过直接序列法重建。推荐使用 Stokes 图后计算的 DOP/AOP/DOCP。\n");
end


%% ========================= 7. 保存结果 =========================

fprintf("\n[6/7] 正在保存结果...\n");

% ---------- 7.1 保存 .mat 原始结果 ----------
if cfg.saveMat
    matPath = fullfile(cfg.outDir, "polarization_reconstruction_raw_results.mat");
    save(matPath, "cfg", "opts", "y", "I", "Stokes", "Param", "DirectRecon", "-v7.3");
    fprintf("已保存 MAT 文件：%s\n", matPath);
end

% ---------- 7.2 保存每一帧图像 ----------
for frameIdx = 1:minFrames
    frameDir = fullfile(cfg.outDir, sprintf("frame_%04d", frameIdx));
    if ~exist(frameDir, 'dir')
        mkdir(frameDir);
    end

    % 强度图
    saveImageSet(frameDir, sprintf("I0_frame_%04d", frameIdx),   I.I0(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("I45_frame_%04d", frameIdx),  I.I45(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("I90_frame_%04d", frameIdx),  I.I90(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("I135_frame_%04d", frameIdx), I.I135(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("IR_frame_%04d", frameIdx),   I.IR(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("IL_frame_%04d", frameIdx),   I.IL(:,:,frameIdx), cfg, "auto");

    % Stokes 图
    saveImageSet(frameDir, sprintf("S0_frame_%04d", frameIdx), Stokes.S0(:,:,frameIdx), cfg, "auto");
    saveImageSet(frameDir, sprintf("S1_frame_%04d", frameIdx), Stokes.S1(:,:,frameIdx), cfg, "signed_auto");
    saveImageSet(frameDir, sprintf("S2_frame_%04d", frameIdx), Stokes.S2(:,:,frameIdx), cfg, "signed_auto");
    saveImageSet(frameDir, sprintf("S3_frame_%04d", frameIdx), Stokes.S3(:,:,frameIdx), cfg, "signed_auto");

    % 偏振参数图
    saveImageSet(frameDir, sprintf("DOP_frame_%04d", frameIdx),  Param.DOP(:,:,frameIdx), cfg, "0_1_clip");
    saveImageSet(frameDir, sprintf("DOLP_frame_%04d", frameIdx), Param.DOLP(:,:,frameIdx), cfg, "0_1_clip");

    if cfg.DOCPMode == "signed"
        saveImageSet(frameDir, sprintf("DOCP_frame_%04d", frameIdx), Param.DOCP(:,:,frameIdx), cfg, "minus1_1");
    else
        saveImageSet(frameDir, sprintf("DOCP_frame_%04d", frameIdx), Param.DOCP(:,:,frameIdx), cfg, "0_1_clip");
    end

    if cfg.AOPRange == "0_to_180"
        saveImageSet(frameDir, sprintf("AOP_deg_frame_%04d", frameIdx), Param.AOP_deg(:,:,frameIdx), cfg, "0_180");
    else
        saveImageSet(frameDir, sprintf("AOP_deg_frame_%04d", frameIdx), Param.AOP_deg(:,:,frameIdx), cfg, "minus90_90");
    end

    % 偏振参数有效区域掩膜。
    % ValidMask：S0 足够强，DOP/DOLP/DOCP 较可信。
    % AOPValidMask：S0 足够强且 DOLP 足够高，AOP 较可信。
    if isfield(cfg, 'saveValidityMask') && cfg.saveValidityMask
        saveImageSet(frameDir, sprintf("ValidMask_frame_%04d", frameIdx), Param.ValidMask(:,:,frameIdx), cfg, "0_1_clip");
        saveImageSet(frameDir, sprintf("AOPValidMask_frame_%04d", frameIdx), Param.AOPValidMask(:,:,frameIdx), cfg, "0_1_clip");
    end

    % ---------- 7.3 保存论文风格伪彩色偏振参数图 ----------
    % 这些图专门用于观察和展示目标轮廓，包含：
    %   1) 单独 AOP/DOLP/DOP/DOCP 伪彩色图；
    %   2) 四联图 PaperStyle_4panel；
    %   3) 增强后的 ValidMask/AOPMask。
    % 它们不会覆盖原始 .mat 数据。
    if isfield(cfg, 'enablePaperStylePolFigure') && cfg.enablePaperStylePolFigure
        savePaperStylePolarizationFigures( ...
            Stokes.S0(:,:,frameIdx), ...
            Param.DOP(:,:,frameIdx), ...
            Param.DOLP(:,:,frameIdx), ...
            Param.DOCP(:,:,frameIdx), ...
            Param.AOP_deg(:,:,frameIdx), ...
            Param.ValidMask(:,:,frameIdx), ...
            Param.AOPValidMask(:,:,frameIdx), ...
            frameIdx, cfg);
    end
end

fprintf("\n[7/7] 全部处理完成。输出目录：%s\n", cfg.outDir);


%% =========================================================================
%                              局部函数区
% =========================================================================
function counts = readPhotonCountsFromTDC(files, cfg)
% readPhotonCountsFromTDC
% -------------------------------------------------------------------------
% 内存优化版本。
%
% 旧版本做法：
%   读取全部 raw -> 解码全部 id/t -> 保留 DMD/SPAD -> 对全部事件排序 -> 统计光子数。
%   当 SPAD 光子事件非常多时，idRaw、tRaw、idKeep、tKeep 会占用巨大内存。
%
% 新版本做法：两遍扫描 bin 文件。
%   第 1 遍：只提取 DMD 触发时间戳。
%   第 2 遍：分块读取 SPAD 光子时间戳，用 histcounts 统计其落在哪两个相邻 DMD 触发之间。
% -------------------------------------------------------------------------

    if ischar(files) || isstring(files)
        files = cellstr(files);
    end

    if ~isfield(cfg, 'readBlockSize') || isempty(cfg.readBlockSize)
        cfg.readBlockSize = 2e6;
    end

    %% -------- 第 1 遍：只读取 DMD 触发时间戳 --------
    fprintf("  第 1 遍扫描：提取 DMD 触发时间戳...\n");
    DMD_times_cell = cell(numel(files), 1);

    for i = 1:numel(files)
        filePath = string(files{i});
        if ~isfile(filePath)
            error("找不到 TDC 文件：%s", filePath);
        end

        fprintf("    扫描 DMD：%s\n", filePath);
        fid = fopen(filePath, 'rb');
        if fid < 0
            error("无法打开文件：%s", filePath);
        end

        dmd_times_this_file = [];

        while ~feof(fid)
            rawBlock = fread(fid, cfg.readBlockSize, 'uint64=>uint64');
            if isempty(rawBlock)
                break;
            end

            idBlock = uint8(bitshift(rawBlock, -57));
            dmdMask = (idBlock == cfg.DMD_CH);

            if any(dmdMask)
                rawDMD = rawBlock(dmdMask);
                [~, tDMD] = decodeTDCUint64(rawDMD);
                dmd_times_this_file = [dmd_times_this_file; tDMD(:)]; %#ok<AGROW>
            end

            clear rawBlock idBlock dmdMask rawDMD tDMD;
        end

        fclose(fid);
        DMD_times_cell{i} = dmd_times_this_file;
        fprintf("    本文件 DMD 触发数量：%d\n", numel(dmd_times_this_file));
    end

    DMD_times = vertcat(DMD_times_cell{:});
    clear DMD_times_cell;

    if numel(DMD_times) < 2
        error("DMD 触发数量小于 2，无法统计掩膜间隔。请检查 DMD 通道或同步信号。");
    end

    DMD_times = sort(DMD_times(:));

    oldNum = numel(DMD_times);
    DMD_times = unique(DMD_times, 'stable');
    if numel(DMD_times) < oldNum
        fprintf("  警告：发现并去除了 %d 个重复 DMD 时间戳。\n", oldNum - numel(DMD_times));
    end

    nIntervals = numel(DMD_times) - 1;
    fprintf("  DMD 触发总数：%d，可形成掩膜周期数：%d\n", numel(DMD_times), nIntervals);

    %% -------- 第 2 遍：只读取 SPAD 时间戳，并统计落入哪个 DMD 周期 --------
    fprintf("  第 2 遍扫描：分块统计 SPAD 光子计数...\n");

    edges = double(DMD_times(:));
    counts = zeros(nIntervals, 1);

    for i = 1:numel(files)
        filePath = string(files{i});
        fprintf("    统计 SPAD：%s\n", filePath);

        fid = fopen(filePath, 'rb');
        if fid < 0
            error("无法打开文件：%s", filePath);
        end

        while ~feof(fid)
            rawBlock = fread(fid, cfg.readBlockSize, 'uint64=>uint64');
            if isempty(rawBlock)
                break;
            end

            idBlock = uint8(bitshift(rawBlock, -57));
            spadMask = (idBlock == cfg.SPAD_CH);

            if any(spadMask)
                rawSPAD = rawBlock(spadMask);
                [~, tSPAD] = decodeTDCUint64(rawSPAD);

                tSPAD_d = double(tSPAD(:));
                valid = (tSPAD_d >= edges(1)) & (tSPAD_d < edges(end));
                tSPAD_d = tSPAD_d(valid);

                if ~isempty(tSPAD_d)
                    c = histcounts(tSPAD_d, edges);
                    counts = counts + c(:);
                end
            end

            clear rawBlock idBlock spadMask rawSPAD tSPAD tSPAD_d valid c;
        end

        fclose(fid);
    end

    %% -------- 后处理 --------
    counts = double(counts(:));

    counts = counts - cfg.countOffset;
    counts(counts < 0) = 0;

    if cfg.skipMasks > 0
        if length(counts) <= cfg.skipMasks
            error("skipMasks=%d 过大，剩余计数不足。", cfg.skipMasks);
        end
        counts = counts(cfg.skipMasks+1:end);
    end

    fprintf("  统计得到掩膜计数数量：%d\n", length(counts));
    fprintf("  光子计数范围：min=%.3f, median=%.3f, mean=%.3f, max=%.3f\n", ...
        min(counts), median(counts), mean(counts), max(counts));
end

function [id, val_int] = decodeTDCUint64(raw)
% decodeTDCUint64
% -------------------------------------------------------------------------
% 功能：
%   按照原始代码的格式，从 uint64 TDC 数据中解析通道号和时间戳。
%
% 原代码逻辑：
%   id = bitshift(A,-57,'uint64');
%   val = bitshift(A,7,'uint64');
%   val = typecast(val, 'int64');
%   val_int = bitshift(val,-7,'int64');
% -------------------------------------------------------------------------

    id = bitshift(raw, -57, 'uint64');
    id = uint8(id);

    val = bitshift(raw, 7, 'uint64');
    val = typecast(val, 'int64');
    val_int = bitshift(val, -7, 'int64');
end


function img = reconstructByTVAL3(Phi, yFrame, cfg, opts)
% reconstructByTVAL3
% -------------------------------------------------------------------------
% 功能：
%   用 TVAL3 重建单帧图像，并做基础数值清理。
%
% 输入：
%   Phi    : 测量矩阵，尺寸 m × N
%   yFrame : 当前帧测量向量，尺寸 m × 1
%   cfg    : 配置结构体
%   opts   : TVAL3 参数
%
% 输出：
%   img    : cfg.imgH × cfg.imgW 的重建图像
% -------------------------------------------------------------------------

    assert(length(yFrame) == size(Phi,1), ...
        "yFrame 长度 %d 与测量矩阵行数 %d 不一致。", length(yFrame), size(Phi,1));

    [U, ~] = TVAL3(Phi, yFrame(:), cfg.imgH, cfg.imgW, opts);

    img = reshape(U(:), [cfg.imgH, cfg.imgW]);

    % 基础数值修正。
    img(isnan(img)) = 0;
    img(isinf(img)) = 0;
end


function [DOP, DOLP, DOCP, AOP_deg, validMask, aopValidMask] = computePolarizationParamsWithMask(S0, S1, S2, S3, cfg)
% computePolarizationParamsWithMask
% -------------------------------------------------------------------------
% 功能：
%   计算 DOP、DOLP、DOCP、AOP，并生成用于清晰显示目标轮廓的有效区域 mask。
%
% 为什么要做质量控制：
%   DOP  = sqrt(S1^2+S2^2+S3^2)/S0，是比值；
%   DOLP = sqrt(S1^2+S2^2)/S0，是比值；
%   DOCP = S3/S0，也是比值；
%   AOP  = 0.5*atan2(S2,S1)，当 S1/S2 很小时角度会随机跳变。
%
% 因此：
%   1) S0 很低的背景区域不应该直接显示偏振参数；
%   2) AOP 最好只在目标区域、并且线偏振分量足够的位置显示；
%   3) 为了展示目标轮廓，可额外用 S0 生成的目标 mask 限制 AOP/DOLP 显示区域。
%
% 输出：
%   DOP/DOLP/DOCP/AOP_deg : 已经经过基础掩膜和显示平滑的偏振参数图；
%   validMask             : 由 S0 得到的目标有效区域；
%   aopValidMask           : AOP 显示区域。若 cfg.AOP_useS0MaskOnly=true，则主要跟随 S0 轮廓。
% -------------------------------------------------------------------------

    % ---------- 1) 数据转 double 并清理异常值 ----------
    S0 = double(S0); S1 = double(S1); S2 = double(S2); S3 = double(S3);
    S0(isnan(S0) | isinf(S0)) = 0;
    S1(isnan(S1) | isinf(S1)) = 0;
    S2(isnan(S2) | isinf(S2)) = 0;
    S3(isnan(S3) | isinf(S3)) = 0;

    % ---------- 2) 可选：对 Stokes 做轻微中值滤波 ----------
    % 意义：
    %   TVAL3 重建的 Stokes 图可能有孤立噪点。
    %   中值滤波可以抑制椒盐噪声，同时尽量保留边缘。
    if isfield(cfg, 'enableStokesMedianFilter') && cfg.enableStokesMedianFilter
        k = cfg.stokesMedianKernel;
        S0p = medfilt2(S0, k, 'symmetric');
        S1p = medfilt2(S1, k, 'symmetric');
        S2p = medfilt2(S2, k, 'symmetric');
        S3p = medfilt2(S3, k, 'symmetric');
    else
        S0p = S0; S1p = S1; S2p = S2; S3p = S3;
    end

    % ---------- 3) 用 S0 生成目标有效区域 validMask ----------
    % S0 代表总强度，目标轮廓通常在 S0 中最清楚。
    % 先对 S0 做中值滤波，再用“最大值比例阈值 + 百分位阈值”联合分割。
    S0_abs = abs(S0p);

    if isfield(cfg, 'maskMedianKernel')
        S0_for_mask = medfilt2(S0_abs, cfg.maskMedianKernel, 'symmetric');
    else
        S0_for_mask = S0_abs;
    end

    S0_max = max(S0_for_mask(:));
    if S0_max <= 0 || isnan(S0_max)
        S0_max = eps;
    end

    % 若没有设置增强参数，则退回旧参数。
    if ~isfield(cfg, 'maskS0Ratio')
        cfg.maskS0Ratio = cfg.S0MinRatioForParam;
    end
    if ~isfield(cfg, 'maskS0Percentile')
        cfg.maskS0Percentile = cfg.S0PercentileForParam;
    end

    th_ratio = cfg.maskS0Ratio * S0_max;
    th_prct  = prctile(S0_for_mask(:), cfg.maskS0Percentile);
    S0_th = max(th_ratio, th_prct);

    validMask = S0_for_mask > S0_th;

    % ---------- 4) 形态学清理，使目标轮廓更连续 ----------
    % 开运算：去小噪声；
    % 闭运算：连接断裂轮廓；
    % 填孔：填补目标内部空洞；
    % 去小连通域：删除背景散点。
    if isfield(cfg, 'maskOpenRadius') && cfg.maskOpenRadius > 0
        validMask = imopen(validMask, strel('disk', cfg.maskOpenRadius));
    end

    if isfield(cfg, 'maskCloseRadius') && cfg.maskCloseRadius > 0
        validMask = imclose(validMask, strel('disk', cfg.maskCloseRadius));
    end

    if isfield(cfg, 'maskFillHoles') && cfg.maskFillHoles
        validMask = imfill(validMask, 'holes');
    end

    if isfield(cfg, 'maskMinArea') && cfg.maskMinArea > 0
        validMask = bwareaopen(validMask, cfg.maskMinArea);
    end

    if isfield(cfg, 'maskDilateRadius') && cfg.maskDilateRadius > 0
        validMask = imdilate(validMask, strel('disk', cfg.maskDilateRadius));
    end

    if isfield(cfg, 'useLargestMaskComponent') && cfg.useLargestMaskComponent
        validMask = keepLargestComponent(validMask);
    end

    % ---------- 5) 防止除零 ----------
    S0_safe = S0p;
    epsS0 = S0_max * 1e-9 + eps;
    S0_safe(abs(S0_safe) < epsS0) = epsS0;

    % ---------- 6) 计算原始偏振参数 ----------
    DOP_raw  = sqrt(S1p.^2 + S2p.^2 + S3p.^2) ./ abs(S0_safe);
    DOLP_raw = sqrt(S1p.^2 + S2p.^2) ./ abs(S0_safe);

    switch cfg.DOCPMode
        case "signed"
            DOCP_raw = S3p ./ S0_safe;
        case "absolute"
            DOCP_raw = abs(S3p) ./ abs(S0_safe);
        otherwise
            error("cfg.DOCPMode 只能为 'signed' 或 'absolute'。");
    end

    AOP_raw = rad2deg(0.5 * atan2(S2p, S1p));
    switch cfg.AOPRange
        case "minus90_to_90"
            % 保持 [-90, 90)
        case "0_to_180"
            AOP_raw = mod(AOP_raw, 180);
        otherwise
            error("cfg.AOPRange 只能为 'minus90_to_90' 或 '0_to_180'。");
    end

    % ---------- 7) 对偏振参数图做展示平滑 ----------
    % 注意：这是为了让轮廓更清楚；原始 Stokes 和强度图仍保存在 .mat 中。
    DOP_s = DOP_raw;
    DOLP_s = DOLP_raw;
    DOCP_s = DOCP_raw;
    AOP_s = AOP_raw;

    if isfield(cfg, 'enableParamMedianFilter') && cfg.enableParamMedianFilter
        pk = cfg.paramMedianKernel;
        DOP_s  = medfilt2(DOP_s,  pk, 'symmetric');
        DOLP_s = medfilt2(DOLP_s, pk, 'symmetric');
        DOCP_s = medfilt2(DOCP_s, pk, 'symmetric');
        AOP_s  = medfilt2(AOP_s,  pk, 'symmetric');
    end

    if isfield(cfg, 'enableParamGaussianFilter') && cfg.enableParamGaussianFilter
        sigma = cfg.paramGaussianSigma;
        if sigma > 0
            DOP_s  = imgaussfilt(DOP_s,  sigma);
            DOLP_s = imgaussfilt(DOLP_s, sigma);
            DOCP_s = imgaussfilt(DOCP_s, sigma);
            AOP_s  = imgaussfilt(AOP_s,  sigma);
        end
    end

    % ---------- 8) AOP 有效区域 ----------
    % 严格 AOP 区域：S0 有目标，且 DOLP 足够高；
    % 展示 AOP 区域：可选择只用 S0 mask，让 AOP 图轮廓更完整。
    strictAOPMask = validMask & (DOLP_raw >= cfg.AOP_DOLP_min);

    if isfield(cfg, 'AOP_useS0MaskOnly') && cfg.AOP_useS0MaskOnly
        aopValidMask = validMask;
    else
        aopValidMask = strictAOPMask;
    end

    % 对 AOP mask 做轻微闭运算，避免角度图零散破碎。
    if isfield(cfg, 'maskCloseRadius') && cfg.maskCloseRadius > 0
        aopValidMask = imclose(aopValidMask, strel('disk', max(1, cfg.maskCloseRadius)));
    end
    if isfield(cfg, 'maskMinArea') && cfg.maskMinArea > 0
        aopValidMask = bwareaopen(aopValidMask, max(20, round(cfg.maskMinArea/2)));
    end

    % ---------- 9) 掩膜外区域置 0，便于普通 png 查看 ----------
    DOP = DOP_s;
    DOLP = DOLP_s;
    DOCP = DOCP_s;
    AOP_deg = AOP_s;

    DOP(~validMask) = 0;
    DOLP(~validMask) = 0;
    DOCP(~validMask) = 0;
    AOP_deg(~aopValidMask) = 0;

    % ---------- 10) 物理范围裁剪 ----------
    if isfield(cfg, 'clipDOPTo01') && cfg.clipDOPTo01
        DOP  = min(max(DOP, 0), 1);
        DOLP = min(max(DOLP, 0), 1);
        if cfg.DOCPMode == "absolute"
            DOCP = min(max(DOCP, 0), 1);
        else
            DOCP = min(max(DOCP, -1), 1);
        end
    end

    if cfg.AOPRange == "0_to_180"
        AOP_deg = mod(AOP_deg, 180);
    end

    validMask = double(validMask);
    aopValidMask = double(aopValidMask);
end


function savePaperStylePolarizationFigures(S0, DOP, DOLP, DOCP, AOP_deg, validMask, aopValidMask, frameIdx, cfg)
% savePaperStylePolarizationFigures
% =========================================================================
% 功能：
%   保存类似论文中的 AOP / DOLP / DOP / DOCP 伪彩色图，让偏振参数轮廓更清晰。
%
% 重要说明：
%   1) 这里主要是“显示增强”，不会改变已经保存的 raw Stokes 数据；
%   2) 背景区域用 NaN 屏蔽，显示为白色；
%   3) AOP 使用 AOPValidMask，DOLP/DOP/DOCP 使用 ValidMask；
%   4) 适合论文插图、组会展示、快速判断轮廓。
% =========================================================================

    if ~exist(cfg.paperFigDir, 'dir')
        mkdir(cfg.paperFigDir);
    end

    S0 = double(S0);
    DOP = double(DOP);
    DOLP = double(DOLP);
    DOCP = double(DOCP);
    AOP_deg = double(AOP_deg);
    validMask = logical(validMask);
    aopValidMask = logical(aopValidMask);

    % 再做一次轻微清理，避免保存图时出现 NaN/Inf。
    DOP(isnan(DOP) | isinf(DOP)) = 0;
    DOLP(isnan(DOLP) | isinf(DOLP)) = 0;
    DOCP(isnan(DOCP) | isinf(DOCP)) = 0;
    AOP_deg(isnan(AOP_deg) | isinf(AOP_deg)) = 0;

    % 背景设为 NaN，画图时显示为白色，轮廓会更突出。
    AOP_show = AOP_deg;
    DOLP_show = DOLP;
    DOP_show = DOP;
    DOCP_show = DOCP;

    AOP_show(~aopValidMask) = NaN;
    DOLP_show(~validMask) = NaN;
    DOP_show(~validMask) = NaN;
    DOCP_show(~validMask) = NaN;

    % 保存单张论文风格图。
    saveOnePaperFigure(AOP_show,  cfg.AOPDisplayRange,  "AOP",  "AOP (deg)", frameIdx, cfg);
    saveOnePaperFigure(DOLP_show, cfg.DOLPDisplayRange, "DOLP", "DOLP",      frameIdx, cfg);
    saveOnePaperFigure(DOP_show,  cfg.DOPDisplayRange,  "DOP",  "DOP",       frameIdx, cfg);
    saveOnePaperFigure(DOCP_show, cfg.DOCPDisplayRange, "DOCP", "DOCP",      frameIdx, cfg);

    % 保存 mask，便于你判断轮廓是否来自有效区域。
    imwrite(validMask, fullfile(cfg.paperFigDir, sprintf("ValidMask_paper_frame_%04d.png", frameIdx)));
    imwrite(aopValidMask, fullfile(cfg.paperFigDir, sprintf("AOPMask_paper_frame_%04d.png", frameIdx)));

    % 保存四联图。
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1200, 1000]);

    subplot(2,2,1);
    imagesc(AOP_show);
    axis image off;
    applyChosenColormap(gca, "jet");
    caxis(cfg.AOPDisplayRange);
    cb = colorbar; cb.Label.String = "AOP (deg)";
    title("AOP", 'FontSize', 28, 'FontWeight', 'bold');

    subplot(2,2,2);
    imagesc(DOLP_show);
    axis image off;
    applyChosenColormap(gca, cfg.paperColormap);
    caxis(cfg.DOLPDisplayRange);
    cb = colorbar; cb.Label.String = "DOLP";
    title("DOLP", 'FontSize', 28, 'FontWeight', 'bold');

    subplot(2,2,3);
    imagesc(DOP_show);
    axis image off;
    applyChosenColormap(gca, cfg.paperColormap);
    caxis(cfg.DOPDisplayRange);
    cb = colorbar; cb.Label.String = "DOP";
    title("DOP", 'FontSize', 28, 'FontWeight', 'bold');

    subplot(2,2,4);
    imagesc(DOCP_show);
    axis image off;
    applyChosenColormap(gca, cfg.paperColormap);
    caxis(cfg.DOCPDisplayRange);
    cb = colorbar; cb.Label.String = "DOCP";
    title("DOCP", 'FontSize', 28, 'FontWeight', 'bold');

    % 让 NaN 背景显示为白色。
    axs = findall(fig, 'Type', 'axes');
    for ii = 1:numel(axs)
        set(axs(ii), 'Color', 'w');
    end

    outName = fullfile(cfg.paperFigDir, sprintf("PaperStyle_4panel_frame_%04d.png", frameIdx));
    saveFigureCompat(fig, outName, 300);
    close(fig);
end


function saveOnePaperFigure(img, rangeVal, titleText, cbLabel, frameIdx, cfg)
% saveOnePaperFigure
% -------------------------------------------------------------------------
% 功能：
%   保存单张 AOP/DOLP/DOP/DOCP 伪彩色图。
% -------------------------------------------------------------------------

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 650, 550]);

    imagesc(img);
    axis image off;

    if titleText == "AOP"
        applyChosenColormap(gca, "jet");
    else
        applyChosenColormap(gca, cfg.paperColormap);
    end

    caxis(rangeVal);

    cb = colorbar;
    cb.Label.String = cbLabel;
    cb.Label.FontSize = 16;
    cb.FontSize = 14;

    title(titleText, 'FontSize', 34, 'FontWeight', 'bold');

    % NaN 背景显示为白色。
    set(gca, 'Color', 'w');

    outName = fullfile(cfg.paperFigDir, sprintf("%s_paper_frame_%04d.png", titleText, frameIdx));
    saveFigureCompat(fig, outName, 300);
    close(fig);
end


function applyChosenColormap(ax, cmapName)
% applyChosenColormap
% -------------------------------------------------------------------------
% 功能：
%   兼容不同 MATLAB 版本的 colormap。
%   新版 MATLAB 支持 turbo；老版本不支持时自动退回 jet。
% -------------------------------------------------------------------------

    try
        colormap(ax, char(cmapName));
    catch
        colormap(ax, jet);
    end
end


function saveFigureCompat(fig, filename, dpi)
% saveFigureCompat
% -------------------------------------------------------------------------
% 功能：
%   兼容保存高分辨率图片。
%   新版 MATLAB 用 exportgraphics；老版本自动退回 print。
% -------------------------------------------------------------------------

    filename = char(filename);
    try
        exportgraphics(fig, filename, 'Resolution', dpi);
    catch
        print(fig, filename, '-dpng', ['-r', num2str(dpi)]);
    end
end


function maskOut = keepLargestComponent(maskIn)
% keepLargestComponent
% -------------------------------------------------------------------------
% 功能：
%   只保留最大连通区域。
% 使用场景：
%   如果目标是一个完整大物体，开启 cfg.useLargestMaskComponent=true 可去掉背景块。
% 注意：
%   如果目标是多个分离字母/笔画，不建议开启，否则会丢掉小笔画。
% -------------------------------------------------------------------------

    maskIn = logical(maskIn);
    cc = bwconncomp(maskIn);
    if cc.NumObjects == 0
        maskOut = maskIn;
        return;
    end

    areas = cellfun(@numel, cc.PixelIdxList);
    [~, idx] = max(areas);

    maskOut = false(size(maskIn));
    maskOut(cc.PixelIdxList{idx}) = true;
end


function saveImageSet(folder, baseName, img, cfg, mode)
% saveImageSet
% -------------------------------------------------------------------------
% 功能：
%   同时保存：
%     1) 原始 .mat 单图；
%     2) 32-bit tif；
%     3) 用于显示观察的 png。
%
% mode 控制 png 显示范围：
%   "auto"        : 自动拉伸到 [0,1]
%   "signed_auto" : 正负值对称显示，适合 S1/S2/S3
%   "0_1_clip"    : 截断到 [0,1]
%   "minus1_1"    : signed DOCP，映射 [-1,1] 到 [0,1]
%   "0_180"       : AOP [0,180] 映射到 [0,1]
%   "minus90_90"  : AOP [-90,90] 映射到 [0,1]
% -------------------------------------------------------------------------

    img = double(img);
    img(isnan(img)) = 0;
    img(isinf(img)) = 0;

    if cfg.saveMat
        save(fullfile(folder, baseName + ".mat"), "img");
    end

    if cfg.saveTif
        % 32-bit float TIFF，尽量保留原始数值。
        % 注意：部分 MATLAB 版本的 imwrite 不支持 single 写入 tif，
        % 因此这里改用 Tiff 类写 IEEE floating-point TIFF。
        writeFloat32Tiff(fullfile(folder, baseName + ".tif"), img);
    end

    if cfg.savePngForView
        viewImg = makeViewImage(img, mode);
        imwrite(viewImg, fullfile(folder, baseName + ".png"));
    end
end


function writeFloat32Tiff(filename, img)
% writeFloat32Tiff
% -------------------------------------------------------------------------
% 功能：
%   将二维矩阵保存为 32-bit floating-point TIFF。
%
% 为什么不用 imwrite(single(img), filename)：
%   部分 MATLAB 版本不支持用 imwrite 直接写 single 类型 TIFF，
%   会报错：“IMWRITE 不支持向 TIFF 文件中写入 single 图像数据。请改用 Tiff。”
%   因此这里使用 MATLAB 的 Tiff 类手动设置标签。
%
% 注意：
%   1) 该 TIFF 用于保存原始数值，适合后续定量分析；
%   2) 普通图片查看器可能无法正确显示 32-bit float TIFF；
%   3) 便于肉眼查看的图像仍然由 PNG 文件提供。
% -------------------------------------------------------------------------

    img = single(img);
    img(isnan(img)) = 0;
    img(isinf(img)) = 0;

    filename = char(filename);

    t = Tiff(filename, 'w');

    tagstruct.ImageLength = size(img, 1);
    tagstruct.ImageWidth = size(img, 2);
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 32;
    tagstruct.SamplesPerPixel = 1;
    tagstruct.SampleFormat = Tiff.SampleFormat.IEEEFP;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Compression = Tiff.Compression.None;

    t.setTag(tagstruct);
    t.write(img);
    t.close();
end


function viewImg = makeViewImage(img, mode)
% makeViewImage
% -------------------------------------------------------------------------
% 功能：
%   把不同物理含义的图像映射为 [0,1] 的显示图。
%   注意：该函数只用于 png 观察图，不改变 .mat 和 .tif 中的原始数据。
% -------------------------------------------------------------------------

    switch mode
        case "auto"
            viewImg = robustNormalize(img, 1, 99);

        case "signed_auto"
            a = prctile(abs(img(:)), 99);
            if a <= 0 || isnan(a)
                a = 1;
            end
            viewImg = (img + a) / (2*a);
            viewImg = min(max(viewImg, 0), 1);

        case "0_1_clip"
            viewImg = min(max(img, 0), 1);

        case "minus1_1"
            viewImg = (img + 1) / 2;
            viewImg = min(max(viewImg, 0), 1);

        case "0_180"
            viewImg = img / 180;
            viewImg = min(max(viewImg, 0), 1);

        case "minus90_90"
            viewImg = (img + 90) / 180;
            viewImg = min(max(viewImg, 0), 1);

        otherwise
            error("未知显示模式：%s", mode);
    end
end


function out = robustNormalize(img, pLow, pHigh)
% robustNormalize
% -------------------------------------------------------------------------
% 功能：
%   百分位归一化，避免少数异常亮点或暗点影响显示。
%   仅用于显示，不用于定量分析。
% -------------------------------------------------------------------------

    lo = prctile(img(:), pLow);
    hi = prctile(img(:), pHigh);

    if hi <= lo
        out = zeros(size(img));
        return;
    end

    out = (img - lo) / (hi - lo);
    out = min(max(out, 0), 1);
end
