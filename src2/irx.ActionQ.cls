/// Stores all actions from iRx
class irx.ActionQ extends %Persistent [ classtype = persistent ]
{

/// Where did this action come from 
/// irx == from the iRx control center
Property Source as %String(MAXLEN = "");

/// Who is this action about - the iRx participant id
Property Participant as %String;

/// When
Property Timestamp as %TimeStamp;

/// Short string descibing what this action is 
/// e.g. 'taken'
Property Action as %String(MAXLEN = "");

/// The raw data sent in - full message
Property Data as %String(MAXLEN = "");

/// Control ID from processing request
Property ControlId as %String;

Index SourceIndex on (Source,Participant);
Index ActionIndex on (Action,Participant);
Index TimeIndex on (Timestamp,Participant);

}
