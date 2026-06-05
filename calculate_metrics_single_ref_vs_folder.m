%% ========================================================================
%  calculate_metrics_single_ref_vs_folder.m
%
%  功能：
%  使用“单张参考图像”评价“一个文件夹内所有待测图像”的质量指标。
%
%  可计算指标：
%  MSE、RMSE、MAE、SNR、PSNR、SSIM、MS-SSIM、CorrCoef、NCC
%
%  适用于：
%  1. S0_ref vs 多张 S0_test
%  2. 无散射清晰图 vs 散射后重建图
%  3. 无散射清晰图 vs 532 nm / 905 nm / 双光融合图
%  4. 偏振增强前后图像质量评价
%
%  内存优化：
%  1. 参考图只读取一次；
%  2. 待测图逐张读取，逐张计算；
%  3. 图像转 single，减少内存占用；
%  4. 不保存中间大矩阵；
%  5. 每轮循环后 clear 临时变量；
%  6. 修复 Windows 下图像重复读取 bug。
%
%  注意：
%  PSNR、SSIM、MS-SSIM 是有参考图指标。
%  参考图和待测图必须是同一种物理图像，例如：
%  S0_ref 对 S0_test，DOP_ref 对 DOP_test。
%
%  ========================================================================

clear;
clc;
close all;

%% ======================= 1. 用户需要修改的区域 ==========================

% ------------------------------------------------------------------------
% 【必须修改 1】单张参考图像路径
%
% 这张图通常选择：
% 1. 无散射介质时的清晰重建图；
% 2. 高采样率重建图；
% 3. 质量最好的基准图；
% 4. 原始目标图。
%
% 示例：
% reference_image_path = 'F:\code\stocks_two\reference_images\GT.bmp';
% ------------------------------------------------------------------------
 
reference_image_path = 'F:\code\stocks_two\reference_images\GT.bmp';


% ------------------------------------------------------------------------
% 【必须修改 2】待评价图像文件夹
%
% 这个文件夹里面可以放很多待测图，例如：
% S0_frame_0001.png
% S0_frame_0002.png
% fused_532_905.png
% result_01.png
% result_02.png
% ------------------------------------------------------------------------

test_folder = 'F:\code\stocks_two\test_images';


% ------------------------------------------------------------------------
% 【必须修改 3】结果输出文件夹
%
% 程序会输出：
% 1. image_quality_metrics_single_ref.xlsx
% 2. image_quality_metrics_single_ref.csv
% ------------------------------------------------------------------------

output_folder = 'F:\code\stocks_two\metrics_results';


% ------------------------------------------------------------------------
% 【可修改 4】支持的图像格式
%
% 注意：
% 这里全部写成小写即可。
% 程序内部会自动统一处理扩展名，避免重复读取。
% ------------------------------------------------------------------------

image_extensions = {'.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff'};


% ------------------------------------------------------------------------
% 【可修改 5】是否将 RGB 图像转为灰度图
%
% 对你的 S0、DOP、AOP、DOLP 等科研图像：
% 通常建议 true。
%
% 因为很多 png 图像可能是伪彩色图。
% 如果是伪彩色图，直接算 RGB 指标意义不严谨。
%
% true  ：RGB 转灰度
% false ：保留 RGB 三通道
% ------------------------------------------------------------------------

convert_rgb_to_gray = true;


% ------------------------------------------------------------------------
% 【可修改 6】尺寸不一致时，是否自动 resize
%
% true  ：把待测图 resize 到参考图大小
% false ：尺寸不一致直接跳过
% ------------------------------------------------------------------------

auto_resize_to_reference = true;


% ------------------------------------------------------------------------
% 【可修改 7】是否对每张图单独 min-max 归一化到 [0,1]
%
% true：
%   每张图根据自身最小值和最大值归一化到 [0,1]。
%   更适合比较轮廓、结构、形状。
%
% false：
%   不做 min-max，只根据图像格式转换到 [0,1]。
%   更适合保留真实灰度强度关系。
%
% 对 S0 图：
%   如果重点比较轮廓清晰度，建议 true；
%   如果重点比较真实强度，建议 false。
%
% 对 DOP/DOLP：
%   若本身已经是 [0,1] 的物理量，建议 false。
% ------------------------------------------------------------------------

