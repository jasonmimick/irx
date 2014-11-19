class irx.MockMedActionOperation extends EnsLib.HTTP.GenericOperation
{

Method SendMedicationUpdate(input as Ens.StreamContainer,output response as Ens.StringContainer) as %Status
{

	set response = ##class(Ens.StringContainer).%New()
	try {
		//$$$THROWONERROR(sc, medUpdate.%Save())
		//$$$TRACE("saved medUpdate %Id()="_medUpdate.%Id())
		set apikey="01C27474-5232-4A18-B797-EAC8224A58D6"
		set httpRequest=##class(%Net.HttpRequest).%New()
		do httpRequest.SetHeader("X-IRX-APIKEY",apikey)
		set httpRequest.EntityBody=input.Stream
		$$$THROWONERROR(sc,..Adapter.SendFormDataArray(.httpResponse,"POST",httpRequest))
		set response.StringValue=""
		if ( $isobject(httpResponse.Data) ) {
			do httpResponse.Data.Rewind()
			while ( 'httpResponse.Data.AtEnd ) {
				set response.StringValue = response.StringValue _ httpResponse.Data.Read() 
			}
		} else {
			set response.StringValue = httpResponse.Data
		}
	} catch error {
		$$$TRACE(error.DisplayString())
		set response.StringValue = error.DisplayString()
	}
	quit $$$OK
} 

XData MessageMap 
{
<MapItems>
	<MapItem MessageType="Ens.StreamContainer" >
		<Method>SendMedicationUpdate</Method>
	</MapItem>
	
</MapItems>
}

}
