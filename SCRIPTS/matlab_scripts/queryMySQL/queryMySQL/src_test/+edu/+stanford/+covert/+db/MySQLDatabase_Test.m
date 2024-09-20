classdef MySQLDatabase_Test < TestCase
    methods
        function this = MySQLDatabase_Test(name)
            this = this@TestCase(name);
        end
        
        function testBlobStoringLoading(~)
            %create database connection
            database = edu.stanford.covert.db.MySQLDatabase(...
                'covertlab.stanford.edu', 'test', 'test', 'test');
            database.setNullValue(0);
            
            %write data to file
            data = char((0:32)');
            fname = tempname;
            fid = fopen(fname,'wb');
            fwrite(fid, data);
            fclose(fid);

            %store blob
            database.prepareStatement('CALL testBlobIn("{Si}","{F}")', 10001, fname);            
            database.query();
            delete(fname);
            
            %get last insert id
            database.lastInsertID();

            %load blob
            database.prepareStatement('CALL testBlobOut("{Si}")', 10001);
            result = database.query();
            assertEqual(data, char(result.data{1}));
            
            %close database connection
            database.close();
        end
    end
end
