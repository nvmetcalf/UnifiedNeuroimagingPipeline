%% Subroutine for PVC pipeline

%% History

%% 2022/11/30 Chunwei
    %% Clean up the indentation
%% 2021/04/01 Chunwei
    %% Create file - From Yasheng Chen's code; NOT modified


function [sx, ex, sy, ey, sz, ez] = determine_window_range(i, j, k, dx, dy, dz, dimx, dimy, dimz)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if i-dx < 1
    sx = 1;
else
    sx = i-dx;
end;

if i+dx > dimx,
    ex = dimx;
else
    ex = i+dx;
end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if j-dy < 1
    sy = 1;
else
    sy = j-dy;
end;

if j+dy > dimy,
    ey = dimy;
else
    ey = j+dy;
end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if k-dz < 1
    sz = 1;
else
    sz = k-dz;
end;

if k+dz > dimz,
    ez = dimz;
else
    ez = k+dz;
end;