use_minmax_normalization = true;


% ------------------------------------------------------------------------
% 【可修改 8】是否进行亮度均值校正
%
% false：
%   原始比较。
%
% true：
%   把待测图的平均亮度调整到和参考图一致。
%   适合分析“去掉整体亮度偏差后，结构相似性是否提高”。
%
% 正式论文中建议：
% 原始指标和亮度校正后指标可以都算，但要注明。
% ------------------------------------------------------------------------

enable_mean_brightness_correction = false;


% ------------------------------------------------------------------------
% 【可修改 9】图像物理类型
%
% 'normal'    ：普通强度图、S0、DOP、DOLP、融合图
% 'angle_deg' ：角度图，单位为度，例如 AOP
% 'angle_rad' ：角度图，单位为弧度，例如 AOP
%
% 如果你现在算的是 S0 图，保持 'normal'。
% 如果你专门算 AOP 图，可以改为 'angle_deg' 或 'angle_rad'。
% ------------------------------------------------------------------------

image_physical_type = 'normal';


% ------------------------------------------------------------------------
% 【可修改 10】是否计算 MS-SSIM
%
% multissim 需要 MATLAB Image Processing Toolbox。
% 如果没有该函数，程序不会报错，会自动记为 NaN。
% ------------------------------------------------------------------------

enable_ms_ssim = true;


%% ======================= 2. 路径检查与输出文件夹创建 ====================

if ~exist(reference_image_path, 'file')
    error('参考图像不存在，请检查 reference_image_path：%s', reference_image_path);
end

if ~exist(test_folder, 'dir')
    error('待评价图像文件夹不存在，请检查 test_folder：%s', test_folder);
end

if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

excel_output_path = fullfile(output_folder, 'image_quality_metrics_single_ref.xlsx');
csv_output_path   = fullfile(output_folder, 'image_quality_metrics_single_ref.csv');

fprintf('参考图像：%s\n', reference_image_path);
fprintf('待测图像文件夹：%s\n', test_folder);
fprintf('输出文件夹：%s\n\n', output_folder);


%% ======================= 3. 扫描待测图像文件 ============================

test_files = get_image_file_list_no_duplicate(test_folder, image_extensions);

if isempty(test_files)
    error('待评价图像文件夹中没有找到支持格式的图像。');
end

fprintf('找到 %d 张待评价图像。\n\n', numel(test_files));


%% ======================= 4. 初始化结果表格 ==============================

result_cell = {};

result_header = { ...
    'Index', ...
    'ImageName', ...
    'ReferencePath', ...
    'TestPath', ...
    'Height', ...
    'Width', ...
    'Channel', ...
    'MSE', ...
    'RMSE', ...
    'MAE', ...
    'SNR_dB', ...
    'PSNR_dB', ...
    'SSIM', ...
    'MS_SSIM', ...
    'CorrCoef', ...
    'NCC', ...
    'MaxAbsError', ...
    'MeanReference', ...
    'MeanTest', ...
    'StdReference', ...
    'StdTest', ...
    'MeanBrightnessCorrection' ...
    };


%% ======================= 5. 读取参考图像，只读取一次 =====================

ref_img_original = read_and_preprocess_image(reference_image_path, convert_rgb_to_gray);
ref_img_original = single(ref_img_original);

fprintf('参考图像读取完成，尺寸为：[%d, %d, %d]\n\n', size(ref_img_original, 1), size(ref_img_original, 2), size(ref_img_original, 3));


%% ======================= 6. 逐张待测图计算指标 ===========================

fprintf('开始计算图像质量指标...\n\n');

valid_count = 0;

