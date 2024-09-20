function M = munzip(Z)

    import com.mathworks.mlwidgets.io.InterruptibleStreamCopier
    a=java.io.ByteArrayInputStream(Z);
    b=java.util.zip.InflaterInputStream(a);
    isc = InterruptibleStreamCopier.getInterruptibleStreamCopier;
    c = java.io.ByteArrayOutputStream;
    isc.copyStream(b,c);
    Q=typecast(c.toByteArray,'uint8');
    cn = double(Q(1)); % class
    nd = double(Q(2)); % # dims
    s = typecast(Q(3:8*nd+2),'double')'; % size
    Q=Q(8*nd+3:end);
    if cn == 3
        M  = logical(Q);
    elseif cn == 4
        M = char(Q);
    else
        ct = {'double','single','logical','char','int8','uint8',...
            'int16','uint16','int32','uint32','int64','uint64'};
        M = typecast(Q,ct{cn});
    end
    M=reshape(M,s);
return
