function [ DataSet Data] = query_GetBehavioral( ProjectName, varargin )
%query_GetBehavioral cycles through the varargin to query the databasse for
%   will join on the participant ID and ProjectID

    %connect to the database
    dbConn = MySQL_Connect('goya.neuroimage.wustl.edu','neuro_db_0.1','user','user');

    %gather the project information
    %ProjectName = 'FCStroke';
    dbConn.prepareStatement(['SELECT ProjectID, IRB_Number FROM Projects WHERE ProjectName = "' ProjectName '"']);
    query = dbConn.query();
    
    IRB_Number = num2str(query.IRB_Number);
    ProjectID = num2str(query.ProjectID);
    
    Data = [];
    for i = 1:length(varargin)
        
        dbConn.prepareStatement(['SELECT Measurements.ParticipantID, Measurements.Project_Participant_ID, Measurements.MeasurementName, Measurements.MeasurementValue, Measurements.Timepoint, Demographics.HealthyControl FROM `neuro_db_0.1`.Measurements, `neuro_db_0.1`.Demographics WHERE Measurements.MeasurementName = "' varargin{i} '" AND Demographics.ParticipantID = Measurements.ParticipantID GROUP BY Measurements.ParticipantID, Measurements.Project_Participant_ID, Measurements.MeasurementName, Measurements.MeasurementValue, Measurements.Timepoint ORDER BY Measurements.Project_Participant_ID']);
        query = dbConn.query();
        
        Data = vertcat(Data, query);
    end
    
    size(Data);
    
    %no for each unique participant ID, make a new cell matrix that has all
    %the data associated with them
    
    ParticipantIDs = [];
    Timepoints = [];
    ProjectParticipantIDs = [];
    HealthyControl = [];
    for i = 1:length(Data)
        ParticipantIDs = vertcat(ParticipantIDs, Data(i).ParticipantID);
        Timepoints = vertcat(Timepoints, Data(i).Timepoint);
        ProjectParticipantIDs =  vertcat(ProjectParticipantIDs, Data(i).Project_Participant_ID);
        HealthyControl = vertcat(HealthyControl, Data(i).HealthyControl);
    end
    
    [ParticipantIDs, ia ic] = unique(ParticipantIDs);
    ProjectParticipantIDs = ProjectParticipantIDs(ia);
    HealthyControl = HealthyControl(ia);
    
    Timepoints = unique(Timepoints);
    
    DataSet = {'ParticipantID','Timepoint','HealthyControl', 'ProjectParticipantID','ProjectName','ProjectID'};
    DataSet = horzcat(DataSet, varargin);
    
    for i = 1:length(ParticipantIDs)
        ProjectParticipantID = ProjectParticipantIDs(i);
        for j = 1:length(Timepoints)
           
            Record = {ParticipantIDs(i), Timepoints(j), HealthyControl(i), ProjectParticipantID, ProjectName, ProjectID };
            for k = 1:length(Data);
                Value = Data(k).MeasurementValue(find( Data(k).ParticipantID == ParticipantIDs(i) & Data(k).Timepoint == Timepoints(j),1,'first'));
                if(isempty(Value))
                    Value = {NaN};
                end
                
                Record = horzcat(Record, Value)
                
            end
            DataSet = vertcat(DataSet, Record);
        end
    end
end

