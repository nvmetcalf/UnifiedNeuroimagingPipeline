function [newmat] = VectoMat(native,d)
% restore matrix
newmat=nan(d,d);
c=1;
for i=1:d
    for j=i+1:d
        newmat(i,j)=native(c);
        newmat(j,i)=native(c);
        c=c+1;
    end
end
       