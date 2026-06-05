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
m = 5248;
% sensing matrix
% A = rand(m,p*q)-.5;   %%生成测量矩阵，生成-0.5到0.5之间的随机数
% A = randsrc(m,4096,[0 1 ; 0.5 0.5]);

% A = readmatrix('C:\Users\ASUS\Desktop\成功频域成像案例\M.csv');"C:\Users\ASUS\Desktop\rand_fdri\m.csv"
A = readmatrix("C:\Users\kiywa\Desktop\0.08.csv");
% original image
% I = readmatrix("C:\Users\ASUS\Desktop\成功频域成像案例\signal.csv");
% for i = 1:1024
%     if I(i) == 1
%        I(i) = 0;
% %     elseif I(i) == 1
% %         I(i) = 255;
%     end
% end
% I = imresize(I,[64 64]);
% I = im2bw(I);
%% 二维码
for i = 1:20
    
I = imread(strcat("C:\Users\kiywa\Desktop\0130\double_frequency_256_600us\0.08\r\",num2str(i),".bmp"));
% I = 255*double(im2bw(I));
% I = imresize(I,[256 256]);
imshow(I,[])


% observation
f = A*I(:);  %这里我们将图像排成一列处理，用观测矩阵
favg = mean(abs(f)); %求取绝对值，针对函数的每一列求取均值这里，favg是f向量的均值
% csvwrite('C:\Users\ASUS\Desktop\f0.csv',f);
% add noise加入噪声
%  f = f + .00*favg*randn(m,1);%加入噪声


%% Run TVAL3
% clear opts
% opts.mu = 2^8;
% opts.beta = 2^5;
% opts.tol = 1E-3;
% opts.maxit = 300;
% opts.TVnorm = 1;
% opts.nonneg = true;

clear opts
opts.mu = 2^6;
opts.beta = 2^3;
opts.mu0 = 2^4;       % trigger continuation shceme
opts.beta0 = 2^-5;    % trigger continuation shceme
opts.maxcnt = 10;
opts.tol_inn = 1e-16;
opts.tol = 1e-4;
opts.maxit = 1000;




[U, out] = TVAL3(A,f,p,q,opts);

U = medfilt2(U);

subplot(122); 
imagesc(U);axis image;colorbar
% imshow(U,[]);
% title('Recovered by TVAL3','fontsize',18);
% xlabel(sprintf(' %2d%% measurements \n Rel-Err: %4.2f%%, CPU: %4.2fs ',ratio*100,norm(U-I,'fro')/nrmI*100,t),'fontsize',16);
% 
% writematrix(f,"C:\Users\ASUS\Desktop\成功频域成像案例\f1.csv")
% % 
% imagesc(reshape(real(double((A(5,:)))),[32,32]));axis image



rgb2gray()

I = imread("C:\Users\ASUS\Desktop\压缩感知多波长检测成像专利\变压器\图片1.bmp");
I = double(I(:,:,1));
contour(I,'ShowText','on','LineWidth',2,'LabelSpacing',1000);
writematrix(U,"C:\Users\ASUS\Desktop\压缩感知多波长检测成像专利\变压器\2.csv")
imshow(U,[]);