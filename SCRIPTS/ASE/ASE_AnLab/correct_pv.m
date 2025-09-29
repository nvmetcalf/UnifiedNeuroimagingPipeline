%% Subroutine for PVC pipeline - NOT USED (?)

%% History

%% 2022/11/30 Chunwei
    %% Clean up the indentation
%% 2021/04/01 Chunwei
    %% Create file - From Yasheng Chen's code; NOT modified



function [im_gm, im_wm, im_csf, mask_pv] = correct_pv(im, mk, gm, wm, csf, nx, ny, nz)

dimx = size(im, 1);
dimy = size(im, 2);
dimz = size(im, 3);

im_gm = zeros(size(im));
im_wm = zeros(size(im));
im_csf = zeros(size(im));

brain = gm+wm+csf;

s3 = eye(3)*1e-10;
s2 = eye(2)*1e-10;

mask_pv = zeros(dimx, dimy, dimz);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for i=1:dimx,
    for j=1:dimy,
        for k=1:dimz,
            if mk(i,j,k) == 0 | brain(i,j,k) < 0.5 | csf(i,j,k) > 0.8
                continue;
            end;
            [sx, ex, sy, ey, sz, ez] = determine_window_range(i, j, k, nx, ny, nz, dimx, dimy, dimz);
            index=1;
            mask_pv(i,j,k) = 1;
            for ii=sx:ex,
                for jj=sy:ey,
                    for kk=sz:ez,
                        if mk(ii,jj,kk)==0 | brain(i,j,k) <=0.8 | csf(i,j,k) > 0.9 
                            continue;
                        end;

                        coeff1(index, 1) = gm(ii,jj,kk) / (gm(ii,jj,kk) + wm(ii,jj,kk)+csf(ii,jj,kk)+eps);
                        coeff1(index, 2) = wm(ii,jj,kk) / (gm(ii,jj,kk) + wm(ii,jj,kk)+csf(ii,jj,kk)+eps);
                        coeff1(index, 3) = csf(ii,jj,kk) / (gm(ii,jj,kk) + wm(ii,jj,kk)+csf(ii,jj,kk)+eps);

                        %coeff2(index, 1) = gm(ii,jj,kk) / (gm(ii,jj,kk) + wm(ii,jj,kk)+eps);
                        %coeff2(index, 2) = wm(ii,jj,kk) / (gm(ii,jj,kk) + wm(ii,jj,kk)+eps);

                        I(index,:) = im(ii,jj,kk,:);
                        index=index+1;
                    end;
                end;
            end;

            p1 = I'*coeff1*inv(coeff1'*coeff1+s3); p1 = p1';

            im_gm(i,j,k,:) = p1(1,:);
            im_wm(i,j,k,:) = p1(2,:);
            im_csf(i,j,k,:) = p1(3,:);

            clear p1 coeff1 coeff2 I;
        end;
    end;
end;
