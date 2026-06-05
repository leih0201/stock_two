% This simple demo examines if TVAL3 works normally. Please try more demos
% in the "Demos" directory, which would show users what TVAL3 is capable of.
% 
% I: 64x64 phantom (real, two-dimentional)
% A: random matrix without normality and orthogonality (real)
% f: observation with/without noise (real)
%
% Written by: Chengbo Li
% Advisor: Prof. Yin Zhang and Wotao Yin
% CAAM department, Rice University
% 05/21/2009

clear; close all;
path(path,genpath(pwd));
fullscreen = get(0,'ScreenSize');

% problem size
n = 256;   %%图像的尺寸
%ratio = .3;   %图像采样的比率
p = n; q = n; % p x q is the size of image   q,p是图像的尺寸
%m = round(ratio*n^2);   %图像采样的次数
m = 2624;
% sensing matrix
% A = rand(m,p*q)-.5;   %%生成测量矩阵，生成-0.5到0.5之间的随机数
A = readmatrix("C:\Users\kiywa\Desktop\双频域小论文\和平鸽\模拟\256M0.04.csv");
% original image
I = readmatrix("C:\Users\kiywa\Desktop\双频域小论文\和平鸽\模拟\橄榄枝.csv");
% I = imresize(I,[64 64]);
I = im2bw(I);
I255 = 255*I;
% I = logical(I);



% observation
f = A*I255(:);  %这里我们将图像排成一列处理，用观测矩阵
favg = mean(abs(f)); %求取绝对值，针对函数的每一列求取均值这里，favg是f向量的均值
% csvwrite('C:\Users\ASUS\Desktop\f0.csv',f);
% add noise加入噪声
% f = f + .00*favg*randn(m,1);%加入噪声
f1 = normalize(f,'range');
writematrix(f,"C:\Users\kiywa\Desktop\双频域小论文\和平鸽\模拟\橄榄枝f.csv")
%% Run TVAL3
clear opts
opts.mu = 2^8;
opts.beta = 2^5;
opts.tol = 1E-3;
opts.maxit = 300;
opts.TVnorm = 1;
opts.nonneg = true;

t = cputime;
[U, out] = TVAL3(A,f1,p,q,opts);
t = cputime - t;

subplot(121);
imshow(I,[]);
subplot(122); 
imshow(U,[]);
title('Recovered by TVAL3','fontsize',18);
xlabel(sprintf(' %2d%% measurements \n Rel-Err: %4.2f%%, CPU: %4.2fs ',ratio*100,norm(U-I,'fro')/nrmI*100,t),'fontsize',16);


% 
% imagesc(reshape(real(double((A(5,:)))),[32,32]));axis image