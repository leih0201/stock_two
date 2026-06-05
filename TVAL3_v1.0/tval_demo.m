clear; close all;
path(path,genpath(pwd));
fullscreen = get(0,'ScreenSize');

% problem size
n = 64;   %%图像的尺寸
% ratio = 0.2; %图像采样的比率
p = n; q = n; %q,p是图像的尺寸
% m = round(ratio*n^2); %图像采样的次数
m = 512;

%% 读取矩阵
% M.csv ="C:\Users\ASUS\Desktop\rand_fdri\m.csv";%读入csv数据
A = csvread(M.csv,0,0);


%% 光子计数统计
[f, sampletimes] = photoncnt_function(1728,"F:\fourier\T2_2023_11_01_10_52_08_s0.txt");



%% Run TVAL3
for i = 1:sampletimes
% clear opts
% opts.mu = 2^12;
% opts.beta = 2^10;
% % opts.mu0 = 2^13;       % trigger continuation shceme
% % opts.beta0 = 2^-2;    % trigger continuation shceme
% opts.maxcnt = 8;
% opts.tol_inn = 1e-8;
% opts.tol = 1e-8;
% opts.maxit = 1000;
%% 频域成像参数
clear opts
opts.mu = 2^12;
opts.beta = 2^8;
opts.mu0 = 2^4;       % trigger continuation shceme
opts.beta0 = 2^-5;    % trigger continuation shceme
opts.maxcnt = 10;
opts.tol_inn = 1e-16;
opts.tol = 1e-4;
opts.maxit = 1000;
f = importdata(strcat("C:\Users\kiywa\Desktop\ 数据提取\",num2str(i),".txt"));
[U, out] = TVAL3(A,f,p,q,opts);
% t = cputime;
% t = cputime - t;
%% 将输出U变成0-255
ymax=1;ymin=0;
xmax = max(max(U)); %求得InImg中的最大值
xmin = min(min(U)); %求得InImg中的最小值
Img = round((ymax-ymin)*(U-xmin)/(xmax-xmin) + ymin); %归一化并取整


% filename = "C:\Users\ASUS\Desktop\reconstruction\data"+i+".jpg";
% writematrix(U,filename);
% imwrite(U,strcat("C:\Users\ASUS\Desktop\reconstruction\",num2str(i),'.jpg'));
% subplot(111); 
% imshow(U,[]);
%% 截图保存
himage = imshow(U,[],'border','tight','initialmagnification','fit');
set(gcf,'Position',[100,100,64,120]);
% saveas(himage,strcat("C:\Users\ASUS\Desktop\reconstruction\325k",num2str(i),'.jpg'));


% subplot(122); 
% surf(U);
% imshow(U,[]);
% im_ref = imread("E:\data\ref.png");
% im_ref = double(im_ref);
% nrmI = norm(im_ref,'fro');
% err = norm(U-im_ref,'fro')/nrmI*100;
% SNR = psnr(Img,im_ref,max(im_ref));
% SNR
end





