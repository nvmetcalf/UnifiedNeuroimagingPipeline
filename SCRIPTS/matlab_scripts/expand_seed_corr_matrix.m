% Xin Hong: Original Author
% Nicholas Metcalf: Simplified args, added dimension check, write out new
%                       matrix, replace diag of new matrix with inf.
function expand_seed_corr_matrix(SubjectID, total_ROI )
% refill the NaN into scrubbed matrix and get complet matrix
% and replace all Inf to be NaN
    scrubbed_matrix = [SubjectID '_seed_regressors_CCR_zfrm.dat'];
    Subject=importdata(scrubbed_matrix);
    usedROI=importdata('MaskedRegionsUsed.txt');

    Valid_ROI_Indices = usedROI.data(:,1);

    if(length(Valid_ROI_Indices) > total_ROI)
        error('Dimensions of input matrix is equal to or greater than the resized matrix dimensions.');
    elseif(length(Valid_ROI_Indices) == total_ROI)
        disp('No regions have been excluded.');
        copyfile([SubjectID '_seed_regressors_CCR_zfrm.dat'], [SubjectID '_seed_regressors_CCR_zfrm_expnd.dat']);
        return;
    end
    
    ExpandendMatrix = nan(total_ROI,total_ROI);
    ExpandedMatrixOutname = [SubjectID '_seed_regressors_CCR_zfrm_expnd.dat'];

    for i = 1:length(Valid_ROI_Indices);
        row = Valid_ROI_Indices(i);
        for j = 1:length(Valid_ROI_Indices);
            column = Valid_ROI_Indices(j);
            ExpandendMatrix(row, column) = Subject(i,j);
        end
    end

    File = fopen(ExpandedMatrixOutname,'w+');

    j = 1;
    for i = 1:length(ExpandendMatrix(:,1))
        ExpandendMatrix(i,j) = inf;
        Buffer = VectorToString(ExpandendMatrix(i,:));
        fwrite(File,sprintf('%s\n',Buffer));
        j = j + 1;
    end

end