for k = 1:numel(test_files)

    test_path = test_files{k};
    [~, test_name, test_ext] = fileparts(test_path);
    test_file_name = [test_name, test_ext];

    try
        % ----------------------------------------------------------------
        % 每次循环复制参考图，读取一张待测图
        % ----------------------------------------------------------------
        ref_img = ref_img_original;

        test_img = read_and_preprocess_image(test_path, convert_rgb_to_gray);
        test_img = single(test_img);

        % ----------------------------------------------------------------
        % 检查尺寸和通道数
        % ----------------------------------------------------------------
        [ref_h, ref_w, ref_c] = size(ref_img);
        [test_h, test_w, test_c] = size(test_img);

        if ref_h ~= test_h || ref_w ~= test_w || ref_c ~= test_c

            if auto_resize_to_reference

                fprintf('[尺寸调整] %s：[%d,%d,%d] -> [%d,%d,%d]\n', ...
                    test_file_name, test_h, test_w, test_c, ref_h, ref_w, ref_c);

                test_img = imresize(test_img, [ref_h, ref_w], 'bilinear');

                % resize 后再检查通道数
                if size(test_img, 3) ~= ref_c

                    if ref_c == 1 && size(test_img, 3) == 3
                        test_img = rgb2gray(test_img);

                    elseif ref_c == 3 && size(test_img, 3) == 1
                        test_img = repmat(test_img, [1, 1, 3]);

                    else
                        fprintf('[跳过] 通道数无法匹配：%s\n', test_file_name);
                        clear ref_img test_img;
                        continue;
                    end
                end

            else
                fprintf('[跳过] 尺寸不一致：%s\n', test_file_name);
                clear ref_img test_img;
                continue;
            end
        end

        % ----------------------------------------------------------------
        % 归一化
        % ----------------------------------------------------------------
        if use_minmax_normalization
            ref_img  = normalize_to_01(ref_img);
            test_img = normalize_to_01(test_img);
        else
            ref_img  = clamp_to_01(ref_img);
            test_img = clamp_to_01(test_img);
        end

        % ----------------------------------------------------------------
        % 可选：亮度均值校正
        %
        % 作用：
        % 把待测图平均亮度调整到参考图平均亮度。
        %
        % 注意：
        % 这会改变原始灰度分布。
        % 如果用于论文，需要说明“亮度校正后指标”。
        % ----------------------------------------------------------------
        if enable_mean_brightness_correction
            mean_ref_before  = mean(ref_img(:), 'omitnan');
            mean_test_before = mean(test_img(:), 'omitnan');

            test_img = test_img - mean_test_before + mean_ref_before;
            test_img = clamp_to_01(test_img);
        end

        % ----------------------------------------------------------------
        % 根据图像物理类型计算误差图
        % ----------------------------------------------------------------
        switch lower(image_physical_type)

            case 'normal'
                err_img = test_img - ref_img;

                ref_for_structural  = ref_img;
                test_for_structural = test_img;

            case 'angle_deg'
                % AOP 角度图，单位为度，默认 180° 周期
                err_img = angular_difference_deg(test_img, ref_img);

                ref_for_structural  = normalize_to_01(ref_img);
                test_for_structural = normalize_to_01(test_img);

            case 'angle_rad'
                % AOP 角度图，单位为弧度，默认 pi 周期
                err_img = angular_difference_rad(test_img, ref_img);

                ref_for_structural  = normalize_to_01(ref_img);
                test_for_structural = normalize_to_01(test_img);

            otherwise
                error('未知 image_physical_type，请使用 normal、angle_deg 或 angle_rad。');
        end

        % ----------------------------------------------------------------
        % MSE、RMSE、MAE、最大绝对误差
        % ----------------------------------------------------------------
        mse_val = mean(err_img(:).^2, 'omitnan');

        rmse_val = sqrt(mse_val);

        mae_val = mean(abs(err_img(:)), 'omitnan');

        max_abs_error_val = max(abs(err_img(:)), [], 'omitnan');

        % ----------------------------------------------------------------
        % SNR
        %
        % SNR = 10 * log10( sum(ref^2) / sum(error^2) )
        % ----------------------------------------------------------------
        signal_power = sum(ref_img(:).^2, 'omitnan');
        noise_power  = sum(err_img(:).^2, 'omitnan');

        if noise_power <= eps
            snr_db = Inf;
        else
            snr_db = 10 * log10(signal_power / noise_power);
        end

        % ----------------------------------------------------------------
        % PSNR
        %
        % 归一化图像峰值取 1。
        % PSNR = 10 * log10(1 / MSE)
        % ----------------------------------------------------------------
        if mse_val <= eps
            psnr_db = Inf;
        else
            psnr_db = 10 * log10(1 / mse_val);
        end

        % ----------------------------------------------------------------
        % SSIM
        % ----------------------------------------------------------------
        try
            ssim_val = ssim(test_for_structural, ref_for_structural, 'DynamicRange', 1);
        catch ME_ssim
            ssim_val = NaN;
            fprintf('[警告] SSIM 计算失败：%s\n', test_file_name);
            fprintf('       原因：%s\n', ME_ssim.message);
        end

        % ----------------------------------------------------------------
        % MS-SSIM
        % ----------------------------------------------------------------
        ms_ssim_val = NaN;

        if enable_ms_ssim

            if exist('multissim', 'file') == 2

                try
                    ms_ssim_val = multissim(test_for_structural, ref_for_structural, ...
                        'DynamicRange', 1);

                catch ME_msssim
                    ms_ssim_val = NaN;
                    fprintf('[警告] MS-SSIM 计算失败：%s\n', test_file_name);
                    fprintf('       原因：%s\n', ME_msssim.message);
                end

            else
                ms_ssim_val = NaN;

                if k == 1
                    fprintf('[提示] 当前 MATLAB 没有检测到 multissim 函数。\n');
                    fprintf('       MS-SSIM 将保存为 NaN。\n');
                    fprintf('       如需 MS-SSIM，请确认安装 Image Processing Toolbox。\n\n');
                end
            end
        end

        % ----------------------------------------------------------------
        % CorrCoef
        % ----------------------------------------------------------------
        ref_vec  = ref_img(:);
        test_vec = test_img(:);

        valid_mask = isfinite(ref_vec) & isfinite(test_vec);

        if sum(valid_mask) > 2
            corr_matrix = corrcoef(double(ref_vec(valid_mask)), double(test_vec(valid_mask)));
            corr_coef_val = corr_matrix(1, 2);
        else
            corr_coef_val = NaN;
        end

        % ----------------------------------------------------------------
        % NCC
        % ----------------------------------------------------------------
        ncc_val = calculate_ncc(ref_img, test_img);

        % ----------------------------------------------------------------
        % 均值和标准差
        % ----------------------------------------------------------------
        mean_ref  = mean(ref_img(:), 'omitnan');
        mean_test = mean(test_img(:), 'omitnan');

        std_ref  = std(ref_img(:), 'omitnan');
        std_test = std(test_img(:), 'omitnan');

        % ----------------------------------------------------------------
        % 保存结果
        % ----------------------------------------------------------------
        valid_count = valid_count + 1;

        result_cell(valid_count, :) = { ...
            valid_count, ...
            test_file_name, ...
            reference_image_path, ...
            test_path, ...
            ref_h, ...
            ref_w, ...
            ref_c, ...
            mse_val, ...
            rmse_val, ...
            mae_val, ...
            snr_db, ...
            psnr_db, ...
            ssim_val, ...
            ms_ssim_val, ...
            corr_coef_val, ...
            ncc_val, ...
            max_abs_error_val, ...
            mean_ref, ...
            mean_test, ...
            std_ref, ...
            std_test, ...
            enable_mean_brightness_correction ...
            };

        fprintf('[完成] %-30s | PSNR = %8.4f dB | SSIM = %.6f | MS-SSIM = %.6f | SNR = %8.4f dB\n', ...
            test_file_name, psnr_db, ssim_val, ms_ssim_val, snr_db);

        % ----------------------------------------------------------------
        % 清理当前循环变量，避免内存累积
        % ----------------------------------------------------------------
        clear ref_img test_img err_img ref_for_structural test_for_structural;
        clear ref_vec test_vec valid_mask corr_matrix;

    catch ME
        fprintf('[错误] 处理图像失败：%s\n', test_file_name);
        fprintf('       原因：%s\n', ME.message);

        clear ref_img test_img err_img ref_for_structural test_for_structural;
        clear ref_vec test_vec valid_mask corr_matrix;

        continue;
    end
