function dbConn = MySQL_Connect(Server, DatabaseName, Username, Password)
    addpath(fullfile([getenv('PP_SCRIPTS') '/matlab_scripts/queryMySQL/queryMySQL/src']));
    javaaddpath([getenv('PP_SCRIPTS') '/matlab_scripts/queryMySQL/queryMySQL/lib/mysql-connector-java-5.1.6/mysql-connector-java-5.1.6-bin.jar']);

    %% import classes
    import edu.stanford.covert.db.MySQLDatabase;

    if(~exist('Server'))
        Server = 'goya.neuroimage.wustl.edu'
    end
    
    if(~exist('DatabaseName'))
        DatabaseName = 'neuro_db_0.1'
    end
    
    if(~exist('Username'))
        Username = 'user';
    end
    
    if(~exist('Password'))
        Password = 'user';
    end
    
    %% create database connection
    dbConn = MySQLDatabase(Server,DatabaseName, Username, Password);

end