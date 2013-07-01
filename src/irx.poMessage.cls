Number of args=2,pull,irx.poMessage.cls,
/// Wrap some persistence around %ZEN.proxyObject's
Class irx.poMessage Extends Ens.Request
{

Property Data As %String(MAXLEN=5000)[ MultiDimensional ];

Property JSON As %Stream.GlobalCharacter;

Method json() As %String 
 {
	do ..JSON.Rewind()
	set line = ..JSON.ReadLine()
	while ( '..JSON.AtEnd ) {
		set line=line_..JSON.ReadLine()
	}
	return line
 }

// Create an instance from a proxyObject

ClassMethod createFromPO(&po:%ZEN.proxyObject) As irx.poMessage 
 {
	
	set me=..%New()
	set me.JSON = ##class(%Stream.GlobalCharacter).%New()
	do ##class(%ZEN.Auxiliary.jsonProvider).%WriteJSONStreamFromObject(me.JSON,po)
	do po.%CopyToArray(.data)
	set key=$order(data(""))
	while ( key'="" ) {
		set me.Data(key)=data(key)	
		set key=$order(data(key))
	}
	set sc=me.%Save()
	return me
 }

}
