clc;
clear;
close all;

%% =========================
% 读取图像
% ==========================

% DOP图
dop_532 = im2double(imread('F:\code\stocks_two\rh_images\dop_532.png'));
dop_905 = im2double(imread('F:\code\stocks_two\rh_images\dop_905.png'));

% AOP图
aop_532 = im2double(imread('F:\code\stocks_two\rh_images\aop_532.png'));
aop_905 = im2double(imread('F:\code\stocks_two\rh_images\aop_905.png'));

% 若为RGB则转灰度
if size(dop_532,3)==3
    dop_532 = rgb2gray(dop_532);
end

if size(dop_905,3)==3
    dop_905 = rgb2gray(dop_905);
end

if size(aop_532,3)==3
    aop_532 = rgb2gray(aop_532);
end

if size(aop_905,3)==3
    aop_905 = rgb2gray(aop_905);
end

%% =========================
% AOP映射到0~pi
% ==========================

aop_532 = aop_532 * pi;
aop_905 = aop_905 * pi;

%% =========================
% DOP融合
% ==========================

alpha = 0.7;

dop_fusion = alpha * dop_532 + (1-alpha) * dop_905;

%% =========================
% AOP矢量融合
% ==========================

sin_532 = sin(2 * aop_532);
cos_532 = cos(2 * aop_532);

sin_905 = sin(2 * aop_905);
cos_905 = cos(2 * aop_905);

sin_fusion = alpha * sin_532 + (1-alpha) * sin_905;
cos_fusion = alpha * cos_532 + (1-alpha) * cos_905;

aop_fusion = 0.5 * atan2(sin_fusion, cos_fusion);

% 归一化
aop_fusion_norm = mat2gray(aop_fusion);

%% =========================
% DOP边缘增强
% ==========================

[Gx, Gy] = imgradientxy(dop_fusion, 'sobel');

edge_dop = sqrt(Gx.^2 + Gy.^2);

edge_dop = mat2gray(edge_dop);

%% =========================
% AOP边缘增强
% ==========================

lap_filter = fspecial('laplacian', 0.2);

edge_aop = imfilter(aop_fusion_norm, lap_filter);

edge_aop = abs(edge_aop);

edge_aop = mat2gray(edge_aop);

%% =========================
% 最终融合增强
% ==========================

beta = 0.6;
gamma = 0.4;

final_enhance = ...
    dop_fusion ...
    + beta * edge_dop ...
    + gamma * edge_aop;

final_enhance = mat2gray(final_enhance);

%% =========================
% CLAHE局部增强
% ==========================

final_clahe = adapthisteq(final_enhance,...
    'ClipLimit',0.02,...
    'NumTiles',[8 8]);

%% =========================
% 显示结果
% ==========================

figure('Color','white');

subplot(2,3,1);
imshow(dop_532,[]);
title('DOP 532nm');

subplot(2,3,2);
imshow(dop_905,[]);
title('DOP 905nm');

subplot(2,3,3);
imshow(dop_fusion,[]);
title('Fusion DOP');

subplot(2,3,4);
imshow(edge_dop,[]);
title('DOP Edge');

subplot(2,3,5);
imshow(edge_aop,[]);
title('AOP Edge');

subplot(2,3,6);
imshow(final_clahe,[]);
title('Final Enhanced');

%% =========================
% 保存结果
% ==========================

imwrite(dop_fusion, 'fusion_dop.png');

imwrite(aop_fusion_norm, 'fusion_aop.png');

imwrite(final_clahe, 'final_enhanced.png');

disp('融合增强完成！');