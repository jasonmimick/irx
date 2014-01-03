class irx.ActionQOperation extends Ens.BusinessOperation
{

Method OnHTTPRequest(request as EnsLib.HTTP.GenericMessage, output response as EnsLib.HTTP.GenericMessage) As %Status
{
	quit $$$OK
}

/// No response - this is called async
Method OnRestRequest(request as irx.RestRequest,output response as Ens.Response) As %Status
{
	set response = ##class(Ens.StringContainer).%New()
	try {
		set inreq = ##class(irx.util.JSON).toObject(request.Content) 
		$$$TRACE(request.Content)	
		if ( '$isobject( inreq ) ) {
			throw ##class(%Exception.General).%New("irx","irx",,"No valid JSON content.")
		}
		if ( inreq.action="" ) {
			set inreq.action = "Unknown"
			$$$TRACE("Unknown action")
			//set response.status = response.status _ "Warning: No 'action' found. "
		}
		if ( inreq.participant="" ) {
			set inreq.participant = "?????"
			$$$TRACE("Unknown participant")
			//set response.status = response.status _ "Warning: No 'participant' found. "
		}
		set qitem = ##class(irx.ActionQ).%New()
		set qitem.Source = request.Source
		set qitem.ControlId = request.ControlId
		set qitem.Timestamp = request.Timestamp
		set qitem.Action = inreq.action
		set qitem.Participant = inreq.participant
		set qitem.Data = request.Content
		$$$THROWONERROR(sc,qitem.%Save())
		set response.StringValue = "irx.ActionQ.Id = "_qitem.%Id()
		$$$TRACE(response.StringValue)
	} catch error {
		/// Log error
		$$$TRACE(error.DisplayString())
		set response.StringValue = "error:"_error.DisplayString()
		do error.Log()
	}
	quit $$$OK
} 
XData MessageMap 
{
<MapItems>
	<MapItem MessageType="EnsLib.HTTP.GenericMessage" >
		<Method>OnHTTPRequest</Method>
	</MapItem>
	<MapItem MessageType="irx.RestRequest" >
		<Method>OnRestRequest</Method>
	</MapItem>
	
</MapItems>

}

}