end

clear ref_img_original;


%% ======================= 7. 保存结果 ===================================

if valid_count == 0
    error('没有成功计算任何图像，请检查路径、图像格式、尺寸或参考图设置。');
end

result_table = cell2table(result_cell, 'VariableNames', result_header);

writetable(result_table, excel_output_path);
writetable(result_table, csv_output_path);

fprintf('\n============================================================\n');
fprintf('全部图像计算完成。\n');
fprintf('成功计算图像数量：%d\n', valid_count);
fprintf('Excel 结果保存至：%s\n', excel_output_path);
fprintf('CSV   结果保存至：%s\n', csv_output_path);
fprintf('============================================================\n');


%% ======================= 8. 输出平均指标 ================================

finite_psnr = result_table.PSNR_dB(isfinite(result_table.PSNR_dB));
finite_snr  = result_table.SNR_dB(isfinite(result_table.SNR_dB));

mean_mse      = mean(result_table.MSE, 'omitnan');
mean_rmse     = mean(result_table.RMSE, 'omitnan');
mean_mae      = mean(result_table.MAE, 'omitnan');
mean_psnr     = mean(finite_psnr, 'omitnan');
mean_snr      = mean(finite_snr, 'omitnan');
mean_ssim     = mean(result_table.SSIM, 'omitnan');
mean_ms_ssim  = mean(result_table.MS_SSIM, 'omitnan');
mean_corrcoef = mean(result_table.CorrCoef, 'omitnan');
mean_ncc      = mean(result_table.NCC, 'omitnan');

