function Z = mzip(M)
    
    s = size(M);
    c = class(M);
    cn = strmatch(c,{'double','single','logical','char','int8','uint8',...
        'int16','uint16','int32','uint32','int64','uint64'});
    if cn == 3 | cn == 4
        M=uint8(M);
    end
    M=typecast(M(:),'uint8');
    M=[uint8(cn);uint8(length(s));typecast(s(:),'uint8');M(:)];
    f=java.io.ByteArrayOutputStream();
    g=java.util.zip.DeflaterOutputStream(f);
    g.write(M);
    g.close;
    Z=typecast(f.toByteArray,'uint8');
    f.close;
return
