class irx.ParticipantMap extends (%Persistent) [ classtype = persistent ]
{

Property iRxID as %String;

Property identifier as %String;

Property source as %String;

Property type as %String;

Index TypeIndex on (type, identifier, iRxID);

ClassMethod saveFromJSON(json as %String) as irx.ParticipantMap
{
	try {
	  set me=##class(irx.util.JSON).toObject(json,..%ClassName(1))
	  $$$THROWONERROR(sc,.me.%Save())
	  return me
	} catch error {
		throw error
	}
}

}