fprintf('\n====================== 平均指标统计 ======================\n');
fprintf('平均 MSE      = %.6f\n', mean_mse);
fprintf('平均 RMSE     = %.6f\n', mean_rmse);
fprintf('平均 MAE      = %.6f\n', mean_mae);
fprintf('平均 SNR      = %.4f dB\n', mean_snr);
fprintf('平均 PSNR     = %.4f dB\n', mean_psnr);
fprintf('平均 SSIM     = %.6f\n', mean_ssim);
fprintf('平均 MS-SSIM  = %.6f\n', mean_ms_ssim);
fprintf('平均 CorrCoef = %.6f\n', mean_corrcoef);
fprintf('平均 NCC      = %.6f\n', mean_ncc);
fprintf('==========================================================\n');


%% ========================================================================
%                              局部函数区域
% ========================================================================


function file_list = get_image_file_list_no_duplicate(folder_path, image_extensions)
% 获取文件夹内所有图像文件，并修复重复读取问题
%
% 重点：
% Windows 文件系统通常不区分大小写。
% 如果同时搜索 *.png 和 *.PNG，可能把同一张图读两次。
%
% 本函数做法：
% 1. 只用 dir('*.*') 扫描一次所有文件；
% 2. 逐个检查扩展名；
% 3. 统一 lower 后判断格式；
% 4. 用 unique 去重；
% 5. 排序保证结果稳定。

    if ~exist(folder_path, 'dir')
        error('文件夹不存在：%s', folder_path);
    end

    % 统一扩展名为小写
    valid_exts = lower(image_extensions);

    % 扫描所有文件
    all_files = dir(fullfile(folder_path, '*.*'));

    file_list = {};

    for i = 1:numel(all_files)

        % 跳过文件夹
        if all_files(i).isdir
            continue;
        end

        current_name = all_files(i).name;
        [~, ~, current_ext] = fileparts(current_name);

        current_ext = lower(current_ext);

        % 判断是否属于支持格式
        if any(strcmp(current_ext, valid_exts))
            full_path = fullfile(all_files(i).folder, all_files(i).name);
            file_list{end+1, 1} = full_path; %#ok<AGROW>
        end
    end

    % 去重，防止 Windows 大小写匹配导致重复
    file_list = unique(file_list, 'stable');

    % 排序，保证每次运行顺序一致
    file_list = sort(file_list);
end


