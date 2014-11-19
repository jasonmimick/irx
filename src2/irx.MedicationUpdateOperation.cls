class irx.MedicationUpdateOperation extends EnsLib.HTTP.GenericOperation
{

Method SendMedicationUpdate(medUpdate as irx.MedicationUpdate,output response as Ens.StringContainer) as %Status
{

	set response = ##class(Ens.StringContainer).%New()
	try {
		//$$$THROWONERROR(sc, medUpdate.%Save())
		//$$$TRACE("saved medUpdate %Id()="_medUpdate.%Id())
		set ..Adapter.URL = "/prescription/"_medUpdate.study_"/"_medUpdate.user
		$$$THROWONERROR(sc,..Adapter.Post(.httpResponse,"medication,schedule,dosage,mood",medUpdate.medication,medUpdate.schedule, medUpdate.dosage, medUpdate.mood))	
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
	<MapItem MessageType="irx.MedicationUpdate" >
		<Method>SendMedicationUpdate</Method>
	</MapItem>
	
</MapItems>
}

}
