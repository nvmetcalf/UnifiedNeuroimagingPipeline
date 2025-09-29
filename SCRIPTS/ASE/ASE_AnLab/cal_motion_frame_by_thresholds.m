%% Subroutine for ASE pipeline
%% AnLab 2025/02/10

function sign_motion = cal_motion_frame_by_thresholds(rx, ry, rz, tx, ty, tz, thre_angle, thre_tran)

   num = length(rx);

   rx_diff = abs(rx(2:end)-rx(1:end-1));
   ry_diff = abs(ry(2:end)-ry(1:end-1));
   rz_diff = abs(rz(2:end)-rz(1:end-1));

   tx_diff = abs(tx(2:end)-tx(1:end-1));
   ty_diff = abs(ty(2:end)-ty(1:end-1));
   tz_diff = abs(tz(2:end)-tz(1:end-1));

   %fprintf('max rotation %f %f %f, max translation %f %f %f\n', max(rx_diff), max(ry_diff), max(rz_diff), max(tx_diff), max(ty_diff), max(tz_diff));

   I = find(rx_diff>thre_angle | ry_diff>thre_angle | rz_diff>thre_angle | tx_diff>thre_tran | ty_diff>thre_tran | tz_diff>thre_tran);

   sign_motion = zeros(num, 1);
   sign_motion(I+1) = 1;

   clear rx_diff ry_diff rz_diff tx_diff ty_diff tz_diff I; 

