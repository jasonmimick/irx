/// Inbound endpoint for REST requests
/// Incoming requests are parsed and persisted
/// Checks HTTP headers for any 'control' requests
/// Expects the first part of the URL path to be the source - /irx
/// Future endpoints can be established for other paths
Class irx.InboundRESTService Extends (EnsLib.HTTP.Service, Ens.Util.JSON) [ ProcedureBlock ]
{

Parameter ADAPTER = "EnsLib.HTTP.InboundAdapter";

/// Configuration item to which to send messages
Property TargetConfigNames As Ens.DataType.ConfigName;

Parameter SETTINGS = "TargetConfigNames:Basic:selector?multiSelect=0&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId}";

/// 
Parameter IRX = "irx";

Parameter ControlHeader = "x-irx-control";
Parameter ApiKeyHeader = "x-irx-apikey";

Property ControlHeaderValue as %String;
Property ApiKey as %String;

/// Populates instance headers property
Method ProcessHeaders(input as %Library.AbstractStream)
{
	set ..ControlHeaderValue = $get( input.Attributes(..#ControlHeader) )
	set ..ApiKey = $get( input.Attributes(..#ApiKeyHeader) )	
}

Method ValidateApiKey() As %Boolean
{
	return ( ..ApiKey = ^irx.System("api-key") )
}


Method ProcessControlHeader(pInput As %Library.AbstractStream, Output pOutput As %Stream.Object) As %Status
{
	set pOutput = ##class(%GlobalBinaryStream).%New()
	do pOutput.WriteLine("ProcessControlHeader ControlHeaderValue="_..ControlHeaderValue)
	quit $$$OK
}

Method OnProcessInput(pInput As %Library.AbstractStream, Output pOutput As %Stream.Object) As %Status
{
	Set tCmd=$ZConvert(pInput.Attributes("HttpRequest"),"U")
	Set tURL=$ZConvert(pInput.Attributes("URL"),"I","URL")
	do ..ProcessHeaders( pInput )
	if ( '$data(^irx.System("api-key") ) ) {
		quit $$$ERROR("irx","Check system configuration, no api-key set!")
	}	
	if ( '..ValidateApiKey() ) {
		quit $$$ERROR("irx","Invalid api-key.")
	}
	Set tService=$ZConvert($Piece(tURL,"/",2),"L")  Quit:"irx"'=tService $$$ERROR("irx","Service /"_tService_"/ not supported.")
	Set pOutput=##class(%GlobalBinaryStream).%New()
	if ( ..ControlHeaderValue'="" ) {
		quit ..ProcessControlHeader(pInput,.pOutput)
	}
	// now we have a legit regular request
	// save it and return response
	set response = ##class(%ZEN.proxyObject).%New()
	set now = $zdt($zts,3,3)
	set response.controlId = $system.Util.CreateGUID()
	set response.timestamp = now
	set response.status = ""	
	try {
		// pull proxy out of input
		set content = ""
		while ( 'pInput.AtEnd ) {
			set content = content _ pInput.Read()
		}
		$$$TRACE("source="_tService_" controlId="_response.controlId_" content = "_content)
		// need to refactor this - should
		// send request to a business operation to 
		// store the actionq item
		set request=##class(irx.RestRequest).%New()
		set request.ControlId = response.controlId
		set request.Content = content
		set request.Timestamp = now
		set request.Source = tService
		// send downstream for processing
		if ( ..TargetConfigNames '= "" ) {
			for i=1:1:$length(..TargetConfigNames, ",") {
				set target = $zstrip( $piece( ..TargetConfigNames, ",", i ), "<>W")
				set sc=..SendRequestAsync(target,request)
				if ( $$$ISERR(sc) ) {
					// store any errors to return in the response
				}
			}
		}
		//set response.action = inreq.action_"_response"
		$$$THROWONERROR(sc,##class(%ZEN.Auxiliary.jsonProvider).%WriteJSONStreamFromObject( pOutput, response ))
	} catch error {
		set response.status = response.status _ "error"	
		set response.error = ##class(%ZEN.proxyObject).%New()
		set response.error.code = error.AsSQLCODE()
		set response.error.description = error.DisplayString()
		set sc=##class(%ZEN.Auxiliary.jsonProvider).%WriteJSONStreamFromObject( pOutput, response ) 
		set status = error.AsStatus()
		if ( $$$ISERR(sc) ) {
			do $system.Status.AppendStatus(status, sc)
		}
		return status
	}
	quit $$$OK
}

/// Control the type and content of error returned to the REST caller
ClassMethod OnErrorStream(pStatus As %Status)
{
 	Set tStream = ##class(%GlobalBinaryStream).%New()  $$$ASSERT($IsObject(tStream))
	Do tStream.Write($ZConvert($$$StatusDisplayString(pStatus)_$C(13,10),"O","UTF8"))
	Set tStream.Attributes("Content-Type")=" text/plain; charset=""UTF-8"""
	Set tStream.Attributes("ResponseCode")="500 Internal Server Error"
 	Quit tStream
}

}

