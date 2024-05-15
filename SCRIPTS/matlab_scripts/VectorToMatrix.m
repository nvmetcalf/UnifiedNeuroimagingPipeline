function [ ResultMatrix ] = VectorToMatrix( Vector, n )
    n = int32(n);
    ResultMatrix(n,n) = 0;
    l = 1;
    for i = 1:n
        ResultMatrix(i,i+1:n) = Vector(l:(l+(n-i)-1));
        ResultMatrix(i+1:n,i) = Vector(l:(l+(n-i)-1));
        l = l + (n-i);
    end
end

