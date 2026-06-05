%% 2023.01.08 生成稀疏观测矩阵

clear; close all;

n = 64;   %%图像的尺寸
% ratio = 0.3;   %图像采样的比率
% p = n; q = n; % p x q is the size of image   q,p是图像的尺寸
% m = round(ratio*n^2);   %图像采样的次数 1229
m = 464;
%% 读取矩阵
x0.csv ="C:\Users\kiywa\Desktop\m.csv";%读入csv数据
%诀窍：把矩阵想象成矩形，左上角的坐标即可涵盖左下角内所有数据，添加了右下角坐标即可指定涵盖的区域
M = csvread(x0.csv,0,0);




%% 把矩阵变成图片 

% for M = 1:m
% B = A(M,:);   %把A的M行变成向量
% B = reshape(B,[256,256]);% 把B变成矩阵


%% 矩阵放大到1024*768
% Row0 = size(B,1);%读取行列数
% Col0 = size(B,2);
% enlarge_Row = 3;%行列放大倍数，表示是反的，完了改一下
% enlarge_Col = 4;
% Row1 = round(enlarge_Row*Row0);%放大后的行数
% Col1 = round(enlarge_Col*Col0);
% C = zeros(Row1,Col1);
% for i=1:Row1
%   for j=1:Col1
%      x=round(i/enlarge_Row);%最小临近法对图像进行插值
%      y=round(j/enlarge_Col);
%      处理边缘
%      if x==0 x=1;end
%      if y==0 y=1;end
%      if x>Row0 x=Row0;end
%      if y>Col0 y=Col0;end
%      C(i,j,:)=B(x,y,:);
%    end
% end




parfor j = 1:length(M(:,1))
B = M(j,:);   %把A的M行变成向量
B = reshape(B,[64,64]);% 把B变成64*64矩阵
B = logical(B);
resized_B = imresize(B,[768 1024]);
resized_B = logical(resized_B);%把矩阵变成二值的矩阵，不然生产的是8位
imwrite(resized_B,strcat('C:\Users\ASUS\Desktop\fdri_60Hz\',num2str(j),'.bmp'));
end


% end
close all;
clear;
clc;
M = readmatrix("C:\Users\kiywa\Desktop\m_0.3.csv");
% M = -1*(M-1);
map_num = length(M(:,1));

            for l = 1:map_num
                m = zeros(768,1024);%769:896 先弄正方形
                map = M(l,:);   %把A的M行变成向量
                map = reshape(map,[128,128]);% 把B变成64*64矩阵
                map = logical(map);
                resized_map = imresize(map,[768 768]);
                m(:,129:896) = resized_map;
                m = logical(m);
                imwrite(m,strcat('E:\128_0.3\',num2str(l),'.bmp'));
            end
  



close all;
clear;
clc;
M = readmatrix("C:\Users\kiywa\Desktop\m_0.3.csv");
% M = -1*(M-1);
map_num = length(M(:,1));

            for l = 1:map_num
%                 m = zeros(768,1024);%769:896 先弄正方形
                map = M(l,:);   %把A的M行变成向量
                map = reshape(map,[128,128]);% 把B变成64*64矩阵
                map = logical(map);
                resized_map = imresize(map,[768 1024]);
                m = resized_map;
                m = logical(m);
                imwrite(m,strcat('E:\128_0.3_full\',num2str(l),'.bmp'));
            end