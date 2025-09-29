function segment_t1(patid, WorkingDirectory)

   fprintf('%s\n', patid);
   
   run_t1_process_1_reorient_resample(WorkingDirectory, patid)
   run_t1_process_2_spm_seg(WorkingDirectory, patid)

end