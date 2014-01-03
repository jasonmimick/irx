class irx.util.JSON extends %RegisteredObject
{

ClassMethod toObject(json as %String, classname as %String) as %RegisteredObject
{
	try {
		$$$THROWONERROR(sc, ##class(%ZEN.Auxiliary.jsonProvider).%ConvertJSONToObject(json, classname, .object))
		if ( '$isobject(object) ) {
			// can this happen?
		}
		return object
	} catch error {
		throw error
	}

}