function img = read_and_preprocess_image(img_path, convert_rgb_to_gray)
% 读取图像并转换为 single 类型
%
% 输出：
% img 的数值范围会尽量转换到 [0,1]。
%
% 对 uint8：
%   除以 255
%
% 对 uint16：
%   除以 65535
%
% 对 single/double：
%   保留原数值，再交给后续 normalize 或 clamp 处理。

    img = imread(img_path);

    % 如果是 RGB 图，并且需要转灰度
    if convert_rgb_to_gray && ndims(img) == 3
        img = rgb2gray(img);
    end

    % 根据数据类型转换
    if islogical(img)
        img = single(img);

    elseif isa(img, 'uint8')
        img = single(img) / 255;

    elseif isa(img, 'uint16')
        img = single(img) / 65535;

    elseif isa(img, 'uint32')
        img = single(img) / single(intmax('uint32'));

    elseif isa(img, 'single')
        img = single(img);

    elseif isa(img, 'double')
        img = single(img);

    else
        img = single(img);
    end
end


function img_norm = normalize_to_01(img)
% 将图像 min-max 归一化到 [0,1]
%
% 公式：
% img_norm = (img - min(img)) / (max(img) - min(img))
%
% 如果图像是常数图，则输出全零图，避免除零。

    img = single(img);

    min_val = min(img(:), [], 'omitnan');
    max_val = max(img(:), [], 'omitnan');

    if ~isfinite(min_val) || ~isfinite(max_val)
        img_norm = img;
        return;
    end

    range_val = max_val - min_val;

    if range_val < eps
        img_norm = zeros(size(img), 'single');
    else
        img_norm = (img - min_val) / range_val;
    end

    img_norm = clamp_to_01(img_norm);
end


function img_out = clamp_to_01(img)
% 将图像限制到 [0,1]
%
% 如果 use_minmax_normalization = false，
% 这个函数可以避免极端异常值影响 PSNR/SSIM。

    img_out = single(img);

    img_out(img_out < 0) = 0;
    img_out(img_out > 1) = 1;
end


function diff_deg = angular_difference_deg(test_angle, ref_angle)
% 计算角度图的周期性误差，单位：度
%
% 适用于 AOP 图。
%
% 默认 AOP 具有 180° 周期。
% 例如：
% 89° 和 -89° 在普通相减下差 178°，
% 但在偏振方向意义下接近 2°。
%
% 如果你的角度定义是 0~360° 周期，
% 请把 period_deg 改为 360。

    period_deg = 180;

    raw_diff = test_angle - ref_angle;

    diff_deg = mod(raw_diff + period_deg / 2, period_deg) - period_deg / 2;

    diff_deg = single(diff_deg);
end


function diff_rad = angular_difference_rad(test_angle, ref_angle)
% 计算角度图的周期性误差，单位：弧度
%
% 默认 AOP 周期为 pi。
% 如果你的角度定义是 2*pi 周期，
% 请把 period_rad 改为 2*pi。

    period_rad = pi;

    raw_diff = test_angle - ref_angle;

    diff_rad = mod(raw_diff + period_rad / 2, period_rad) - period_rad / 2;

    diff_rad = single(diff_rad);
end


function ncc_val = calculate_ncc(ref_img, test_img)
% 计算 NCC：Normalized Cross Correlation
%
% 公式：
% NCC = sum((A-mean(A)) .* (B-mean(B))) /
%       sqrt(sum((A-mean(A)).^2) * sum((B-mean(B)).^2))
%
% NCC 越接近 1，说明两张图越相关。

    ref_vec  = single(ref_img(:));
    test_vec = single(test_img(:));

    valid_mask = isfinite(ref_vec) & isfinite(test_vec);

    ref_vec  = ref_vec(valid_mask);
    test_vec = test_vec(valid_mask);

    if numel(ref_vec) < 2
        ncc_val = NaN;
        return;
    end

    ref_vec  = ref_vec - mean(ref_vec, 'omitnan');
    test_vec = test_vec - mean(test_vec, 'omitnan');

    numerator = sum(ref_vec .* test_vec, 'omitnan');

    denominator = sqrt( ...
        sum(ref_vec.^2, 'omitnan') * ...
        sum(test_vec.^2, 'omitnan') ...
        );

    if denominator < eps
        ncc_val = NaN;
    else
        ncc_val = double(numerator / denominator);
    end
end